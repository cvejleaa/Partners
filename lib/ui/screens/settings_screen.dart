import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_controller.dart';

/// Farver der matcher resten af app'en.
const Color _kBrown = Color(0xFF8B5E3C);
const Color _kBackground = Color(0xFF0E2A1A);

/// Indstillinger-skærm med persistente brugerpræferencer.
///
/// Lyd, haptik og tema gemmes med det samme via [settingsProvider], så valgene
/// huskes på tværs af sessioner.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBrown,
        foregroundColor: Colors.white,
        title: const Text('Indstillinger'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const _SectionTitle('Lyd og vibration'),
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: const Icon(Icons.volume_up),
                      title: const Text('Lyd'),
                      subtitle: const Text('Afspil lyd ved slag, bytte og sejr'),
                      value: settings.soundEnabled,
                      activeColor: _kBrown,
                      onChanged: controller.setSoundEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.vibration),
                      title: const Text('Haptisk feedback'),
                      subtitle: const Text('Vibrér ved vigtige begivenheder'),
                      value: settings.hapticsEnabled,
                      activeColor: _kBrown,
                      onChanged: controller.setHapticsEnabled,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('Udseende'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12, left: 4),
                        child: Text('Tema'),
                      ),
                      SegmentedButton<ThemeMode>(
                        segments: const <ButtonSegment<ThemeMode>>[
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            label: Text('Lyst'),
                            icon: Icon(Icons.light_mode),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            label: Text('Mørkt'),
                            icon: Icon(Icons.dark_mode),
                          ),
                        ],
                        selected: <ThemeMode>{settings.themeMode},
                        onSelectionChanged: (Set<ThemeMode> selection) {
                          controller.setThemeMode(selection.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
