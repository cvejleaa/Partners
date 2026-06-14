import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';

import 'test_helpers.dart';

void main() {
  const geom = BoardGeometry();
  final rules = Rules(geom);

  group('Es', () {
    test('kan flytte brik ud af start når udgangsfelt er frit', () {
      final state = makeState();
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.ace, Suit.hearts));
      expect(moves.where((Move m) => m.exitsStart), isNotEmpty);
    });

    test('kan IKKE flytte brik ud af start hvis egen brik blokerer entry', () {
      final state = makeState(piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(0), // egen brik blokerer udgangsfelt
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ]);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.ace, Suit.hearts));
      expect(moves.where((Move m) => m.exitsStart), isEmpty);
    });

    test('når man slår modstander mens man kommer ud af start', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(0, s)],
        <PiecePosition>[
          const TrackPosition(0), // modstander på spiller 0's udgangsfelt
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.hearts));
      final exit = moves.firstWhere((Move m) => m.exitsStart);
      expect(exit.steps.first.capturedPieceId, isNotNull);
    });

    test('1 og 11 frem er gyldige fra banen', () {
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(5)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.ace, Suit.hearts));
      final targets = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, containsAll(<int>[6, 16]));
    });
  });

  group('Konge', () {
    test('13 frem er gyldigt fra banen', () {
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(2)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.spades));
      final targets = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, contains(15));
    });
  });

  group('4-kort', () {
    test('flytter 4 frem og 4 baglæns', () {
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(20)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.four, Suit.clubs));
      final targets = moves
          .where((Move m) => m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, containsAll(<int>[24, 16]));
    });

    test('4 baglæns krydser felt 0 korrekt (wrap-around)', () {
      // Brik på TrackPosition(2) — 4 baglæns → TrackPosition(58)
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(2)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.four, Suit.clubs));
      final targets = moves
          .where((Move m) => m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, contains(58));
    });
  });

  group('7-kort split', () {
    test('split over to brikker er muligt', () {
      final state = makeState(piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const TrackPosition(20),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ]);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.seven, Suit.hearts));
      final hasSplit = moves.any((Move m) => m.steps.length >= 2);
      expect(hasSplit, true);
    });

    test('total er aldrig > 7', () {
      final state = makeState(piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const TrackPosition(20),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ]);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.seven, Suit.hearts));
      for (final m in moves) {
        int total = 0;
        for (final s in m.steps) {
          if (s.from is TrackPosition && s.to is TrackPosition) {
            int d = (s.to as TrackPosition).index -
                (s.from as TrackPosition).index;
            if (d < 0) d += geom.trackLength;
            total += d;
          }
        }
        expect(total, lessThanOrEqualTo(7));
      }
    });
  });

  group('Slag', () {
    test('lander på modstanderbrik → capturedPieceId sættes', () {
      final positions = <List<PiecePosition>>[
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
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.five, Suit.hearts));
      final hit = moves.firstWhere(
        (Move m) =>
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 15,
      );
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
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.five, Suit.hearts));
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

  group('Hjemstræk', () {
    test('passerer udgangsfelt og lander i hjemstræk slot 0', () {
      // Spiller 0, entry=0. Brik på TrackPosition(55). distanceToEntry = 5.
      // Card = 6 → past entry by 1 → home slot 0.
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(55)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.six, Suit.hearts));
      final homeMove = moves.firstWhere(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      final hp = homeMove.steps.first.to as HomeStretchPosition;
      expect(hp.ownerIndex, 0);
      expect(hp.slot, 0);
    });

    test('kan ikke overskride hjemstræk-bagende', () {
      // Brik på TrackPosition(55), Konge (13) → ville lande på slot 7 → ulovligt.
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(55)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.spades));
      final tooFar = moves.where(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      // Med distanceToEntry=5, max slot = 13-5-1 = 7 → ulovligt
      expect(tooFar, isEmpty);
    });

    test('blokkeret af egen brik i hjemstrækket', () {
      // Brik på TrackPosition(55), egen brik på H(0,0). 6 frem ville lande slot 0 — blokeret.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(55),
          const HomeStretchPosition(0, 0),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.six, Suit.hearts));
      final homeMoves = moves.where(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      expect(homeMoves, isEmpty);
    });

    test('brik allerede i hjemstræk kan rykke videre indad', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 0),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.two, Suit.clubs));
      final target = moves.firstWhere(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      final hp = target.steps.first.to as HomeStretchPosition;
      expect(hp.slot, 2);
    });

    test('brik i hjemstrækket må ikke springe over egen brik', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 0),
          const HomeStretchPosition(0, 2),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      // Brik på slot 0, 3 frem → slot 3, men slot 2 er optaget.
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.three, Suit.clubs));
      final fromSlot0 = moves.where(
          (Move m) =>
              m.steps.first.from is HomeStretchPosition &&
              (m.steps.first.from as HomeStretchPosition).slot == 0);
      expect(fromSlot0, isEmpty);
    });
  });
}

List<List<PiecePosition>> _onlyOneAt(PiecePosition pos) {
  return <List<PiecePosition>>[
    <PiecePosition>[
      pos,
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ],
    for (int i = 1; i < 4; i++)
      <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
  ];
}
