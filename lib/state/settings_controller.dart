import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Brugerindstillinger der huskes lokalt på enheden.
///
/// Til forskel fra [CardRules] (som er globale spilleregler i Firestore) er
/// disse rent personlige enheds-præferencer (lyd, haptik, tema), så de gemmes
/// kun lokalt via shared_preferences — samme persistens-mønster som
/// [CardRulesController]s lokale fallback-kopi.
@immutable
class Settings {
  const Settings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.themeMode = ThemeMode.system,
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final ThemeMode themeMode;

  Settings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    ThemeMode? themeMode,
  }) {
    return Settings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'soundEnabled': soundEnabled,
        'hapticsEnabled': hapticsEnabled,
        'themeMode': themeMode.name,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
      themeMode: _themeModeFromName(json['themeMode'] as String?),
    );
  }

  static ThemeMode _themeModeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

final StateNotifierProvider<SettingsController, Settings> settingsProvider =
    StateNotifierProvider<SettingsController, Settings>(
  (ref) => SettingsController(),
);

class SettingsController extends StateNotifier<Settings> {
  SettingsController() : super(const Settings()) {
    _load();
  }

  static const String _prefsKey = 'user_settings_v1';

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw != null) {
        state = Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[settings] prefs read fail: $e');
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('[settings] prefs write fail: $e');
    }
  }

  void setSoundEnabled(bool value) {
    state = state.copyWith(soundEnabled: value);
    _save();
  }

  void setHapticsEnabled(bool value) {
    state = state.copyWith(hapticsEnabled: value);
    _save();
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save();
  }
}
