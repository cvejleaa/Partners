import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/card_rules.dart';
import '../models/playing_card.dart';
import '../models/variant_config.dart';
import '../online/online_service.dart';
import 'card_rules_payload.dart';

/// Admin-tilstand for ÉN variant i config/cardRules → variants.{id}: et
/// PARTIELT override-map (kun de rangs admin har rørt) + meta (navn,
/// beskrivelse, mærke, tema, custom/arkiv-flag).
///
/// Semantik for 25 år ift. [partners25.cardRuleOverrides] (kode-seedet):
///  - Intet gemt → seedet gælder (kun de fem indbyggede specialkort).
///  - Gemt → admin er autoritet; seedet bruges ikke.
/// For CUSTOM-varianter findes intet kode-seed: tomme overrides betyder
/// "følger klassisk" — det er startpunktet for en ny variant (QC-krav: ikke
/// et materialiseret snapshot, så diff-visningen forbliver meningsfuld).
class VariantAdminConfig {
  const VariantAdminConfig({
    required this.overrides,
    this.name,
    this.description,
    this.label,
    this.theme,
    this.custom = false,
    this.archived = false,
    this.stored = false,
  });

  /// Aktuelle overrides (seed eller gemte). Aldrig null — tom = "ingen rangs
  /// afviger" (også en gyldig, gembar tilstand).
  final Map<Rank, CardRuleConfig> overrides;

  /// Admins eget navn/beskrivelse (null = variantens kode-tekst).
  final String? name;
  final String? description;

  /// Kort mærke til badge-chippen (kun customs; maks. [kMaxCustomLabelLength]).
  final String? label;

  /// Kurateret tema-id ([kVariantThemes]); kun customs.
  final String? theme;

  /// True for admin-definerede varianter (variants-entryens 'custom': true).
  final bool custom;

  /// Arkiveret: kan ikke vælges til NYE spil, men historik/stats/navne-
  /// opslag virker stadig (derfor arkiv frem for sletning).
  final bool archived;

  /// True når tilstanden kommer fra (eller er gemt til) databasen — dvs. admin
  /// har overtaget autoriteten fra kode-seedet.
  final bool stored;

  VariantAdminConfig copyWith({
    Map<Rank, CardRuleConfig>? overrides,
    String? name,
    String? description,
    String? label,
    String? theme,
    bool? custom,
    bool? archived,
    bool? stored,
  }) =>
      VariantAdminConfig(
        overrides: overrides ?? this.overrides,
        name: name ?? this.name,
        description: description ?? this.description,
        label: label ?? this.label,
        theme: theme ?? this.theme,
        custom: custom ?? this.custom,
        archived: archived ?? this.archived,
        stored: stored ?? this.stored,
      );

  /// Entry-json i variants-mappets form. VIGTIGT (QC-fund): skrivningen
  /// bruger mergeFields på HELE entryen, så ALT (tema, mærke, custom-flag)
  /// skal med hver gang — ellers ville en kortredigering slette variantens
  /// tema og navn.
  Map<String, dynamic> toEntryJson() => variantEntryJson(
        rulesJson: cardRuleOverridesToJson(overrides),
        name: name,
        description: description,
        label: label,
        theme: theme,
        custom: custom,
        archived: archived,
      );
}

/// Hele variants-mappet som admin-tilstand. ÉN controller ejer mappet (QC:
/// en family-provider ville give ét auth-abonnement og ét doc-read PR.
/// variant og en prefs-cache der taber de andre varianter).
class VariantsAdminState {
  const VariantsAdminState({this.entries = const <String, VariantAdminConfig>{}});

  /// Kun det der ER gemt (eller redigeret i denne session). p25 uden entry =
  /// kode-seedet gælder.
  final Map<String, VariantAdminConfig> entries;

  /// Tilstanden for [id] — med korrekt fallback: p25 falder til kode-seedet
  /// (stored=false), et ukendt custom-id til en tom custom-skabelon.
  VariantAdminConfig configFor(String id) =>
      entries[id] ??
      (id == partners25.id
          ? VariantAdminConfig(
              overrides:
                  partners25.cardRuleOverrides ?? <Rank, CardRuleConfig>{},
            )
          : const VariantAdminConfig(
              overrides: <Rank, CardRuleConfig>{}, custom: true));

  /// Rå variants-map-form (samme som doc-feltet) — føder variantFromRaw,
  /// picker-listerne og prefs-cachen.
  Map<String, dynamic> toRawJson() => <String, dynamic>{
        for (final MapEntry<String, VariantAdminConfig> e in entries.entries)
          e.key: e.value.toEntryJson(),
      };

  VariantsAdminState withEntry(String id, VariantAdminConfig cfg) =>
      VariantsAdminState(
          entries: <String, VariantAdminConfig>{...entries, id: cfg});

  VariantsAdminState withoutEntry(String id) => VariantsAdminState(
      entries: Map<String, VariantAdminConfig>.from(entries)..remove(id));
}

/// Status/gem-fejl for variant-reglerne (vises i admin-UI'et ved siden af de
/// klassiske, så "Gem nu"/"Hent nu" kan rapportere BEGGE datasæt ærligt).
final variantCardRulesSaveErrorProvider = StateProvider<String>((_) => '');
final variantCardRulesLoadSourceProvider = StateProvider<String>((_) => '');

final variantCardRulesProvider =
    StateNotifierProvider<VariantCardRulesController, VariantsAdminState>(
  (ref) => VariantCardRulesController(
    errorSink: (msg) {
      ref.read(variantCardRulesSaveErrorProvider.notifier).state = msg;
    },
    sourceSink: (s) {
      ref.read(variantCardRulesLoadSourceProvider.notifier).state = s;
    },
  ),
);

/// Admin-skærmens valgte variant (højre kolonne). Default 25 år.
final selectedAdminVariantIdProvider =
    StateProvider<String>((_) => partners25.id);

/// Den valgte variants admin-tilstand — det admin-UI'et redigerer.
final selectedVariantAdminProvider = Provider<VariantAdminConfig>((ref) {
  final String id = ref.watch(selectedAdminVariantIdProvider);
  return ref.watch(variantCardRulesProvider).configFor(id);
});

/// Picker-listen (setup/lobby): indbyggede + ikke-arkiverede customs,
/// materialiseret fra controllerens variants-map. Alle klienter (ikke kun
/// admin) læser config-doc'et, så customs vises for alle.
final selectableVariantsProvider = Provider<List<VariantConfig>>((ref) =>
    selectableVariantsFrom(ref.watch(variantCardRulesProvider).toRawJson()));

class VariantCardRulesController extends StateNotifier<VariantsAdminState> {
  VariantCardRulesController({this.errorSink, this.sourceSink})
      : super(const VariantsAdminState()) {
    _load();
    // Genindlæs når auth fuldfører (samme mønster som CardRulesController) —
    // med sin EGEN touched-vagt, så en klassisk redigering ikke blokerer
    // variant-loadet og omvendt.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !_userTouched) {
        _load();
      }
    });
  }

  void Function(String)? errorSink;
  void Function(String)? sourceSink;

  /// v2: cacher HELE variants-mappet (v1 rummede kun p25 — et gem af én
  /// variant overskrev de andres cache, QC-fund). v1 læses som fallback
  /// (samme form, blot med kun én nøgle).
  static const String _prefsKey = 'card_rules_variants_v2';
  static const String _prefsKeyV1 = 'card_rules_variants_v1';

  bool _userTouched = false;

  /// Id'er med uskrevne ændringer. Gemmet skriver KUN disse entries (med
  /// mergeFields pr. id), så en anden admins samtidige redigering af en
  /// ANDEN variant ikke overskrives.
  final Set<String> _dirty = <String>{};

  /// Debounce (samme mønster som CardRulesController): tekst-commits pr.
  /// tastetryk samles til én skrivning. State opdateres straks lokalt.
  Timer? _saveTimer;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  DocumentReference<Map<String, dynamic>>? get _doc {
    try {
      return firestore.collection('config').doc('cardRules');
    } catch (_) {
      return null;
    }
  }

  static VariantsAdminState _fromRaw(dynamic variantsRaw) {
    if (variantsRaw is! Map) return const VariantsAdminState();
    final entries = <String, VariantAdminConfig>{};
    variantsRaw.forEach((dynamic k, dynamic v) {
      if (k is! String || v is! Map) return;
      final Map<Rank, CardRuleConfig> overrides =
          storedOverridesFor(variantsRaw, k) ?? <Rank, CardRuleConfig>{};
      String? str(String key) =>
          v[key] is String && (v[key] as String).trim().isNotEmpty
              ? (v[key] as String)
              : null;
      entries[k] = VariantAdminConfig(
        overrides: overrides,
        name: str('name'),
        description: str('description'),
        label: str('label'),
        theme: str('theme'),
        custom: v['custom'] == true,
        archived: v['archived'] == true,
        stored: true,
      );
    });
    return VariantsAdminState(entries: entries);
  }

  Future<void> _load() async {
    String source = 'seed';
    // 1) Lokal cache (hurtig). null-nøgle = "aldrig cachet" ≠ cachet tom.
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey) ?? sp.getString(_prefsKeyV1);
      if (raw != null && !_userTouched) {
        state = _fromRaw(jsonDecode(raw));
        source = 'prefs';
      }
    } catch (e) {
      debugPrint('[variantCardRules] prefs read fail: $e');
    }
    // 2) Database (autoritativ).
    try {
      final snap = await _doc?.get();
      if (!_userTouched && snap != null) {
        state = _fromRaw(snap.data()?['variants']);
        source = state.entries.isNotEmpty ? 'firestore' : 'seed';
      }
    } catch (e) {
      debugPrint('[variantCardRules] firestore read fail: $e');
    }
    sourceSink?.call(source);
  }

  Future<void> _cachePrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(state.toRawJson()));
    } catch (e) {
      debugPrint('[variantCardRules] prefs write fail: $e');
    }
  }

  Future<void> _save() async {
    // Intet at gemme = kode-seedet er autoriteten for p25 — SKRIV IKKE.
    // (QC-fund: vagten skelner "entry findes" fra "overrides findes" — en
    // nyoprettet custom HAR et entry (navn/tema) selv med tomme overrides,
    // og det SKAL skrives.)
    if (_dirty.isEmpty) {
      errorSink?.call('');
      return;
    }
    final List<String> ids = _dirty.toList();
    final Map<String, dynamic> variants = <String, dynamic>{
      for (final String id in ids)
        if (state.entries.containsKey(id))
          id: state.entries[id]!.toEntryJson(),
    };
    await _cachePrefs();
    if (FirebaseAuth.instance.currentUser == null) {
      errorSink
          ?.call('Du er ikke logget ind — variant-regler er kun gemt lokalt.');
      return;
    }
    try {
      final doc = _doc;
      if (doc == null) {
        errorSink?.call('Firestore ikke initialiseret');
        return;
      }
      // mergeFields: ERSTAT præcis variants.{id} for hver berørt variant (så
      // en fjernet rang faktisk forsvinder) uden at røre 'rules'/'updatedAt'
      // eller de øvrige varianter. FieldPath (ikke dotted string), så id'er
      // aldrig knækker stien.
      await doc.set(
          <String, dynamic>{'variants': variants},
          SetOptions(mergeFields: <Object>[
            for (final String id in variants.keys)
              FieldPath(<String>['variants', id]),
          ]));
      _dirty.removeAll(variants.keys);
      errorSink?.call('');
    } catch (e) {
      errorSink?.call('$e');
      debugPrint('[variantCardRules] firestore write fail: $e');
    }
  }

  void _touch(String id, VariantAdminConfig next) {
    _userTouched = true;
    state = state.withEntry(id, next.copyWith(stored: true));
    _dirty.add(id);
    _scheduleSave();
  }

  void updateRank(String id, Rank rank, CardRuleConfig config) {
    final cfg = state.configFor(id);
    _touch(
        id,
        cfg.copyWith(overrides: <Rank, CardRuleConfig>{
          ...cfg.overrides,
          rank: config,
        }));
  }

  /// Fjern én rangs override → rangen FØLGER klassisk igen.
  void clearRank(String id, Rank rank) {
    final cfg = state.configFor(id);
    final next = Map<Rank, CardRuleConfig>.from(cfg.overrides)..remove(rank);
    _touch(id, cfg.copyWith(overrides: next));
  }

  /// "Kopiér klassisk til varianten": materialisér ALLE rangs som overrides ud
  /// fra [effective] (variantens aktuelle effektive regler). Derefter er
  /// varianten et fuldt uafhængigt snapshot — en senere klassisk ændring
  /// rører den ikke.
  void materializeAll(String id, CardRules effective) {
    final cfg = state.configFor(id);
    _touch(
        id,
        cfg.copyWith(overrides: <Rank, CardRuleConfig>{
          for (final Rank r in Rank.values) r: effective.forRank(r),
        }));
  }

  void updateMeta(String id,
      {String? name, String? description, String? label, String? theme}) {
    final cfg = state.configFor(id);
    _touch(
        id,
        cfg.copyWith(
            name: name, description: description, label: label, theme: theme));
  }

  /// Opret en ny custom-variant. Returnerer fejltekst (null = OK, [outId]
  /// via returværdi). Guards: loft, navnekollision, reserverede id'er.
  /// Starter med TOMME overrides = "følger klassisk" og gemmes STRAKS (uden
  /// debounce): et entry uden regler er en gyldig, gembar variant.
  Future<String?> createVariant({
    required String name,
    required String label,
    required String theme,
    String? description,
  }) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) return 'Navnet må ikke være tomt.';
    final String id = slugForVariantName(trimmedName);
    if (id == 'cv-variant') {
      return 'Navnet skal indeholde bogstaver eller tal.';
    }
    if (state.entries.containsKey(id)) {
      return 'Der findes allerede en variant med det navn ($id). '
          'Id\'er genbruges aldrig — vælg et andet navn.';
    }
    final int customCount =
        state.entries.values.where((e) => e.custom).length;
    if (customCount >= kMaxCustomVariants) {
      return 'Loftet er $kMaxCustomVariants egne varianter (hver variant '
          'koster en kopi i alle spilleres statistik-dokumenter). Arkivér '
          'er ikke nok — genbrug en eksisterende.';
    }
    _userTouched = true;
    state = state.withEntry(
        id,
        VariantAdminConfig(
          overrides: const <Rank, CardRuleConfig>{},
          name: trimmedName,
          label: label.trim().isEmpty ? null : label.trim(),
          theme: theme,
          description:
              (description != null && description.trim().isNotEmpty)
                  ? description.trim()
                  : null,
          custom: true,
          stored: true,
        ));
    _dirty.add(id);
    _saveTimer?.cancel();
    await _save();
    return null;
  }

  /// Nulstil KUN variantens kortregler (QC-fund: for en custom må "Nulstil"
  /// ikke slette selve varianten):
  ///  - p25: SLET entryen (kode-seedet overtager — som hidtil).
  ///  - custom: behold entry (navn/tema/mærke), tøm overrides → "følger
  ///    klassisk".
  Future<void> resetRules(String id) async {
    _userTouched = true;
    final cfg = state.configFor(id);
    if (cfg.custom) {
      _touch(id, cfg.copyWith(overrides: const <Rank, CardRuleConfig>{}));
      _saveTimer?.cancel();
      await _save();
      return;
    }
    // p25: slet entryen — en kø-lagt skrivning må ikke genoplive det slettede.
    _saveTimer?.cancel();
    _dirty.remove(id);
    state = state.withoutEntry(id);
    await _cachePrefs();
    if (FirebaseAuth.instance.currentUser == null) {
      errorSink?.call('Du er ikke logget ind — nulstilling er kun sket lokalt.');
      return;
    }
    try {
      await _doc?.update(<Object, Object?>{
        FieldPath(<String>['variants', id]): FieldValue.delete(),
      });
      errorSink?.call('');
    } catch (e) {
      // not-found = doc'et findes ikke endnu = intet at slette (OK). Alt andet
      // rapporteres. Typed fejlkode frem for skrøbelig streng-matchning.
      final bool notFound = e is FirebaseException && e.code == 'not-found';
      errorSink?.call(notFound ? '' : '$e');
    }
  }

  /// Arkivér/gendan en custom-variant. Arkiv frem for sletning: historiske
  /// spil og statistik beholder navn/farve, igangværende spil spiller færdigt
  /// ('cr'), kun vælgeren mister varianten.
  Future<void> setArchived(String id, bool archived) async {
    final cfg = state.configFor(id);
    if (!cfg.custom) return;
    _touch(id, cfg.copyWith(archived: archived));
    _saveTimer?.cancel();
    await _save();
  }

  Future<void> retrySave() async {
    _saveTimer?.cancel();
    // "Gem nu" skal skrive ALT admin har i hånden, ikke kun det u-flushede:
    // markér alle kendte entries som dirty først.
    _dirty.addAll(state.entries.keys);
    await _save();
  }

  Future<void> refresh() async {
    _userTouched = false;
    await _load();
  }

  @override
  void dispose() {
    // En kø-lagt (debounced) skrivning må ikke overleve controlleren.
    _saveTimer?.cancel();
    super.dispose();
  }
}
