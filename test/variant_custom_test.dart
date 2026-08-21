// Admin-definerede varianter (Del B): kuraterede temaer, ren materialisering
// (variantFromRaw), slug-id'er, picker-lister og entry-payload-kontrakten.
//
// Kontrast-låsene beregnes EKSAKT her (WCAG relativ luminans), ikke påstås:
// - bord/felt ligger i samme luminans-bånd som klassisk grøn og 25 år-navy,
//   så hvid tekst og brik-kontrast aldrig er ringere end de indbyggede;
// - badge-farverne har ≥4,5:1 mod hvid 13px-tekst (informationsbæreren).
// Muteres en tema-farve til noget lysere/svagere, bliver båndet/ratioen rød.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/state/card_rules_payload.dart';
import 'package:partners/state/variant_card_rules_controller.dart';

import 'test_helpers.dart';

/// WCAG relativ luminans af en farve (sRGB-linearisering).
double _lum(Color c) {
  double lin(double ch) => ch <= 0.04045
      ? ch / 12.92
      : math.pow((ch + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

/// WCAG-kontrastforhold mellem to farver.
double _contrast(Color a, Color b) {
  final double la = _lum(a), lb = _lum(b);
  final double hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('kuraterede temaer — kontrast-låse (beregnet, ikke påstået)', () {
    test('bord/felt ligger i de indbyggedes luminans-bånd (brik-paritet)', () {
      // Båndet er defineret af de fire indbyggede referencer: klassisk
      // 0,0182/0,0262 og navy 0,0178/0,0260. Et tema uden for båndet ville
      // enten koste hvid-tekst-kontrast (lysere) eller kulør (mørkere).
      // Grænserne er skrevet så STRAMT at fx den gamle grønne felt-farve som
      // tema-TABLE (0,0262 > 0,0186) ville være rød.
      for (final VariantTheme t in kVariantThemes) {
        expect(_lum(t.tableColor), inInclusiveRange(0.0170, 0.0186),
            reason: '${t.id} tableColor uden for bånd');
        expect(_lum(t.feltColor), inInclusiveRange(0.0250, 0.0266),
            reason: '${t.id} feltColor uden for bånd');
        // Felt skal være lysere end bord (samme relief som klassisk/navy).
        expect(_lum(t.feltColor) > _lum(t.tableColor), isTrue);
      }
    });

    test('badges har ≥4,5:1 mod hvid 13px-tekst (som de indbyggede)', () {
      const Color white = Color(0xFFFFFFFF);
      for (final VariantTheme t in kVariantThemes) {
        expect(_contrast(t.badgeColor, white), greaterThanOrEqualTo(4.5),
            reason: '${t.id} badge fejler som informationsbærer');
      }
      // Sanity på metoden selv: de indbyggede badges måler som dokumenteret
      // (grøn 5,13 / blå 4,76 — skrevet med begge tal, så en regnefejl i
      // _contrast ikke kan bestå).
      expect(_contrast(classicVariant.badgeColor, white),
          closeTo(5.13, 0.05));
      expect(_contrast(partners25.badgeColor, white), closeTo(4.76, 0.05));
    });
    test('fire temaer, ingen genbrug af grøn/marineblå badge-farver', () {
      expect(kVariantThemes.length, 4);
      expect(kVariantThemes.map((t) => t.id).toSet(),
          <String>{'ruby', 'amber', 'violet', 'graphite'});
      final Set<int> badges = kVariantThemes
          .map((t) => t.badgeColor.toARGB32())
          .toSet();
      expect(badges.length, 4, reason: 'temaernes badges skal være unikke');
      expect(badges.contains(classicVariant.badgeColor.toARGB32()), isFalse);
      expect(badges.contains(partners25.badgeColor.toARGB32()), isFalse);
    });

    test('tema-farverne er låst eksakt (hex)', () {
      VariantTheme t(String id) => variantThemeById(id);
      expect(t('ruby').tableColor, const Color(0xFF3C1A1C));
      expect(t('ruby').feltColor, const Color(0xFF4A2022));
      expect(t('ruby').badgeColor, const Color(0xFFB03A3A));
      expect(t('amber').tableColor, const Color(0xFF352009));
      expect(t('amber').feltColor, const Color(0xFF40270B));
      expect(t('amber').badgeColor, const Color(0xFF8D6E1F));
      expect(t('violet').tableColor, const Color(0xFF301A44));
      expect(t('violet').feltColor, const Color(0xFF3A2056));
      expect(t('violet').badgeColor, const Color(0xFF7E57C2));
      expect(t('graphite').tableColor, const Color(0xFF232428));
      expect(t('graphite').feltColor, const Color(0xFF2B2D31));
      expect(t('graphite').badgeColor, const Color(0xFF5A6570));
    });

    test('ukendt/manglende tema-id → grafit (neutral fallback)', () {
      expect(variantThemeById('nyt-tema-fra-fremtiden').id, 'graphite');
      expect(variantThemeById(null).id, 'graphite');
    });
  });

  group('slugForVariantName — stabile cv-id\'er', () {
    test('dansk navn → translittereret slug', () {
      expect(slugForVariantName('Familie Special'), 'cv-familie-special');
      expect(slugForVariantName('Æblegrød på Ø'), 'cv-aeblegroed-paa-oe');
      expect(slugForVariantName('  Hurtig!  '), 'cv-hurtig');
    });

    test('degenererede navne falder til cv-variant (afvises af opret-vagten)',
        () {
      expect(slugForVariantName(''), 'cv-variant');
      expect(slugForVariantName('!!!'), 'cv-variant');
    });

    test('lange navne kappes, og id\'et er ALTID velformet', () {
      final String id =
          slugForVariantName('Et meget meget meget langt variantnavn');
      expect(id.length <= 32, isTrue);
      expect(isWellFormedVariantId(id), isTrue);
      // Ingen hængende bindestreg efter afkapning.
      expect(id.endsWith('-'), isFalse);
    });

    test('isWellFormedVariantId håndhæver id-formen', () {
      expect(isWellFormedVariantId('cv-familie'), isTrue);
      expect(isWellFormedVariantId('classic'), isTrue);
      expect(isWellFormedVariantId('CV-Familie'), isFalse);
      expect(isWellFormedVariantId(''), isFalse);
      expect(isWellFormedVariantId(null), isFalse);
      expect(isWellFormedVariantId('x' * 33), isFalse);
    });
  });

  group('variantFromRaw — ren materialisering (intet globalt registry)', () {
    final Map<String, dynamic> raw = <String, dynamic>{
      'cv-familie': <String, dynamic>{
        'rules': <String, dynamic>{},
        'name': 'Familie Special',
        'label': 'Familie',
        'theme': 'ruby',
        'description': 'Vores husregler.',
        'custom': true,
      },
      'cv-arkiveret': <String, dynamic>{
        'rules': <String, dynamic>{},
        'name': 'Gammel',
        'theme': 'violet',
        'custom': true,
        'archived': true,
      },
      'p25': <String, dynamic>{
        'rules': <String, dynamic>{},
        'name': 'Mit 25 år',
        // Fjendtligt/forvirret entry: builtin markeret custom må IKKE kunne
        // om-tematiseres.
        'custom': true,
        'theme': 'ruby',
      },
    };

    test('custom materialiseres: navn, mærke, temafarver, forbehold', () {
      final VariantConfig v = variantFromRaw('cv-familie', raw);
      expect(v.id, 'cv-familie');
      expect(v.name, 'Familie Special');
      expect(v.shortLabel, 'Familie'); // admins mærke, ikke navnet
      expect(v.tableColor, variantThemeById('ruby').tableColor);
      expect(v.feltColor, variantThemeById('ruby').feltColor);
      expect(v.badgeColor, variantThemeById('ruby').badgeColor);
      // Klassisk-formet: geometri identisk med klassisk.
      expect(v.geometry.trackLength, classicVariant.geometry.trackLength);
      expect(v.playerCount, 4);
      // Forbeholdet står ALTID i beskrivelsen/infoteksten.
      expect(v.infoText, contains('Vores husregler.'));
      expect(v.infoText, contains(kCustomVariantDisclaimer));
    });

    test('custom uden beskrivelse får forbeholdet alene', () {
      final VariantConfig v = variantFromRaw('cv-arkiveret', raw);
      expect(v.infoText, kCustomVariantDisclaimer);
      expect(v.shortLabel, 'Gammel'); // intet mærke → navnet
    });

    test('builtin kan IKKE om-tematiseres af et custom-flag i data', () {
      final VariantConfig v = variantFromRaw('p25', raw);
      expect(v.feltColor, partners25.feltColor,
          reason: 'p25 beholder marineblå uanset entry-indhold');
      expect(v.name, partners25.name,
          reason: 'admin-NAVNET resolves separat via variantDisplayName');
    });

    test('ukendt id uden entry → id bevaret, klassisk udseende', () {
      final VariantConfig v = variantFromRaw('cv-ukendt', raw);
      expect(v.id, 'cv-ukendt');
      expect(v.feltColor, classicVariant.feltColor);
      expect(v.shortLabel, 'cv-ukendt'); // ærligt: id, aldrig "Klassisk"
    });

    test('vanformet id / skæv rawdata → klassisk', () {
      expect(variantFromRaw('IKKE gyldigt!', raw).id, 'classic');
      expect(variantFromRaw('cv-familie', 42).id, 'cv-familie');
      expect(variantFromRaw('cv-familie', 42).feltColor,
          classicVariant.feltColor);
      expect(variantFromRaw(null, raw).id, 'classic');
    });

    test('customVariantIdsFrom: arkiverede kun med includeArchived', () {
      expect(customVariantIdsFrom(raw), <String>['cv-familie']);
      expect(customVariantIdsFrom(raw, includeArchived: true),
          <String>['cv-arkiveret', 'cv-familie']);
      // p25 er ALDRIG i custom-listen (builtin), skæv input → tom.
      expect(customVariantIdsFrom(null), isEmpty);
      expect(customVariantIdsFrom(<String, dynamic>{'HELT SKÆVT': raw}),
          isEmpty);
    });

    test('selectableVariantsFrom: builtins først, så ikke-arkiverede customs',
        () {
      final List<VariantConfig> list = selectableVariantsFrom(raw);
      expect(list.map((v) => v.id).toList(),
          <String>['classic', 'p25', 'cv-familie']);
    });
  });

  group('entry-payload-kontrakten (mergeFields ERSTATTER hele entryen)', () {
    test('variantEntryJson bærer ALT varianten ejer — tema/mærke/custom', () {
      final Map<String, dynamic> e = variantEntryJson(
        rulesJson: <String, dynamic>{},
        name: 'Familie Special',
        label: 'Familie',
        theme: 'ruby',
        custom: true,
      );
      // QC-fund: manglede tema/custom her, ville en kortredigering slette
      // variantens tema og flag ved næste gem (entry-erstatning).
      expect(e['theme'], 'ruby');
      expect(e['custom'], true);
      expect(e['label'], 'Familie');
      expect(e.containsKey('archived'), isFalse,
          reason: 'false-flag skrives ikke');
      expect(
          variantEntryJson(rulesJson: <String, dynamic>{}, archived: true)[
              'archived'],
          true);
    });

    test('VariantAdminConfig.toEntryJson round-tripper via variantFromRaw', () {
      const VariantAdminConfig cfg = VariantAdminConfig(
        overrides: <Rank, CardRuleConfig>{},
        name: 'Familie Special',
        label: 'Familie',
        theme: 'amber',
        custom: true,
        stored: true,
      );
      final Map<String, dynamic> raw = <String, dynamic>{
        'cv-familie-special': cfg.toEntryJson(),
      };
      final VariantConfig v = variantFromRaw('cv-familie-special', raw);
      expect(v.name, 'Familie Special');
      expect(v.shortLabel, 'Familie');
      expect(v.feltColor, variantThemeById('amber').feltColor);
    });

    test('VariantsAdminState.configFor: p25 falder til seed, customs til tom',
        () {
      const VariantsAdminState s = VariantsAdminState();
      final VariantAdminConfig p25 = s.configFor('p25');
      expect(p25.stored, isFalse);
      expect(p25.overrides, isNotEmpty,
          reason: 'kode-seedet (de fem specialkort) gælder');
      final VariantAdminConfig custom = s.configFor('cv-x');
      expect(custom.custom, isTrue);
      expect(custom.overrides, isEmpty,
          reason: 'ny custom følger klassisk (intet materialiseret snapshot)');
      expect(custom.stored, isFalse);
    });
  });

  group('custom-variant i spillets state (id + tema hele vejen)', () {
    test('gameStateFromMap materialiserer custom-variant når variantsRaw gives',
        () {
      final Map<String, dynamic> raw = <String, dynamic>{
        'cv-familie': <String, dynamic>{
          'rules': <String, dynamic>{},
          'name': 'Familie Special',
          'theme': 'violet',
          'custom': true,
        },
      };
      final Map<String, dynamic> m = gameStateToMap(makeState());
      m['vid'] = 'cv-familie';
      final state = gameStateFromMap(m, variantsRaw: raw);
      expect(state.variant.id, 'cv-familie');
      expect(state.variant.feltColor, variantThemeById('violet').feltColor);
      // Round-trippet bevarer id'et — også med materialisering.
      expect(gameStateToMap(state)['vid'], 'cv-familie');
      // Uden variantsRaw: id stadig bevaret (klassisk udseende).
      final bare = gameStateFromMap(m);
      expect(bare.variant.id, 'cv-familie');
      expect(bare.variant.feltColor, classicVariant.feltColor);
    });

    test('variantFromAutosave opløser custom med variantsRaw og bevarer id '
        'uden', () {
      final Map<String, dynamic> raw = <String, dynamic>{
        'cv-x': <String, dynamic>{
          'rules': <String, dynamic>{},
          'name': 'X',
          'theme': 'ruby',
          'custom': true,
        },
      };
      final Map<String, dynamic> save = <String, dynamic>{
        'state': <String, dynamic>{'vid': 'cv-x'},
      };
      expect(variantFromAutosave(save, variantsRaw: raw).feltColor,
          variantThemeById('ruby').feltColor);
      // Uden raw: id bevaret — badgen må ALDRIG lyve 'Klassisk' om en custom.
      expect(variantFromAutosave(save).id, 'cv-x');
      expect(variantFromAutosave(save).shortLabel, 'cv-x');
    });
  });
}
