import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';

import 'test_helpers.dart';

void main() {
  test('AI vælger Es til ud-af-start hvis brikker er i start', () {
    final state = makeState(
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          for (int s = 0; s < 4; s++) StartPosition(0, s),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard(Rank.ace, Suit.hearts),
          PlayingCard(Rank.two, Suit.clubs),
          PlayingCard(Rank.three, Suit.spades),
          PlayingCard(Rank.four, Suit.diamonds),
        ],
        for (int i = 1; i < 4; i++) <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    final Move? move = ai.chooseMove(state, 0);
    expect(move, isNotNull);
    expect(move!.exitsStart, true);
  });

  test('AI foretrækker slag over alm. fremad-træk', () {
    final state = makeState(
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(15),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard(Rank.five, Suit.hearts),
        ],
        for (int i = 1; i < 4; i++) <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    final Move? move = ai.chooseMove(state, 0);
    expect(move, isNotNull);
    expect(move!.steps.first.capturedPieceId, isNotNull);
  });
}
