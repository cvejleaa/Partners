import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/online_service.dart';
import 'admin_screen.dart';
import 'online_screens.dart';
import 'self_test_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: const Text('Partners'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Admin — kortfunktioner',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const AdminScreen())),
          ),
          IconButton(
            tooltip: 'Selvtest',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const SelfTestScreen())),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('PARTNERS',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
              const SizedBox(height: 40),
              _bigButton(context, Icons.smart_toy, 'Spil mod AI', () {
                Navigator.of(context).push<void>(MaterialPageRoute<void>(
                    builder: (_) => const SetupScreen()));
              }),
              const SizedBox(height: 16),
              _bigButton(context, Icons.group, 'Online med venner', () {
                final loggedIn = auth.valueOrNull != null;
                Navigator.of(context).push<void>(MaterialPageRoute<void>(
                    builder: (_) =>
                        loggedIn ? const OnlineHomeScreen() : const AuthScreen()));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigButton(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: const Color(0xFF8B5E3C),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
