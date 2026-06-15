import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/card_rules.dart';
import '../models/playing_card.dart';

/// Aktuelle (eventuelt brugerjusterede) kortregler. Persisteres lokalt med
/// shared_preferences, så admin-ændringer huskes mellem sessioner.
final cardRulesProvider =
    StateNotifierProvider<CardRulesController, CardRules>(
  (ref) => CardRulesController(),
);

class CardRulesController extends StateNotifier<CardRules> {
  CardRulesController() : super(CardRules.defaults()) {
    _load();
  }

  static const String _key = 'card_rules_v1';

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null) {
        state = CardRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Ignorér korrupt persisteret data — falder tilbage på defaults.
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {
      // Bedst muligt; persistens er ikke kritisk for spilbarhed.
    }
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
