import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/online_service.dart';
import '../../stats/stats_repository.dart';
import '../../stats/user_stats.dart';

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
    return Scaffold(
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
      ),
      body: StreamBuilder<UserStats?>(
        stream: _repo.watch(user.uid),
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            );
          }
          return _StatsBody(stats: stats);
        },
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});
  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _section('Sejre & resultater', <Widget>[
          _statRow('Vundne spil', '${s.gamesWon}/${s.gamesPlayed}'),
          _statRow('Win-rate', '${(s.winRate * 100).toStringAsFixed(0)}%'),
          if (s.shortestWin != null)
            _statRow('Kortest sejr 🏁', '${s.shortestWin} hænder'),
          if (s.longestWinStreak > 0)
            _statRow('Længste sejrsstime 📈', '${s.longestWinStreak}'),
          if (s.bestPartner != null)
            _statRow(
                'Bedste makker',
                '${s.bestPartner!.value.displayName} '
                    '(${s.bestPartner!.value.wins}/${s.bestPartner!.value.games})'),
          if (s.worstRival != null)
            _statRow(
                'Værste rival',
                '${s.worstRival!.value.displayName} '
                    '(${s.worstRival!.value.games - s.worstRival!.value.wins}/${s.worstRival!.value.games})'),
        ]),
        _section('Stil & strategi', <Widget>[
          if (s.split7Count + s.solid7Count > 0)
            _statRow('Split-7 vs Saml-7 ✂️',
                '${(s.split7Ratio * 100).toStringAsFixed(0)}% split (${s.split7Count}/${s.split7Count + s.solid7Count})'),
          if (s.captureGames > 0)
            _statRow('Slag pr. spil ⚔️',
                s.avgCapturesPerGame.toStringAsFixed(1)),
          if (s.maxCapturesInGame > 0)
            _statRow('Brand-mester 🔥', '${s.maxCapturesInGame} slag i ét spil'),
          if (s.timesCaptured > 0)
            _statRow('Slag modtaget', '${s.timesCaptured}'),
          if (s.swapCount > 0)
            _statRow('Byttejunkie 🔀', '${s.swapCount}'),
          if (s.homeStretchEntries > 0)
            _statRow('Hjem-mester 🏠', '${s.homeStretchEntries} brikker i mål'),
          if (s.favoriteOpener != null)
            _statRow('Yndlingsåbner 🎴', s.favoriteOpener!),
        ]),
        _section('Held & uheld', <Widget>[
          if (s.passCount > 0)
            _statRow('Sad over 😴', '${s.passCount} runder'),
          if (s.totalCardsDiscarded > 0)
            _statRow('Døde kort ☠️', '${s.totalCardsDiscarded} smidt'),
        ]),
        _section('Tempo & adfærd', <Widget>[
          if (s.gamesPlayed > 0) ...<Widget>[
            _statRow('Online vs AI',
                '${s.gamesOnline} online · ${s.gamesAiOnly} med AI'),
            _statRow('Værts-rate 👑',
                '${s.gamesAsHost}/${s.gamesPlayed} spil'),
          ],
          if (s.avgHandsPerWin > 0)
            _statRow('Snit hænder pr. sejr',
                s.avgHandsPerWin.toStringAsFixed(1)),
          if (s.avgThinkSeconds != null)
            _statRow('Tænketid pr. træk ⏱️',
                '${s.avgThinkSeconds!.toStringAsFixed(1)} s'),
          if (s.fastestThinkSeconds != null)
            _statRow('Lyn-træk ⚡',
                '${s.fastestThinkSeconds!.toStringAsFixed(1)} s'),
          if (s.totalMinutesPlayed > 0)
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
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
