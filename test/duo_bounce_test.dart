// Duo-trin 7: bounce-back i målet.
//
// Regelbogen, s. 3: "Hvis kortværdien ikke passer, så brikken kan blive låst,
// skal den flyttes det overskydende antal felter baglæns. Det er dog KUN på
// en målcirkel, at brikken kan skifte retning. Når en brik står på en
// målcirkel, er brikken fredet." — og "Når en brik er i mål er den låst og
// kan ikke længere flyttes." Rækker tilbageløbet ud over målet, fortsætter
// brikken ud på banen (ejerens valg).
//
// Klassisk og 25 år har IKKE bounce (husregel, §11) — begge grene låses her.
// Testene kører på klassisk bræt (4 målcirkler); logikken er den samme ved
// Duos 3.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'test_helpers.dart';

const Map<Rank, CardRuleConfig> rene = <Rank, CardRuleConfig>{
  // Rene fremad-kort, så hvert kort giver præcis ét træk pr. brik.
  Rank.four: CardRuleConfig(forwardSteps: <int>[4]),
  Rank.seven: CardRuleConfig(forwardSteps: <int>[7]),
};
const VariantConfig medBounce = VariantConfig(
    id: 'bounce', name: 'Bounce', goalBounce: true, cardRuleOverrides: rene);
const VariantConfig udenBounce =
    VariantConfig(id: 'nobounce', name: 'Uden', cardRuleOverrides: rene);

const Map<int, Rank> kort = <int, Rank>{
  2: Rank.two, 3: Rank.three, 4: Rank.four, 5: Rank.five, 6: Rank.six,
  7: Rank.seven, 8: Rank.eight, 9: Rank.nine,
};

List<PiecePosition> startOf(int seat, {int skip = 0}) =>
    <PiecePosition>[for (int s = skip; s < 4; s++) StartPosition(seat, s)];

/// Hvor ender brik p0.0 med et kort på [n] felter? null = intet lovligt træk.
PiecePosition? hvorhen(VariantConfig v, List<PiecePosition> mine, int n,
    {List<PiecePosition>? plads1}) {
  final GameState s = makeState(
    variant: v,
    cardRules: effectiveCardRules(v, CardRules.defaults()),
    piecePositions: <List<PiecePosition>>[
      mine,
      plads1 ?? startOf(1),
      startOf(2),
      startOf(3),
    ],
  );
  final List<Move> ms = Rules(s.geometry)
      .legalMoves(s, s.players[0], PlayingCard(kort[n]!, Suit.spades))
      .where((Move m) => m.steps.first.pieceId == 'p0.0')
      .toList();
  if (ms.isEmpty) return null;
  expect(ms, hasLength(1));
  return ms.single.steps.single.to;
}

void main() {
  // p0.0 står på feltet lige før eget UD (59); resten i start.
  final List<PiecePosition> vedIndgang = <PiecePosition>[
    const TrackPosition(59),
    ...startOf(0, skip: 1),
  ];

  test('passer kortet, er der ingen forskel', () {
    for (final VariantConfig v in <VariantConfig>[medBounce, udenBounce]) {
      expect(hvorhen(v, vedIndgang, 4), const HomeStretchPosition(0, 3),
          reason: '${v.id}: 4 felter = den inderste af fire cirkler');
      expect(hvorhen(v, vedIndgang, 2), const HomeStretchPosition(0, 1));
    }
  });

  test('for stort kort: bounce vender i målet — uden bounce er det ulovligt', () {
    // 5 = 4 ind til den inderste + 1 tilbage.
    expect(hvorhen(medBounce, vedIndgang, 5), const HomeStretchPosition(0, 2));
    expect(hvorhen(medBounce, vedIndgang, 7), const HomeStretchPosition(0, 0));
    expect(hvorhen(udenBounce, vedIndgang, 5), isNull,
        reason: 'husreglen (§11): klassisk og 25 år har IKKE bounce');
  });

  test('rækker tilbageløbet ud over målet, fortsætter brikken ud på banen', () {
    // 8 = 4 ind + 3 tilbage til yderste cirkel + 1 ud på feltet før UD (59).
    expect(hvorhen(medBounce, vedIndgang, 8), const TrackPosition(59));
    expect(hvorhen(medBounce, vedIndgang, 9), const TrackPosition(58));
  });

  test('den vender på den dybeste FRIE cirkel — ingen overspringning', () {
    // Inderste cirkel (3) er optaget: der vendes på 2.
    final List<PiecePosition> enIMaal = <PiecePosition>[
      const TrackPosition(59),
      const HomeStretchPosition(0, 3),
      ...startOf(0, skip: 2),
    ];
    expect(hvorhen(medBounce, enIMaal, 3), const HomeStretchPosition(0, 2));
    expect(hvorhen(medBounce, enIMaal, 4), const HomeStretchPosition(0, 1),
        reason: '3 ind til cirkel 2, så 1 tilbage');
  });

  test('en brik I MÅL er låst — den kan ikke flyttes', () {
    // p0.0 på den inderste cirkel = i mål.
    final List<PiecePosition> iMaal = <PiecePosition>[
      const HomeStretchPosition(0, 3),
      ...startOf(0, skip: 1),
    ];
    expect(hvorhen(medBounce, iMaal, 2), isNull);
  });

  test('en brik på en målcirkel, der IKKE er i mål, kan bounce videre', () {
    // p0.0 på yderste cirkel (0), dybere cirkler frie: ikke låst.
    final List<PiecePosition> yderst = <PiecePosition>[
      const HomeStretchPosition(0, 0),
      ...startOf(0, skip: 1),
    ];
    expect(hvorhen(medBounce, yderst, 3), const HomeStretchPosition(0, 3));
    expect(hvorhen(medBounce, yderst, 5), const HomeStretchPosition(0, 1),
        reason: '3 ind + 2 tilbage');
    // Tilbage OVER sin egen gamle plads: den er fri, for brikken har forladt den.
    expect(hvorhen(medBounce, yderst, 6), const HomeStretchPosition(0, 0));
  });

  test('bouncer brikken ud på banen, kan den slå en modstander', () {
    // 9 fra 59: ind (4) + tilbage (3) + ud på 59 (1) + 58 (1). Modstander på 58.
    final GameState s = makeState(
      variant: medBounce,
      cardRules: effectiveCardRules(medBounce, CardRules.defaults()),
      piecePositions: <List<PiecePosition>>[
        vedIndgang,
        <PiecePosition>[const TrackPosition(58), ...startOf(1, skip: 1)],
        startOf(2),
        startOf(3),
      ],
    );
    final Move m = Rules(s.geometry)
        .legalMoves(s, s.players[0], const PlayingCard(Rank.nine, Suit.spades))
        .singleWhere((Move m) => m.steps.first.pieceId == 'p0.0');
    expect(m.steps.single.to, const TrackPosition(58));
    expect(m.steps.single.capturedPieceId, 'p1.0');
  });

  test('tilbagevejen spærret af egen brik: trækket er ulovligt — ingen ny vending',
      () {
    // p0.0 ved indgangen, p0.1 på yderste cirkel (0), cirkel 1-3 frie.
    // 6 = 4 ind til inderste + 2 tilbage — men på vej tilbage står p0.1 på 0?
    // Nej: 6 ender på cirkel 1. 7 ville ende på 0, hvor p0.1 står → spærret.
    final List<PiecePosition> enYderst = <PiecePosition>[
      const TrackPosition(59),
      const HomeStretchPosition(0, 0),
      ...startOf(0, skip: 2),
    ];
    // Første cirkel optaget: p0.0 kan slet ikke komme ind.
    expect(hvorhen(medBounce, enYderst, 2), isNull);
    // p0.1 selv: fra 0 ind til 3 (3) + 3 tilbage ville passere sin egen
    // gamle plads og ende ... på 0 — fri, for den har forladt den.
    final List<PiecePosition> toIMaalet = <PiecePosition>[
      const HomeStretchPosition(0, 0),
      const HomeStretchPosition(0, 2),
      ...startOf(0, skip: 2),
    ];
    // p0.0 på 0, p0.1 på 2 (ikke i mål: 3 er fri). p0.0 frem: 1 er fri, 2
    // er optaget → vender på 1. Et kort på 3: 1 frem, 2 tilbage → forbi
    // cirkel 0 (sin egen, fri) og ud på banen (59).
    expect(hvorhen(medBounce, toIMaalet, 3), const TrackPosition(59));
  });

  test('bounce virker også midt i en deling (4×1-typen)', () {
    // Et delekort på 5 med én brik ved indgangen: alle 5 på den ene brik =
    // 4 ind + 1 tilbage. Uden bounce findes trækket ikke.
    const Map<Rank, CardRuleConfig> del5 = <Rank, CardRuleConfig>{
      Rank.five: CardRuleConfig(splitTotal: 5),
    };
    List<Move> traek(VariantConfig v) {
      final GameState s = makeState(
        variant: v,
        cardRules: effectiveCardRules(v, CardRules.defaults()),
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[const TrackPosition(59), ...startOf(0, skip: 1)],
          startOf(1), startOf(2), startOf(3),
        ],
      );
      return Rules(s.geometry)
          .legalMoves(s, s.players[0], const PlayingCard(Rank.five, Suit.spades));
    }
    const VariantConfig delMed = VariantConfig(
        id: 'd1', name: 'd1', goalBounce: true, cardRuleOverrides: del5);
    const VariantConfig delUden =
        VariantConfig(id: 'd2', name: 'd2', cardRuleOverrides: del5);
    expect(traek(delMed).map((Move m) => m.steps.single.to).toSet(),
        <PiecePosition>{const HomeStretchPosition(0, 2)});
    expect(traek(delUden), isEmpty);
  });
}
