/// Rene payload-byggere for config/cardRules-dokumentet — INGEN Firestore-
/// imports, så formen kan unit-testes uden plugins.
///
/// Kontrakten (bindes til skrivningen i controllerne, som skriver med
/// SetOptions(mergeFields: payload.keys)): et payload må KUN indeholde de
/// felter det ejer. Klassisk-gemmet ejer 'rules' (+ 'updatedAt'); variant-
/// gemmet ejer 'variants'. Dermed kan et klassisk-gem aldrig slette admins
/// variant-regler og omvendt — emulator-testen i firestore-tests/rules.test.mjs
/// beviser selve mergeFields-semantikken.
library;

/// Klassisk-gemmets felter. Bevidst UDEN 'variants'. ('updatedAt' tilføjes af
/// kalderen, som også nævner den i sine mergeFields.)
Map<String, dynamic> classicSavePayload(Map<String, dynamic> rulesJson) =>
    <String, dynamic>{'rules': rulesJson};

/// Variant-gemmets felter: hele variantens under-map (rules + evt. navn/
/// beskrivelse) under variants.{id}. Bevidst UDEN 'rules' (klassisk).
Map<String, dynamic> variantSavePayload(
  String variantId, {
  required Map<String, dynamic> rulesJson,
  String? name,
  String? description,
}) =>
    <String, dynamic>{
      'variants': <String, dynamic>{
        variantId: <String, dynamic>{
          'rules': rulesJson,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
        },
      },
    };
