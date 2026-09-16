// Kortværdien er nu UDLEDT af kortets evner i stedet for slået op i en fast
// rang-tabel. Det, der testes her, er RANGORDNINGEN — ikke vægtene.
//
// Grunden: vægtene er et gæt, og en test på konkrete tal ville bare være
// tabellen igen, skrevet et andet sted. Rangordningen er derimod en påstand
// om spillet, som kan være rigtig eller forkert — og som en realistisk
// mutation af formlen gør rød.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

void main() {
  final CardRules classic = CardRules.defaults();
  final CardRules p25 = effectiveCardRules(partners25, CardRules.defaults());

  int v(CardRules r, Rank rank) =>
      cardAbilityValue(r, PlayingCard(rank, Suit.spades));

  group('klassisk', () {
    test('esset slår damen — fælden enhver ren rækkevidde-formel går i', () {
      // Esset rykker 1 ELLER 11; damen rykker 12. Måles kun rækkevidde,
      // vinder damen — og AI'en ville forære esset væk. Det er den enkelt-
      // fejl, der ville gøre AI'en DÅRLIGERE i kassens egne kort.
      expect(v(classic, Rank.ace), greaterThan(v(classic, Rank.queen)));
    });

    test('fireren er et TOP-kort, ikke et bundkort', () {
      // Den gamle tabel gav fireren 1 af 12 — næstlavest. Men baglæns fra
      // eget UD-felt er spillets største enkelt-tempo: en brik lige ude har
      // hele ringen til sin egen hjemindgang, og 4 tilbage sætter den 4
      // felter fra mål.
      expect(v(classic, Rank.four), greaterThan(v(classic, Rank.queen)));
      expect(v(classic, Rank.four), greaterThan(v(classic, Rank.ten)));
    });

    test('delekortet slår de høje enkelt-kort', () {
      expect(v(classic, Rank.seven), greaterThan(v(classic, Rank.queen)));
    });

    test('et lille enkelt-kort er stadig det mindst værd', () {
      expect(v(classic, Rank.two), lessThan(v(classic, Rank.four)));
      expect(v(classic, Rank.two), lessThan(v(classic, Rank.seven)));
    });
  });

  group('25 år', () {
    test('alle fem specialkort slår den bedste almindelige (damen)', () {
      // Den gamle tabel smed 4×1 (score 1), 5↷ (2) og 7/+2−5 (4) FØR en
      // dame (9). Tre af kassens fem specialkort røg først.
      for (final Rank r in <Rank>[
        Rank.four, // 4×1
        Rank.five, // 5↷ hopsakortet
        Rank.seven, // 7 ELLER +2−5
        Rank.nine, // byt ELLER 9
        Rank.jack, // 11 ELLER 1×1
      ]) {
        expect(v(p25, r), greaterThan(v(p25, Rank.queen)),
            reason: '$r er et specialkort og må ikke gives væk før en dame');
      }
    });

    test('hopsakortet slår en almindelig femmer', () {
      // Samme rækkevidde, men 5↷ kan passere et blokeret startfelt. Uden
      // evne-tillægget ville de to være lige, og AI'en ligeglad.
      expect(v(p25, Rank.five), greaterThan(v(classic, Rank.five)));
    });
  });

  // ---------------------------------------------------------------------
  // PAR-TESTS: hver evne-vægt isoleret.
  //
  // De fire rangordnings-tests ovenfor koder en påstand om SPILLET ("esset
  // slår damen") og skal blive. Men de beviser ikke, at den enkelte
  // evne-vægt findes: så længe kortet også har et fremad-træk, kunne
  // evne-tillægget fjernes helt, og rangordningen holdt alligevel — en
  // mutation af netop den linje stod grøn (TM-fund).
  //
  // Her varieres derfor ÉT flag ad gangen, med samme forwardSteps på begge
  // sider. Det kunne ikke lade sig gøre før: "kan-vælge"-bonussen talte de
  // samme evner én gang til, så et ekstra flag ændrede to ting på én gang.
  // ---------------------------------------------------------------------
  int valueOf(CardRuleConfig cfg) => cardAbilityValue(
      CardRules.defaults().withRank(Rank.six, cfg),
      const PlayingCard(Rank.six, Suit.clubs));

  group('hver evne tæller for sig', () {
    const CardRuleConfig basis = CardRuleConfig(forwardSteps: <int>[6]);

    test('baglæns', () {
      expect(
          valueOf(const CardRuleConfig(
              forwardSteps: <int>[6], backwardSteps: 6)),
          greaterThan(valueOf(basis)));
    });

    test('byt', () {
      expect(valueOf(const CardRuleConfig(forwardSteps: <int>[6], swap: true)),
          greaterThan(valueOf(basis)));
    });

    test('sekvens (frem og så tilbage)', () {
      expect(
          valueOf(const CardRuleConfig(
              forwardSteps: <int>[6], seqForward: 2, seqBackward: 5)),
          greaterThan(valueOf(basis)));
    });

    test('flere brikker', () {
      expect(
          valueOf(const CardRuleConfig(
              forwardSteps: <int>[6], multiPieces: 2, multiSteps: 1)),
          greaterThan(valueOf(basis)));
    });

    test('blokade-spring', () {
      expect(
          valueOf(const CardRuleConfig(
              forwardSteps: <int>[6], jumpsBlockade: true)),
          greaterThan(valueOf(basis)));
    });

    test('deling', () {
      // Delekortet har ingen forwardSteps — sammenlign derfor mod et kort med
      // samme rækkevidde udtrykt som et almindeligt træk.
      expect(valueOf(const CardRuleConfig(splitTotal: 6)),
          greaterThan(valueOf(basis)));
    });

    test('flere afstande at vælge imellem tæller OGSÅ', () {
      // Den bonus der er tilbage: at kunne vælge sin afstand. Esset (1 ELLER
      // 11) er stærkere end det lange træk alene.
      expect(valueOf(const CardRuleConfig(forwardSteps: <int>[1, 6])),
          greaterThan(valueOf(basis)));
    });
  });

  test('UD-kortet har ingen egenværdi — dets værdi er kontekst', () {
    // Et rent UD-kort kan intet andet end at sætte ud. Er der ingen brikker
    // i start, er det dødt. Exit-hensynet ligger derfor i AI'en, hvor
    // stillingen kendes — ikke i kortets tal.
    expect(cardAbilityValue(classic, const PlayingCard.exit(0)), 0);
  });
}
