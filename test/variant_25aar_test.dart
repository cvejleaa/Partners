// Varianter fase 3: Partners 25 år (forsmag) + Hopsakort-mekanikken (5↷).
//
// Beviser:
//  T1 registret indeholder p25 og resolver korrekt.
//  T2 p25 er strukturelt = klassisk (bræt uændret; kun kort adskiller).
//  T3 p25's kort adskiller sig PÅ 5-kortet (jumpsBlockade) og KUN dér.
//  T3b klassisk (ingen overrides) resolver til BASEN uændret — falder ikke
//     tilbage til CardRules.defaults() og taber dermed ikke admins live-regler.
//  T4 (kernen) motoren lader FAKTISK 5-kortet passere et blokeret startfelt
//     med p25's regler, men IKKE med klassiske regler — ende-til-ende.
//  T5 serialisering bevarer variant-id OG jumpsBlockade-flaget (round-trip).
//  T6 effectiveCardRules komponerer BASEN (ikke defaults()) med p25's overrides.
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
    test(
        'variantFromDoc: defensiv klampning af variantId fra et Firestore-doc '
        '(bruges af startGameFromLobby/createRematch/lobby-UI)', () {
      // Den normale sti: kendt string-id slås korrekt op.
      expect(variantFromDoc(<String, dynamic>{'variantId': 'p25'}).id, 'p25');
      // Fjendtlig/skæv lobby-deltager: variantId er IKKE en string (fx et tal
      // eller et map) — skal klampes til klassisk, ikke kaste eller vælte
      // starten. Muteres `is String`-tjekket væk (fx til blot `!= null`),
      // bliver denne assertion rød (enten et forkert id eller en cast-fejl).
      expect(variantFromDoc(<String, dynamic>{'variantId': 42}).id, 'classic');
      expect(
          variantFromDoc(<String, dynamic>{
            'variantId': <String, dynamic>{'hack': true}
          }).id,
          'classic');
      // Ukendt string-id og manglende felt klampes også til klassisk.
      expect(
          variantFromDoc(<String, dynamic>{'variantId': 'findes-ikke'}).id,
          'classic');
      expect(variantFromDoc(<String, dynamic>{}).id, 'classic');
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

  group('T3 — p25 overrider KUN de fem specialkort; resten arves fra basen',
      () {
    test('seedet er de fem bekræftede rangs; urørt rang = base', () {
      // Kun de fem specialkort står i override-mappet — resten kommer fra de
      // live regler. (Selve kort-indholdet bevises i M5,
      // variant_25aar_mekanikker_test.dart.)
      expect(partners25.cardRuleOverrides!.keys.toSet(),
          <Rank>{Rank.four, Rank.five, Rank.seven, Rank.nine, Rank.jack});
      final CardRuleConfig five = partners25.cardRuleOverrides![Rank.five]!;
      expect(five.jumpsBlockade, isTrue, reason: '5 skal kunne hoppe');
      expect(five.forwardSteps, <int>[5]);

      final CardRules classic = CardRules.defaults();
      final CardRules resolved = effectiveCardRules(partners25, classic);
      expect(resolved.forRank(Rank.five).jumpsBlockade, isTrue);
      // En urørt rang er identisk med basen (ingen skjult drift).
      expect(resolved.forRank(Rank.three).forwardSteps,
          classic.forRank(Rank.three).forwardSteps);
      // Klassisk 5 kan IKKE hoppe — det er præcis forskellen.
      expect(classic.forRank(Rank.five).jumpsBlockade, isFalse);
    });
  });

  group(
      'T3b — klassisk (cardRuleOverrides == null): effectiveCardRules returnerer '
      'BASEN uændret, ikke defaults()', () {
    test(
        'admin-tilpassede LIVE regler overlever klassisk resolve (falder '
        'IKKE tilbage til CardRules.defaults())', () {
      // Basen AFVIGER bevidst fra defaults() (admin har gjort Dame til
      // byttekort i stedet for 12 frem) — så testen ikke er en tautologi.
      final CardRules live = CardRules.defaults().withRank(
          Rank.queen, const CardRuleConfig(swap: true, forwardSteps: <int>[]));
      final CardRules resolved = effectiveCardRules(classicVariant, live);
      // Muteres effectiveCardRules til at returnere CardRules.defaults() (eller
      // bygge et nyt regelsæt) i null-grenen frem for selve basen, taber
      // klassisk admins live-regler tavst — denne assertion bliver rød.
      expect(resolved.forRank(Rank.queen).swap, isTrue,
          reason: 'klassisk uden overrides må bevare admins live-regler');
      expect(resolved.forRank(Rank.queen).forwardSteps, isEmpty);
      // Den ellers upåvirkede Es er stadig som live (=defaults for Es).
      expect(resolved.forRank(Rank.ace).forwardSteps, live.forRank(Rank.ace).forwardSteps);
    });
  });

  group('T6 — varianten ARVER basens overrides (fx admin-byttekort på Knægt)', () {
    test('effectiveCardRules bevarer basens Knægt-swap OG tilføjer Hopsakortet',
        () {
      // De LIVE regler: admin har gjort Knægten til byttekort (det kort der
      // ellers ville være 11 frem). Varianten må ikke tabe det.
      final CardRules live = CardRules.defaults()
          .withRank(Rank.jack, const CardRuleConfig(swap: true));
      final CardRules resolved = effectiveCardRules(partners25, live);
      // Byttekortet fra basen bevares...
      expect(resolved.forRank(Rank.jack).swap, isTrue,
          reason: '25 år må ikke tavst tabe basens byttekort');
      // ...OG Hopsakortet lægges ovenpå. Muteres kompositionen til at bygge fra
      // defaults() frem for basen, taber Knægt-swap → denne assertion rød.
      expect(resolved.forRank(Rank.five).jumpsBlockade, isTrue);
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
      final GameState st =
          scenario(effectiveCardRules(partners25, CardRules.defaults()));
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
        cardRules: effectiveCardRules(partners25, CardRules.defaults()),
        variant: partners25,
      );
      final GameState back =
          gameStateFromMap(gameStateToMap(src));
      expect(back.variant.id, 'p25');
      // Det AFGØRENDE: de faktisk spillede regler (fra 'cr', ikke registret)
      // bærer hop-flaget efter round-trip.
      expect(back.cardRules.forRank(Rank.five).jumpsBlockade, isTrue);
    });

    test(
        'klassisk kort-map får IKKE jumpsBlockade-nøglen (bagud-kompat); '
        'p25s 5-kort får den', () {
      final Map<String, dynamic> classicFive =
          CardRules.defaults().toJson()['five'] as Map<String, dynamic>;
      // Nøglen må slet ikke stå for klassisk — ikke bare være false — så
      // gamle Firestore-docs (skrevet før feltet fandtes) forbliver
      // byte-identiske, og et manglende felt læses entydigt som false.
      expect(classicFive.containsKey('jumpsBlockade'), isFalse,
          reason: 'klassisk 5-kort må ikke skrive jumpsBlockade-nøglen');

      final Map<String, dynamic> p25Five =
          effectiveCardRules(partners25, CardRules.defaults())
              .toJson()['five'] as Map<String, dynamic>;
      expect(p25Five['jumpsBlockade'], isTrue,
          reason: 'p25s Hopsakort SKAL skrive nøglen som true');

      // Et gammelt/klassisk kort-map uden nøglen skal læses som false —
      // det er selve bagud-kompat-kontrakten.
      final CardRuleConfig fromOldDoc =
          CardRuleConfig.fromJson(<String, dynamic>{
        'exitStart': false,
        'forwardSteps': <int>[5],
        'swap': false,
      });
      expect(fromOldDoc.jumpsBlockade, isFalse);
    });
  });
}
