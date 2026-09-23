// Duo-trin 3: hvilke af spillerens to sæt må et træk bruge?
//
// Regelbogen (s. 3-4):
// - "Spilleren kan frit vælge mellem brikker fra begge sine startcirkler."
// - 4×1: "De fire felter kan fordeles mellem de brikker, man har i spil fra
//   SAMME startcirkel" — medmindre man kan få den sidste brik i mål ved den
//   ene cirkel; så må de overskydende felter bruges på den modsatte cirkels
//   brikker.
//
// Tre porte i motoren afgjorde det hver for sig (activePool, multi, split).
// Nu er det én vagt; klassisk er uændret (låst af fingeraftrykket).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'test_helpers.dart';

const VariantConfig duoForm = VariantConfig(
  id: 'duo-test',
  name: 'Duo-test',
  onePlayerPerTeam: true,
  exchangeRule: ExchangeRule.opponentSwap,
  cardRuleOverrides: <Rank, CardRuleConfig>{
    Rank.four: CardRuleConfig(splitTotal: 4), // Duos 4×1
  },
);

const PlayingCard three = PlayingCard(Rank.three, Suit.spades);
const PlayingCard ace = PlayingCard(Rank.ace, Suit.spades);
const PlayingCard fourByOne = PlayingCard(Rank.four, Suit.spades);

List<PiecePosition> startOf(int seat) =>
    <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(seat, s)];

GameState stilling(VariantConfig v, List<List<PiecePosition>> pos) => makeState(
      variant: v,
      cardRules: effectiveCardRules(v, CardRules.defaults()),
      piecePositions: pos,
    );

List<Move> traek(GameState s, PlayingCard c) =>
    Rules(s.geometry).legalMoves(s, s.players[0], c);

Set<int> ejere(Move m) => <int>{
      for (final MoveStep st in m.steps) int.parse(st.pieceId.substring(1, 2)),
    };

Set<String> brikker(List<Move> ms) =>
    <String>{for (final Move m in ms) m.steps.first.pieceId};

void main() {
  // Én brik ude i hvert af mine sæt (0 og 2); ingen af dem er færdige.
  List<List<PiecePosition>> beggeUde() => <List<PiecePosition>>[
        <PiecePosition>[const TrackPosition(10), ...startOf(0).skip(1)],
        startOf(1),
        <PiecePosition>[const TrackPosition(40), ...startOf(2).skip(1)],
        startOf(3),
      ];

  test('et almindeligt kort kan flytte en brik fra BEGGE mine sæt', () {
    expect(brikker(traek(stilling(duoForm, beggeUde()), three)),
        <String>{'p0.0', 'p2.0'});
    // Klassisk: makkerens brik er først til rådighed, når egne er hjemme.
    expect(brikker(traek(stilling(classicVariant, beggeUde()), three)),
        <String>{'p0.0'});
  });

  test('et startkort kan sætte ud fra BEGGE mine startcirkler', () {
    final List<List<PiecePosition>> alleInde = <List<PiecePosition>>[
      for (int s = 0; s < 4; s++) startOf(s),
    ];
    expect(brikker(traek(stilling(duoForm, alleInde), ace)),
        <String>{'p0.0', 'p2.0'});
    expect(brikker(traek(stilling(classicVariant, alleInde), ace)),
        <String>{'p0.0'});
  });

  test('4×1 blander IKKE mine to sæt, så længe intet sæt bliver færdigt', () {
    final List<Move> ms = traek(stilling(duoForm, beggeUde()), fourByOne);
    expect(ms, isNotEmpty);
    for (final Move m in ms) {
      expect(ejere(m), hasLength(1),
          reason: 'felterne skal fordeles mellem brikker fra SAMME startcirkel: '
              '${m.steps.map((MoveStep s) => s.pieceId).toList()}');
    }
    // Men hvert sæt kan bruge kortet for sig.
    expect(ms.any((Move m) => ejere(m).contains(0)), isTrue);
    expect(ms.any((Move m) => ejere(m).contains(2)), isTrue);
  });

  test('4×1: gør et sæt færdigt, må resten bruges på det andet sæt', () {
    // Sæt 0: tre brikker i mål, den sidste ét felt fra. Sæt 2: én brik ude.
    // 1 felt får sæt 0 i mål; de 3 overskydende går til sæt 2's brik.
    final GameState s = stilling(duoForm, <List<PiecePosition>>[
      <PiecePosition>[
        const HomeStretchPosition(0, 3),
        const HomeStretchPosition(0, 2),
        const HomeStretchPosition(0, 1),
        const TrackPosition(59),
      ],
      startOf(1),
      <PiecePosition>[const TrackPosition(40), ...startOf(2).skip(1)],
      startOf(3),
    ]);
    final List<Move> blandede = traek(s, fourByOne)
        .where((Move m) => ejere(m).length == 2)
        .toList();
    expect(blandede, isNotEmpty,
        reason: 'regelbogens undtagelse: sidste brik i mål, resten på det '
            'modsatte sæt');
    for (final Move m in blandede) {
      expect(m.steps.first.pieceId, 'p0.3',
          reason: 'det færdiggjorte sæt skal komme FØRST — sæt 2 kan ikke '
              'åbne sæt 0');
    }
  });
}
