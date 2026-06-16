import 'package:flutter/material.dart';

import '../../online/online_service.dart';
import '../../stats/badges.dart';
import '../../stats/stats_repository.dart';
import '../../stats/user_stats.dart';

class SiteStatsScreen extends StatefulWidget {
  const SiteStatsScreen({super.key});

  @override
  State<SiteStatsScreen> createState() => _SiteStatsScreenState();
}

class _SiteStatsScreenState extends State<SiteStatsScreen> {
  final _repo = StatsRepository();
  Map<String, UserStats> _allStats = <String, UserStats>{};
  int _liveGames = 0;
  int _totalGames = 0;
  double? _avgHands;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Live + igangværende
      final live = await firestore
          .collection('games')
          .where('status', whereIn: ['lobby', 'playing'])
          .get();
      _liveGames = live.docs.length;

      // Færdige + gns-hænder
      final over = await firestore
          .collection('games')
          .where('status', isEqualTo: 'over')
          .get();
      _totalGames = over.docs.length;
      if (over.docs.isNotEmpty) {
        final sumHands = over.docs.fold<int>(0, (acc, d) {
          final hn = ((d.data()['state'] as Map?)?['hn'] as num?)?.toInt() ?? 0;
          return acc + hn;
        });
        _avgHands = sumHands / over.docs.length;
      }

      // Per-spiller-stats (læser cachen direkte; brugere uden cache springes)
      final statsSnap = await firestore.collection('userStats').get();
      _allStats = <String, UserStats>{
        for (final d in statsSnap.docs)
          d.id: UserStats.fromJson(Map<String, dynamic>.from(d.data()))
      };

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _repo.recomputeAndSave();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik · alle'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Genberegn',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Fejl: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    _siteCard(),
                    const SizedBox(height: 12),
                    _ranking('🏆 Win-rate (mindst 3 spil)',
                        _topBy((s) => s.gamesPlayed >= 3 ? s.winRate : -1,
                            (s) => '${(s.winRate * 100).toStringAsFixed(0)}%')),
                    _ranking(
                        '🔥 Hot streak (aktuelle sejrsstime)',
                        _topBy(
                            (s) => s.currentWinStreak.toDouble(),
                            (s) => '${s.currentWinStreak}')),
                    _ranking(
                        '⚔️ Mest aggressive (slag pr. spil)',
                        _topBy(
                            (s) => s.captureGames >= 3
                                ? s.avgCapturesPerGame
                                : -1,
                            (s) => s.avgCapturesPerGame.toStringAsFixed(1))),
                    _ranking(
                        '✂️ Mest split-7-glade',
                        _topBy(
                            (s) =>
                                (s.split7Count + s.solid7Count) >= 3
                                    ? s.split7Ratio
                                    : -1,
                            (s) =>
                                '${(s.split7Ratio * 100).toStringAsFixed(0)}%')),
                    _ranking(
                        '🏠 Flest brikker i mål',
                        _topBy((s) => s.homeStretchEntries.toDouble(),
                            (s) => '${s.homeStretchEntries}')),
                    _ranking(
                        '🏆 Flest badges',
                        _topBy(
                            (s) => unlockedBadgeCount(s) > 0
                                ? unlockedBadgeCount(s).toDouble()
                                : -1,
                            (s) =>
                                '${unlockedBadgeCount(s)}/${kAllBadges.length}')),
                  ],
                ),
    );
  }

  Widget _siteCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('🌐 Hele siden',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _row('Spil i gang nu', '$_liveGames'),
            _row('Afsluttede spil', '$_totalGames'),
            _row('Registrerede spillere', '${_allStats.length}'),
            if (_avgHands != null)
              _row('Gns. hænder pr. spil', _avgHands!.toStringAsFixed(1)),
          ],
        ),
      ),
    );
  }

  List<MapEntry<UserStats, String>> _topBy(
      double Function(UserStats) score, String Function(UserStats) display) {
    final entries = _allStats.values
        .map((s) => MapEntry(s, score(s)))
        .where((e) => e.value >= 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).map((e) => MapEntry(e.key, display(e.key))).toList();
  }

  Widget _ranking(String title, List<MapEntry<UserStats, String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (int i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                        width: 28,
                        child: Text('${i + 1}.',
                            style: TextStyle(
                                color: Colors.grey.shade600))),
                    Expanded(child: Text(rows[i].key.displayName)),
                    Text(rows[i].value,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
