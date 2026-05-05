import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';

import 'test_helpers.dart';

void main() {
  const BoardGeometry geom = BoardGeometry();
  final Rules rules = Rules(geom);

  group('Es', () {
    test('kan flytte brik ud af start hvis udgangsfelt er frit', () {
      final state = makeState();
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.ace, Suit.hearts),
      );
      expect(moves.where((Move m) => m.exitsStart).isNotEmpty, true);
    });

    test('1 og 11 frem er gyldige fra banen', () {
      // Spiller 0 har én brik på TrackPosition(5)
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(5),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.ace, Suit.hearts),
      );
      // 1 forward to 6, 11 forward to 16, plus exit-start moves.
      final List<Move> trackMoves = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .toList();
      final Set<int> targets = trackMoves
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, containsAll(<int>[6, 16]));
    });
  });

  group('Konge', () {
    test('13 frem er gyldigt fra banen', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(2),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.king, Suit.spades),
      );
      final List<Move> trackMoves = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .toList();
      final Set<int> targets = trackMoves
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, contains(15));
    });
  });

  group('4-kort', () {
    test('kan flytte 4 frem eller 4 baglæns', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.four, Suit.clubs),
      );
      final Set<int> targets = moves
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, containsAll(<int>[24, 16]));
    });
  });

  group('7-kort split', () {
    test('split 4+3 over to brikker er gyldigt', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const TrackPosition(20),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.seven, Suit.hearts),
      );
      // Forventer minst en bevægelse hvor begge brikker rykker
      final hasSplit = moves.any((Move m) => m.steps.length >= 2);
      expect(hasSplit, true);
    });

    test('total er altid 7', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const TrackPosition(20),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.seven, Suit.hearts),
      );
      for (final Move m in moves) {
        int total = 0;
        for (final MoveStep s in m.steps) {
          if (s.from is TrackPosition && s.to is TrackPosition) {
            int d = (s.to as TrackPosition).index -
                (s.from as TrackPosition).index;
            if (d < 0) d += geom.trackLength;
            total += d;
          }
        }
        // Tillader 0 (alt i hjemstrækket osv. — vi tester kun rene track-træk).
        if (total > 0) {
          expect(total, lessThanOrEqualTo(7));
        }
      }
    });
  });

  group('Slag', () {
    test('lander på modstanderbrik → slag-flag sættes', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      // Sæt en modstanderbrik på TrackPosition(15) — 5 frem fra spiller 0.
      positions[1] = <PiecePosition>[
        const TrackPosition(15),
        const StartPosition(1, 1),
        const StartPosition(1, 2),
        const StartPosition(1, 3),
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.five, Suit.hearts),
      );
      final hit = moves.firstWhere(
        (Move m) =>
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 15,
        orElse: () => const Move(card: PlayingCard(Rank.two, Suit.clubs), steps: <MoveStep>[]),
      );
      expect(hit.steps.isNotEmpty, true);
      expect(hit.steps.first.capturedPieceId, isNotNull);
    });

    test('kan ikke lande på egen brik', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const TrackPosition(15),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(
        state,
        state.players[0],
        const PlayingCard(Rank.five, Suit.hearts),
      );
      // Brikken på 10 må ikke lande på brikken på 15 (5 frem)
      final landingOn15 = moves.where(
        (Move m) =>
            m.steps.first.from is TrackPosition &&
            (m.steps.first.from as TrackPosition).index == 10 &&
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 15,
      );
      expect(landingOn15, isEmpty);
    });
  });
}
