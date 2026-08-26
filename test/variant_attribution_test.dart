// Attribution + id-bevarende serialisering — fundamentet under statistik pr.
// variant.
//
// De to fælder testene låser:
// 1. `vid` skrives TILBAGE af klienter der ikke kender varianten (hvert
//    online-træk, AI-træk hos værten, autosave-resume). Klampede
//    gameStateFromMap et ukendt id til 'classic', ville ét træk forgifte
//    doc'et permanent — og dermed statistik-attributionen for alle fire
//    spillere. Derfor round-trip-testen på et UKENDT id.
// 2. Attributions-nøglen er det RÅ state.vid — aldrig normaliseret gennem
//    variantFromId (det ville folde enhver ukendt variant i classic-spanden),
//    og aldrig topniveau-'variantId' (AI-docs har det ikke, og online-feltet
//    kan ændres af ethvert medlem midt i spillet).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';

import 'test_helpers.dart';

void main() {
  group('variantForState — id-bevarende resolver til gemt state', () {
    test('kendte id\'er → deres config', () {
      expect(variantForState('classic').id, 'classic');
      expect(variantForState('p25').id, 'p25');
      expect(variantForState('p25').feltColor, partners25.feltColor);
    });

    test('UKENDT velformet id bevares (klassisk-formet, id intakt)', () {
      final v = variantForState('cv-min-variant');
      expect(v.id, 'cv-min-variant');
      // Klassisk form: samme geometri, så spillet renderer og spiller korrekt
      // ('cr' bærer i forvejen de opløste kort).
      expect(v.geometry.trackLength, classicVariant.geometry.trackLength);
      expect(v.playerCount, 4);
    });

    test('manglende/skævt id klampes stadig til klassisk', () {
      expect(variantForState(null).id, 'classic');
      expect(variantForState('').id, 'classic');
      expect(variantForState('IKKE gyldigt id!').id, 'classic');
      expect(variantForState('x' * 33).id, 'classic'); // for langt
    });
  });

  group('round-trip af vid gennem gameStateFromMap/gameStateToMap', () {
    test('ukendt id overlever serialiserings-round-trippet', () {
      final Map<String, dynamic> m = gameStateToMap(makeState());
      m['vid'] = 'cv-x';
      // Muteres gameStateFromMap tilbage til den klampende variantFromId,
      // bliver dette 'classic' → rød. Det er PRÆCIS den stille datatabs-fejl
      // QC fandt: én ikke-hydreret klients træk gør spillet klassisk for alle.
      expect(gameStateToMap(gameStateFromMap(m))['vid'], 'cv-x');
    });

    test('kendte id\'er round-tripper uændret', () {
      final Map<String, dynamic> m =
          gameStateToMap(makeState(variant: partners25));
      expect(gameStateToMap(gameStateFromMap(m))['vid'], 'p25');
    });
  });

  group('variantIdOfGameDoc — den rå attributions-nøgle', () {
    test('state.vid vinder over topniveau-variantId (UENIGHED, ikke fravær)',
        () {
      // Denne test består IKKE med implementationen "variantFromDoc ??
      // state.vid" — topniveau siger classic, state siger p25.
      expect(
          variantIdOfGameDoc(<String, dynamic>{
            'variantId': 'classic',
            'state': <String, dynamic>{'vid': 'p25'},
          }),
          'p25');
    });

    test('ukendt id returneres RÅT — ikke foldet til classic', () {
      expect(
          variantIdOfGameDoc(<String, dynamic>{
            'state': <String, dynamic>{'vid': 'cv-x'},
          }),
          'cv-x');
    });

    test('manglende/skævt → classic (historiske docs)', () {
      expect(variantIdOfGameDoc(<String, dynamic>{}), 'classic');
      expect(
          variantIdOfGameDoc(<String, dynamic>{
            'state': <String, dynamic>{'hn': 3},
          }),
          'classic');
      expect(
          variantIdOfGameDoc(<String, dynamic>{
            'state': <String, dynamic>{'vid': 42},
          }),
          'classic');
      expect(variantIdOfGameDoc(<String, dynamic>{'state': 'nope'}), 'classic');
    });

    test('vanformet STRENG-vid → classic, ikke returneret rå (formen '
        'valideres her, ikke kun typen)', () {
      // De øvrige tests dækker kun ikke-String vid'er (fravær/42/'nope').
      // Fjernes selve regex-tjekket i variantIdOfGameDoc (`vid is String ?
      // vid : 'classic'` uden _kVariantIdForm), passerer de stadig — kun
      // denne test fanger det, fordi vid HER er en String, blot vanformet.
      expect(
          variantIdOfGameDoc(<String, dynamic>{
            'state': <String, dynamic>{'vid': 'IKKE gyldigt id!'},
          }),
          'classic');
      expect(
          variantIdOfGameDoc(<String, dynamic>{
            'state': <String, dynamic>{'vid': 'x' * 33}, // for langt
          }),
          'classic');
    });
  });
}
