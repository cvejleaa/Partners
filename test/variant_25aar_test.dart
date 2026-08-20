// Varianter fase 3: Partners 25 år (forsmag) + Hopsakort-mekanikken (5↷).
//
// Beviser:
//  T1 registret indeholder p25 og resolver korrekt.
//  T2 p25 er strukturelt = klassisk (bræt uændret; kun kort adskiller).
//  T3 p25's kort adskiller sig PÅ 5-kortet (jumpsBlockade) og KUN dér.
//  T4 (kernen) motoren lader FAKTISK 5-kortet passere et blokeret startfelt
//     med p25's regler, men IKKE med klassiske regler — ende-til-ende.
//  T5 serialisering bevarer variant-id OG jumpsBlockade-flaget (round-trip).
//
// Hver test er mutations-følsom: fjernes p25-override, ~/segments-delegationen
// eller jumpsBlockade-honoreringen i _advanceFrom, bliver en test rød.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';

import 'test_helpers.dart';

void main() {
  group('T1 — registret', () {
    test('kAllVariants indeholder klassisk og p25', () {
      expect(kAllVariants.map((VariantConfig v) => v.id),
          containsAll(<String>['classic', 'p25']));
    });
    test('variantFromId slår p25 op; ukendt → klassisk', () {
      expect(variantFromId('p25').id, 'p25');
      expect(variantFromId('findes-ikke').id, 'classic');
      expect(variantFromId(null).id, 'classic');
    });
  });

  group('T2 — p25 er strukturelt = klassisk', () {
    test('geometri felt-for-felt lig klassisk (4/60/4)', () {
      final BoardGeometry g = partners25.geometry;
      final BoardGeometry c = classicVariant.geometry;
      expect(g.trackLength, c.trackLength);
      expect(g.homeStretchLength, c.homeStretchLength);
      expect(g.segments, c.segments);
      expect(partners25.piecesPerPlayer, 4);
    });
  });

  group('T3 — p25s kort adskiller sig KUN på 5-kortet', () {
    test('5-kortet er Hopsakortet (frem 5 + jumpsBlockade), 3-kortet uændret', () {
      final CardRules p25 = partners25.cardRules!;
      final CardRules classic = CardRules.defaults();
      final CardRuleConfig five = p25.forRank(Rank.five);
      expect(five.jumpsBlockade, isTrue, reason: '5 skal kunne hoppe');
      expect(five.forwardSteps, <int>[5]);
      // Klassisk 5 kan IKKE hoppe — det er præcis forskellen.
      expect(classic.forRank(Rank.five).jumpsBlockade, isFalse);
      // En urørt rang er identisk med klassisk (ingen skjult drift).
      expect(p25.forRank(Rank.three).forwardSteps,
          classic.forRank(Rank.three).forwardSteps);
      expect(p25.forRank(Rank.three).jumpsBlockade, isFalse);
    });
  });

  group('T4 — motoren: 5-kortet passerer et blokeret startfelt (kun med p25)', () {
    // Opsætning: modstander (sæde 1) står på sit EGET UD-felt (indeks 15) og
    // spærrer passage. Vores brik står på felt 11. En 5'er skal passere UD-15:
    // 11→12→13→14→[UD15 spærret]→16→17. Klassisk: spærret (intet træk). p25:
    // hopper og lander på felt 17.
    GameState scenario(CardRules rules) => makeState(
          phase: GamePhase.play,
          cardRules: rules,
          piecePositions: <List<PiecePosition>>[
            <PiecePosition>[
              const TrackPosition(11), // vores brik der skal flytte
              const StartPosition(0, 1),
              const StartPosition(0, 2),
              const StartPosition(0, 3),
            ],
            <PiecePosition>[
              const TrackPosition(15), // modstander PÅ sit eget UD → blokade
              const StartPosition(1, 1),
              const StartPosition(1, 2),
              const StartPosition(1, 3),
            ],
            <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(2, s)],
            <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
          ],
        );

    bool landsAt17(List<Move> moves) => moves.any((Move m) => m.steps.any(
        (MoveStep s) =>
            s.pieceId == 'p0.0' && s.to == const TrackPosition(17)));

    const PlayingCard five = PlayingCard(Rank.five, Suit.spades);

    test('klassisk 5: blokeret — brikken kan IKKE nå felt 17', () {
      final GameState st = scenario(CardRules.defaults());
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], five);
      expect(landsAt17(moves), isFalse,
          reason: 'uden hop spærrer UD-15 passagen');
    });

    test('p25 5 (Hopsakort): passerer blokaden og lander på felt 17', () {
      final GameState st = scenario(partners25.cardRules!);
      final List<Move> moves =
          Rules(st.geometry).legalMoves(st, st.players[0], five);
      expect(landsAt17(moves), isTrue,
          reason: 'jumpsBlockade skal lade 5 passere UD-15');
    });
  });

  group('T5 — serialisering bevarer variant + jumpsBlockade', () {
    test('round-trip beholder vid=p25 og 5-kortets hop', () {
      final GameState src = GameState(
        players: makeState().players,
        geometry: partners25.geometry,
        deck: <PlayingCard>[],
        discard: <PlayingCard>[],
        dealerIndex: 0,
        currentPlayerIndex: 0,
        phase: GamePhase.play,
        handNumber: 1,
        cardRules: partners25.cardRules,
        variant: partners25,
      );
      final GameState back =
          gameStateFromMap(gameStateToMap(src));
      expect(back.variant.id, 'p25');
      // Det AFGØRENDE: de faktisk spillede regler (fra 'cr', ikke registret)
      // bærer hop-flaget efter round-trip.
      expect(back.cardRules.forRank(Rank.five).jumpsBlockade, isTrue);
    });
  });
}
