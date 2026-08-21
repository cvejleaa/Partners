import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../models/variant_config.dart';
import '../widgets/variant_badge.dart';
import '../../online/friends_service.dart';
import '../../online/online_service.dart';
import '../../state/variant_card_rules_controller.dart';
import '../../utils/avatars.dart';
import 'admin_screen.dart';
import 'game_screen.dart';
import 'online_screens.dart';
import 'profile_screen.dart';
import 'self_test_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'site_stats_screen.dart';
import 'tutorial_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
    final user = authAsync.valueOrNull;
    final loggedIn = user != null;
    final admin = isAdmin(user);
    // Tæl ulæste invitationer (kun når man er logget ind). Streamen er
    // robust mod manglende/tomme docs og returnerer en tom liste hvis
    // brugeren ikke er logget ind.
    final int unreadInvites = loggedIn
        ? (ref
                .watch(inboxStreamProvider)
                .valueOrNull
                ?.where((i) => !i.seen)
                .length ??
            0)
        : 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Partners'),
            if (unreadInvites > 0) ...<Widget>[
              const SizedBox(width: 8),
              _InviteBadge(count: unreadInvites),
            ],
          ],
        ),
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
          IconButton(
            tooltip: 'Indstillinger',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
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
                if (loggedIn) const _InviteBanner(),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: _smallButton(
                    context,
                    Icons.school,
                    'Sådan spiller du',
                    () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                            builder: (_) => const TutorialScreen())),
                  ),
                ),
                const SizedBox(height: 16),
                if (!loggedIn)
                  _bigButton(context, Icons.login, 'Log ind / opret konto',
                      () {
                    Navigator.of(context).push<void>(MaterialPageRoute<void>(
                        builder: (_) => const AuthScreen()));
                  }),
                if (loggedIn) ...<Widget>[
                  const _ResumeButton(),
                  _bigButton(context, Icons.smart_toy, 'Spil mod AI', () async {
                    await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                            builder: (_) => const SetupScreen()));
                    ref.invalidate(savedGameProvider);
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
                const SizedBox(height: 24),
                const _BuildStamp(),
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

/// Viser en "Fortsæt spil"-knap hvis der findes et gemt, igangværende spil.
/// Skjuler sig selv (og sin spacing) når der ikke er noget at genoptage.
class _ResumeButton extends ConsumerWidget {
  const _ResumeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SavedGameInfo? saved = ref.watch(savedGameProvider).valueOrNull;
    if (saved == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: const Color(0xFF2E7D32),
              ),
              onPressed: () async {
                final bool ok = ref.read(gameProvider.notifier).resumeFrom(
                    saved,
                    variantsRaw:
                        ref.read(variantCardRulesProvider).toRawJson());
                if (!ok) {
                  // Korrupt/forældet save — det er nu ryddet. Fjern knappen og
                  // vis en kort besked i stedet for at navigere ind i et tomt
                  // spil.
                  ref.invalidate(savedGameProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Det gemte spil kunne ikke genoptages (for gammelt format).')));
                  }
                  return;
                }
                await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const GameScreen()));
                ref.invalidate(savedGameProvider);
              },
              icon: const Icon(Icons.play_circle),
              label: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                // Variant-badgen følger med det gemte spil ("samme sted hver
                // gang") — vid læses defensivt af det rå save.
                VariantBadge(
                  // vid ligger i raw['state'], ikke på topniveau — én delt,
                  // testet vagt (variantFromAutosave), så fejlen ikke kan
                  // genopstå et andet sted.
                  variant: variantFromAutosave(saved.raw,
                      variantsRaw:
                          ref.watch(variantCardRulesProvider).toRawJson()),
                  compact: true,
                  interactive: false,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Fortsæt spil (hånd #${saved.handNumber})',
                      style: const TextStyle(fontSize: 18),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Slet det gemte spil (med bekræftelse).
          SizedBox(
            height: 56,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () async {
                final bool? ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Slet gemt spil?'),
                    content: Text(
                        'Det igangværende spil (hånd #${saved.handNumber}) '
                        'slettes. Handlingen kan ikke fortrydes.'),
                    actions: <Widget>[
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annullér')),
                      FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Slet')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(gameProvider.notifier).discardSavedGame();
                  ref.invalidate(savedGameProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Gemt spil slettet.')));
                  }
                }
              },
              child: const Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginIndicator extends ConsumerWidget {
  const _LoginIndicator({required this.user, required this.admin});
  final dynamic user;
  final bool admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
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
    final fallbackName = (user.displayName as String?) ??
        (user.email as String?) ??
        'Spiller';
    final profile =
        ref.watch(myProfileProvider).valueOrNull;
    final name = profile?.displayName ?? fallbackName;
    final emoji = avatarEmoji(profile?.avatar);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 18)),
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

/// Lille badge der viser antallet af ulæste invitationer i app-baren.
class _InviteBadge extends StatelessWidget {
  const _InviteBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// In-app banner der viser den nyeste aktive spil-invitation, med en
/// "Hop ind"-knap der navigerer ind i online-spillets lobby. Vises kun
/// hvis der er mindst én invitation der hverken er set eller har resulteret
/// i en lobby-/spil-side endnu. Når flere er aktive vises kun den nyeste
/// med en lille "(+N flere)"-indikator.
class _InviteBanner extends ConsumerWidget {
  const _InviteBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitesAsync = ref.watch(inboxStreamProvider);
    final list = invitesAsync.valueOrNull ?? const <InboxInvite>[];
    // Foretræk invitationer der ikke er markeret som set; ellers vis alligevel
    // den nyeste hvis den endnu ikke er slettet — så brugeren altid har en
    // hurtig genvej tilbage til den seneste invitation.
    final active = list
        .where((i) => i.type == 'gameInvite' && i.gameCode.isNotEmpty && !i.seen)
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final top = active.first;
    final extra = active.length - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final friends = ref.read(friendsServiceProvider);
            // Marker som set først — så badge tæller ned uanset hvad der sker
            // dernæst, og banneret ikke vender tilbage hvis lobbyen lukker.
            // ignore: discarded_futures
            friends.markSeen(top.id);
            await Navigator.of(context).push<void>(MaterialPageRoute<void>(
                builder: (_) => LobbyScreen(code: top.gameCode)));
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.mail, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${top.fromName} inviterede dig',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        extra > 0
                            ? 'Kode ${top.gameCode}  ·  (+$extra flere)'
                            : 'Kode ${top.gameCode}  ·  Hop ind',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lille build-stempel der gør det muligt at se hvilket build der kører.
/// Sættes via --dart-define=BUILD_TAG=... i CI; default 'dev' lokalt.
class _BuildStamp extends StatelessWidget {
  const _BuildStamp();

  static const String _buildTag =
      String.fromEnvironment('BUILD_TAG', defaultValue: 'dev');

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'build $_buildTag',
        style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 11),
      ),
    );
  }
}
