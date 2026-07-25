import 'dart:convert';
import 'dart:math';

// Skjul Firestores 'Settings' så vores egen Settings-model (settings_controller)
// ikke giver navnekollision (ambiguous_import).
import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'game/ai/ai_player.dart';
import 'game/card_rules.dart';
import 'game/deck.dart';
import 'game/game_engine.dart';
import 'models/board.dart';
import 'models/game_state.dart';
import 'models/move.dart';
import 'models/piece.dart';
import 'models/player.dart';
import 'models/playing_card.dart';
import 'online/online_service.dart';
import 'online/push_service.dart';
import 'online/serialize.dart';
import 'state/settings_controller.dart';
import 'stats/stats_repository.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/online_game_screen.dart';
import 'ui/screens/online_screens.dart';

/// Letvægts-info om et gemt, igangværende spil — bruges af forsiden til at
/// vise en "Fortsæt spil"-knap uden at genskabe hele [GameState].
class SavedGameInfo {
  SavedGameInfo({
    required this.names,
    required this.handNumber,
    required this.savedAt,
    required this.raw,
  });

  final List<String> names;
  final int handNumber;
  final DateTime savedAt;
  final Map<String, dynamic> raw;
}

class PlayerSetup {
  PlayerSetup({
    required this.name,
    required this.color,
    required this.isHuman,
  });
  final String name;
  final Color color;
  final bool isHuman;
}

final StateNotifierProvider<GameController, GameState> gameProvider =
    StateNotifierProvider<GameController, GameState>(
  (ref) => GameController(),
);

/// Kigger efter et gemt, igangværende lokalt spil (til "Fortsæt spil" på
/// forsiden). Invalidér provideren efter at have startet/genoptaget et spil
/// for at få frisk status.
final FutureProvider<SavedGameInfo?> savedGameProvider =
    FutureProvider<SavedGameInfo?>((ref) => GameController.peekSavedGame());

class GameController extends StateNotifier<GameState> {
  GameController() : super(_emptyState());

  GameEngine? _engine;
  final Uuid _uuid = const Uuid();
  final Random _rng = Random();

  /// Spillerens valgte AI-sværhedsgrad for det lokale spil (0/1/2). Læses af
  /// game_screen når AI'en skal handle. Parametrene bag graden sættes af admin.
  int aiLevel = kAiLevelDefault;

  // Træk-log for AI-spil (svarende til online-spillets log).
  final List<Map<String, dynamic>> _aiLog = <Map<String, dynamic>>[];
  String? _aiGameCode;
  bool _aiSavedAtEnd = false;
  String? _aiHostUid;
  String? _aiHostName;

  /// Offentlig adgang til den aktuelle state (StateNotifier.state er protected).
  GameState get currentState => state;

  /// Nøgle til lokal autosave af et igangværende AI-/lokalt spil.
  static const String _saveKey = 'saved_game_v1';

  static GameState _emptyState() {
    return GameState(
      players: <Player>[],
      geometry: const BoardGeometry(),
      deck: <PlayingCard>[],
      discard: <PlayingCard>[],
      dealerIndex: 0,
      currentPlayerIndex: 0,
      phase: GamePhase.setup,
      handNumber: 0,
    );
  }

  void startGame(List<PlayerSetup> setups,
      {CardRules? cardRules, int aiLevel = kAiLevelDefault}) {
    this.aiLevel = aiLevel;
    const BoardGeometry geom = BoardGeometry();
    final List<Player> players = <Player>[
      for (int i = 0; i < setups.length; i++)
        Player(
          index: i,
          name: setups[i].name,
          color: setups[i].color,
          isHuman: setups[i].isHuman,
          pieces: <Piece>[
            for (int s = 0; s < 4; s++)
              Piece(
                id: 'p$i.$s',
                ownerIndex: i,
                position: StartPosition(i, s),
              ),
          ],
        ),
    ];
    // Tilfældig start-spiller, så det ikke altid er den samme (plads 0) der
    // starter et nyt spil.
    final int starter = _rng.nextInt(players.length);
    final GameState s = GameState(
      players: players,
      geometry: geom,
      deck: Deck.fresh(),
      discard: <PlayingCard>[],
      dealerIndex: starter,
      currentPlayerIndex: starter,
      phase: GamePhase.setup,
      handNumber: 0,
      starterIndex: starter,
      cardRules: cardRules,
    );
    _engine = GameEngine(state: s, rng: _rng);
    _aiLog.clear();
    _aiGameCode = 'AI-${_uuid.v4().substring(0, 6).toUpperCase()}';
    _aiSavedAtEnd = false;
    final fbUser = FirebaseAuth.instance.currentUser;
    _aiHostUid = fbUser?.uid;
    _aiHostName = fbUser?.displayName ?? fbUser?.email ?? 'Spiller';
    state = s;
  }

  void startHand() {
    _engine?.startNewHand();
    state = _engine!.state;
    _bump();
  }

  void submitExchange(int playerIndex, PlayingCard card) {
    _engine?.submitExchangeCard(playerIndex, card);
    _bump();
  }

  List<Move> legalMovesFor(int playerIndex, PlayingCard card) {
    return _engine?.legalMovesFor(playerIndex, card) ?? const <Move>[];
  }

  void applyMove(int playerIndex, Move move) {
    _engine?.applyMove(playerIndex, move);
    _aiLog.add(_withTimestamp(moveLogEntry(playerIndex, move)));
    _bump();
  }

  bool canPlay(int playerIndex) => _engine?.canPlay(playerIndex) ?? false;

  void passHand(int playerIndex) {
    final int discarded = _engine?.state.players[playerIndex].hand.length ?? 0;
    _engine?.passHand(playerIndex);
    _aiLog.add(_withTimestamp(passLogEntry(playerIndex, discarded)));
    _bump();
  }

  Map<String, dynamic> _withTimestamp(Map<String, dynamic> entry) {
    return <String, dynamic>{...entry, 't': Timestamp.now()};
  }

  Future<void> _persistFinishedAiGame() async {
    if (_aiSavedAtEnd) return;
    if (_engine == null) return;
    final s = _engine!.state;
    if (s.winningTeamIndex == null) return;
    final uid = _aiHostUid;
    if (uid == null) return; // ikke logget ind → kan ikke skrive
    _aiSavedAtEnd = true;
    try {
      final code = _aiGameCode ?? 'AI-${_uuid.v4().substring(0, 6)}';
      await firestore.collection('games').doc(code).set(<String, dynamic>{
        'status': 'over',
        'hostUid': uid,
        'hostName': _aiHostName,
        'names': s.players.map((p) => p.name).toList(),
        'colors': s.players.map((p) => p.color.toARGB32()).toList(),
        // Kun værten har en uid; AI-pladserne er null.
        'uids':
            s.players.map((p) => p.isHuman ? uid : null).toList(),
        'members': <String>[uid],
        'invitedUids': <String>[],
        'cardRules': s.cardRules.toJson(),
        'state': gameStateToMap(s),
        'log': _aiLog,
        'winningTeamIndex': s.winningTeamIndex,
        'createdAt': FieldValue.serverTimestamp(),
        'finishedAt': FieldValue.serverTimestamp(),
        'mode': 'ai',
      });
      // Genberegn stats-cachen så profilen opdaterer sig — kun værtens egen
      // doc (AI-pladser har ingen uid). Firestore-reglerne tillader ikke at
      // skrive andres userStats.
      // ignore: discarded_futures
      StatsRepository().recomputeAndSaveOwn(uid);
    } catch (e) {
      debugPrint('[AI persist] $e');
    }
  }

  void reset() {
    _engine = null;
    state = _emptyState();
    // ignore: discarded_futures
    _clearSave();
  }

  /// Slet et gemt (igangværende) lokalt AI-spil uden at starte det. Bruges fra
  /// forsiden når brugeren vil kassere et hængende spil.
  Future<void> discardSavedGame() async {
    await _clearSave();
  }

  // ---------------------------------------------------------------------------
  // Autosave / genoptag (kun lokale AI-spil)
  // ---------------------------------------------------------------------------

  /// Log-indlæg gøres JSON-venligt til lokal lagring (Timestamp → millis).
  /// Ved genskab læses 't' som int; stats-modulet håndterer både int og
  /// Timestamp, så det er sikkert at blande gamle og nye indlæg.
  Map<String, dynamic> _logEntryForStorage(Map<String, dynamic> e) {
    final Map<String, dynamic> copy = Map<String, dynamic>.from(e);
    final t = copy['t'];
    if (t is Timestamp) copy['t'] = t.millisecondsSinceEpoch;
    return copy;
  }

  /// Gem det aktuelle spil lokalt, så det kan genoptages. Gemmer kun spil der
  /// reelt er i gang (ikke opsætning eller afsluttet). Fejler stille.
  void _autosave() {
    final GameEngine? e = _engine;
    if (e == null) return;
    final GameState s = e.state;
    if (s.phase == GamePhase.setup || s.winningTeamIndex != null) return;
    final Map<String, dynamic> payload = <String, dynamic>{
      'state': gameStateToMap(s),
      'log': _aiLog.map(_logEntryForStorage).toList(),
      'code': _aiGameCode,
      'hostUid': _aiHostUid,
      'hostName': _aiHostName,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    SharedPreferences.getInstance().then((sp) {
      sp.setString(_saveKey, jsonEncode(payload));
    }).catchError((Object e) {
      debugPrint('[autosave] $e');
    });
  }

  Future<void> _clearSave() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_saveKey);
    } catch (_) {
      // Ligegyldigt hvis det fejler — et forældet save overskrives ved næste spil.
    }
  }

  /// Kig efter et gemt, igangværende spil (uden at genskabe det). Returnerer
  /// null hvis der ikke findes et brugbart save.
  static Future<SavedGameInfo?> peekSavedGame() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_saveKey);
      if (raw == null) return null;
      final Map<String, dynamic> map =
          Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final Map<String, dynamic> state =
          Map<String, dynamic>.from(map['state'] as Map);
      final List<dynamic> players = state['pl'] as List;
      final List<String> names =
          players.map((p) => (p as Map)['n'] as String).toList();
      final int hn = (state['hn'] as num?)?.toInt() ?? 0;
      final DateTime savedAt = DateTime.fromMillisecondsSinceEpoch(
          (map['savedAt'] as num?)?.toInt() ?? 0);
      return SavedGameInfo(
          names: names, handNumber: hn, savedAt: savedAt, raw: map);
    } catch (_) {
      return null;
    }
  }

  /// Genskab et tidligere gemt spil ind i controlleren. Returnerer false hvis
  /// save'et ikke kunne deserialiseres (fx et gammelt format fra før nye
  /// felter blev tilføjet) — så rydder vi det korrupte save så knappen
  /// forsvinder i stedet for at crashe hver gang.
  bool resumeFrom(SavedGameInfo info) {
    try {
      final Map<String, dynamic> map = info.raw;
      final GameState s =
          gameStateFromMap(Map<String, dynamic>.from(map['state'] as Map));
      _engine = GameEngine(state: s, rng: _rng);
      _aiLog
        ..clear()
        ..addAll((map['log'] as List? ?? const <dynamic>[])
            .map((e) => Map<String, dynamic>.from(e as Map)));
      _aiGameCode = map['code'] as String?;
      _aiHostUid = map['hostUid'] as String?;
      _aiHostName = map['hostName'] as String?;
      _aiSavedAtEnd = false;
      state = s;
      return true;
    } catch (e) {
      debugPrint('[resume] kunne ikke genskabe save: $e');
      // ignore: discarded_futures
      _clearSave();
      return false;
    }
  }

  void _bump() {
    if (_engine == null) return;
    // Tving Riverpod til at notificere ved at lave en kopi af staten. VIGTIGT:
    // vi DYB-kopierer spillere + brikker. Ellers ville hver snapshot dele de
    // samme muterbare Piece-objekter som motoren flytter in-place, og
    // GamePlayView's animation (der sammenligner forrige vs. ny briks position
    // i didUpdateWidget) ville ALDRIG se en ændring → ingen animation lokalt.
    final GameState e = _engine!.state;
    state = GameState(
      players: e.players
          .map((Player p) => Player(
                index: p.index,
                name: p.name,
                color: p.color,
                isHuman: p.isHuman,
                pieces: p.pieces.map((Piece pi) => pi.copy()).toList(),
                hand: List<PlayingCard>.from(p.hand),
              ))
          .toList(),
      geometry: e.geometry,
      deck: e.deck,
      discard: e.discard,
      dealerIndex: e.dealerIndex,
      currentPlayerIndex: e.currentPlayerIndex,
      phase: e.phase,
      handNumber: e.handNumber,
      winningTeamIndex: e.winningTeamIndex,
      starterIndex: e.starterIndex,
      starterStreak: e.starterStreak,
      starterCounts: List<int>.from(e.starterCounts),
      cardRules: e.cardRules,
      exchangeBuffer: Map<int, PlayingCard?>.from(e.exchangeBuffer),
    );
    // Når spillet lige er afsluttet, persistér det til Firestore for stats og
    // ryd den lokale autosave. Ellers gem løbende så spillet kan genoptages.
    if (e.winningTeamIndex != null) {
      // ignore: discarded_futures
      _persistFinishedAiGame();
      // ignore: discarded_futures
      _clearSave();
    } else {
      _autosave();
    }
  }
}

/// Global nøgle så foregrund-push-beskeder kan vise en SnackBar uanset
/// hvilken skærm der er øverst.
final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Global navigator-nøgle så et notifikations-deeplink (?game=/?invite=) kan
/// navigere ind i spillet uanset hvilken skærm der er øverst.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class PartnersApp extends ConsumerStatefulWidget {
  const PartnersApp({super.key});

  @override
  ConsumerState<PartnersApp> createState() => _PartnersAppState();
}

class _PartnersAppState extends ConsumerState<PartnersApp> {
  // Ventende deeplink fra opstarts-URL'en (?game=<code> / ?invite=<code>).
  String? _pendingCode;
  bool _pendingIsGame = false;
  bool _linkHandled = false;

  @override
  void initState() {
    super.initState();
    _readInitialDeepLink();
  }

  /// Læs ?game=/?invite= fra URL'en appen blev åbnet med (fx fra et
  /// notifikationsklik der åbnede /?game=<code>).
  void _readInitialDeepLink() {
    try {
      final Map<String, String> q = Uri.base.queryParameters;
      final String? game = _sanitizeCode(q['game']);
      final String? invite = _sanitizeCode(q['invite']);
      if (game != null) {
        _pendingCode = game;
        _pendingIsGame = true;
      } else if (invite != null) {
        _pendingCode = invite;
        _pendingIsGame = false;
      }
    } catch (_) {
      // URL-parsing må aldrig fælde opstarten.
    }
  }

  static String? _sanitizeCode(String? raw) {
    if (raw == null) return null;
    final String v = raw.trim();
    if (v.isEmpty || v.length > 12) return null;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(v) ? v : null;
  }

  /// Naviger ind i det deeplinkede spil, når vi er klar (logget ind). Kaldes
  /// efter første frame og hver gang login-tilstanden skifter.
  void _maybeHandleDeepLink() {
    if (_linkHandled) return;
    final String? code = _pendingCode;
    if (code == null) return;
    // Online kræver login — vent til brugeren er der.
    final User? user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final NavigatorState? nav = _navigatorKey.currentState;
    if (nav == null) return;
    _linkHandled = true;
    final bool isGame = _pendingIsGame;
    nav.push(MaterialPageRoute<void>(
      builder: (_) =>
          isGame ? OnlineGameScreen(code: code) : LobbyScreen(code: code),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode = ref.watch(
      settingsProvider.select((Settings s) => s.themeMode),
    );

    // Vis en SnackBar når der lander en push i forgrunden. Lyt via
    // listen() så vi ikke kører rebuild ved hver besked.
    ref.listen<AsyncValue<PushMessage>>(pushMessageProvider, (prev, next) {
      final msg = next.valueOrNull;
      if (msg == null) return;
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.showSnackBar(SnackBar(
        content: Text('${msg.title}: ${msg.body}'),
        duration: const Duration(seconds: 5),
      ));
    });

    // Når login bliver klar (eller ved opstart), håndtér et evt. deeplink.
    ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
      if (next.valueOrNull != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeHandleDeepLink());
      }
    });
    if (_pendingCode != null && !_linkHandled) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeHandleDeepLink());
    }

    return MaterialApp(
      title: 'Partners',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF8B5E3C),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        // Behold den brune/grønne identitet i en mørk variant.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5E3C),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E2A1A),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
