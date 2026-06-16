import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/online_service.dart';
import 'admin_screen.dart';
import 'online_screens.dart';
import 'profile_screen.dart';
import 'self_test_screen.dart';
import 'setup_screen.dart';
import 'site_stats_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
    final user = authAsync.valueOrNull;
    final loggedIn = user != null;
    final admin = isAdmin(user);

    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: const Text('Partners'),
        actions: <Widget>[
          if (admin)
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
          if (loggedIn)
            IconButton(
              tooltip: 'Log ud',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(onlineServiceProvider).signOut(),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('PARTNERS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4)),
                const SizedBox(height: 24),
                _LoginIndicator(user: user, admin: admin),
                const SizedBox(height: 32),
                if (!loggedIn)
                  _bigButton(context, Icons.login, 'Log ind / opret konto',
                      () {
                    Navigator.of(context).push<void>(MaterialPageRoute<void>(
                        builder: (_) => const AuthScreen()));
                  }),
                if (loggedIn) ...<Widget>[
                  _bigButton(context, Icons.smart_toy, 'Spil mod AI', () {
                    Navigator.of(context).push<void>(MaterialPageRoute<void>(
                        builder: (_) => const SetupScreen()));
                  }),
                  const SizedBox(height: 12),
                  _bigButton(context, Icons.group, 'Online med venner', () {
                    Navigator.of(context).push<void>(MaterialPageRoute<void>(
                        builder: (_) => const OnlineHomeScreen()));
                  }),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _smallButton(
                          context,
                          Icons.person,
                          'Min profil',
                          () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                  builder: (_) => const ProfileScreen())),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _smallButton(
                          context,
                          Icons.leaderboard,
                          'Statistik',
                          () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                  builder: (_) => const SiteStatsScreen())),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
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

  Widget _smallButton(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF8B5E3C)),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _LoginIndicator extends StatelessWidget {
  const _LoginIndicator({required this.user, required this.admin});
  final dynamic user;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.no_accounts, color: Colors.white70, size: 18),
            SizedBox(width: 6),
            Text('Ikke logget ind',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      );
    }
    final name = (user.displayName as String?) ??
        (user.email as String?) ??
        'Spiller';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.account_circle, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text('Logget ind som $name',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          if (admin) ...<Widget>[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('ADMIN',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}
