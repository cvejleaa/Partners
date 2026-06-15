import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/card_rules.dart';
import '../models/playing_card.dart';

/// Aktuelle (eventuelt brugerjusterede) kortregler.
///
/// Gemmes i databasen (Firestore: config/cardRules) så indstillingen huskes på
/// tværs af enheder/sessioner. En lokal kopi (shared_preferences) bruges som
/// hurtig/offline fallback. Alt er pakket i try/catch, så spillet også virker
/// hvis Firebase ikke er tilgængeligt.
final cardRulesProvider =
    StateNotifierProvider<CardRulesController, CardRules>(
  (ref) => CardRulesController(),
);

class CardRulesController extends StateNotifier<CardRules> {
  CardRulesController() : super(CardRules.defaults()) {
    _load();
  }

  static const String _prefsKey = 'card_rules_v1';

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
      if (raw != null) {
        state = CardRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}

    // 2) Database (autoritativ).
    try {
      final snap = await _doc?.get();
      final data = snap?.data();
      final rules = data?['rules'];
      if (rules is Map) {
        state = CardRules.fromJson(Map<String, dynamic>.from(rules));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(state.toJson()));
    } catch (_) {}
    try {
      await _doc?.set(<String, dynamic>{
        'rules': state.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void updateRank(Rank rank, CardRuleConfig config) {
    state = state.withRank(rank, config);
    _save();
  }

  void resetDefaults() {
    state = CardRules.defaults();
    _save();
  }
}
