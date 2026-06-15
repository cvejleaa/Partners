import 'dart:math';

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
                id: _uuid.v4(),
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
    _bump();
  }

  void discard(int playerIndex, PlayingCard card) {
    _engine?.discardCard(playerIndex, card);
    _bump();
  }

  bool canPlay(int playerIndex) => _engine?.canPlay(playerIndex) ?? false;

  void passHand(int playerIndex) {
    _engine?.passHand(playerIndex);
    _bump();
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
