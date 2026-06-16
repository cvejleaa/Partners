import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
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

    test('kan stable på eget første felt (egen brik blokerer ikke længere)', () {
      final state = makeState(piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(0), // egen brik står allerede på felt 1
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ]);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.ace, Suit.hearts));
      final exit = moves.where((Move m) => m.exitsStart);
      expect(exit, isNotEmpty);
      // Stak på egen brik → intet slag.
      expect(exit.first.steps.first.capturedPieceId, isNull);
    });

    test('kommer ud på ud-feltet (ikke felt 1, intet slag)', () {
      // Selv hvis en modstander står på felt 1 (index 0), lander den
      // udgående brik på ud-feltet (ExitPosition) — ikke på felt 1 — og slår
      // derfor ingen.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(0, s)],
        <PiecePosition>[
          const TrackPosition(0), // modstander på spiller 0's felt 1
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
      expect(exit.steps.first.to, const ExitPosition(0));
      expect(exit.steps.first.capturedPieceId, isNull);
    });

    test('slår modstander når man rykker fra ud-feltet ind på felt 1', () {
      // Egen brik står på ud-feltet; en modstander står på felt 1 (index 0).
      // Et 1-skridt (Es) rykker fra ud-feltet ind på felt 1 og slår.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const ExitPosition(0),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(0), // modstander på spiller 0's felt 1
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.ace, Suit.hearts));
      final hit = moves.firstWhere((Move m) =>
          !m.exitsStart &&
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 0);
      expect(hit.steps.first.capturedPieceId, isNotNull);
    });

    test('ud-felt + 7 lander på felt 7', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const ExitPosition(0),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.seven, Suit.hearts));
      // 7'eren deles; med kun én brik i spil lander den på felt 7 (index 6).
      final to7 = moves.any((Move m) =>
          m.steps.length == 1 &&
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 6);
      expect(to7, isTrue);
    });

    test('1 og 11 frem er gyldige fra banen', () {
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(5)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.ace, Suit.hearts));
      final targets = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      // 5+1=6; 5+11=16 (ren ring, ud-felter tælles ikke).
      expect(targets, containsAll(<int>[6, 16]));
    });
  });

  group('Konge', () {
    test('13 frem er gyldigt fra banen', () {
      // Start på 3, 13 frem (ren ring) → 16.
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(3)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.spades));
      final targets = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, contains(16));
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

    test('4 baglæns wrap-around (ren 56-ring)', () {
      // Brik på 2 — 4 baglæns krydser felt 0 → 54 (2-4+56).
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(2)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.four, Suit.clubs));
      final targets = moves
          .where((Move m) => m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, contains(54));
    });
  });

  group('7-kort split', () {
    test('split over to brikker er muligt', () {
      final state = makeState(piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(1),
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
          const TrackPosition(1),
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
          const TrackPosition(13),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.three, Suit.hearts));
      final hit = moves.firstWhere(
        (Move m) =>
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 13,
      );
      expect(hit.steps.first.capturedPieceId, isNotNull);
    });

    test('kan stable på egen brik (intet slag)', () {
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const TrackPosition(13),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.three, Suit.hearts));
      final landingOn13 = moves.where(
        (Move m) =>
            m.steps.first.from is TrackPosition &&
            (m.steps.first.from as TrackPosition).index == 10 &&
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 13,
      );
      expect(landingOn13, isNotEmpty);
      expect(landingOn13.first.steps.first.capturedPieceId, isNull);
    });

    test('lande på modstander-dobbelt brænder egen brik hjem', () {
      // To modstanderbrikker på felt 13 (en dobbelt). Spiller 0 fra 10 med en
      // 3'er kan godt lande, men egen brik slås hjem (burnsMover), ingen slag.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(13),
          const TrackPosition(13),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.three, Suit.hearts));
      final landingOn13 = moves.firstWhere(
        (Move m) =>
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 13,
      );
      expect(landingOn13.steps.first.burnsMover, isTrue);
      expect(landingOn13.steps.first.capturedPieceId, isNull);
    });

    test('bevogtet udgangsfelt kan ikke slås', () {
      // Spiller 1's brik står på sit eget udgangsfelt (index 14) → bevogtet.
      // Spiller 0 fra 11 med en 3'er kan derfor IKKE lande på 14 og slå den.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(11),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(14),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.three, Suit.hearts));
      final landingOn14 = moves.where((Move m) =>
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 14);
      expect(landingOn14, isEmpty);
    });

    test('bevogtet udgangsfelt spærrer for passage', () {
      // Spiller 1's brik på sit udgangsfelt (14). Spiller 0 fra 13 med en
      // femmer ville passere 14 og er derfor blokeret.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(13),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(14),
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
      final fromThirteen = moves.where((Move m) =>
          m.steps.first.from is TrackPosition &&
          (m.steps.first.from as TrackPosition).index == 13);
      expect(fromThirteen, isEmpty);
    });

    test('ubevogtet felt kan passeres (enlig brik væk fra udgangsfelt)', () {
      // Spiller 1's brik på felt 15 (IKKE et udgangsfelt). Spiller 0 fra 13
      // med en femmer passerer 14/15 og lander på 18.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(13),
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
      final toEighteen = moves.where((Move m) =>
          m.steps.first.from is TrackPosition &&
          (m.steps.first.from as TrackPosition).index == 13 &&
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 18);
      expect(toEighteen, isNotEmpty);
    });
  });

  group('Hjemstræk', () {
    test('passerer eget første felt og lander i hjemstræk slot 0', () {
      // Brik på 51: fem tæller 52,53,54,55 (4) og drejer så ind i hjemstræk
      // slot 0 (entry/felt 1 ved index 0 tælles ikke med på ringen).
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(51)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.five, Suit.hearts));
      final homeMove = moves.firstWhere(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      final hp = homeMove.steps.first.to as HomeStretchPosition;
      expect(hp.ownerIndex, 0);
      expect(hp.slot, 0);
    });

    test('kan ikke overskride hjemstræk-bagende', () {
      // Brik på TrackPosition(51), Konge (13) → ville lande for langt → ulovligt.
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(51)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.spades));
      final tooFar = moves.where(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      // Distance til entry = 5; max slot = 13-5-1 = 7 ≥ 4 → ulovligt.
      expect(tooFar, isEmpty);
    });

    test('blokkeret af egen brik i hjemstrækket', () {
      // Brik på TrackPosition(50), egen brik på H(0,0). 6 frem ville lande slot 0 — blokeret.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(50),
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

  group('Byt to brikker', () {
    // Regelsæt hvor Knægt kan bytte.
    final swapRules = CardRules.defaults()
        .withRank(Rank.jack, const CardRuleConfig(swap: true));

    test('kan bytte to forskellige spilleres brikker, men aldrig samme spillers',
        () {
      // Spiller 0 har to brikker ude (10, 20); makker (2) på 25; modstander
      // (1) på 35.
      final state = makeState(
        cardRules: swapRules,
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[
            const TrackPosition(10),
            const TrackPosition(20),
            const StartPosition(0, 2),
            const StartPosition(0, 3),
          ],
          <PiecePosition>[
            const TrackPosition(35),
            const StartPosition(1, 1),
            const StartPosition(1, 2),
            const StartPosition(1, 3),
          ],
          <PiecePosition>[
            const TrackPosition(25),
            const StartPosition(2, 1),
            const StartPosition(2, 2),
            const StartPosition(2, 3),
          ],
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
        ],
      );
      final moves = rules.legalMoves(
          state, state.players[0], const PlayingCard(Rank.jack, Suit.hearts));
      // Alle bytte-træk har 2 steps og involverer to forskellige ejere.
      expect(moves, isNotEmpty);
      for (final m in moves) {
        expect(m.steps.length, 2);
        final a = state.pieceById(m.steps[0].pieceId);
        final b = state.pieceById(m.steps[1].pieceId);
        expect(a.ownerIndex == b.ownerIndex, isFalse);
      }
      // Der findes et bytte mellem makker (2) og modstander (1) — uden mig.
      final bool partnerVsOpp = moves.any((m) {
        final o = <int>{
          state.pieceById(m.steps[0].pieceId).ownerIndex,
          state.pieceById(m.steps[1].pieceId).ownerIndex,
        };
        return o.containsAll(<int>{1, 2});
      });
      expect(partnerVsOpp, isTrue);
    });
  });

  group('Ud-kort', () {
    test('rent ud-kort kan kun rykke en brik ud', () {
      final state = makeState();
      final moves =
          rules.legalMoves(state, state.players[0], const PlayingCard.exit(0));
      expect(moves, isNotEmpty);
      expect(moves.every((Move m) => m.exitsStart), isTrue);
    });

    test('ud-kort gør intet når alle brikker er ude af start', () {
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(5)));
      // Spiller 0 har stadig 3 brikker i start her, så ud-kort virker; test i
      // stedet en spiller helt uden start-brikker.
      final allOut = makeState(piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(2),
          const TrackPosition(5),
          const TrackPosition(8),
          const TrackPosition(11),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ]);
      expect(
        rules.legalMoves(
            allOut, allOut.players[0], const PlayingCard.exit(0)),
        isEmpty,
      );
      // (state bruges ikke yderligere)
      expect(state.players[0].pieces.length, 4);
    });
  });

  group('Spil på makker når egne brikker er i mål', () {
    test('spiller flytter makkerens brik når alle 4 egne er hjemme', () {
      // Spiller 0 har alle 4 brikker i hjemstrækket. Makker (P2) har én brik
      // på banen. Med et kort der ellers ikke ville give træk (alle egne i
      // mål er færdige), skal vi nu kunne rykke makkerens brik.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 0),
          const HomeStretchPosition(0, 1),
          const HomeStretchPosition(0, 2),
          const HomeStretchPosition(0, 3),
        ],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(1, s)],
        <PiecePosition>[
          const TrackPosition(35),
          const StartPosition(2, 1),
          const StartPosition(2, 2),
          const StartPosition(2, 3),
        ],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.three, Suit.hearts));
      // Trækket må flytte makkerens (P2's) brik p2.0 fra 35 til 38.
      expect(moves, isNotEmpty);
      final m = moves.first;
      expect(m.steps.first.pieceId, 'p2.0');
      expect(m.steps.first.to, const TrackPosition(38));
    });

    test('Knægt-byt kan stadig bruges når mine brikker er færdige', () {
      // Spiller 0 alle hjemme. Modstander (P1) og makker (P2) har én brik
      // hver på banen. Knægt med swap=true skal give byt-træk.
      final swapRules = CardRules.defaults()
          .withRank(Rank.jack, const CardRuleConfig(swap: true));
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 0),
          const HomeStretchPosition(0, 1),
          const HomeStretchPosition(0, 2),
          const HomeStretchPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        <PiecePosition>[
          const TrackPosition(40),
          const StartPosition(2, 1),
          const StartPosition(2, 2),
          const StartPosition(2, 3),
        ],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
      ];
      final state = makeState(
        piecePositions: positions,
        cardRules: swapRules,
      );
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.jack, Suit.hearts));
      expect(moves, isNotEmpty);
      // Træk har 2 steps og involverer to forskellige ejere (P1+P2).
      final m = moves.first;
      expect(m.steps.length, 2);
      final owners = m.steps
          .map((s) => state.pieceById(s.pieceId).ownerIndex)
          .toSet();
      expect(owners, containsAll(<int>[1, 2]));
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
