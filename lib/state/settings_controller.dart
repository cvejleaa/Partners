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
    this.pushEnabled = false,
    this.preferredColorValue,
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final ThemeMode themeMode;

  /// Browser-push (FCM). Default: slået fra. Når brugeren slår til,
  /// spørges der om browser-permission og en FCM-token registreres
  /// under `users/{uid}.fcmTokens`.
  final bool pushEnabled;

  /// Personlig ønske-farve for EGNE brikker (ARGB-værdi), rent lokalt. Når sat
  /// roteres farve-paletten på brættet lokalt, så ens egen plads vises i denne
  /// farve — kun for denne enhed, uden at ændre spillets data. null = ingen
  /// præference (brættets oprindelige farver).
  final int? preferredColorValue;

  Settings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    ThemeMode? themeMode,
    bool? pushEnabled,
    int? preferredColorValue,
    bool clearPreferredColor = false,
  }) {
    return Settings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      themeMode: themeMode ?? this.themeMode,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      preferredColorValue: clearPreferredColor
          ? null
          : (preferredColorValue ?? this.preferredColorValue),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'soundEnabled': soundEnabled,
        'hapticsEnabled': hapticsEnabled,
        'themeMode': themeMode.name,
        'pushEnabled': pushEnabled,
        if (preferredColorValue != null)
          'preferredColorValue': preferredColorValue,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
      themeMode: _themeModeFromName(json['themeMode'] as String?),
      pushEnabled: json['pushEnabled'] as bool? ?? false,
      preferredColorValue: (json['preferredColorValue'] as num?)?.toInt(),
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

  void setPushEnabled(bool value) {
    state = state.copyWith(pushEnabled: value);
    _save();
  }

  void setPreferredColorValue(int? value) {
    state = value == null
        ? state.copyWith(clearPreferredColor: true)
        : state.copyWith(preferredColorValue: value);
    _save();
  }
}
