import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/rules.dart';
import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/piece.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../state/display_config.dart';
import '../../state/settings_controller.dart';
import 'board_view.dart';
import 'card_view.dart';
import 'player_panel.dart';

/// Den fælles spil-overflade — board, paneler, hånd, taps, valg-dialoger og
/// hele split-7-/byt-flowet. Bruges af både single-player- og online-skærmen
/// så vi kun har ÉT sæt regler for hvordan brugeren interagerer med spillet.
///
/// Skærmene udenom (single-player vs. online) leverer state'en og håndterer
/// hvordan ændringer persisteres (lokal engine vs. Firestore-transaktion) via
/// [onApplyMove] / [onPass] / [onSubmitExchange]-callbacks.
class GamePlayView extends ConsumerStatefulWidget {
  const GamePlayView({
    required this.state,
    required this.mySeat,
    required this.onApplyMove,
    required this.onPass,
    required this.onSubmitExchange,
    this.lastPlayedCards = const <int, PlayingCard>{},
    this.bottomStatusOverride,
    this.onlineSeats,
    super.key,
  });

  /// Den aktuelle spil-state.
  final GameState state;

  /// Hvilket sæde brugeren styrer (= hånden vi viser). For single-player er
  /// dette det eneste menneske; for online er det `uids.indexOf(myUid)`. Sæt
  /// til -1 hvis brugeren er tilskuer (read-only).
  final int mySeat;

  /// Når brugeren har valgt et træk. Skærmen kalder enten engine.applyMove
  /// (single-player) eller _svc.mutate (online).
  final void Function(int seat, Move move) onApplyMove;

  /// Når brugeren ikke kan spille noget og smider sin hånd.
  final void Function(int seat) onPass;

  /// Når brugeren har valgt et kort til byttet før play-fasen.
  final void Function(int seat, PlayingCard card) onSubmitExchange;

  /// Seneste spillede kort pr. spiller (vises i panel). Kan være tom.
  final Map<int, PlayingCard> lastPlayedCards;

  /// Override af status-tekst nederst (fx "AL 4 spiller…" i online-mode hvor
  /// der ikke køres animation lokalt). Hvis null bruger widget'en sin egen
  /// status afhængigt af tilstand.
  final String? bottomStatusOverride;

  /// Sæder (0..3) hvis menneskelige spiller er "online" (frisk presence) i et
  /// online-spil. `null` = ikke et online-spil (fx AI-/lokalt spil) → ingen
  /// online-markør vises. En human-plads der IKKE er i sættet vises som "væk".
  final Set<int>? onlineSeats;

  @override
  ConsumerState<GamePlayView> createState() => _GamePlayViewState();
}

class _GamePlayViewState extends ConsumerState<GamePlayView>
    with SingleTickerProviderStateMixin {
  PlayingCard? _selectedCard;
  List<Move> _candidateMoves = <Move>[];
  PlayingCard? _humanExchangeChoice;
  String? _swapFirstPiece;
  final List<MoveStep> _splitPath = <MoveStep>[];

  /// Hybrid-kort (byt + bevægelse, fx 25 års "Byt ELLER 9"): true når
  /// spilleren har valgt BYT-tilstanden for det valgte kort.
  bool _hybridSwapMode = false;

  /// Memo for canPlay (se _buildPlayArea).
  String? _canPlayKey;
  bool _canPlayMemo = false;

  // Lokal farve-rotation: sat i build() ud fra brugerens ønske-farve, brugt af
  // board + paneler. Rent visuelt for denne enhed.
  int _colorOffset = 0;

  // Brik-animation: når widget.state skifter, sammenligner vi brik-positioner
  // pr. piece-id og animerer alle ændrede brikker fra deres FORRIGE til deres
  // NUVÆRENDE position over 480 ms. Bruges af både single-player (lokal
  // engine) og online (Firestore-snapshot) — i begge tilfælde har state
  // allerede ændret sig før vi når didUpdateWidget, så vi animerer fra det
  // gamle state's positioner mod det nye state's positioner.
  late final AnimationController _anim;
  Map<String, ({PiecePosition from, PiecePosition to})> _animMoves = {};

  /// Zoom/panorering af brættet (knib eller scroll). Nulstilles ved spil-slut,
  /// så slutstillings-billedet ikke fanges zoomet ind.
  final TransformationController _boardZoom = TransformationController();

  GameState get _state => widget.state;
  int get _mySeat => widget.mySeat;
  bool get _animating => _animMoves.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((AnimationStatus s) {
        // Ryd kun animationen når den NÅR ENDEN (completed). Brug ikke
        // whenComplete på Future'n, da den fires med cancel hvis vi
        // restarter med forward(from: 0), og ville rydde det nye sæt af
        // animations-moves der lige er sat.
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _animMoves = {});
        }
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    _boardZoom.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GamePlayView old) {
    super.didUpdateWidget(old);
    final bool phaseOrTurnChanged =
        _state.currentPlayerIndex != old.state.currentPlayerIndex ||
            _state.handNumber != old.state.handNumber ||
            _state.phase != old.state.phase;
    // Nulstil også hvis det valgte kort ikke længere er på min hånd — dækker
    // det tilfælde hvor turen "bliver hos mig" sidst i en hånd (alle andre har
    // tomme hænder), så currentPlayerIndex/handNumber/phase er uændret, men mit
    // netop spillede kort er væk. Ellers ville _candidateMoves pege på gamle
    // brik-positioner og taps sende stale træk.
    final Player? me = (_mySeat >= 0 && _mySeat < _state.players.length)
        ? _state.players[_mySeat]
        : null;
    final bool selectedGone = _selectedCard != null &&
        (me == null || !me.hand.contains(_selectedCard));
    if (phaseOrTurnChanged || selectedGone) {
      _selectedCard = null;
      _candidateMoves = <Move>[];
      _swapFirstPiece = null;
      _hybridSwapMode = false;
      _splitPath.clear();
    }
    if (phaseOrTurnChanged) {
      // Bytte-valget hører til én bestemt hånd/fase — ryd det ved skift, så et
      // gammelt valg ikke står forudvalgt (og evt. matcher et andet kort i den
      // nye hånd via værdi-lighed) i næste byttefase.
      _humanExchangeChoice = null;
    }
    // Beregn evt. animation: find alle brikker hvis position er ændret.
    final newAnim = <String, ({PiecePosition from, PiecePosition to})>{};
    for (final Player pNew in _state.players) {
      for (final Piece piece in pNew.pieces) {
        final Piece? oldPiece = _findPiece(old.state, piece.id);
        if (oldPiece == null) continue;
        if (oldPiece.position != piece.position) {
          newAnim[piece.id] =
              (from: oldPiece.position, to: piece.position);
        }
      }
    }
    if (newAnim.isNotEmpty) {
      _animMoves = newAnim;
      _anim.forward(from: 0);
    }
    // Nulstil zoom ved spil-slut, så slutstillings-billedet fanges i normal
    // størrelse (ikke zoomet ind).
    if (_state.phase == GamePhase.gameOver &&
        old.state.phase != GamePhase.gameOver) {
      _boardZoom.value = Matrix4.identity();
    }
  }

  Piece? _findPiece(GameState s, String id) {
    for (final Player p in s.players) {
      for (final Piece piece in p.pieces) {
        if (piece.id == id) return piece;
      }
    }
    return null;
  }

  /// Farve-rotation der får MIN plads til at vise brugerens ønske-farve.
  /// displayColor(seat) = players[(seat + offset) % n].color.
  int _offsetFor(GameState state, int mySeat, int? preferred) {
    if (preferred == null) return 0;
    final int n = state.players.length;
    for (int k = 0; k < n; k++) {
      if (state.players[(mySeat + k) % n].color.toARGB32() == preferred) {
        return k;
      }
    }
    return 0;
  }

  void _cycleColor(GameState state, int mySeat) {
    final int n = state.players.length;
    final int next = (_colorOffset + 1) % n;
    final int nextColor =
        state.players[(mySeat + next) % n].color.toARGB32();
    ref.read(settingsProvider.notifier).setPreferredColorValue(nextColor);
  }

  /// Vis-farve for en plads efter lokal rotation.
  Color _displayColor(GameState state, int seat) {
    final int n = state.players.length;
    return state.players[(seat + _colorOffset) % n].color;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (_mySeat < 0 || _mySeat >= state.players.length) {
      // Tilskuer: vis kun brættet uden interaktioner.
      return _SpectatorView(state: state, lastPlayedCards: widget.lastPlayedCards);
    }
    final int? preferred = ref.watch(
        settingsProvider.select((s) => s.preferredColorValue));
    _colorOffset = _offsetFor(state, _mySeat, preferred);
    final Player me = state.players[_mySeat];
    final Player partner = state.players[me.partnerIndex];
    final Player left = state.players[(me.index + 1) % state.players.length];
    final Player right = state.players[(me.index + 3) % state.players.length];

    // Admin-justerbart minimum for brættets størrelse (config/ui.boardMinPx).
    final double boardMin =
        ref.watch(boardMinPxProvider).valueOrNull ?? kBoardMinDefault;

    // Samme layout på ALLE skærmstørrelser (telefon-opsætningen): paneler i
    // rækker over/under brættet. Det gamle "wide"-layout satte panelerne ved
    // SIDEN af brættet, hvilket på iPad gjorde selve brættet unødigt lille —
    // højden (ikke bredden) er den knappe ressource, og side-paneler stjæler
    // netop bredde som brættet kunne have brugt via sin AspectRatio.
    return _buildMobile(state, me, partner, left, right, boardMin);
  }

  Widget _buildMobile(GameState state, Player me, Player partner, Player left,
      Player right, double boardMin) {
    // Mobil-layout: paneler er nu placeret OVER og UNDER brættet i to rækker,
    // så de ikke længere overlapper brikkerne i brættets hjørner (gjorde det
    // svært at tappe brikker tæt på panelerne). Top-rækken har makker og
    // højre-modstander; bund-rækken har venstre-modstander og dig selv —
    // hver i deres "kvarter" af bordet relativt til dig.
    // Flexible + maxWidth 152: panelerne er 152 brede på normale skærme, men
    // krymper i stedet for at overflowe på meget smalle skærme (< ~316 px).
    Widget panelCell(Player p) => Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 152),
            child: _panel(state, p, compact: true),
          ),
        );
    final Widget topRow = Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          panelCell(partner),
          // "Starter N/3" placeret i det tomme midterfelt mellem panelerne —
          // sparer den højde en etikette under panelet ellers lagde til.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _starterChip(state),
          ),
          panelCell(right),
        ],
      ),
    );
    // Min plads får en lille "skift farve"-knap ved siden af panelet, så jeg
    // lokalt kan rotere brættets farver til min ønske-farve.
    final Widget myCell = Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Flexible(child: _panel(state, me, compact: true)),
            const SizedBox(width: 4),
            _colorCycleButton(state, me.index),
          ],
        ),
      ),
    );
    final Widget bottomRow = Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[panelCell(left), myCell],
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cns) {
        final double w = cns.maxWidth;
        final double h = cns.maxHeight.isFinite ? cns.maxHeight : 600;
        // Brættet har PRIORITET og et læsbart minimum. Panelerne og hånd-
        // kortene er kompakte, så brættet kan fylde resten. Kun hvis vinduet er
        // SÅ lavt at selv minimums-brættet + de kompakte paneler/kort ikke kan
        // være der, scroller siden — så brættet aldrig krymper væk.
        final double minBoard = min(w, boardMin);
        const double chrome = 225.0; // skøn: 2 kompakte panel-rækker + kort
        final bool fits = h - chrome >= minBoard;

        // Kompakte hånd-kort (fill: false), så de fylder mindre end brættet.
        final Widget human =
            _buildHumanArea(state, me, showPanel: false, fill: false);

        if (fits) {
          // Brættet fylder den resterende højde (≥ minimum) — ingen scroll.
          return Column(
            children: <Widget>[
              topRow,
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _boardArea(state, me),
                  ),
                ),
              ),
              bottomRow,
              human,
            ],
          );
        }
        // Meget lavt vindue: fast minimums-bræt, resten kan scrolles.
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              topRow,
              Center(
                child: SizedBox(
                  width: minBoard,
                  height: minBoard,
                  child: _boardArea(state, me),
                ),
              ),
              bottomRow,
              human,
            ],
          ),
        );
      },
    );
  }

  /// Lille tap-knap der roterer brættets farver ét skridt, så min egen brik
  /// skifter farve — rent lokalt for denne enhed. Cirklen viser min nuværende
  /// vis-farve; swap-ikonet antyder at man kan skifte.
  Widget _colorCycleButton(GameState state, int mySeat) {
    final Color mine = _displayColor(state, mySeat);
    return Tooltip(
      message: 'Skift din farve (kun for dig)',
      child: InkResponse(
        onTap: () => _cycleColor(state, mySeat),
        radius: 24,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: mine,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35), blurRadius: 3),
            ],
          ),
          child: const Icon(Icons.palette, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  /// "Starter · Navn N/3"-chip til det tomme midterfelt mellem top-panelerne.
  /// Farven følger STARTEREN (samme farve som starterens panel/brik) og
  /// respekterer den lokale farve-rotation. N nulstilles ved starter-rotation.
  Widget _starterChip(GameState state) {
    final int n = (state.starterStreak % 3) + 1;
    final Color c = _displayColor(state, state.starterIndex);
    final Color fg =
        c.computeLuminance() < 0.5 ? Colors.white : const Color(0xFF1A1A1A);
    // Navnet på starteren, hvis pladsen findes. Holdes kompakt (afkortes med
    // ellipsis) så chippen ikke sprænger det smalle felt mellem top-panelerne.
    final String? starterName =
        (state.starterIndex >= 0 && state.starterIndex < state.players.length)
            ? state.players[state.starterIndex].name
            : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
        boxShadow: <BoxShadow>[
          BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.outlined_flag, size: 12, color: fg),
          const SizedBox(width: 4),
          Text('Starter',
              style: TextStyle(
                  color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
          if (starterName != null && starterName.isNotEmpty) ...<Widget>[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                starterName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Text('$n/3',
              style: TextStyle(
                  // Tælleren en anelse dæmpet, så navnet er det primære.
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _boardArea(GameState state, Player me) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: AspectRatio(
          aspectRatio: 1,
          // InteractiveViewer: knib/scroll for at zoome ind og træk for at
          // panorere — så et lille bræt kan forstørres. Et tap på en brik
          // rammer stadig igennem (kun træk panorerer).
          child: InteractiveViewer(
            transformationController: _boardZoom,
            minScale: 1.0,
            maxScale: 4.0,
            clipBehavior: Clip.hardEdge,
            child: BoardView(
              state: state,
              viewerIndex: me.index,
              colorOffset: _colorOffset,
              // Drej altid 45°: start-/UD-båsene peger mod hjørnerne, så
              // brikkerne ikke skæres af kanten (heller ikke på store skærme).
              quarterTurn: true,
              highlightedPieceIds:
                  _animating ? const <String>{} : _highlightSet(state),
              animation:
                  _animating ? BoardAnimation(_animMoves, _anim.value) : null,
              // Deaktivér tap mens en animation kører — ellers risikerer vi
              // race mellem brugerens valg og den igangværende state-overgang.
              onPieceTap:
                  _animating ? null : (id) => _handlePieceTap(state, id),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(GameState state, Player p, {bool compact = false}) =>
      PlayerPanel(
        player: p,
        rules: state.cardRules,
        isCurrent: state.currentPlayerIndex == p.index,
        cardCount: p.hand.length,
        // Online-markør: kun i online-spil (onlineSeats != null) og kun for
        // menneskelige pladser. AI-pladser får ingen markør.
        online: widget.onlineSeats == null || !p.isHuman
            ? null
            : widget.onlineSeats!.contains(p.index),
        isStarter: state.starterIndex == p.index,
        satOut: state.phase == GamePhase.play &&
            state.sittingOut.contains(p.index),
        lastCard: widget.lastPlayedCards[p.index],
        compact: compact,
        colorOverride: _displayColor(state, p.index),
      );

  Widget _buildHumanArea(GameState state, Player me,
      {required bool showPanel, required bool fill}) {
    Widget body;
    if (state.phase == GamePhase.exchange) {
      body = _buildExchangeArea(state, me, fill: fill);
    } else if (state.phase == GamePhase.play) {
      body = _buildPlayArea(state, me, fill: fill);
    } else {
      body = const SizedBox(height: 16);
    }
    if (!showPanel) return body;
    final Widget panel = Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Center(child: _panel(state, me)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[panel, body],
    );
  }

  Widget _buildExchangeArea(GameState state, Player me, {required bool fill}) {
    final bool done = state.exchangeBuffer.containsKey(me.index);
    // Kortene får HELE bredden (Bekræft-knappen ligger nu nedenunder, ikke ved
    // siden af), så de kan være store nok til at vise kortets funktion.
    final double maxCardW = fill ? 84 : 60;
    // Det kort jeg har afgivet ligger i bufferen til byttet udføres — markér
    // det i hånden indtil jeg får makkerens kort (fasen skifter til play).
    final PlayingCard? givenCard = done ? state.exchangeBuffer[me.index] : null;
    final Widget cards = _handCards(
      state: state,
      hand: me.hand,
      faceUp: true,
      maxCardW: maxCardW,
      selected: _humanExchangeChoice,
      onTapCard: done ? null : (c) => setState(() => _humanExchangeChoice = c),
      givenCard: givenCard,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: _state.variant.feltColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          Text(
            done
                ? _waitingText(state, me)
                : 'Vælg ét kort til din makker (skjult bytte)',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 8),
          cards,
          if (!done) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _humanExchangeChoice == null
                  ? null
                  : () {
                      widget.onSubmitExchange(me.index, _humanExchangeChoice!);
                      setState(() => _humanExchangeChoice = null);
                    },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Bekræft bytte'),
            ),
          ],
        ],
      ),
    );
  }

  /// Hvem mangler at afgive et kort i byttet? Vis navnene tydeligt.
  String _waitingText(GameState state, Player me) {
    final missing = <String>[
      for (final Player p in state.players)
        if (!state.exchangeBuffer.containsKey(p.index)) p.name,
    ];
    if (missing.isEmpty) return 'Bytter kort…';
    return 'Venter på: ${missing.join(', ')}';
  }

  Widget _buildPlayArea(GameState state, Player me, {required bool fill}) {
    final bool myTurn = state.currentPlayerIndex == me.index;
    final rules = Rules(state.geometry);
    // canPlay kører hele move-generatoren for hånden — memoiseret pr.
    // (hånd, tur, brætrunde), for build() kaldes ~30×/s under animationer,
    // og brættet kan ikke ændre sig inden for samme (tur, håndstørrelse).
    final String canPlayKey =
        '${state.handNumber}|${state.currentPlayerIndex}|${me.hand.length}';
    final bool canPlay;
    if (myTurn) {
      if (_canPlayKey != canPlayKey) {
        _canPlayKey = canPlayKey;
        _canPlayMemo =
            me.hand.any((c) => rules.legalMoves(state, me, c).isNotEmpty);
      }
      canPlay = _canPlayMemo;
    } else {
      _canPlayKey = null;
      canPlay = false;
    }
    String? overrideStatus = widget.bottomStatusOverride;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: _state.variant.feltColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (overrideStatus != null)
            Text(overrideStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 13))
          else if (!myTurn)
            Text('${state.currentPlayer.name} spiller…',
                style: const TextStyle(color: Colors.white, fontSize: 13))
          else if (myTurn && canPlay)
            _statusRow(state)
          else if (myTurn && !canPlay)
            Text('Du kan ikke rykke nogen brik',
                style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
          const SizedBox(height: 8),
          _handCards(
            state: state,
            hand: me.hand,
            // Dine egne kort er ALTID face-up — også når det ikke er din tur,
            // så du kan planlægge dit næste træk. Dimming markerer i stedet
            // at hånden ikke er tap-bar lige nu.
            faceUp: true,
            maxCardW: fill ? 84 : 48,
            selected: _selectedCard,
            onTapCard: (!myTurn || !canPlay)
                ? null
                : (c) => _selectCard(state, me, c),
            dim: !myTurn,
          ),
          if (myTurn && !canPlay)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: () => widget.onPass(me.index),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Smid kortene og sid over'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusRow(GameState state) {
    final card = _selectedCard;
    String label;
    if (card == null) {
      label = 'Vælg et kort';
    } else if (_isSplitCard(state, card)) {
      final int rem = _splitRemaining(state);
      label = _splitPath.isEmpty
          ? 'Vælg første brik ($rem træk tilbage)'
          : '$rem træk tilbage — vælg næste brik eller bekræft';
    } else if (_isMultiPieceCard(state, card)) {
      // Multi-brik-kort (fx 1×1): tæl BRIKKER, ikke felter — "11 træk
      // tilbage" ville være nonsens her.
      final cfg = state.cardRules.forRank(card.rank!);
      final int n = cfg.multiPieces ?? 2;
      final int st = cfg.multiSteps ?? 1;
      label = _splitPath.isEmpty
          ? 'Vælg en brik (gult = lovligt træk)'
          : 'Vælg brik ${_splitPath.length + 1} af $n ($st frem hver)';
    } else if (_swapFlowActive(state, card)) {
      label = _swapFirstPiece == null
          ? 'Byt: vælg den første af to brikker'
          : 'Byt: vælg brikken der byttes med';
    } else if (!card.isExit && state.cardRules.forRank(card.rank!).swap) {
      // Hybrid-kort i FLYT-tilstand: sig tilstanden, så den ikke er usynlig.
      label = 'Flyt: vælg en brik (gult = lovligt træk)';
    } else {
      label = 'Vælg en brik (gult = lovligt træk)';
    }
    // Hybrid-kort (byt + bevægelse): giv en synlig vej til at skifte tilstand
    // — ellers er gen-tap på kortet den eneste (usynlige) vej tilbage.
    final bool isHybrid = card != null &&
        !card.isExit &&
        state.cardRules.forRank(card.rank!).swap &&
        !_isSwapCard(state, card);
    final bool isMultiStep = card != null && _isMultiPieceCard(state, card);
    final bool canCommit = isMultiStep && _firstFullyMatching() != null;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        if (isHybrid)
          TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                foregroundColor: Colors.amber),
            onPressed: () => _chooseHybridMode(card),
            child: const Text('Skift'),
          ),
        if (isMultiStep && _splitPath.isNotEmpty) ...<Widget>[
          if (canCommit)
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  backgroundColor: const Color(0xFF43A047)),
              onPressed: _commitSplit,
              child: const Text('Bekræft'),
            ),
          TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                foregroundColor: Colors.amber),
            onPressed: () => setState(() => _splitPath.clear()),
            child: const Text('Annullér'),
          ),
        ],
      ],
    );
  }

  Widget _handCards({
    required GameState state,
    required List<PlayingCard> hand,
    required bool faceUp,
    required double maxCardW,
    required PlayingCard? selected,
    required void Function(PlayingCard)? onTapCard,
    bool dim = false,
    PlayingCard? givenCard, // markeres som "afgivet" (kortbytte)
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int n = hand.isEmpty ? 1 : hand.length;
        const double gap = 6;
        double cardW = (c.maxWidth - gap * n) / n;
        if (cardW > maxCardW) cardW = maxCardW;
        if (cardW < 32) cardW = 32;
        bool givenUsed = false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (final PlayingCard card in hand)
              Builder(builder: (_) {
                // Markér KUN det første match, så to ens kort ikke begge
                // markeres når man kun har afgivet det ene.
                final bool isGiven =
                    !givenUsed && givenCard != null && card == givenCard;
                if (isGiven) givenUsed = true;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                  child: Opacity(
                    opacity: isGiven ? 0.5 : (dim ? 0.55 : 1.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CardView(
                          card: card,
                          rules: state.cardRules,
                          faceUp: faceUp,
                          width: cardW,
                          selected: selected == card,
                          onTap:
                              onTapCard == null ? null : () => onTapCard(card),
                        ),
                        if (isGiven)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5E3C),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('AFGIVET',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tap-håndtering: vælg kort, brik, split-7, byt, multi-valg
  // ---------------------------------------------------------------------------

  void _selectCard(GameState state, Player me, PlayingCard c) {
    final rules = Rules(state.geometry);
    final List<Move> moves = rules.legalMoves(state, me, c);
    setState(() {
      _selectedCard = c;
      _candidateMoves = moves;
      _swapFirstPiece = null;
      _hybridSwapMode = false;
      _splitPath.clear();
    });
    // Hybrid-kort (25 års "Byt ELLER 9"): kortet har BÅDE byt og bevægelse.
    // Uden et eksplicit valg ville byt-parrene forurene det generiske flow
    // (modstander-brikker highlightet, byt beskrevet som geometri). Spejl
    // kortets "ELLER": spørg om tilstand med det samme.
    if (!c.isExit) {
      final cfg = state.cardRules.forRank(c.rank!);
      if (cfg.swap && !_isSwapCard(state, c)) {
        final bool hasSwaps = moves.any(_isSwapMove);
        final bool hasOthers = moves.any((Move m) => !_isSwapMove(m));
        if (hasSwaps && hasOthers) {
          _chooseHybridMode(c);
        } else if (hasSwaps) {
          setState(() => _hybridSwapMode = true);
        }
      }
    }
  }

  /// Positiv byt-genkendelse — delegerer til den ENE delte vagt i
  /// models/move.dart (isSwapMove), så UI-routing, lyd og stats aldrig driver
  /// fra hinanden.
  bool _isSwapMove(Move m) => isSwapMove(m);

  Future<void> _chooseHybridMode(PlayingCard c) async {
    final bool? swapMode = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _grabber(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('Hvad vil du bruge kortet til?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_forward),
              title: const Text('Flyt en brik',
                  style: TextStyle(fontSize: 16, color: Colors.black87)),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Byt to brikker',
                  style: TextStyle(fontSize: 16, color: Colors.black87)),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (!mounted || _selectedCard != c) return;
    setState(() => _hybridSwapMode = swapMode ?? false);
  }

  /// Er byt-flowet aktivt for det valgte kort? Rene byt-kort altid; hybrid-
  /// kort kun når spilleren har valgt byt-tilstanden.
  bool _swapFlowActive(GameState state, PlayingCard c) =>
      _isSwapCard(state, c) || _hybridSwapMode;

  bool _isSwapCard(GameState state, PlayingCard c) {
    if (c.isExit) return false;
    final cfg = state.cardRules.forRank(c.rank!);
    // RENT byt-kort = ingen andre evner. Uden multi/sekvens-tjekkene ville
    // et admin-kort med byt+multi låse multi-trækkene ude (byt-flowet ville
    // altid være aktivt, og tilstands-arket aldrig vist).
    return cfg.swap &&
        cfg.forwardSteps.isEmpty &&
        cfg.backwardSteps == null &&
        cfg.splitTotal == null &&
        !cfg.hasMultiForward &&
        !cfg.hasFwdThenBack &&
        !cfg.exitStart;
  }

  bool _isSplitCard(GameState state, PlayingCard c) {
    if (c.isExit) return false;
    final cfg = state.cardRules.forRank(c.rank!);
    return cfg.splitTotal != null;
  }

  /// Kort hvis træk vælges brik-for-brik ad splittens flertrins-flow: split
  /// (7×1/4×1) OG multi-brik (1×1). Bruges til ROUTING; _isSplitCard bruges
  /// fortsat til tælle-teksten.
  bool _isMultiPieceCard(GameState state, PlayingCard c) {
    if (c.isExit) return false;
    final cfg = state.cardRules.forRank(c.rank!);
    return cfg.splitTotal != null || cfg.hasMultiForward;
  }

  Set<String> _highlightSet(GameState state) {
    final card = _selectedCard;
    if (card != null && _swapFlowActive(state, card)) {
      // Kun BYT-parrene (positivt genkendt) — på et hybrid-kort må 9-frem-
      // trækkene ikke blande sig i byt-highlighten.
      final List<Move> swaps =
          _candidateMoves.where(_isSwapMove).toList();
      if (_swapFirstPiece == null) {
        return <String>{
          for (final m in swaps)
            for (final s in m.steps) s.pieceId,
        };
      }
      final set = <String>{_swapFirstPiece!};
      for (final m in swaps) {
        final ids = m.steps.map((s) => s.pieceId).toList();
        if (ids.contains(_swapFirstPiece)) {
          set.addAll(ids.where((id) => id != _swapFirstPiece));
        }
      }
      return set;
    }
    if (card != null && _isMultiPieceCard(state, card)) {
      // Højlight ALLE brikker der kan vælges som næste delskridt — uanset
      // hvor i m.steps de står. Brikker der allerede er valgt udelukkes.
      final Set<String> alreadyChosen = <String>{
        for (final MoveStep s in _splitPath) s.pieceId,
      };
      final List<Move> matching = _splitMatchingMoves();
      return <String>{
        for (final Move m in matching)
          for (final MoveStep s in m.steps)
            if (!alreadyChosen.contains(s.pieceId)) s.pieceId,
      };
    }
    return <String>{
      for (final m in _candidateMoves)
        if (!_isSwapMove(m)) m.steps.first.pieceId,
    };
  }

  /// Et move matcher hvis hver (pieceId, destination) i _splitPath findes
  /// SOMEWHERE i m.steps — rækkefølgen i UI er fri. Byt-par (positivt
  /// genkendt) hører aldrig til i dette flow, uanset admin-kombination.
  List<Move> _splitMatchingMoves() {
    return _candidateMoves.where((Move m) => !_isSwapMove(m)).where((Move m) {
      if (m.steps.length < _splitPath.length) return false;
      for (final MoveStep p in _splitPath) {
        final bool found = m.steps.any((MoveStep s) =>
            s.pieceId == p.pieceId && _posKey(s.to) == _posKey(p.to));
        if (!found) return false;
      }
      return true;
    }).toList();
  }

  String _posKey(PiecePosition p) {
    if (p is TrackPosition) return 'T${p.index}';
    if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
    if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
    return '?';
  }

  /// Maks. felter der stadig kan rykkes på en MATCHING fordeling. Når flere
  /// sums er gyldige (fx både [A=1, B=4]=5 og [A=1, B=5]=6), viser vi det
  /// største — brugeren kan altid trykke 'Bekræft' tidligere hvis de er
  /// tilfredse.
  int _splitRemaining(GameState state) {
    final List<Move> matching = _splitMatchingMoves();
    final List<Move> pool =
        matching.isEmpty ? _candidateMoves : matching;
    if (pool.isEmpty) return 0;
    int used = 0;
    for (final MoveStep s in _splitPath) {
      used += _stepDistance(state, s);
    }
    int maxRemaining = 0;
    for (final Move m in pool) {
      int total = 0;
      for (final MoveStep s in m.steps) {
        total += _stepDistance(state, s);
      }
      final int r = total - used;
      if (r > maxRemaining) maxRemaining = r;
    }
    return maxRemaining;
  }

  /// Antal TÆLLENDE felter et delskridt udgør. UD-felter tæller ikke (§6), så
  /// vi går ringen igennem og springer dem over — ellers ville et skridt der
  /// krydser et fremmed UD blive vist med ét felt for meget.
  int _stepDistance(GameState state, MoveStep s) {
    final from = s.from;
    final to = s.to;
    final int len = state.geometry.trackLength;
    final int q = len ~/ 4;
    if (from is TrackPosition && to is TrackPosition) {
      int idx = from.index;
      int count = 0;
      while (idx != to.index && count <= len) {
        idx = (idx + 1) % len;
        if (idx % q == 0) continue; // UD-felt: tæller ikke
        count++;
        if (idx == to.index) break;
      }
      return count;
    }
    if (from is TrackPosition && to is HomeStretchPosition) {
      final int entry = state.geometry.startTrackIndexFor(to.ownerIndex);
      int idx = from.index;
      int count = 0;
      // Gå frem til feltet lige før ejerens eget UD (entry); UD-felter
      // undervejs tæller ikke. Drej så ind i hjemstrækket: +1 for at nå slot 0
      // og + slot for resten.
      while (count <= len) {
        final int next = (idx + 1) % len;
        if (next == entry) return count + to.slot + 1;
        idx = next;
        if (idx % q == 0) continue; // fremmed UD
        count++;
      }
      return count + to.slot + 1;
    }
    if (from is HomeStretchPosition && to is HomeStretchPosition) {
      return to.slot - from.slot;
    }
    return 0;
  }

  void _handlePieceTap(GameState state, String pieceId) {
    if (state.currentPlayerIndex != _mySeat) return;
    if (_selectedCard == null) return;
    if (_swapFlowActive(state, _selectedCard!)) {
      _handleSwapTap(state, pieceId);
      return;
    }
    if (_isMultiPieceCard(state, _selectedCard!)) {
      _handleSplitTap(state, pieceId);
      return;
    }
    // Byt-par (hybrid-kortets anden tilstand) hører ikke hjemme i det
    // generiske flow — de vælges via byt-tilstanden.
    final List<Move> matching = _candidateMoves
        .where((Move m) =>
            !_isSwapMove(m) && m.steps.first.pieceId == pieceId)
        .toList();
    if (matching.isEmpty) return;
    if (matching.length == 1) {
      widget.onApplyMove(_mySeat, matching.first);
    } else {
      _showMoveChoice(state, matching);
    }
  }

  Future<void> _handleSplitTap(GameState state, String pieceId) async {
    final List<Move> matching = _splitMatchingMoves();
    final Set<String> alreadyChosen = <String>{
      for (final MoveStep s in _splitPath) s.pieceId,
    };
    if (alreadyChosen.contains(pieceId)) return;
    final Map<String, MoveStep> byKey = <String, MoveStep>{};
    for (final Move m in matching) {
      for (final MoveStep s in m.steps) {
        if (s.pieceId != pieceId) continue;
        if (alreadyChosen.contains(s.pieceId)) continue;
        final String key = _posKey(s.to);
        byKey.putIfAbsent(key, () => s);
      }
    }
    if (byKey.isEmpty) return;

    MoveStep? chosen;
    if (byKey.length == 1) {
      chosen = byKey.values.first;
    } else {
      chosen = await _chooseSplitStep(state, byKey.values.toList());
    }
    if (chosen == null || !mounted) return;

    setState(() => _splitPath.add(chosen!));

    // Auto-anvend KUN hvis der ikke kan tilføjes flere brikker — dvs. ingen
    // matchende moves har FLERE steps end vi allerede har valgt. Hvis der
    // stadig kan tilføjes (typisk fordi vi inkluderer alle sums 1..7, så fx
    // sum=1 [A alene] og sum=5 [A+B] begge er valide), venter vi på
    // brugeren — de kan tappe flere brikker eller trykke 'Bekræft' for at
    // afslutte med den nuværende delvise split.
    final bool canExtend = _candidateMoves.any((Move m) {
      if (m.steps.length <= _splitPath.length) return false;
      return _moveMatchesPath(m);
    });
    if (!canExtend) {
      final Move? commit = _firstFullyMatching();
      if (commit != null) widget.onApplyMove(_mySeat, commit);
    }
  }

  /// Forsigtighed: sæt-baseret check at et move indeholder ALT i _splitPath.
  bool _moveMatchesPath(Move m) {
    for (final MoveStep p in _splitPath) {
      final bool found = m.steps.any((MoveStep s) =>
          s.pieceId == p.pieceId && _posKey(s.to) == _posKey(p.to));
      if (!found) return false;
    }
    return true;
  }

  /// Det første move hvor præcis vores valgte sti er hele move'et.
  Move? _firstFullyMatching() {
    for (final Move m in _candidateMoves) {
      if (m.steps.length != _splitPath.length) continue;
      if (_moveMatchesPath(m)) return m;
    }
    return null;
  }

  /// Bekræft den nuværende delvise split. Bruges af 'Bekræft'-knappen når
  /// brugeren vil afslutte 7'eren tidligere end nogle af de længere match.
  void _commitSplit() {
    final Move? commit = _firstFullyMatching();
    if (commit != null) widget.onApplyMove(_mySeat, commit);
  }

  Future<MoveStep?> _chooseSplitStep(
      GameState state, List<MoveStep> options) async {
    options.sort(
        (a, b) => _stepDistance(state, a).compareTo(_stepDistance(state, b)));
    return showModalBottomSheet<MoveStep>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _grabber(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Hvor mange felter?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, int i) {
                    final s = options[i];
                    final int d = _stepDistance(state, s);
                    final String label = (s.to is HomeStretchPosition
                            ? '$d ind i hjemstrækket (slot ${(s.to as HomeStretchPosition).slot + 1})'
                            : '$d frem') +
                        _captureNote(state, s);
                    return ListTile(
                      title: Text(label,
                          style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500)),
                      onTap: () => Navigator.of(ctx).pop(s),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSwapTap(GameState state, String pieceId) {
    // Kun de positivt genkendte byt-par — på et hybrid-kort må et 9-frem-træk
    // aldrig kunne "findes" som byt.
    final List<Move> swaps = _candidateMoves.where(_isSwapMove).toList();
    if (_swapFirstPiece == null) {
      final participates =
          swaps.any((m) => m.steps.any((s) => s.pieceId == pieceId));
      if (participates) setState(() => _swapFirstPiece = pieceId);
      return;
    }
    if (pieceId == _swapFirstPiece) {
      setState(() => _swapFirstPiece = null);
      return;
    }
    Move? found;
    for (final m in swaps) {
      final ids = m.steps.map((s) => s.pieceId).toSet();
      if (ids.contains(_swapFirstPiece) && ids.contains(pieceId)) {
        found = m;
        break;
      }
    }
    if (found != null) _confirmSwap(state, found);
  }

  String _pieceLocation(GameState state, Piece p) {
    final PiecePosition pos = p.position;
    if (pos is StartPosition) return 'i start';
    if (pos is HomeStretchPosition) return 'i hjemmet (felt ${pos.slot + 1})';
    if (pos is TrackPosition) {
      final int quarter = state.geometry.trackLength ~/ 4;
      final int field = pos.index % quarter;
      return field == 0 ? 'på UD-feltet' : 'på felt $field';
    }
    return '';
  }

  Future<void> _confirmSwap(GameState state, Move move) async {
    final a = state.pieceById(move.steps[0].pieceId);
    final b = state.pieceById(move.steps[1].pieceId);
    final String an = state.players[a.ownerIndex].name;
    final String bn = state.players[b.ownerIndex].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Byt brikker?'),
        content: Text('Byt $an-brikken ${_pieceLocation(state, a)} '
            'med $bn-brikken ${_pieceLocation(state, b)}?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annullér')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Byt')),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _swapFirstPiece = null);
    if (ok == true) widget.onApplyMove(_mySeat, move);
  }

  Future<void> _showMoveChoice(GameState state, List<Move> options) async {
    final Map<String, Move> byEffect = <String, Move>{};
    for (final Move m in options) {
      byEffect.putIfAbsent(_describeMove(state, m), () => m);
    }
    final entries = byEffect.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final Move? chosen = await showModalBottomSheet<Move>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _grabber(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Vælg træk',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, int i) => ListTile(
                    title: Text(entries[i].key,
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500)),
                    onTap: () => Navigator.of(ctx).pop(entries[i].value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) widget.onApplyMove(_mySeat, chosen);
  }

  String _describeMove(GameState state, Move m) {
    if (m.exitsStart) return 'Gå ud af start';
    if (m.steps.length == 1) {
      return _describeStep(state, m.steps.first) +
          _captureNote(state, m.steps.first);
    }
    if (_isSwapMove(m)) {
      final a = state.pieceById(m.steps[0].pieceId);
      final b = state.pieceById(m.steps[1].pieceId);
      return 'Byt ${state.players[a.ownerIndex].name}-brikken med '
          '${state.players[b.ownerIndex].name}-brikken';
    }
    final bool samePiece =
        m.steps.every((MoveStep s) => s.pieceId == m.steps.first.pieceId);
    if (samePiece) {
      // Sekvens-træk (fx +2−5): RÆKKEFØLGEN er pointen — sortér ikke, og
      // nævn slagene, for de er grunden til at vælge sekvensen frem for
      // det lige træk.
      return m.steps
          .map((MoveStep s) =>
              _describeStep(state, s) + _captureNote(state, s))
          .join(', så ');
    }
    final List<String> parts = m.steps
        .map((s) => _describeStep(state, s) + _captureNote(state, s))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return parts.join(' + ');
  }

  /// " — slår Gul hjem" / " — brænder (egen brik hjem)" når steppet har en
  /// konsekvens; ellers tom. Konsekvensen skal stå i valg-arket — den er
  /// usynlig på brættet, indtil trækket er gjort.
  String _captureNote(GameState state, MoveStep s) {
    if (s.burnsMover) return ' — brænder (egen brik hjem)';
    if (s.capturedPieceId == null) return '';
    final Piece captured = state.pieceById(s.capturedPieceId!);
    return ' — slår ${state.players[captured.ownerIndex].name} hjem';
  }

  String _describeStep(GameState state, MoveStep s) {
    final from = s.from;
    final to = s.to;
    if (from is StartPosition && to is TrackPosition) return 'ud af start';
    if (to is HomeStretchPosition) return 'hjem (felt ${to.slot + 1})';
    if (from is TrackPosition && to is TrackPosition) {
      // Tæl TÆLLENDE felter (UD-felter springes over, §6) i begge retninger —
      // et rå indeks-delta ville vise fx "-6" for et 5-tilbage der krydser
      // et UD-felt.
      final int len = state.geometry.trackLength;
      final int q = len ~/ 4;
      int count(int fromIdx, int toIdx, int dir) {
        int idx = fromIdx;
        int c = 0;
        while (idx != toIdx && c <= len) {
          idx = (idx + dir + len) % len;
          if (idx % q == 0) continue; // UD-felt: tæller ikke
          c++;
          if (idx == toIdx) break;
        }
        return c;
      }
      if (from.index == to.index) return 'bliv stå';
      final int fwd = count(from.index, to.index, 1);
      final int back = count(from.index, to.index, -1);
      return fwd <= back ? '$fwd frem' : '$back tilbage';
    }
    return 'træk';
  }

  Widget _grabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SpectatorView extends StatelessWidget {
  const _SpectatorView(
      {required this.state, required this.lastPlayedCards});
  final GameState state;
  final Map<int, PlayingCard> lastPlayedCards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: BoardView(state: state, viewerIndex: 0),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: state.variant.feltColor,
          padding: const EdgeInsets.all(12),
          child: const Text('Du ser med (ikke din plads).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
