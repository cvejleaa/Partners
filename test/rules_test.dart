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

    test('Konge sender brik ud på UD-feltet (TrackPosition(0))', () {
      // På 60-ringen er UD-feltet for spiller 0 ringens TrackPosition(0).
      // Felt 1 er TrackPosition(1), felt 2 er TrackPosition(2) osv.
      final state = makeState();
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.hearts));
      final exit = moves.firstWhere((Move m) => m.exitsStart);
      expect(exit.steps.first.to, const TrackPosition(0));
      expect(exit.steps.first.capturedPieceId, isNull);
    });

    test('slår modstander når man rykker fra UD-feltet ind på felt 1', () {
      // Egen brik står på UD-feltet (TrackPosition(0)); en modstander står
      // på felt 1 (TrackPosition(1)). Et 1-skridt med Es slår modstanderen.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(0), // egen brik på UD-felt
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(1), // modstander på spiller 0's felt 1
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
          (m.steps.first.to as TrackPosition).index == 1);
      expect(hit.steps.first.capturedPieceId, isNotNull);
    });

    test('UD-felt + 7 lander på felt 7', () {
      // Brik på UD-feltet (index 0). En 7'er forward = TrackPosition(7) = felt 7.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(0),
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
      final to7 = moves.any((Move m) =>
          m.steps.length == 1 &&
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 7);
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
      // 5+1=6. 5+11: krydser spiller 1's UD-felt (idx 15) som springes over
      // (tæller ikke), så 11 tællende skridt fra idx 5 lander på idx 17.
      expect(targets, containsAll(<int>[6, 17]));
    });
  });

  group('Konge', () {
    test('13 frem er gyldigt fra banen', () {
      // Start på idx 3, 13 frem. Krydser spiller 1's UD-felt (idx 15) som
      // springes over → 13 tællende skridt lander på idx 17.
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(3)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.spades));
      final targets = moves
          .where((Move m) => !m.exitsStart && m.steps.first.to is TrackPosition)
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(targets, contains(17));
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

    test('4 baglæns wrap-around (60-ring)', () {
      // Brik på 2 — 4 baglæns krydser felt 0 → 58 (2-4+60).
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

    test('andre spillere kan ikke lande på et fremmed UD-felt', () {
      // Spiller 1's brik står på sit eget UD-felt (index 15). Spiller 0 kan
      // ALDRIG lande på idx 15 — UD-felter springes over af alle andre.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(12),
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
      // Prøv alle korttal: ingen forward-distance lander spiller 0 på idx 15.
      for (final Rank r in <Rank>[
        Rank.two, Rank.three, Rank.four, Rank.five, Rank.six
      ]) {
        final moves = rules.legalMoves(
            state, state.players[0], PlayingCard(r, Suit.hearts));
        final onUd = moves.where((Move m) =>
            m.steps.first.to is TrackPosition &&
            (m.steps.first.to as TrackPosition).index == 15);
        expect(onUd, isEmpty, reason: 'kort $r landede på fremmed UD-felt');
      }
    });

    test('andre spillere springer TOMT fremmed UD-felt over (14 → 1 direkte)',
        () {
      // Spiller 1's UD-felt (15) er TOMT. Spiller 0 fra 13 med en femmer
      // SPRINGER idx 15 over (tæller ikke) → 5 tællende skridt lander på 19,
      // ikke 18. Passage er tilladt (ikke blokeret).
      final state =
          makeState(piecePositions: _onlyOneAt(const TrackPosition(13)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.five, Suit.hearts));
      final to19 = moves.where((Move m) =>
          m.steps.first.from is TrackPosition &&
          (m.steps.first.from as TrackPosition).index == 13 &&
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 19);
      expect(to19, isNotEmpty);
    });

    test('BESAT fremmed UD-felt spærrer — andre kan ikke passere', () {
      // Eksempel fra docs/regler.md (1b): Røds UD-felt (idx 0) har 2 røde
      // brikker. Gul (spiller 3) står på rødt felt 10 (idx 55) — nej, idx 55
      // er sidste felt før røds UD. Test scenariet: spiller 3 (gul) på idx 55
      // forsøger at rykke fremad med en konge (13). Skal blive blokeret —
      // ingen forward-move med Konge fra idx 55 skal eksistere når der står
      // brikker på idx 0.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(0), // 2 røde på røds UD-felt
          const TrackPosition(0),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 3; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
        <PiecePosition>[
          const TrackPosition(55), // gul på sit felt 10
          const StartPosition(3, 1),
          const StartPosition(3, 2),
          const StartPosition(3, 3),
        ],
      ];
      final state = makeState(piecePositions: positions);
      // Konge giver 13 frem ELLER ud-af-start. Vi tjekker kun forward.
      final moves = rules.legalMoves(state, state.players[3],
          const PlayingCard(Rank.king, Suit.hearts));
      final forwardMoves = moves.where((Move m) =>
          !m.exitsStart &&
          m.steps.first.from is TrackPosition &&
          (m.steps.first.from as TrackPosition).index == 55);
      expect(forwardMoves, isEmpty,
          reason: 'gul må ikke passere besat rødt UD-felt');

      // Også med en mindre forward-værdi der ville krydse UD — fx 5'er fra 55.
      final fiveMoves = rules.legalMoves(state, state.players[3],
          const PlayingCard(Rank.five, Suit.hearts));
      final fiveForward = fiveMoves.where((Move m) =>
          !m.exitsStart &&
          m.steps.first.from is TrackPosition &&
          (m.steps.first.from as TrackPosition).index == 55);
      expect(fiveForward, isEmpty,
          reason: '5\'er fra 55 må heller ikke passere besat UD');
    });

    test('BESAT fremmed UD-felt spærrer også baglæns', () {
      // Gul (spiller 3) på rødt felt 5 (idx 5). Røds UD-felt (idx 0) har en
      // rød brik. Gul prøver at rykke 6 baglæns med en 4'er er kun 4 — så vi
      // bruger en 4'er der ville lande på idx 1, ikke krydse UD (lovligt).
      // For at TESTE blokering bruger vi 4'er fra idx 3 → ville krydse idx 0.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(0), // rød på sit eget UD
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 3; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
        <PiecePosition>[
          const TrackPosition(3), // gul på rødt felt 3
          const StartPosition(3, 1),
          const StartPosition(3, 2),
          const StartPosition(3, 3),
        ],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[3],
          const PlayingCard(Rank.four, Suit.hearts));
      final backward = moves.where((Move m) =>
          m.steps.first.from is TrackPosition &&
          (m.steps.first.from as TrackPosition).index == 3);
      // 4 frem (3 → 7) skal være ok. 4 bagud (3 → 59 via idx 0) skal være
      // blokeret.
      final tos = backward
          .map((Move m) => (m.steps.first.to as TrackPosition).index)
          .toSet();
      expect(tos, contains(7), reason: '4 frem skal stadig være lovligt');
      expect(tos, isNot(contains(59)),
          reason: '4 baglæns gennem besat UD skal være blokeret');
    });

    test('ejeren bruger sit eget UD-felt normalt (tæller med)', () {
      // Spiller 1's egen brik på idx 14 (sit felt 14) med en 2'er: 14 → 15
      // (eget UD) → ... Faktisk: ejeren TÆLLER sit eget UD-felt. Fra idx 16
      // (spiller 1 felt 1) er det lettere at vise: spiller 1 på idx 29
      // (felt 14) + 2 = idx 30? Nej — idx 30 er spiller 2's UD (springes).
      // Test i stedet at spiller 1 fra sit UD (15) + 1 = felt 1 (idx 16).
      final positions = <List<PiecePosition>>[
        for (int i = 0; i < 1; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(0, s)],
        <PiecePosition>[
          const TrackPosition(15), // spiller 1 på eget UD-felt
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ];
      final state = makeState(piecePositions: positions);
      final moves = rules.legalMoves(state, state.players[1],
          const PlayingCard(Rank.ace, Suit.hearts));
      final to16 = moves.any((Move m) =>
          !m.exitsStart &&
          m.steps.first.to is TrackPosition &&
          (m.steps.first.to as TrackPosition).index == 16);
      expect(to16, isTrue);
    });
  });

  group('Hjemstræk', () {
    test('når tilbage til eget UD-felt og lander i hjemstræk slot 0', () {
      // Brik på 55: 5 forward tæller 56,57,58,59 (4) og drejer så ind i
      // hjemstræk slot 0 ved næste step (60 = 0 = eget UD-felt = ownEntry).
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(55)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.five, Suit.hearts));
      final homeMove = moves.firstWhere(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      final hp = homeMove.steps.first.to as HomeStretchPosition;
      expect(hp.ownerIndex, 0);
      expect(hp.slot, 0);
    });

    test('kan ikke overskride hjemstræk-bagende', () {
      // Brik på TrackPosition(55), Konge (13) → distance to entry=5,
      // max slot = 13-5-1 = 7 ≥ 4 → ulovligt.
      final state = makeState(piecePositions: _onlyOneAt(const TrackPosition(55)));
      final moves = rules.legalMoves(state, state.players[0],
          const PlayingCard(Rank.king, Suit.spades));
      final tooFar = moves.where(
          (Move m) => m.steps.first.to is HomeStretchPosition);
      expect(tooFar, isEmpty);
    });

    test('blokkeret af egen brik i hjemstrækket', () {
      // Brik på TrackPosition(54), egen brik på H(0,0). 6 frem (54+6=60=0
      // = ownEntry, slot 0) blokeres af egen brik i slot 0.
      final positions = <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(54),
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

    test('brik på sit eget UD-felt kan ikke byttes', () {
      // Spiller 0 har en brik på sit eget UD-felt (index 0) og en på felt 5.
      // Modstander (1) på felt 35. Et byt må ALDRIG involvere brikken på
      // UD-feltet — den er beskyttet.
      final state = makeState(
        cardRules: swapRules,
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[
            const TrackPosition(0), // eget UD-felt — beskyttet
            const TrackPosition(5),
            const StartPosition(0, 2),
            const StartPosition(0, 3),
          ],
          <PiecePosition>[
            const TrackPosition(35),
            const StartPosition(1, 1),
            const StartPosition(1, 2),
            const StartPosition(1, 3),
          ],
          for (int i = 2; i < 4; i++)
            <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
        ],
      );
      final moves = rules.legalMoves(
          state, state.players[0], const PlayingCard(Rank.jack, Suit.hearts));
      // Ingen byt-træk må flytte brikken på UD-feltet (p0.0).
      final involvesUdFelt = moves.any((Move m) =>
          m.steps.any((MoveStep s) => s.pieceId == 'p0.0'));
      expect(involvesUdFelt, isFalse);
      // Men brikken på felt 5 KAN stadig byttes med modstanderen.
      final involvesFive = moves.any((Move m) =>
          m.steps.any((MoveStep s) => s.pieceId == 'p0.1'));
      expect(involvesFive, isTrue);
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
