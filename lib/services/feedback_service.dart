import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_controller.dart';

/// Lyd- og haptisk feedback ved vigtige spil-begivenheder.
///
/// Bruger KUN Flutters indbyggede [HapticFeedback] og [SystemSound] — ingen
/// eksterne audio-pakker og ingen asset-filer. Hver metode respekterer de
/// brugervalgte indstillinger ([sound] / [haptics]).
///
/// På web er [HapticFeedback] og [SystemSound] stort set no-ops, men de er
/// harmløse at kalde, så koden er den samme på alle platforme.
///
/// TODO: Rigere, spil-specifikke lyde (fx en egentlig "slag"-effekt eller
/// fanfare ved sejr) kræver egne lydfiler som assets plus en audio-pakke
/// (fx audioplayers/just_audio) i pubspec.yaml. Det er bevidst udeladt her —
/// ligesom et rigtigt PNG-app-ikon — og kan tilføjes i et senere trin.
class FeedbackService {
  const FeedbackService();

  /// Et træk blev anvendt (diskret feedback).
  void move({required bool sound, required bool haptics}) {
    if (haptics) HapticFeedback.selectionClick();
    if (sound) SystemSound.play(SystemSoundType.click);
  }

  /// En brik blev slået hjem (slag).
  void capture({required bool sound, required bool haptics}) {
    if (haptics) HapticFeedback.mediumImpact();
    if (sound) SystemSound.play(SystemSoundType.click);
  }

  /// To brikker blev byttet (Tier/swap).
  void swap({required bool sound, required bool haptics}) {
    if (haptics) HapticFeedback.selectionClick();
    if (sound) SystemSound.play(SystemSoundType.click);
  }

  /// Spillet blev vundet (sejr).
  void win({required bool sound, required bool haptics}) {
    if (haptics) HapticFeedback.heavyImpact();
    if (sound) SystemSound.play(SystemSoundType.click);
  }
}

/// Wrapper der læser de aktuelle indstillinger og videresender til
/// [FeedbackService], så UI-koden bare kan kalde fx `feedback.capture()` uden
/// selv at slå indstillinger op.
class SettingsAwareFeedback {
  const SettingsAwareFeedback(this._service, this._settings);

  final FeedbackService _service;
  final Settings _settings;

  void move() => _service.move(
        sound: _settings.soundEnabled,
        haptics: _settings.hapticsEnabled,
      );

  void capture() => _service.capture(
        sound: _settings.soundEnabled,
        haptics: _settings.hapticsEnabled,
      );

  void swap() => _service.swap(
        sound: _settings.soundEnabled,
        haptics: _settings.hapticsEnabled,
      );

  void win() => _service.win(
        sound: _settings.soundEnabled,
        haptics: _settings.hapticsEnabled,
      );
}

/// Læser de aktuelle indstillinger og giver en klar-til-brug feedback-helper.
final Provider<SettingsAwareFeedback> feedbackProvider =
    Provider<SettingsAwareFeedback>((ref) {
  final settings = ref.watch(settingsProvider);
  return SettingsAwareFeedback(const FeedbackService(), settings);
});
