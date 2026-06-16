import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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
import 'online/serialize.dart';
import 'stats/stats_repository.dart';
import 'ui/screens/home_screen.dart';

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

class GameController extends StateNotifier<GameState> {
  GameController() : super(_emptyState());

  GameEngine? _engine;
  final Uuid _uuid = const Uuid();
  final Random _rng = Random();

  // Træk-log for AI-spil (svarende til online-spillets log).
  final List<Map<String, dynamic>> _aiLog = <Map<String, dynamic>>[];
  String? _aiGameCode;
  bool _aiSavedAtEnd = false;
  String? _aiHostUid;
  String? _aiHostName;

  /// Offentlig adgang til den aktuelle state (StateNotifier.state er protected).
  GameState get currentState => state;

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

  void startGame(List<PlayerSetup> setups, {CardRules? cardRules}) {
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
    final GameState s = GameState(
      players: players,
      geometry: geom,
      deck: Deck.fresh(),
      discard: <PlayingCard>[],
      dealerIndex: 0,
      currentPlayerIndex: 0,
      phase: GamePhase.setup,
      handNumber: 0,
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

  void discard(int playerIndex, PlayingCard card) {
    _engine?.discardCard(playerIndex, card);
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
      // Genberegn stats-cachen så profilen opdaterer sig.
      // ignore: discarded_futures
      StatsRepository().recomputeAndSave();
    } catch (e) {
      debugPrint('[AI persist] $e');
    }
  }

  void reset() {
    _engine = null;
    state = _emptyState();
  }

  void _bump() {
    if (_engine == null) return;
    // Tving Riverpod til at notificere ved at lave en kopi af staten.
    final GameState e = _engine!.state;
    state = GameState(
      players: e.players,
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
    // Når spillet lige er afsluttet, persistér det til Firestore for stats.
    if (e.winningTeamIndex != null) {
      // ignore: discarded_futures
      _persistFinishedAiGame();
    }
  }
}

class PartnersApp extends StatelessWidget {
  const PartnersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Partners',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF8B5E3C),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
