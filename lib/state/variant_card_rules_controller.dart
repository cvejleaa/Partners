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

/// Admin-gemte kortregler for Partners 25 år: et PARTIELT override-map (kun de
/// rangs admin har rørt) + valgfrit eget navn/beskrivelse. Gemmes i SAMME
/// dokument som de klassiske regler (config/cardRules → variants.p25), så
/// spil-oprettelse stadig henter alt i ét read.
///
/// Semantik ift. [partners25.cardRuleOverrides] (kode-seedet):
///  - Intet gemt → seedet gælder (dagens opførsel, kun Hopsakortet).
///  - Gemt → admin er autoritet; seedet bruges ikke.
/// Starttilstanden ER seedet (jf. CardRulesController der starter på
/// defaults()), så der findes ingen "første gang"-materialiseringslogik: en
/// redigering af én rang gemmer hele det aktuelle map.
class VariantAdminConfig {
  const VariantAdminConfig({
    required this.overrides,
    this.name,
    this.description,
    this.stored = false,
  });

  /// Aktuelle overrides (seed eller gemte). Aldrig null — tom = "ingen rangs
  /// afviger" (også en gyldig, gembar tilstand).
  final Map<Rank, CardRuleConfig> overrides;

  /// Admins eget navn/beskrivelse (null = brug variantens kode-tekst).
  final String? name;
  final String? description;

  /// True når tilstanden kommer fra (eller er gemt til) databasen — dvs. admin
  /// har overtaget autoriteten fra kode-seedet.
  final bool stored;

  VariantAdminConfig copyWith({
    Map<Rank, CardRuleConfig>? overrides,
    String? name,
    String? description,
    bool? stored,
  }) =>
      VariantAdminConfig(
        overrides: overrides ?? this.overrides,
        name: name ?? this.name,
        description: description ?? this.description,
        stored: stored ?? this.stored,
      );
}

/// Status/gem-fejl for variant-reglerne (vises i admin-UI'et ved siden af de
/// klassiske, så "Gem nu"/"Hent nu" kan rapportere BEGGE datasæt ærligt).
final variantCardRulesSaveErrorProvider = StateProvider<String>((_) => '');
final variantCardRulesLoadSourceProvider = StateProvider<String>((_) => '');

final variantCardRulesProvider =
    StateNotifierProvider<VariantCardRulesController, VariantAdminConfig>(
  (ref) => VariantCardRulesController(
    errorSink: (msg) {
      ref.read(variantCardRulesSaveErrorProvider.notifier).state = msg;
    },
    sourceSink: (s) {
      ref.read(variantCardRulesLoadSourceProvider.notifier).state = s;
    },
  ),
);

class VariantCardRulesController extends StateNotifier<VariantAdminConfig> {
  VariantCardRulesController({this.errorSink, this.sourceSink})
      : super(VariantAdminConfig(
          overrides: partners25.cardRuleOverrides ?? <Rank, CardRuleConfig>{},
        )) {
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

  /// Egen prefs-nøgle (IKKE card_rules_v1 — det er klassisk-cachen).
  static const String _prefsKey = 'card_rules_variants_v1';

  static const String _variantId = 'p25';

  bool _userTouched = false;

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

  VariantAdminConfig _fromRaw(dynamic variantsRaw) {
    final Map<Rank, CardRuleConfig>? stored =
        storedOverridesFor(variantsRaw, _variantId);
    if (stored == null) {
      // Intet gemt → kode-seedet gælder.
      return VariantAdminConfig(
        overrides: partners25.cardRuleOverrides ?? <Rank, CardRuleConfig>{},
      );
    }
    final dynamic entry = (variantsRaw as Map)[_variantId];
    return VariantAdminConfig(
      overrides: stored,
      name: entry is Map && entry['name'] is String
          ? entry['name'] as String
          : null,
      description: entry is Map && entry['description'] is String
          ? entry['description'] as String
          : null,
      stored: true,
    );
  }

  Future<void> _load() async {
    String source = 'seed';
    // 1) Lokal cache (hurtig). null-nøgle = "aldrig cachet" ≠ cachet tom.
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
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
        source = state.stored ? 'firestore' : 'seed';
      }
    } catch (e) {
      debugPrint('[variantCardRules] firestore read fail: $e');
    }
    sourceSink?.call(source);
  }

  Future<void> _save() async {
    // Intet gemt (stored=false) = kode-seedet er autoriteten — SKRIV IKKE.
    // Ellers ville "Gem nu" lige efter en nulstilling genoplive det slettede
    // felt og fryse seedet fast i databasen.
    if (!state.stored) {
      errorSink?.call('');
      return;
    }
    final Map<String, dynamic> payload = variantSavePayload(
      _variantId,
      rulesJson: cardRuleOverridesToJson(state.overrides),
      name: state.name,
      description: state.description,
    );
    // Lokal cache af variants-mappet (samme form som doc-feltet).
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(payload['variants']));
    } catch (e) {
      debugPrint('[variantCardRules] prefs write fail: $e');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      errorSink?.call('Du er ikke logget ind — 25 år-regler er kun gemt lokalt.');
      return;
    }
    try {
      final doc = _doc;
      if (doc == null) {
        errorSink?.call('Firestore ikke initialiseret');
        return;
      }
      // mergeFields: ERSTAT præcis variants.p25 (så en fjernet rang faktisk
      // forsvinder) uden at røre 'rules'/'updatedAt' eller andre varianter.
      // FieldPath (ikke dotted string), så et fremtidigt variant-id med
      // specialtegn ikke knækker stien.
      await doc.set(
          payload,
          SetOptions(mergeFields: <Object>[
            FieldPath(<String>['variants', _variantId]),
          ]));
      errorSink?.call('');
    } catch (e) {
      errorSink?.call('$e');
      debugPrint('[variantCardRules] firestore write fail: $e');
    }
  }

  void updateRank(Rank rank, CardRuleConfig config) {
    _userTouched = true;
    state = state.copyWith(
      overrides: <Rank, CardRuleConfig>{...state.overrides, rank: config},
      stored: true,
    );
    _scheduleSave();
  }

  /// Fjern én rangs override → rangen FØLGER klassisk igen.
  void clearRank(Rank rank) {
    _userTouched = true;
    final next = Map<Rank, CardRuleConfig>.from(state.overrides)..remove(rank);
    state = state.copyWith(overrides: next, stored: true);
    _scheduleSave();
  }

  /// "Kopiér klassisk til 25 år": materialisér ALLE rangs som overrides ud fra
  /// [effective] (de aktuelle effektive 25 år-regler = klassisk + seed/gemte).
  /// Derefter er 25 år et fuldt uafhængigt snapshot — en senere klassisk
  /// ændring rører den ikke.
  void materializeAll(CardRules effective) {
    _userTouched = true;
    state = state.copyWith(
      overrides: <Rank, CardRuleConfig>{
        for (final Rank r in Rank.values) r: effective.forRank(r),
      },
      stored: true,
    );
    _scheduleSave();
  }

  void updateMeta({String? name, String? description}) {
    _userTouched = true;
    state = state.copyWith(name: name, description: description, stored: true);
    _scheduleSave();
  }

  /// Nulstil: SLET variants.p25-feltet i databasen (ikke skrive seedet ind —
  /// så en senere kode-ændring af seedet stadig slår igennem) og fald tilbage
  /// til kode-seedet lokalt.
  Future<void> resetToSeed() async {
    _userTouched = true;
    _saveTimer?.cancel(); // en kø-lagt skrivning må ikke genoplive det slettede
    state = VariantAdminConfig(
      overrides: partners25.cardRuleOverrides ?? <Rank, CardRuleConfig>{},
    );
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefsKey);
    } catch (_) {}
    if (FirebaseAuth.instance.currentUser == null) {
      errorSink?.call('Du er ikke logget ind — nulstilling er kun sket lokalt.');
      return;
    }
    try {
      await _doc?.update(<Object, Object?>{
        FieldPath(<String>['variants', _variantId]): FieldValue.delete(),
      });
      errorSink?.call('');
    } catch (e) {
      // not-found = doc'et findes ikke endnu = intet at slette (OK). Alt andet
      // rapporteres. Typed fejlkode frem for skrøbelig streng-matchning.
      final bool notFound =
          e is FirebaseException && e.code == 'not-found';
      errorSink?.call(notFound ? '' : '$e');
    }
  }

  Future<void> retrySave() async {
    _saveTimer?.cancel();
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
