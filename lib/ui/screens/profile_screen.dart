import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/online_service.dart';
import '../../stats/badges.dart';
import '../../stats/stats_repository.dart';
import '../../stats/user_stats.dart';
import '../widgets/badge_chip.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _repo = StatsRepository();
  bool _recomputing = false;
  String? _error;

  Future<void> _recompute() async {
    setState(() {
      _recomputing = true;
      _error = null;
    });
    try {
      await _repo.recomputeAndSave();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: Text('Log ind for at se din profil')),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Min profil'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Genberegn stats',
              icon: _recomputing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: _recomputing ? null : _recompute,
            ),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Sidste spil'),
              Tab(text: 'I alt'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _LastGameTab(uid: user.uid, repo: _repo),
            _AllTimeTab(uid: user.uid, repo: _repo, error: _error),
          ],
        ),
      ),
    );
  }
}

class _AllTimeTab extends StatelessWidget {
  const _AllTimeTab({required this.uid, required this.repo, this.error});
  final String uid;
  final StatsRepository repo;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserStats?>(
      stream: repo.watch(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final stats = snap.data;
        if (stats == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ingen stats endnu. Spil et spil til ende, og tryk så '
                    'på refresh-ikonet for at beregne.',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child:
                        Text(error!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          );
        }
        return _StatsBody(stats: stats, singleGame: false);
      },
    );
  }
}

class _LastGameTab extends StatefulWidget {
  const _LastGameTab({required this.uid, required this.repo});
  final String uid;
  final StatsRepository repo;

  @override
  State<_LastGameTab> createState() => _LastGameTabState();
}

class _LastGameTabState extends State<_LastGameTab> {
  Future<UserStats?>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.lastGameStatsFor(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _future = widget.repo.lastGameStatsFor(widget.uid);
        });
        await _future;
      },
      child: FutureBuilder<UserStats?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snap.data;
          if (stats == null) {
            return ListView(
              children: const <Widget>[
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Du har ikke spillet et færdigspillet spil endnu.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }
          return _StatsBody(stats: stats, singleGame: true);
        },
      ),
    );
  }
}

/// Viser stats. Når [singleGame] er true skjules tværgående tal
/// (streaks, makker-/rival-aggregater) der ikke giver mening for ét spil.
class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats, required this.singleGame});
  final UserStats stats;
  final bool singleGame;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        if (!singleGame) _BadgesSection(stats: s),
        _section('Sejre & resultater', <Widget>[
          _statRow(singleGame ? 'Resultat' : 'Vundne spil',
              singleGame
                  ? (s.gamesWon > 0 ? 'Vundet' : 'Tabt')
                  : '${s.gamesWon}/${s.gamesPlayed}'),
          if (!singleGame)
            _statRow('Win-rate', '${(s.winRate * 100).toStringAsFixed(0)}%'),
          if (s.shortestWin != null)
            _statRow(singleGame ? 'Antal hænder' : 'Kortest sejr 🏁',
                '${s.shortestWin} hænder'),
          if (!singleGame && s.longestWinStreak > 0)
            _statRow('Længste sejrsstime 📈', '${s.longestWinStreak}'),
          if (!singleGame && s.bestPartner != null)
            _statRow(
                'Bedste makker',
                '${s.bestPartner!.value.displayName} '
                    '(${s.bestPartner!.value.wins}/${s.bestPartner!.value.games})'),
          if (!singleGame && s.worstRival != null)
            _statRow(
                'Værste rival',
                '${s.worstRival!.value.displayName} '
                    '(${s.worstRival!.value.games - s.worstRival!.value.wins}/${s.worstRival!.value.games})'),
          if (singleGame && s.partnerStats.isNotEmpty)
            _statRow('Makker', s.partnerStats.values.first.displayName),
        ]),
        _section('Stil & strategi', <Widget>[
          if (s.split7Count + s.solid7Count > 0)
            _statRow('Split-7 vs Saml-7 ✂️',
                '${(s.split7Ratio * 100).toStringAsFixed(0)}% split (${s.split7Count}/${s.split7Count + s.solid7Count})'),
          if (s.captureGames > 0)
            _statRow(singleGame ? 'Slag givet ⚔️' : 'Slag pr. spil ⚔️',
                singleGame
                    ? '${s.totalCaptures}'
                    : s.avgCapturesPerGame.toStringAsFixed(1)),
          if (!singleGame && s.maxCapturesInGame > 0)
            _statRow('Brand-mester 🔥', '${s.maxCapturesInGame} slag i ét spil'),
          if (s.timesCaptured > 0)
            _statRow('Slag modtaget', '${s.timesCaptured}'),
          if (s.swapCount > 0)
            _statRow('Byttejunkie 🔀', '${s.swapCount}'),
          if (s.homeStretchEntries > 0)
            _statRow('Hjem-mester 🏠', '${s.homeStretchEntries} brikker i mål'),
          if (s.favoriteOpener != null)
            _statRow(singleGame ? 'Åbnede med 🎴' : 'Yndlingsåbner 🎴',
                s.favoriteOpener!),
        ]),
        _section('Held & uheld', <Widget>[
          if (s.passCount > 0)
            _statRow('Sad over 😴', '${s.passCount} runder'),
          if (s.totalCardsDiscarded > 0)
            _statRow('Døde kort ☠️', '${s.totalCardsDiscarded} smidt'),
        ]),
        _section('Tempo & adfærd', <Widget>[
          if (!singleGame && s.gamesPlayed > 0) ...<Widget>[
            _statRow('Online vs AI',
                '${s.gamesOnline} online · ${s.gamesAiOnly} med AI'),
            _statRow('Værts-rate 👑',
                '${s.gamesAsHost}/${s.gamesPlayed} spil'),
          ],
          if (singleGame)
            _statRow('Spil-type',
                s.gamesOnline > 0 ? 'Online' : 'Med AI'),
          if (!singleGame && s.avgHandsPerWin > 0)
            _statRow('Snit hænder pr. sejr',
                s.avgHandsPerWin.toStringAsFixed(1)),
          if (s.avgThinkSeconds != null)
            _statRow(singleGame ? 'Tænketid pr. træk ⏱️' : 'Tænketid pr. træk ⏱️',
                '${s.avgThinkSeconds!.toStringAsFixed(1)} s'),
          if (s.fastestThinkSeconds != null)
            _statRow('Lyn-træk ⚡',
                '${s.fastestThinkSeconds!.toStringAsFixed(1)} s'),
          if (singleGame && s.totalMinutesPlayed > 0)
            _statRow('Spilletid',
                '${s.totalMinutesPlayed.toStringAsFixed(0)} min'),
          if (!singleGame && s.totalMinutesPlayed > 0)
            _statRow('Total spilletid',
                '${s.totalMinutesPlayed.toStringAsFixed(0)} min'),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) {
    final filtered = rows.where((w) => w is! SizedBox).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...filtered,
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Viser optjente badges som farverige chips og låste badges nedtonet,
/// grupperet pr. kategori. En lille tæller i toppen viser fremgangen.
class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.stats});
  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final unlocked = unlockedBadgeCount(stats);
    final total = kAllBadges.length;
    final groups = badgesByCategory();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('Badges 🏆',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('$unlocked/$total',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Optjen badges ved at spille og udvikle din stil.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            for (final entry in groups.entries) ...<Widget>[
              const SizedBox(height: 12),
              Text(entry.key.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final badge in entry.value)
                    BadgeChip(badge: badge, stats: stats),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
