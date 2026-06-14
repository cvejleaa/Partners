import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/deck.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/player.dart';
import 'package:partners/models/playing_card.dart';

/// Kør et helt spil til ende med 4 AI-spillere. Verificér at alle træk er
/// gyldige, og at spillet slutter med en vinder inden for [maxHands] hænder.
void main() {
  test('et komplet spil afsluttes med en gyldig vinder', () {
    final result = playFullGame(seed: 42, maxHands: 500);
    expect(result.winningTeam, isNotNull,
        reason: 'Spil skulle slutte med en vinder inden for ${result.handsPlayed} hænder');
    expect(result.illegalMoves, 0, reason: 'Alle træk skal være lovlige');
    expect(result.handsPlayed, lessThanOrEqualTo(500));
    // ignore: avoid_print
    print('Spil sluttede: hold ${result.winningTeam} vandt på '
        '${result.handsPlayed} hænder (${result.movesPlayed} træk, '
        '${result.captures} slag, ${result.discards} smid)');
  });

  test('AI spiller flere spil i træk uden at fejle', () {
    for (int seed = 0; seed < 5; seed++) {
      final r = playFullGame(seed: seed, maxHands: 500);
      expect(r.winningTeam, isNotNull, reason: 'Seed $seed skulle slutte');
      expect(r.illegalMoves, 0, reason: 'Seed $seed: ingen ulovlige træk');
    }
  });
}

class GameResult {
  GameResult({
    required this.winningTeam,
    required this.handsPlayed,
    required this.movesPlayed,
    required this.captures,
    required this.discards,
    required this.illegalMoves,
  });
  final int? winningTeam;
  final int handsPlayed;
  final int movesPlayed;
  final int captures;
  final int discards;
  final int illegalMoves;
}

GameResult playFullGame({int seed = 0, int maxHands = 500}) {
  final rng = Random(seed);
  const geom = BoardGeometry();
  final players = <Player>[
    for (int i = 0; i < 4; i++)
      Player(
        index: i,
        name: 'P$i',
        color: Colors.black,
        isHuman: false,
        pieces: <Piece>[
          for (int s = 0; s < 4; s++)
            Piece(id: 'p$i.$s', ownerIndex: i, position: StartPosition(i, s)),
        ],
      ),
  ];
  final state = GameState(
    players: players,
    geometry: geom,
    deck: Deck.fresh(),
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.setup,
    handNumber: 0,
  );
  final engine = GameEngine(state: state, rng: rng);
  final ai = HeuristicAi(rng: rng);

  int handsPlayed = 0;
  int movesPlayed = 0;
  int captures = 0;
  int discards = 0;
  int illegalMoves = 0;

  while (state.phase != GamePhase.gameOver && handsPlayed < maxHands) {
    engine.startNewHand();
    handsPlayed++;
    expect(state.phase, GamePhase.exchange);
    // Exchange
    for (int i = 0; i < 4; i++) {
      final card = ai.chooseExchangeCard(state, i);
      engine.submitExchangeCard(i, card);
    }
    expect(state.phase, anyOf(GamePhase.play, GamePhase.gameOver));

    // Play out hand
    int safety = 100;
    while (state.phase == GamePhase.play && safety-- > 0) {
      final idx = state.currentPlayerIndex;
      final move = ai.chooseMove(state, idx);
      if (move != null) {
        // Verificér lovlighed igen — kort skal være på hånden + i lovlige træk
        final legal = engine.legalMovesFor(idx, move.card);
        final isLegal = legal.any((Move m) => _movesEquivalent(m, move));
        if (!isLegal) {
          illegalMoves++;
        }
        for (final s in move.steps) {
          if (s.capturedPieceId != null) captures++;
        }
        engine.applyMove(idx, move);
        movesPlayed++;
      } else {
        final card = ai.chooseDiscard(state, idx);
        engine.discardCard(idx, card);
        discards++;
      }
    }
    expect(safety > 0, true, reason: 'Hånd skal afsluttes inden 100 træk');
  }

  return GameResult(
    winningTeam: state.winningTeamIndex,
    handsPlayed: handsPlayed,
    movesPlayed: movesPlayed,
    captures: captures,
    discards: discards,
    illegalMoves: illegalMoves,
  );
}

bool _movesEquivalent(Move a, Move b) {
  if (a.card != b.card) return false;
  if (a.steps.length != b.steps.length) return false;
  for (int i = 0; i < a.steps.length; i++) {
    if (a.steps[i].pieceId != b.steps[i].pieceId) return false;
    if (_posKey(a.steps[i].to) != _posKey(b.steps[i].to)) return false;
  }
  return true;
}

String _posKey(PiecePosition p) {
  if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
  if (p is TrackPosition) return 'T${p.index}';
  if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
  return '?';
}
