import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import 'deck.dart';
import 'rules.dart';

class GameEngine extends ChangeNotifier {
  GameEngine({
    required this.state,
    Random? rng,
  })  : _deck = Deck(rng: rng),
        rules = Rules(state.geometry);

  final GameState state;
  final Rules rules;
  final Deck _deck;

  static const int handSize = 4;

  // ---------------------------------------------------------------------------
  // Hånd-lifecycle
  // ---------------------------------------------------------------------------

  void startNewHand() {
    state.exchangeBuffer.clear();
    // Ny kortgiver-cyklus (samme startende spiller i 3 runder): saml alle 56
    // kort og bland, så der igen er 4 af hver slags. Inden for en cyklus deles
    // der videre fra den samme bunke uden at blande om.
    if (state.starterStreak == 0) {
      state.deck
        ..clear()
        ..addAll(Deck.fresh());
      state.discard.clear();
      for (final Player p in state.players) {
        p.hand.clear();
      }
      _deck.shuffle(state.deck);
    }
    // Nødfald (bør ikke ske i normalt spil med 56 kort til 3 runder).
    if (state.deck.length < state.players.length * handSize) {
      state.deck.addAll(Deck.fresh());
      _deck.shuffle(state.deck);
    }
    for (int i = 0; i < handSize; i++) {
      for (int p = 0; p < state.players.length; p++) {
        state.players[p].hand.add(state.deck.removeLast());
      }
    }
    if (state.starterIndex < state.starterCounts.length) {
      state.starterCounts[state.starterIndex] += 1;
    }
    state.phase = GamePhase.exchange;
    state.handNumber += 1;
    notifyListeners();
  }

  /// Spilleren vælger sit bytte-kort (skjult). Når alle har valgt, byttes der.
  void submitExchangeCard(int playerIndex, PlayingCard card) {
    if (state.phase != GamePhase.exchange) return;
    if (!state.players[playerIndex].hand.contains(card)) return;
    state.exchangeBuffer[playerIndex] = card;

    if (state.exchangeBuffer.length == state.players.length) {
      _applyExchange();
      state.phase = GamePhase.play;
      state.currentPlayerIndex = state.starterIndex;
    }
    notifyListeners();
  }

  void _applyExchange() {
    // Hvert kort bevæger sig fra spiller -> partner (index + 2).
    final Map<int, PlayingCard> incoming = <int, PlayingCard>{};
    for (final MapEntry<int, PlayingCard?> e
        in state.exchangeBuffer.entries) {
      final PlayingCard? card = e.value;
      if (card == null) continue;
      final Player giver = state.players[e.key];
      giver.hand.remove(card);
      final int partnerIdx = giver.partnerIndex;
      incoming[partnerIdx] = card;
    }
    incoming.forEach((int idx, PlayingCard card) {
      state.players[idx].hand.add(card);
    });
    state.exchangeBuffer.clear();
  }

  // ---------------------------------------------------------------------------
  // Træk
  // ---------------------------------------------------------------------------

  List<Move> legalMovesFor(int playerIndex, PlayingCard card) {
    final Player player = state.players[playerIndex];
    return rules.legalMoves(state, player, card);
  }

  /// Returnerer alle gyldige træk over alle kort på hånden.
  List<Move> allLegalMoves(int playerIndex) {
    final Player player = state.players[playerIndex];
    final List<Move> moves = <Move>[];
    for (final PlayingCard c in player.hand) {
      moves.addAll(rules.legalMoves(state, player, c));
    }
    return moves;
  }

  /// Sand hvis spilleren kan lave mindst ét lovligt træk med sin hånd.
  bool canPlay(int playerIndex) => allLegalMoves(playerIndex).isNotEmpty;

  /// Spilleren kan ikke rykke nogen brik: smid resten af hånden og sid over
  /// resten af runden.
  void passHand(int playerIndex) {
    final Player player = state.players[playerIndex];
    state.discard.addAll(player.hand);
    player.hand.clear();
    _afterMove(playerIndex);
  }

  /// Spil et træk (validering antages allerede udført).
  void applyMove(int playerIndex, Move move) {
    final Player player = state.players[playerIndex];
    for (final MoveStep step in move.steps) {
      final Piece moving = state.pieceById(step.pieceId);
      // Selv-brænd: landede på en modstander-dobbelt → den flyttende brik
      // slås selv hjem til en fri start-slot. Ingen modstander slås.
      if (step.burnsMover) {
        moving.position = StartPosition(
          moving.ownerIndex,
          _firstFreeStartSlot(moving.ownerIndex),
        );
        moving.hasLeftStart = false;
        continue;
      }
      // Slag — den slåede brik returnerer til en fri start-slot.
      if (step.capturedPieceId != null) {
        final Piece captured = state.pieceById(step.capturedPieceId!);
        captured.position = StartPosition(
          captured.ownerIndex,
          _firstFreeStartSlot(captured.ownerIndex),
        );
        captured.hasLeftStart = false;
      }
      moving.position = step.to;
      if (step.from is StartPosition && step.to is TrackPosition) {
        moving.hasLeftStart = true;
      }
    }
    player.hand.remove(move.card);
    state.discard.add(move.card);
    _afterMove(playerIndex);
  }

  /// Smid et kort uden effekt (når der ikke findes gyldigt træk).
  void discardCard(int playerIndex, PlayingCard card) {
    final Player player = state.players[playerIndex];
    if (!player.hand.remove(card)) return;
    state.discard.add(card);
    _afterMove(playerIndex);
  }

  void _afterMove(int playerIndex) {
    // Tjek vinder
    for (int t = 0; t < 2; t++) {
      if (state.teamHasWon(t)) {
        state.winningTeamIndex = t;
        state.phase = GamePhase.gameOver;
        notifyListeners();
        return;
      }
    }
    // Hvis alle hænder er tomme (alle har spillet/sat over): ny hånd.
    // Samme startende spiller i 3 runder, derefter roteres med uret.
    if (state.players.every((Player p) => p.hand.isEmpty)) {
      state.starterStreak += 1;
      if (state.starterStreak >= 3) {
        state.starterIndex = (state.starterIndex + 1) % state.players.length;
        state.starterStreak = 0;
      }
      startNewHand();
      return;
    }
    // Næste spiller med kort på hånden (spring spillere over der sidder over).
    final int n = state.players.length;
    int next = (playerIndex + 1) % n;
    while (state.players[next].hand.isEmpty) {
      next = (next + 1) % n;
    }
    state.currentPlayerIndex = next;
    notifyListeners();
  }

  int _firstFreeStartSlot(int ownerIndex) {
    for (int slot = 0; slot < 4; slot++) {
      final Piece? occ =
          state.pieceAt(StartPosition(ownerIndex, slot));
      if (occ == null) return slot;
    }
    return 0;
  }
}
