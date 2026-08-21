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

/// ÉN variants entry-json (variants.{id}-værdien). Skrivningen bruger
/// mergeFields på HELE entryen, så alt hvad varianten ejer — regler, navn,
/// beskrivelse, mærke, tema, custom/arkiv-flag — skal med hver gang; et felt
/// der udelades her SLETTES ved næste gem (QC-fund: en kortredigering må
/// aldrig kunne slette variantens tema).
Map<String, dynamic> variantEntryJson({
  required Map<String, dynamic> rulesJson,
  String? name,
  String? description,
  String? label,
  String? theme,
  bool custom = false,
  bool archived = false,
}) =>
    <String, dynamic>{
      'rules': rulesJson,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (custom) 'custom': true,
      if (archived) 'archived': true,
    };

/// Variant-gemmets felter: hele variantens under-map under variants.{id}.
/// Bevidst UDEN 'rules' (klassisk). BEMÆRK: produktions-controlleren bygger
/// i dag multi-entry-payloads direkte via [variantEntryJson] (én pr. dirty
/// id); denne én-variant-form bevares som den KANONISKE kontrakt-form, som
/// merge-testene (A4 + emulator-testen i rules.test.mjs) låser.
Map<String, dynamic> variantSavePayload(
  String variantId, {
  required Map<String, dynamic> rulesJson,
  String? name,
  String? description,
  String? label,
  String? theme,
  bool custom = false,
  bool archived = false,
}) =>
    <String, dynamic>{
      'variants': <String, dynamic>{
        variantId: variantEntryJson(
          rulesJson: rulesJson,
          name: name,
          description: description,
          label: label,
          theme: theme,
          custom: custom,
          archived: archived,
        ),
      },
    };
