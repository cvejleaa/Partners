// De to nye 25 år-motor-mekanikker: sekvens-træk (+2−5) og multi-brik-træk
// (1×1) — plus det fulde ejer-bekræftede seed.
//
// Geometri-facit (ring 60, UD på 0/15/30/45; UD-felter tæller ALDRIG):
//  M1  +2−5 dobbelt-slag: brik på 11, +2 → mellem 13 (slår enlig), −5 →
//      12,11,10,9,8 → slut 8 (slår enlig). Move = 2 steps, samme brik,
//      begge captures. applyMove ende-til-ende: slutposition + begge slåede
//      hjemme + kortet ude af hånden (motoren re-validerer selv — en tavs
//      afvisning ville efterlade brikken på 11 og gøre testen rød).
//  M2  afvisninger: mellem i hjemstræk / mellem-brænd (dobbelt) / baglæns
//      blokeret af besat fremmed UD / brik i hjemstræk.
//  M3  baglæns forbi EGET UD tæller ikke og spærrer aldrig ejeren: fra mellem
//      4 går −5 til 3,2,1,[0=eget UD springes],59,58 → slut 58. Mutation der
//      tæller UD med → slut 59 → rød.
//  M4  multi: præcis 2 brikker à 1 felt; sekventiel landing; dedup af de to
//      rækkefølger; kun 1 brik i spil → ingen multi (11 frem består);
//      2 i spil men én blokeret → ingen multi; vinder-undtagelsen.
//  M5  seedet = de fem bekræftede specialkort.
//  M6  serialisering: nye nøgler kun når sat; klassisk uændret.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'test_helpers.dart';

/// p25s effektive regler (seed oven på klassisk).
final CardRules p25 = effectiveCardRules(partners25, CardRules.defaults());

const PlayingCard seven = PlayingCard(Rank.seven, Suit.spades);
const PlayingCard jackC = PlayingCard(Rank.jack, Suit.hearts);

List<PiecePosition> startRow(int owner, {List<PiecePosition>? replace}) =>
    <PiecePosition>[
      for (int s = 0; s < 4; s++)
        (replace != null && s < replace.length)
            ? replace[s]
            : StartPosition(owner, s),
    ];

/// Sekvens-træk = 2 steps med SAMME brik.
bool isSeq(Move m) =>
    m.steps.length == 2 && m.steps[0].pieceId == m.steps[1].pieceId;

/// Multi-træk = 2 steps med FORSKELLIGE brikker der IKKE er et byt.
bool isMulti(Move m) =>
    m.steps.length == 2 &&
    m.steps[0].pieceId != m.steps[1].pieceId &&
    !(m.steps[0].to == m.steps[1].from && m.steps[1].to == m.steps[0].from);

void main() {
  group('M1 — +2−5: dobbelt-slag ende-til-ende', () {
    GameState scenario() => makeState(
          cardRules: p25,
          hands: <List<PlayingCard>>[
            <PlayingCard>[seven],
            <PlayingCard>[const PlayingCard(Rank.two, Suit.clubs)],
            <PlayingCard>[const PlayingCard(Rank.two, Suit.spades)],
            <PlayingCard>[const PlayingCard(Rank.two, Suit.hearts)],
          ],
          piecePositions: <List<PiecePosition>>[
            startRow(0, replace: <PiecePosition>[const TrackPosition(11)]),
            startRow(1, replace: <PiecePosition>[const TrackPosition(13)]),
            startRow(2, replace: <PiecePosition>[const TrackPosition(8)]),
            startRow(3),
          ],
        );

    test('genereres med begge slag i rækkefølge (mellem 13, slut 8)', () {
      final GameState st = scenario();
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], seven);
      final Move seq = moves.singleWhere(isSeq);
      expect(seq.steps[0].to, const TrackPosition(13));
      expect(seq.steps[0].capturedPieceId, 'p1.0',
          reason: 'mellem-landingen er en RIGTIG landing — enlig slås hjem');
      expect(seq.steps[1].to, const TrackPosition(8));
      expect(seq.steps[1].capturedPieceId, 'p2.0');
      // INVARIANT: step 0 må ALDRIG brænde (så ville applyMove sende brikken
      // hjem i step 1s "fortsættelse").
      for (final Move m in moves) {
        expect(m.steps.first.burnsMover, isFalse);
      }
      // 7 frem findes stadig som alternativ? 11+7 krydser UD-15 (besat? nej —
      // p1.0 står på 13, UD-15 er tom) → 7-frem-mål = 19. Kortets to
      // tilstande lever side om side.
      expect(moves.any((m) => m.steps.length == 1), isTrue);
    });

    test('applyMove afspiller begge steps (position + 2 hjemslag + kort væk)',
        () {
      final GameState st = scenario();
      final GameEngine engine = GameEngine(state: st);
      final Move seq = Rules(st.geometry)
          .legalMoves(st, st.players[0], seven)
          .singleWhere(isSeq);
      engine.applyMove(0, seq);
      expect(st.pieceById('p0.0').position, const TrackPosition(8),
          reason: 'en tavs applyMove-afvisning ville efterlade brikken på 11');
      expect(st.pieceById('p1.0').position, isA<StartPosition>());
      expect(st.pieceById('p2.0').position, isA<StartPosition>());
      expect(st.players[0].hand, isEmpty);
    });
  });

  group('M2 — +2−5: afvisninger', () {
    test('mellem-skridt ind i hjemstrækket → ingen sekvens', () {
      // Brik på 58 (owner 0, hasLeftStart): +2 → 59, [0=eget UD → drej] →
      // hjemstræk. Mellem i hjemstræk er forbudt.
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[const TrackPosition(58)]),
          startRow(1),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], seven);
      expect(moves.where(isSeq), isEmpty);
    });

    test('mellem-landing på DOBBELT (brænd) → ingen sekvens', () {
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[const TrackPosition(11)]),
          startRow(1, replace: <PiecePosition>[
            const TrackPosition(13),
            const TrackPosition(13), // dobbelt på mellemfeltet
          ]),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], seven);
      expect(moves.where(isSeq), isEmpty,
          reason: 'brænd ved mellem-landing gør sekvensen ulovlig (navngivet '
              'fortolkning, regler.md §15)');
    });

    test('baglæns-sti blokeret af besat fremmed UD → ingen sekvens', () {
      // Brik på 16: +2 → 17,18. −5 fra 18: 17,16,[15=fremmed UD BESAT] → stop.
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[const TrackPosition(16)]),
          startRow(1, replace: <PiecePosition>[const TrackPosition(15)]),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], seven);
      expect(moves.where(isSeq), isEmpty,
          reason: 'blokaden spærrer begge retninger (§6) — intet hop på 7');
    });

    test('brik i hjemstrækket kan ikke bruge sekvensen', () {
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0,
              replace: <PiecePosition>[const HomeStretchPosition(0, 0)]),
          startRow(1),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], seven);
      expect(moves.where(isSeq), isEmpty);
    });
  });

  group('M3 — baglæns forbi EGET UD', () {
    test('UD tæller ikke og spærrer aldrig ejeren: mellem 4 → slut 58', () {
      // Brik owner 0 på 2: +2 → 3,4 (mellem 4). −5 fra 4: 3,2,1,[0=eget UD,
      // springes UDEN at tælle — selv med egen brik på det],59,58 → slut 58.
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[
            const TrackPosition(2),
            const TrackPosition(0), // egen brik PÅ eget UD — spærrer ikke ejeren
          ]),
          startRow(1),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], seven);
      final Iterable<Move> seqs = moves.where(
          (m) => isSeq(m) && m.steps.first.pieceId == 'p0.0');
      expect(seqs, hasLength(1));
      // Muteres baglæns-løkken til at TÆLLE UD-feltet, bliver slutfeltet 59.
      expect(seqs.single.steps[1].to, const TrackPosition(58));
    });
  });

  group('M4 — 1×1: præcis to brikker, 1 felt hver', () {
    test('to brikker i spil → ét dedup\'et multi-træk (12 og 21)', () {
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[
            const TrackPosition(11),
            const TrackPosition(20),
          ]),
          startRow(1),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], jackC);
      final List<Move> multis = moves.where(isMulti).toList();
      expect(multis, hasLength(1),
          reason: 'de to rækkefølger skal dedup\'es til ét træk');
      final Set<PiecePosition> tos =
          multis.single.steps.map((s) => s.to).toSet();
      expect(tos, <PiecePosition>{
        const TrackPosition(12),
        const TrackPosition(21),
      });
      // 11 frem findes stadig som kortets anden tilstand.
      expect(moves.any((m) => m.steps.length == 1), isTrue);
    });

    test('nabobrikker: B må lande på As forladte felt (sekventiel)', () {
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[
            const TrackPosition(11),
            const TrackPosition(12),
          ]),
          startRow(1),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> multis = Rules(st.geometry)
          .legalMoves(st, st.players[0], jackC)
          .where(isMulti)
          .toList();
      expect(multis, isNotEmpty);
      final Set<PiecePosition> tos =
          multis.first.steps.map((s) => s.to).toSet();
      expect(tos, <PiecePosition>{
        const TrackPosition(12),
        const TrackPosition(13),
      });
    });

    test('kun ÉN brik i spil → ingen multi, men 11 frem består', () {
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[const TrackPosition(20)]),
          startRow(1),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], jackC);
      expect(moves.where(isMulti), isEmpty,
          reason: 'PRÆCIS 2 brikker kræves — ikke "op til 2"');
      expect(moves.any((m) => m.steps.length == 1), isTrue);
    });

    test('to i spil men den ene blokeret → ingen multi (præcis-N-grænsen)',
        () {
      // B på 14: +1 = [15=fremmed UD, BESAT] → blokeret.
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          startRow(0, replace: <PiecePosition>[
            const TrackPosition(5),
            const TrackPosition(14),
          ]),
          startRow(1, replace: <PiecePosition>[const TrackPosition(15)]),
          startRow(2),
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], jackC);
      expect(moves.where(isMulti), isEmpty);
    });

    test('vinder-undtagelsen: ét skridt der låser holdets sidste brik gælder',
        () {
      // Spiller 0: alle 4 i hjemstrækket (endgame → makkerens pulje åbnes).
      // Makkeren (2, eget UD=30): 3 brikker låst + 1 på felt 29, der med ét
      // skridt drejer ind på hjemslot 0 → holdet har vundet → trækket gælder
      // med KUN den ene brik (spejlet fra 7×1-undtagelsen).
      final GameState st = makeState(
        cardRules: p25,
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[
            for (int s = 0; s < 4; s++) HomeStretchPosition(0, s)
          ],
          startRow(1),
          <PiecePosition>[
            const TrackPosition(29),
            const HomeStretchPosition(2, 1),
            const HomeStretchPosition(2, 2),
            const HomeStretchPosition(2, 3),
          ],
          startRow(3),
        ],
      );
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], jackC);
      final Iterable<Move> winning = moves.where((m) =>
          m.steps.length == 1 &&
          m.steps.single.to == const HomeStretchPosition(2, 0));
      expect(winning, isNotEmpty,
          reason: 'vinder-undtagelsen skal spejles fra splitten');
    });
  });

  group('M5 — seedet er de fem bekræftede specialkort', () {
    test('4×1, 5↷, 7/+2−5, byt/9, 11/1×1 — og intet −4', () {
      final Map<Rank, CardRuleConfig> seed = partners25.cardRuleOverrides!;
      expect(seed.keys.toSet(),
          <Rank>{Rank.four, Rank.five, Rank.seven, Rank.nine, Rank.jack});
      expect(seed[Rank.four]!.splitTotal, 4);
      expect(seed[Rank.four]!.backwardSteps, isNull,
          reason: 'ejer-bekræftet: 25 år har INTET −4-kort');
      expect(seed[Rank.five]!.jumpsBlockade, isTrue);
      expect(seed[Rank.seven]!.forwardSteps, <int>[7]);
      expect(seed[Rank.seven]!.seqForward, 2);
      expect(seed[Rank.seven]!.seqBackward, 5);
      expect(seed[Rank.nine]!.swap, isTrue);
      expect(seed[Rank.nine]!.forwardSteps, <int>[9]);
      expect(seed[Rank.jack]!.forwardSteps, <int>[11]);
      expect(seed[Rank.jack]!.multiPieces, 2);
      expect(seed[Rank.jack]!.multiSteps, 1);
    });
  });

  group('M6 — serialisering af de nye felter', () {
    test('kun skrevet når sat; round-trip; klassisk uændret', () {
      final Map<String, dynamic> seq = const CardRuleConfig(
              forwardSteps: <int>[7], seqForward: 2, seqBackward: 5)
          .toJson();
      expect(seq['seqForward'], 2);
      expect(seq['seqBackward'], 5);
      expect(seq.containsKey('multiPieces'), isFalse);
      final CardRuleConfig back =
          CardRuleConfig.fromJson(Map<String, dynamic>.from(seq));
      expect(back.hasFwdThenBack, isTrue);
      expect(back.seqBackward, 5);

      // Klassiske kort-maps får INGEN af de nye nøgler (bagud-kompat).
      final Map<String, dynamic> classicJson = CardRules.defaults().toJson();
      for (final dynamic v in classicJson.values) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(v as Map);
        expect(m.containsKey('seqForward'), isFalse);
        expect(m.containsKey('seqBackward'), isFalse);
        expect(m.containsKey('multiPieces'), isFalse);
        expect(m.containsKey('multiSteps'), isFalse);
      }
    });
  });
}
