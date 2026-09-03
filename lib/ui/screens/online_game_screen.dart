import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/ai/ai_player.dart';
import '../../game/progress.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../models/variant_config.dart';
import '../../online/online_service.dart';
import '../../online/replay_story.dart';
import '../../online/serialize.dart';
import '../../state/display_config.dart';
import '../../stats/stats_repository.dart';
import '../../stats/user_stats.dart';
import '../widgets/card_legend_sheet.dart';
import '../widgets/game_play_view.dart';
import '../widgets/replay_step_view.dart';
import '../widgets/variant_badge.dart';
import 'online_screens.dart';
import 'win_navigation.dart';
import 'win_screen.dart';

/// Online-skærm. Selve UI-laget (tap, valg, split-7, byt, paneler, board)
/// kommer fra den fælles [GamePlayView] som single-player også bruger — så
/// vi kun har ÉT sæt regler for spil-interaktioner. Denne skærm håndterer
/// kun det online-specifikke: heartbeat, vært-driven AI, og catch-up replay
/// af events man missed inden man åbnede skærmen.
class OnlineGameScreen extends ConsumerStatefulWidget {
  const OnlineGameScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends ConsumerState<OnlineGameScreen>
    with WidgetsBindingObserver {
  String _lastProcessed = '';
  bool _busy = false;
  bool _aiActionPending = false;

  /// Nøgle til at fange et billede af brættet ved spil-slut.
  final GlobalKey _boardKey = GlobalKey();


  bool _replayActive = false;
  int _replayTarget = 0; // rå log-længde (til markSeen)
  // De træk der vises i "mens du var væk"-replay'en, med utilsigtede dubletter
  // filtreret fra, samt den aktuelle position i den liste.
  List<Map<String, dynamic>> _replayItems = <Map<String, dynamic>>[];

  bool _statsRecomputed = false;

  /// Navigations-låsen til sejrsskærmen — BEVIDST adskilt fra
  /// [_statsRecomputed]: da de delte flag, spærrede et mislykket
  /// navigations-forsøg for alle senere forsøg, og spillet skriver aldrig
  /// mere til doc'et efter 'over'. Se WinNavigator.
  /// Var spillet ALLEREDE slut ved første build? Så kigger man på en gammel
  /// slutrapport fra arkivet — ikke på et parti der lige er endt. Bruges til
  /// at undgå unødigt arbejde på et dødt spil (genberegning, replay) og til
  /// at springe ventetiden på brik-animationen over.
  bool? _wasOverOnOpen;

  /// Har vi markeret en åbnet slutrapport som set? (én gang pr. skærm).
  bool _archiveSeenMarked = false;

  WinNavigator? _winNavField;
  WinNavigator get _winNav => _winNavField ??= WinNavigator(
        // Ingen brik-animation at vente på i et afsluttet spil.
        settleDelay: _wasOverOnOpen == true
            ? Duration.zero
            : const Duration(milliseconds: 560),
      );
  Timer? _heartbeat;
  String _lastTakeoverSig = '';
  bool _initialReplayChecked = false;
  int _liveSeenAck = 0;
  // Skrive-amplifikation (#10): seen-positionen skrives IKKE pr. træk længere.
  // Vi husker den seneste sete log-længde lokalt og flusher den kun ved
  // pause/dispose/replay-slut. _seenFlushed = sidst skrevne værdi.
  int _seenFlushed = 0;
  // Om DENNE klient er vært. Kun værten driver AI, så kun værten har brug for
  // det periodiske sikkerhedsnets-rebuild (#11).
  bool _isHost = false;
  // Fanget service-instans, så flush i dispose() virker selv når ref er væk.
  OnlineService? _capturedSvc;
  // Hvornår skærmen sidst gik i baggrunden — bruges til kun at tvinge en
  // Firestore-genforbindelse efter et reelt ophold (ikke et hurtigt fane-skift).
  DateTime? _hiddenAt;
  // Baggrunds-ophold længere end dette regnes som "rigtig væk" og udløser en
  // Firestore-genforbindelse ved resume; kortere (fane-flimmer) gør ikke.
  static const Duration _kLongBackground = Duration(seconds: 5);
  // Presence (uid → ms) opdateres løbende af en manuel lytter, men UI'et
  // rebuild'es kun THROTTLET (#14) — ikke pr. heartbeat-snapshot.
  Map<String, int> _presenceMs = const <String, int>{};
  ProviderSubscription<AsyncValue<Map<String, int>>>? _presenceSub;
  Timer? _presenceThrottle;

  OnlineService get _svc => ref.read(onlineServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capturedSvc = _svc;
    // ignore: discarded_futures
    _svc.heartbeat(widget.code);
    _heartbeat = Timer.periodic(kPresenceInterval, (_) {
      // Opdater KUN presence når appen er synlig/i forgrunden. Ellers lader vi
      // presence blive forældet, så en fraværende spiller (fx en Android-PWA
      // der lever i baggrunden) faktisk ser "væk" ud og får en tur-push.
      if (_appVisible()) {
        // ignore: discarded_futures
        _svc.heartbeat(widget.code);
      }
      // Sikkerhedsnet mod AI-freeze: hvis _maybeHostAct har markeret en sig
      // som behandlet men handlingen aldrig trådte i kraft (transient fejl,
      // app i baggrunden, mistet snapshot), står vi fast indtil Firestore-
      // doc'et opdateres — hvilket ikke sker når intet sker. Ryd
      // dedup-nøglerne her og rebuild så _maybeHostAct prøver igen.
      // aiSeatMove er idempotent: den exit'er hvis state.currentPlayerIndex
      // har bevæget sig, så vi kan ikke trække to gange ved en uskyld.
      //
      // KUN værten (#11): kun værten driver AI og bruger _lastProcessed/
      // _lastTakeoverSig. Ikke-værter havde intet udbytte af dette rebuild —
      // det var bare spildt CPU/batteri hvert 7. sekund pr. åben fane.
      if (_isHost && mounted && !_busy && !_aiActionPending) {
        _lastProcessed = '';
        _lastTakeoverSig = '';
        setState(() {});
      }
    });
    // Presence-lytter (#14): opdatér feltet løbende, men rebuild THROTTLET.
    // ref.listenManual abonnerer UDEN at rebuild'e widget'en pr. snapshot —
    // så en heartbeat hvert ~1,75s ikke længere trigger et fuldt rebuild af
    // hele skærmen hos alle klienter. onlineSeats/AI-tjek er stadig baseret på
    // friske stempler (feltet), kun selve genrenderingen er throttlet.
    _presenceSub = ref.listenManual<AsyncValue<Map<String, int>>>(
      presenceStreamProvider(widget.code),
      (prev, next) {
        final Map<String, int>? m = next.valueOrNull;
        if (m == null) return;
        _presenceMs = m;
        _schedulePresenceRebuild();
      },
      fireImmediately: true,
    );
  }

  /// Planlæg ét rebuild om lidt, hvis der ikke allerede er et planlagt — så en
  /// byge af presence-snapshots (op til ~hver 1,75s i et 4-spillers spil)
  /// koalesceres til højst ét rebuild pr. vindue i stedet for ét pr. snapshot.
  ///
  /// Friskheds-grænsen for online-markørerne afhænger af at presence-streamen
  /// bliver ved med at emitte (i praksis garanteret af klientens EGEN heartbeat
  /// hvert kPresenceInterval, der selv skriver til presence-collectionen) — det
  /// er ikke et hårdt ur-garanteret loft. AI-overtagelsen er dækket separat af
  /// værtens 7s-timer, så den påvirkes ikke.
  void _schedulePresenceRebuild() {
    if (_presenceThrottle != null) return;
    _presenceThrottle = Timer(const Duration(seconds: 4), () {
      _presenceThrottle = null;
      if (mounted) setState(() {});
    });
  }

  /// Skriv den seneste sete log-position til Firestore — men KUN hvis den er
  /// rykket siden sidst. Kaldes ved pause/dispose/replay-slut, IKKE pr. træk,
  /// så vi undgår skrive-amplifikation (#10): før skrev hver tilsluttet klient
  /// `seen.$uid` til spil-doc'et ved hvert eneste træk (op til ~5× writes +
  /// `onGameTurn`-invocations pr. træk i et 4-spillers spil).
  void _flushSeen() {
    if (_liveSeenAck <= _seenFlushed) return;
    final int n = _liveSeenAck;
    _seenFlushed = n;
    // Fire-and-forget via den fangede service (ref kan være væk i dispose).
    // ignore: discarded_futures
    (_capturedSvc ?? _svc).markSeen(widget.code, n).catchError((_) {});
  }

  /// True når appen er synlig/i forgrunden (så vi bør opdatere presence).
  bool _appVisible() {
    final AppLifecycleState? s = WidgetsBinding.instance.lifecycleState;
    return s != AppLifecycleState.hidden && s != AppLifecycleState.paused;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Nulstil AI-dedup så værten straks driver et evt. fastlåst AI-træk igen.
      _lastProcessed = '';
      _lastTakeoverSig = '';
      // Tving KUN en genforbindelse efter et reelt baggrunds-ophold (vi HAR
      // været skjult, i >5s) — ikke ved cold start (hidden == null → frisk
      // forbindelse i forvejen) og ikke ved et hurtigt fane-skift, hvor
      // forbindelsen stadig er sund.
      final DateTime? hidden = _hiddenAt;
      _hiddenAt = null;
      final bool longBackground = hidden != null &&
          DateTime.now().difference(hidden) > _kLongBackground;
      // ignore: discarded_futures
      _refreshFromBackground(reconnect: longBackground);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _hiddenAt = DateTime.now();
      // På vej i baggrunden: gem seen-positionen nu (#10), så en reconnect
      // starter replay det rigtige sted uden at vi skrev pr. træk undervejs.
      _flushSeen();
    }
  }

  /// Tilbage i forgrunden (fx åbnet fra en notifikation). Tidligere fik det
  /// spillet til at "fryse" i 30-60s: appen havde været i baggrunden, Firestores
  /// WebChannel var død, og en `invalidate` alene gav kun den cachede (frosne)
  /// state, mens SDK'en selv brugte op til et minut på at opdage den døde
  /// forbindelse. Nu tvinger vi en genforbindelse FØRST (disable+enable), så en
  /// frisk lytter straks får server-state.
  Future<void> _refreshFromBackground({required bool reconnect}) async {
    if (reconnect) await _svc.reconnect();
    if (!mounted) return;
    // ignore: discarded_futures
    _svc.heartbeat(widget.code);
    ref.invalidate(gameStreamProvider(widget.code));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSeen();
    _heartbeat?.cancel();
    _presenceThrottle?.cancel();
    _presenceSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(gameStreamProvider(widget.code));
    // Presence læses fra et felt der opdateres af en THROTTLET lytter (#14) —
    // IKKE ref.watch, som ville rebuild'e hele skærmen ved hver spillers
    // heartbeat (~hver 1,75s i et 4-spillers spil, hos alle klienter). Feltet
    // holdes friskt løbende; selve rebuild'et sker højst hvert par sekunder.
    final Map<String, int> presenceMs = _presenceMs;
    // Varianten skal på SCAFFOLD'en, som bygges FØR snap.when — læs doc'et
    // defensivt her (loading/fejl/ukendt id → klassisk grøn). NB: ved allerførste
    // load blinker fladen derfor grøn→blå for et 25 år-spil; navngivet fravalg
    // (en initialVariantId-param gennem begge navigationssteder er ikke det værd).
    final Map<String, dynamic>? rawDoc = snap.valueOrNull?.data();
    // Efter start er state'ns 'vid' autoriteten (matcher brættet); før start
    // gælder lobby-feltet. Defensivt hele vejen — loading/skævt → klassisk.
    final dynamic rawState = rawDoc?['state'];
    // variantFromRaw: custom-varianters navn/tema materialiseres fra doc'ets
    // egen cardRulesVariants-kopi — også for gæster der aldrig har set dem.
    final VariantConfig variant = rawDoc == null
        ? classicVariant
        : variantFromRaw(
            (rawState is Map && rawState['vid'] is String)
                ? rawState['vid'] as String
                : (rawDoc['variantId'] is String
                    ? rawDoc['variantId'] as String
                    : null),
            rawDoc['cardRulesVariants']);
    return Scaffold(
      backgroundColor: variant.tableColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: Row(children: <Widget>[
          VariantBadge(variant: variant, compact: true),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Online — ${widget.code}',
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: <Widget>[
          // Legenden for kortenes token-sprog. Reglerne er spillets OPLØSTE
          // (state.cr — bærer variantens kort); før start resolves de som
          // startGameFromLobby ville (klassisk + variantens overrides).
          if (rawDoc != null)
            IconButton(
              tooltip: 'Kortene i dette spil',
              icon: const Icon(Icons.style),
              onPressed: () {
                showCardLegendSheet(
                    context, cardRulesOfGameDoc(rawDoc, variant));
              },
            ),
        ],
      ),
      body: snap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fejl: $e')),
        data: (doc) {
          final d = doc.data();
          if (d == null || d['state'] == null) {
            return const Center(
                child: Text('Venter på at spillet starter…',
                    style: TextStyle(color: Colors.white)));
          }
          final state = gameStateFromMap(
              Map<String, dynamic>.from(d['state'] as Map),
              variantsRaw: d['cardRulesVariants']);
          _wasOverOnOpen ??= state.winningTeamIndex != null;
          final uids = d['uids'] as List;
          final myUid = _svc.uid;
          final int mySeat = uids.indexOf(myUid);
          final bool isHost = d['hostUid'] == myUid;
          _isHost = isHost; // så heartbeat-timeren kun rebuild'er hos værten (#11)
          final log = (d['log'] as List? ?? <dynamic>[]);
          final lastByPlayer = _parseLog(log);

          final seenMap = (d['seen'] as Map?) ?? const <String, dynamic>{};
          final int mySeen = (seenMap[myUid] as num?)?.toInt() ?? 0;
          // Intet "mens du var væk"-replay i et afsluttet spil: rapporten er
          // det man kom efter, og navigationen ville alligevel afbryde det.
          if (state.winningTeamIndex == null) {
            _maybeStartReplay(state, log, mySeen);
          } else if (!_archiveSeenMarked && mySeen < log.length) {
            // Men markér den så SET her — ellers ville "Ny slutrapport"-
            // mærket i arkivet aldrig kunne ryddes (replay'en er normalt den
            // der kalder markSeen). Én skrivning, kun når der faktisk er
            // noget uset.
            _archiveSeenMarked = true;
            // ignore: discarded_futures
            _svc.markSeen(widget.code, log.length);
          }

          if (!_replayActive) _maybeHostAct(state, isHost, d, presenceMs);

          final names = (d['names'] as List).map((e) => e as String).toList();

          // Online-status pr. sæde: en spiller er "online" hvis de IKKE ser
          // "væk" ud (frisk presence-stempel). Genbruger samme kilde-sandhed som
          // AI-overtagelsen (seatIsAway), så de to ikke kan divergere. Presence
          // kommer fra en SEPARAT stream (subcollection), så de hyppige
          // heartbeats ikke rører spil-doc'et — se forbrugs-fund #4.
          final Set<int> onlineSeats = <int>{
            for (int seat = 0; seat < uids.length; seat++)
              if (!OnlineService.seatIsAway(uids, presenceMs, seat)) seat,
          };

          if (state.winningTeamIndex != null && !_winNav.navigated) {
            // Stats genberegnes præcis én gang; navigationen har sin EGEN
            // lås, så et forsøg der ikke nåede igennem kan prøves igen.
            // Genberegning hører til det ØJEBLIK spillet sluttede. Åbner man
            // en gammel rapport fra arkivet, er tallene for længst skrevet —
            // og et fuldt scan af brugerens spil pr. åbning ville være den
            // dyreste linje i hele arkivet (QC-fund).
            if (!_statsRecomputed && _wasOverOnOpen == false) {
              _statsRecomputed = true;
              // Samme værdi som den ydre myUid — men et eget navn, så det
              // er tydeligt at genberegningen ikke hænger sammen med
              // kortregnskabet længere nede.
              final String? recomputeUid = _svc.uid;
              if (recomputeUid != null && mySeat >= 0) {
                // ignore: discarded_futures
                StatsRepository().recomputeAndSaveOwn(recomputeUid);
              }
            }
            final int winner = state.winningTeamIndex!;
            final int? margin = winMarginFields(state);
            final bool? viewerWon =
                mySeat < 0 ? null : (mySeat % 2 == winner);
            // Vinderholdets navne + farver (pladser winner, winner+2).
            final winnerNames = <String>[];
            final winnerColors = <Color>[];
            for (int i = 0; i < state.players.length; i++) {
              if (i % 2 == winner) {
                winnerNames.add(i < names.length ? names[i] : 'Spiller');
                winnerColors.add(state.players[i].color);
              }
            }
            final String oldCode = widget.code;
            // Kortregnskabet for PRÆCIS dette parti. Beregnes her, hvor doc'et
            // allerede er i hånden — så slutrapporten koster ingen ekstra
            // Firestore-læsning for at kunne vise det. Reglerne følger med fra
            // samme doc, så underteksten navngiver de kort der blev talt.
            final UserStats? cardMix =
                myUid == null ? null : computeAllStats(<Map<String, dynamic>>[
                    Map<String, dynamic>.from(d)])[myUid];
            // Fang service-instansen NU, mens denne skærm stadig er i live.
            // WinScreen pushes via pushReplacement, så OnlineGameScreen (og dens
            // ref) disposes — en senere `ref.read` i revanche-callbacken ville
            // ellers kaste "Cannot use ref after the widget was disposed".
            final OnlineService svc = _svc;
            // Naviger til WinScreen. Brætbilledet er VALGFRIT (WinNavigator
            // har timeout på det): en baggrundsfane tegner ingen frames, og
            // fejringen må aldrig koste på et billede der ikke kan tages.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // ignore: discarded_futures
              _winNav.run(
                gameOver: true,
                stillMounted: () => mounted,
                capture: () => captureBoardImage(_boardKey),
                navigate: (Uint8List? shot) {
                  Navigator.of(context).pushReplacement<void, void>(
                    MaterialPageRoute<void>(
                      builder: (_) => WinScreen(
                        variant: state.variant,
                        winningTeamIndex: winner,
                        fromOnline: true,
                        gameCode: widget.code,
                        archived: _wasOverOnOpen == true,
                        playedAt: d['finishedAt'] is Timestamp
                            ? (d['finishedAt'] as Timestamp).toDate()
                            : null,
                        boardImage: shot,
                        marginFields: margin,
                        viewerWon: viewerWon,
                        winnerNames: winnerNames,
                        winnerColors: winnerColors,
                        rematchLabel: 'Revanche',
                        cardMix: cardMix,
                        cardMixRules: cardRulesOfGameDoc(
                            Map<String, dynamic>.from(d), state.variant),
                        onRematch: (ctx) async {
                          final code = await svc.createRematch(oldCode);
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pushReplacement<void, void>(
                            MaterialPageRoute<void>(
                              builder: (_) => LobbyScreen(code: code),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            });
          }

          return SafeArea(
            child: RepaintBoundary(
              key: _boardKey,
              child: Stack(
                children: <Widget>[
                  GamePlayView(
                    state: state,
                    mySeat: mySeat,
                    onApplyMove: (seat, move) => _applyMove(seat, move),
                    onPass: (seat) => _passHand(state, seat),
                    onSubmitExchange: (seat, card) =>
                        _submitExchange(seat, card),
                    lastPlayedCards: lastByPlayer,
                    onlineSeats: onlineSeats,
                  ),
                  if (_replayActive) _replayOverlay(names, state, mySeat),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Write-side: spil-handlinger via Firestore-transaktion.
  // ---------------------------------------------------------------------------

  Future<void> _applyMove(int seat, Move move) async {
    await _run(() => _svc.mutate(widget.code,
        (engine, _) => engine.applyMove(seat, move),
        logEntry: moveLogEntry(seat, move)));
  }

  Future<void> _passHand(GameState state, int seat) async {
    final discarded = state.players[seat].hand.length;
    await _run(() => _svc.mutate(widget.code,
        (engine, _) => engine.passHand(seat),
        logEntry: passLogEntry(seat, discarded)));
  }

  Future<void> _submitExchange(int seat, PlayingCard card) async {
    await _run(() => _svc.mutate(widget.code,
        (engine, _) => engine.submitExchangeCard(seat, card)));
  }

  Future<void> _run(Future<void> Function() fn) async {
    _busy = true;
    try {
      await fn();
    } catch (_) {} finally {
      _busy = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Catch-up replay
  // ---------------------------------------------------------------------------

  void _maybeStartReplay(GameState state, List log, int mySeen) {
    if (_replayActive) return;
    if (log.length <= mySeen) {
      _initialReplayChecked = true;
      return;
    }
    if (!_initialReplayChecked) {
      _initialReplayChecked = true;
      // Byg listen af træk der skal vises, med ALLE utilsigtede dubletter
      // fjernet (ikke kun sammenhængende): samme spiller+kort+brik-flyt =
      // samme handling logget flere gange. Et ægte identisk træk kan ikke ske
      // to gange i samme hånd (kortet er unikt), så global de-dup er sikker.
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
      for (int i = mySeen; i < log.length; i++) {
        final e = Map<String, dynamic>.from(log[i] as Map);
        if (items.any((Map<String, dynamic> x) => sameLoggedMove(e, x))) {
          continue;
        }
        items.add(e);
      }
      if (items.isEmpty) {
        // Alt var dubletter (bør ikke ske) — marker set (lokalt) og vis intet.
        _liveSeenAck = log.length;
        return;
      }
      // _maybeStartReplay kaldes fra build() — setState må ikke kaldes midt i
      // en build. Udskyd til efter frame'en.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _replayActive = true;
          _replayItems = items;
          _replayTarget = log.length;
        });
      });
      return;
    }
    // Følg den seneste sete log-længde LOKALT. Skrives ikke pr. træk (#10) —
    // flushes ved pause/dispose/replay-slut via _flushSeen().
    if (log.length > _liveSeenAck) {
      _liveSeenAck = log.length;
    }
  }

  Future<void> _finishReplay() async {
    // Replay slut = brugeren har set alt op til _replayTarget. Skriv det nu
    // (og opdatér flush-bogholderiet, så _flushSeen ikke skriver samme værdi
    // igen).
    try {
      await _svc.markSeen(widget.code, _replayTarget);
      if (_replayTarget > _seenFlushed) _seenFlushed = _replayTarget;
    } catch (_) {}
    if (_replayTarget > _liveSeenAck) _liveSeenAck = _replayTarget;
    if (!mounted) return;
    setState(() => _replayActive = false);
  }

  /// "Mens du var væk" som en RULBAR LISTE, ikke ti modale klik.
  ///
  /// Den gamle form viste ét skridt ad gangen med Næste/Spring over. En
  /// genindtræden kan rumme 10+ skridt, og ti tryk før man må spille er en
  /// afgift, alle betaler ved at trykke "Spring over" — hvorefter
  /// informationen er væk for altid (markSeen). Nu kan man rulle listen
  /// igennem på få sekunder og se alle kortene på én gang.
  Widget _replayOverlay(List<String> names, GameState state, int mySeat) {
    final List<ReplayStory> stories = <ReplayStory>[
      for (final Map<String, dynamic> m in _replayItems)
        storyFor(m,
            mySeat: mySeat, names: names, geometry: state.variant.geometry),
    ];
    // TM-fund: et EKSAKT strengmatch talte for lavt. Rammer ét træk mig to
    // gange (fx +2−5-sekvensen), skriver storyFor "Slog din brik hjem (2 i
    // alt)" — og den linje blev slet ikke talt med. Derfor præfiks-match,
    // og tælleren spørger om ANTALLET, ikke om linjen.
    final int hitsOnMe = stories.fold<int>(
        0, (int n, ReplayStory s) => n + s.hitsOnMe);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                              'Mens du var væk — '
                              '${_replayItems.length} træk',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          // Det man faktisk vil vide, sagt ÉN gang øverst i
                          // stedet for et udbrud ved hvert skridt.
                          if (hitsOnMe > 0)
                            Text(
                                hitsOnMe == 1
                                    ? 'Din brik røg hjem én gang.'
                                    : 'Dine brikker røg hjem $hitsOnMe gange.',
                                style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _replayItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int i) =>
                            ReplayStepView(
                          story: stories[i],
                          card: _replayItems[i]['card'] == null
                              ? null
                              : cardFromMap(Map<String, dynamic>.from(
                                  _replayItems[i]['card'] as Map)),
                          rules: state.cardRules,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          // ignore: discarded_futures
                          onPressed: _finishReplay,
                          child: const Text('Videre'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Replay-teksten bor i online/replay_story.dart som rene funktioner
  // (storyFor/fieldName/stepsAdvanced) — så ordvalget kan mutationstestes
  // uden en widget-pumpe (se test/replay_story_test.dart).

  Map<int, PlayingCard> _parseLog(List log) {
    final out = <int, PlayingCard>{};
    for (final e in log) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['type'] == 'move' && m['card'] != null) {
        out[(m['player'] as num).toInt()] =
            cardFromMap(Map<String, dynamic>.from(m['card'] as Map));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Vært-driven AI: kører beslutninger INDE i transaktionen så stale-snapshot
  // ikke kan afvises af applyMoves runtime-guard.
  // ---------------------------------------------------------------------------

  void _maybeHostAct(GameState state, bool isHost, Map<String, dynamic> d,
      Map<String, int> presenceMs) {
    if (!isHost || _busy) return;
    if (state.winningTeamIndex != null) return;
    // Spillets valgte AI-grad (fra doc'et) → parametre (admin-styret).
    final List<AiParams> aiLevels =
        ref.read(aiLevelsProvider).valueOrNull ?? kDefaultAiLevels;
    final int gameAiLevel = (d['aiLevel'] as num?)?.toInt() ?? kAiLevelDefault;
    final AiParams aiParams =
        aiLevels[gameAiLevel.clamp(0, aiLevels.length - 1)];
    final sig =
        '${state.handNumber}:${state.phase.name}:${state.currentPlayerIndex}:${state.exchangeBuffer.length}';

    if (state.phase == GamePhase.exchange) {
      if (sig == _lastProcessed) return;
      final missingAi = <int>[
        for (int i = 0; i < state.players.length; i++)
          if (!state.players[i].isHuman && !state.exchangeBuffer.containsKey(i))
            i,
      ];
      if (missingAi.isEmpty) return;
      _lastProcessed = sig;
      _run(() => _svc.mutate(widget.code, (engine, s) {
            for (final i in missingAi) {
              engine.submitExchangeCard(
                  i, onlineAi.chooseExchangeCard(s, i, params: aiParams));
            }
          }));
    } else if (state.phase == GamePhase.play) {
      final idx = state.currentPlayerIndex;
      final bool isAiSeat = !state.currentPlayer.isHuman;

      // AI-overtagelse gælder KUN spil der har mindst én AI-plads. I et spil
      // med 4 rigtige spillere er der ingen timeout — vi venter på spilleren
      // uanset hvor længe de er væk (afbrudt netværk, telefonopkald, kaffe).
      final bool allHuman = state.players.every((Player p) => p.isHuman);

      bool takeover = false;
      if (!isAiSeat && !allHuman) {
        final since = OnlineService.timeSinceLastAction(d);
        final away =
            OnlineService.seatIsAway(d['uids'] as List, presenceMs, idx);
        if (away && since != null && since > kAiTakeoverTimeout) {
          takeover = true;
        }
      }

      if (!isAiSeat && !takeover) return;

      if (isAiSeat) {
        if (sig == _lastProcessed) return;
        _lastProcessed = sig;
        // Dæk 600 ms-forsinkelsen med et in-flight-flag, så heartbeat-timeren
        // ikke rydder _lastProcessed midt i vinduet og aflyrer en dublet-
        // transaktion.
        _aiActionPending = true;
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          _run(() async {
            final acted = await _svc.aiSeatMove(widget.code, idx,
                params: aiParams);
            if (!acted && mounted) _lastProcessed = '';
          }).whenComplete(() => _aiActionPending = false);
        });
      } else {
        if (sig == _lastTakeoverSig) return;
        _lastTakeoverSig = sig;
        _run(() async {
          final acted = await _svc.aiTakeoverMove(widget.code, idx,
              params: aiParams);
          if (!acted && mounted) _lastTakeoverSig = '';
        });
      }
    }
  }
}
