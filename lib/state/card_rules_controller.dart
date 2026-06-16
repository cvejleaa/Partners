import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/card_rules.dart';
import '../models/playing_card.dart';

/// Aktuelle (eventuelt brugerjusterede) kortregler.
///
/// Gemmes i databasen (Firestore: config/cardRules) så indstillingen huskes på
/// tværs af enheder/sessioner. En lokal kopi (shared_preferences) bruges som
/// hurtig fallback. Skrivefejl rapporteres via [lastSaveError] så admin-UI
/// kan vise dem.
/// Senest registrerede gem-fejl (string er tom = OK). Opdateres af
/// [CardRulesController] hver gang den forsøger at gemme.
final cardRulesSaveErrorProvider = StateProvider<String>((_) => '');

final cardRulesProvider =
    StateNotifierProvider<CardRulesController, CardRules>(
  (ref) => CardRulesController(errorSink: (msg) {
    ref.read(cardRulesSaveErrorProvider.notifier).state = msg;
  }),
);

class CardRulesController extends StateNotifier<CardRules> {
  CardRulesController({this.errorSink}) : super(CardRules.defaults()) {
    _load();
  }

  /// Bruges til at rapportere gem-fejl til UI (sat fra provider-fabrikken).
  void Function(String)? errorSink;

  static const String _prefsKey = 'card_rules_v1';

  /// Senest registrerede gem-fejl (vises i admin-UI). Tom = OK.
  String lastSaveError = '';

  void _setError(String s) {
    lastSaveError = s;
    errorSink?.call(s);
  }

  /// Sand så længe vi henter eksisterende regler fra DB. Når true, ignorerer
  /// _load eventuelle ændringer brugeren har lavet imens (undgår at en sen
  /// hentet remote-værdi overskriver et frisk lokalt valg).
  bool _loading = true;
  bool _userTouched = false;

  DocumentReference<Map<String, dynamic>>? get _doc {
    try {
      return FirebaseFirestore.instance.collection('config').doc('cardRules');
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    // 1) Lokal cache (hurtig).
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw != null && !_userTouched) {
        state = CardRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[cardRules] prefs read fail: $e');
    }

    // 2) Database (autoritativ — men respekter at brugeren kan have ændret
    //    imens vi hentede).
    try {
      final snap = await _doc?.get();
      final data = snap?.data();
      final rules = data?['rules'];
      if (rules is Map && !_userTouched) {
        state = CardRules.fromJson(Map<String, dynamic>.from(rules));
      }
    } catch (e) {
      debugPrint('[cardRules] firestore read fail: $e');
    } finally {
      _loading = false;
    }
  }

  Future<void> _save() async {
    // Lokal kopi altid (hurtig fallback).
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('[cardRules] prefs write fail: $e');
    }
    // Database — fejl rapporteres til UI.
    try {
      final doc = _doc;
      if (doc == null) {
        _setError('Firestore ikke initialiseret');
        return;
      }
      await doc.set(<String, dynamic>{
        'rules': state.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _setError('');
    } catch (e) {
      _setError('$e');
      debugPrint('[cardRules] firestore write fail: $e');
    }
  }

  void updateRank(Rank rank, CardRuleConfig config) {
    _userTouched = true;
    state = state.withRank(rank, config);
    _save();
  }

  void resetDefaults() {
    _userTouched = true;
    state = CardRules.defaults();
    _save();
  }

  /// Tvinger en synkron retry mod Firestore (når UI ved at brugeren netop er
  /// logget ind eller har rettet et rettighedsproblem).
  Future<void> retrySave() async => _save();

  /// Hent regler fra DB nu (bruges fx efter login).
  Future<void> refresh() async {
    _userTouched = false;
    await _load();
  }
}
