// Admin-redigering af kortregler pr. variant (klassisk | 25 år, side om side).
//
// Beviser de RENE dele af kæden (Firestore-IO dækkes af emulator-testen i
// firestore-tests/rules.test.mjs — merge/deleteField-semantikken):
//  A1 overrides-serialisering: round-trip inkl. jumpsBlockade; partielt map
//     forbliver partielt; skæve værdier springes over (defensivt).
//  A2 effectiveCardRules-precedens: GEMTE overrides vinder over kode-seedet —
//     også når de SLÅR NOGET FRA (admin fjerner Hopsakortet: seedet må ikke
//     tavst genindsætte det). Uden gemte → seed. Klassisk → basen uændret.
//  A3 storedOverridesFor: defensiv klampning af doc-læsning på alle niveauer.
//  A4 payload-former: klassisk-gemmet ejer KUN 'rules'; variant-gemmet KUN
//     'variants' — kombineret med mergeFields kan de ikke slette hinanden.
//  A5 deckSanityWarnings: uspillelige/ødelagte sæt advares; klassisk er ren;
//     25 års sekvens FANGET i split/multi advares (kan ikke vælges i UI).
//  A6 CardRules.sameConfig dækker ALLE felter inkl. jumpsBlockade OG 25 års
//     fire nye felter hver for sig (UI-sync).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/state/card_rules_payload.dart';

void main() {
  group('A1 — overrides-serialisering', () {
    test('round-trip bevarer jumpsBlockade og forbliver PARTIELT', () {
      final Map<Rank, CardRuleConfig> src = <Rank, CardRuleConfig>{
        Rank.five:
            const CardRuleConfig(forwardSteps: <int>[5], jumpsBlockade: true),
        Rank.jack: const CardRuleConfig(swap: true),
      };
      final Map<Rank, CardRuleConfig> back =
          cardRuleOverridesFromJson(cardRuleOverridesToJson(src));
      expect(back.keys.toSet(), <Rank>{Rank.five, Rank.jack},
          reason: 'et partielt map må IKKE udfyldes med defaults');
      expect(back[Rank.five]!.jumpsBlockade, isTrue);
      expect(back[Rank.jack]!.swap, isTrue);
    });

    test('skæve værdier (ukendt rang / ikke-map) springes over', () {
      final Map<Rank, CardRuleConfig> back =
          cardRuleOverridesFromJson(<String, dynamic>{
        'five': <String, dynamic>{'forwardSteps': <int>[5]},
        'findesIkke': <String, dynamic>{'swap': true},
        'jack': 42, // ikke et map
      });
      expect(back.keys.toList(), <Rank>[Rank.five]);
    });
  });

  group('A2 — effectiveCardRules-precedens (kernen)', () {
    test('GEMTE overrides vinder — også når de SLÅR hoppet FRA', () {
      // Admin har afskrevet sit fysiske sæt og fjernet Hopsakortet fra 5'eren.
      final Map<Rank, CardRuleConfig> stored = <Rank, CardRuleConfig>{
        Rank.five: const CardRuleConfig(forwardSteps: <int>[5]),
      };
      final CardRules r = effectiveCardRules(
          partners25, CardRules.defaults(),
          stored: stored);
      // Muteres resolveren til stadig at anvende kode-seedet (fx
      // `stored ?? seed` byttet om, eller seed lagt ovenpå til sidst), bliver
      // denne RØD: seedet ville genindsætte jumpsBlockade=true.
      expect(r.forRank(Rank.five).jumpsBlockade, isFalse,
          reason: 'admins fravalg må ikke overtrumfes af kode-seedet');
      expect(r.forRank(Rank.five).forwardSteps, <int>[5]);
    });

    test('uden gemte → kode-seedet (Hopsakortet) gælder', () {
      final CardRules r =
          effectiveCardRules(partners25, CardRules.defaults());
      expect(r.forRank(Rank.five).jumpsBlockade, isTrue);
    });

    test('gemte overrides rører kun de nævnte rangs; resten = basen', () {
      final CardRules live = CardRules.defaults()
          .withRank(Rank.jack, const CardRuleConfig(swap: true));
      final CardRules r = effectiveCardRules(partners25, live,
          stored: <Rank, CardRuleConfig>{
            Rank.queen: const CardRuleConfig(forwardSteps: <int>[12], swap: true),
          });
      expect(r.forRank(Rank.queen).swap, isTrue); // den gemte
      expect(r.forRank(Rank.jack).swap, isTrue); // arvet fra basen
      // 5'eren er IKKE i de gemte → den arver BASEN (ikke seedet): gemte
      // overrides ERSTATTER seedet som helhed, de blandes ikke.
      expect(r.forRank(Rank.five).jumpsBlockade, isFalse);
    });

    test('klassisk: basen uændret uanset stored=null', () {
      final CardRules live = CardRules.defaults()
          .withRank(Rank.queen, const CardRuleConfig(swap: true));
      final CardRules r = effectiveCardRules(classicVariant, live);
      expect(identical(r, live), isTrue,
          reason: 'ingen overrides → PRÆCIS basen, ikke en kopi/defaults');
    });
  });

  group('A3 — storedOverridesFor: defensiv doc-læsning', () {
    test('gyldigt variants-map parses', () {
      final Map<Rank, CardRuleConfig>? s = storedOverridesFor(<String, dynamic>{
        'p25': <String, dynamic>{
          'rules': <String, dynamic>{
            'five': <String, dynamic>{'forwardSteps': <int>[5]},
          },
        },
      }, 'p25');
      expect(s, isNotNull);
      expect(s!.keys.toList(), <Rank>[Rank.five]);
    });

    test('ikke-map på ETHVERT niveau → null (fald til seed)', () {
      expect(storedOverridesFor(null, 'p25'), isNull);
      expect(storedOverridesFor('hack', 'p25'), isNull);
      expect(storedOverridesFor(<String, dynamic>{'p25': 42}, 'p25'), isNull);
      expect(
          storedOverridesFor(
              <String, dynamic>{'p25': <String, dynamic>{'rules': 'x'}},
              'p25'),
          isNull);
      // Andet variant-id → null.
      expect(
          storedOverridesFor(<String, dynamic>{
            'p25': <String, dynamic>{'rules': <String, dynamic>{}}
          }, 'andet'),
          isNull);
    });
  });

  group('A4 — payload-former (merge-kontrakten)', () {
    test('klassisk-gemmet ejer KUN rules', () {
      // Kombineret med SetOptions(mergeFields: [rules, updatedAt]) kan et
      // klassisk-gem dermed ALDRIG slette variants-feltet. Muteres payloaden
      // til også at bære variants (eller mergeFields droppes for et rent set),
      // fanger emulator-testen i rules.test.mjs sletningen.
      expect(classicSavePayload(<String, dynamic>{}).keys.toList(),
          <String>['rules']);
    });

    test('variant-gemmet ejer KUN variants — navn/beskrivelse kun når udfyldt',
        () {
      final Map<String, dynamic> p = variantSavePayload('p25',
          rulesJson: <String, dynamic>{}, name: ' Partners 25 år ');
      expect(p.keys.toList(), <String>['variants']);
      final Map<String, dynamic> entry =
          (p['variants'] as Map<String, dynamic>)['p25']
              as Map<String, dynamic>;
      expect(entry['name'], 'Partners 25 år'); // trimmet
      expect(entry.containsKey('description'), isFalse,
          reason: 'tom beskrivelse skrives ikke');
    });
  });

  group('A5 — deckSanityWarnings', () {
    test('klassisk default er ren (ingen advarsler)', () {
      expect(deckSanityWarnings(CardRules.defaults()), isEmpty);
    });

    test('intet ud-kort / intet frem-kort / 3+ hop advares', () {
      // Alt fjernet: både "ingen ud" og "ingen frem".
      final CardRules dead = CardRules(<Rank, CardRuleConfig>{
        for (final Rank r in Rank.values) r: const CardRuleConfig(),
      });
      final List<String> w1 = deckSanityWarnings(dead);
      expect(w1.length, 2);

      // 3 hop-kort → blokade-advarsel.
      CardRules hoppy = CardRules.defaults();
      for (final Rank r in <Rank>[Rank.two, Rank.three, Rank.five]) {
        hoppy = hoppy.withRank(
            r,
            hoppy.forRank(r).copyWith(jumpsBlockade: true));
      }
      final List<String> w2 = deckSanityWarnings(hoppy);
      expect(w2, hasLength(1));
      expect(w2.single, contains('blokade'));
    });

    test(
        'sekvens (frem+tilbage) FANGET i split/multi-kort advares (kan ikke '
        'vælges brik-for-brik i spilfladen)', () {
      // 25 år-motoren: et kort kan i teorien få BÅDE splitTotal/multi OG
      // seqForward/seqBackward slået til fra admin. Spilfladens flertrins-
      // flow kan ikke udtrykke sekvensen dér (samme brik skal vælges to
      // gange) — det skal advares, ikke tabes tavst.
      CardRules trapped = CardRules.defaults();
      trapped = trapped.withRank(
          Rank.seven,
          trapped
              .forRank(Rank.seven)
              .copyWith(seqForward: 2, seqBackward: 5, splitTotal: 7));
      final List<String> w = deckSanityWarnings(trapped);
      expect(w.any((s) => s.contains('frem+tilbage')), isTrue,
          reason:
              'sekvens+split-kombinationen på ét kort skal give en advarsel');
    });
  });

  group('A5b — nye mekanik-vagter', () {
    test('hasFwdThenBack kræver >= 1/>= 1 (skævt doc kan ikke få kortet til '
        'at lyve)', () {
      // Et Firestore-doc med seqForward: 0 må hverken vise chip/tutorial-tekst
      // eller nå motoren — én vagt i getteren.
      expect(
          const CardRuleConfig(seqForward: 0, seqBackward: 5).hasFwdThenBack,
          isFalse);
      expect(
          const CardRuleConfig(seqForward: 2, seqBackward: 0).hasFwdThenBack,
          isFalse);
      expect(
          const CardRuleConfig(seqForward: 2, seqBackward: 5).hasFwdThenBack,
          isTrue);
    });

    test('anyForward kender multi/sekvens (ingen falsk "ingen kort kan '
        'flytte frem")', () {
      // Al fremad-bevægelse ligger i et multi-kort — det er et spilbart sæt.
      final CardRules rules = CardRules(<Rank, CardRuleConfig>{
        Rank.ace: const CardRuleConfig(exitStart: true),
        Rank.jack: const CardRuleConfig(multiPieces: 2, multiSteps: 1),
      });
      final List<String> w = deckSanityWarnings(rules);
      expect(w.where((x) => x.contains('flytte frem')), isEmpty,
          reason: 'multi ER fremad-bevægelse');
    });
  });

  group('A6 — sameConfig dækker alle felter (UI-sync)', () {
    test('to configs der KUN afviger på jumpsBlockade er IKKE ens', () {
      // Muteres sameConfig til at glemme jumpsBlockade (som den gamle
      // _sameConfig i admin-skærmen), bliver denne rød — og admin-UI'et ville
      // vise en løgn efter et load der kun flipper hop.
      const CardRuleConfig a = CardRuleConfig(forwardSteps: <int>[5]);
      const CardRuleConfig b =
          CardRuleConfig(forwardSteps: <int>[5], jumpsBlockade: true);
      expect(CardRules.sameConfig(a, b), isFalse);
      expect(CardRules.sameConfig(a, a), isTrue);
    });

    test(
        'dækker OGSÅ 25 års nye felter (seqForward/seqBackward/multiPieces/'
        'multiSteps) — hver for sig', () {
      // Hver linje i sameConfig er sin EGEN vagt. Muteres én af de fire nye
      // felt-tjek væk (fx glemmes multiSteps), bliver PRÆCIS den test rød —
      // ikke de andre tre, som stadig sammenligner deres eget felt korrekt.
      const CardRuleConfig base =
          CardRuleConfig(forwardSteps: <int>[7], seqForward: 2, seqBackward: 5);
      expect(
          CardRules.sameConfig(
              base, const CardRuleConfig(forwardSteps: <int>[7], seqForward: 3, seqBackward: 5)),
          isFalse,
          reason: 'seqForward alene skal gøre configs forskellige');
      expect(
          CardRules.sameConfig(
              base, const CardRuleConfig(forwardSteps: <int>[7], seqForward: 2, seqBackward: 4)),
          isFalse,
          reason: 'seqBackward alene skal gøre configs forskellige');
      const CardRuleConfig multiBase =
          CardRuleConfig(forwardSteps: <int>[11], multiPieces: 2, multiSteps: 1);
      expect(
          CardRules.sameConfig(
              multiBase,
              const CardRuleConfig(
                  forwardSteps: <int>[11], multiPieces: 3, multiSteps: 1)),
          isFalse,
          reason: 'multiPieces alene skal gøre configs forskellige');
      expect(
          CardRules.sameConfig(
              multiBase,
              const CardRuleConfig(
                  forwardSteps: <int>[11], multiPieces: 2, multiSteps: 2)),
          isFalse,
          reason: 'multiSteps alene skal gøre configs forskellige');
      expect(CardRules.sameConfig(base, base), isTrue);
      expect(CardRules.sameConfig(multiBase, multiBase), isTrue);
    });
  });

  group('A7 — variantDisplayName/Description: admins tekst vinder, trimmet',
      () {
    test('gemt navn/beskrivelse bruges (trimmet); tom beskrivelse falder '
        'tilbage til kode-teksten', () {
      final Map<String, dynamic> raw = <String, dynamic>{
        'p25': <String, dynamic>{'name': '  Mit navn  ', 'description': ''},
      };
      // Muteres funktionen til altid at returnere v.name (ignorerer admins
      // gemte tekst), bliver denne rød.
      expect(variantDisplayName(partners25, raw), 'Mit navn');
      // Tom streng skal IKKE overtrumfe kode-beskrivelsen (kun ikke-tomt gør).
      expect(variantDisplayDescription(partners25, raw), partners25.description);
    });

    test('intet gemt / ikke-map → kode-teksten (fallback), ikke tom/null', () {
      expect(variantDisplayName(partners25, null), partners25.name);
      expect(variantDisplayName(partners25, 'hack'), partners25.name);
      expect(variantDisplayName(partners25, <String, dynamic>{}),
          partners25.name);
      expect(variantDisplayDescription(classicVariant, null),
          classicVariant.description);
    });
  });
}
