import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  int _registeredPlayers = 0;
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
      // Forbrug: denne skærm er en OFFENTLIG rangliste (åbnes fra forsiden af
      // alle brugere). Tidligere hentede vi HVERT eneste spil-dokument bare for
      // at TÆLLE dem og udregne et gennemsnit — ét read pr. spil, ved hver
      // åbning. Nu bruger vi Firestore aggregation-queries (count()/average()),
      // der afregnes ~1 read pr. 1000 matchede dokumenter i stedet for ét pr.
      // dokument.

      // Live + igangværende (kun antal).
      final liveAgg = await firestore
          .collection('games')
          .where('status', whereIn: ['lobby', 'playing'])
          .count()
          .get();
      _liveGames = liveAgg.count ?? 0;

      // Afsluttede spil — site-tallet skal KUN tælle rigtige spil, ikke
      // AI-solospil. Alle mode:'ai'-spil er også status:'over', så online-
      // antallet = (alle over) − (mode:'ai'). To ENKELT-felt-counts, så der ikke
      // kræves et sammensat indeks.
      final overCountAgg = await firestore
          .collection('games')
          .where('status', isEqualTo: 'over')
          .count()
          .get();
      final int overCount = overCountAgg.count ?? 0;
      final aiCountAgg = await firestore
          .collection('games')
          .where('mode', isEqualTo: 'ai')
          .count()
          .get();
      final int aiCount = aiCountAgg.count ?? 0;
      _totalGames = (overCount - aiCount).clamp(0, overCount);

      // Gns. hænder (online-kun) via aggregat-subtraktion: sum(alle) − sum(AI),
      // hvor sum = gns × antal. average() på indlejret felt kan i sjældne
      // tilfælde fejle — det må ikke vælte skærmen, så det hentes defensivt.
      _avgHands = null;
      if (_totalGames > 0) {
        try {
          final avgAllAgg = await firestore
              .collection('games')
              .where('status', isEqualTo: 'over')
              .aggregate(average('state.hn'))
              .get();
          final double? avgAll = avgAllAgg.getAverage('state.hn');
          if (avgAll != null && aiCount == 0) {
            _avgHands = avgAll;
          } else if (avgAll != null) {
            final avgAiAgg = await firestore
                .collection('games')
                .where('mode', isEqualTo: 'ai')
                .aggregate(average('state.hn'))
                .get();
            final double? avgAi = avgAiAgg.getAverage('state.hn');
            _avgHands = avgAi == null
                ? avgAll // fallback: kan ikke trække AI fra → vis samlet gns.
                : (avgAll * overCount - avgAi * aiCount) / _totalGames;
          }
        } catch (_) {
          _avgHands = null; // gennemsnit udelades hvis aggregeringen fejler
        }
      }

      // Rangliste: læs KUN online-cachen (userStatsOnline) — AI-solospil er
      // ekskluderet der, så man ikke kan klatre ved at slå let AI.
      // #16: bind læsningen — hent ikke hele collectionen ubegrænset ved hver
      // visning. Sortér efter aktivitet (gamesPlayed, auto-indekseret enkelt-
      // felt — intet sammensat indeks nødvendigt) og tag de mest aktive. Ved
      // nuværende skala rummer 500 alle spillere; ved stor vækst bliver
      // læsningen bundet i stedet for at vokse lineært med brugerantallet. De
      // mest aktive er også netop dem der kan rangere (mindst-3-spil-tærskler).
      final onlineSnap = await firestore
          .collection('userStatsOnline')
          .orderBy('gamesPlayed', descending: true)
          .limit(500)
          .get();
      _allStats = <String, UserStats>{
        for (final d in onlineSnap.docs)
          d.id: UserStats.fromJson(Map<String, dynamic>.from(d.data()))
      };

      // Registrerede spillere = alle med en profil-cache (inkl. dem der kun har
      // spillet mod AI og derfor ikke er på ranglisten).
      final playersAgg =
          await firestore.collection('userStats').count().get();
      _registeredPlayers = playersAgg.count ?? _allStats.length;

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
          if (isAdmin(FirebaseAuth.instance.currentUser))
            IconButton(
              tooltip: 'Nulstil al statistik (admin)',
              icon: const Icon(Icons.delete_forever),
              onPressed: _loading ? null : _confirmReset,
            ),
          // Kun admin: "Genberegn" kører recomputeAndSave() — en FULD scan af
          // hele games-collectionen. Ikke-admins ville alligevel fejle på
          // Firestore-skrivereglen, men først EFTER det dyre read; skjul derfor
          // knappen helt for dem (som nulstil-knappen ovenfor).
          if (isAdmin(FirebaseAuth.instance.currentUser))
            IconButton(
              tooltip: 'Genberegn (admin)',
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
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        'Ranglisterne tæller kun spil mod andre spillere — '
                        'solospil mod computeren tælles med i din egen profil, '
                        'men ikke her.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 8),
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
            _row('Afsluttede spil (online)', '$_totalGames'),
            _row('Registrerede spillere', '$_registeredPlayers'),
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
        // Spillere uden online-spil har en 0-stats online-cache (skrives så
        // gamle tal ryddes) — de skal ikke optræde som "spøgelses-rækker" med 0
        // i de ranglister der ikke selv har en minimums-tærskel.
        .where((s) => s.gamesPlayed > 0)
        .map((s) => MapEntry(s, score(s)))
        .where((e) => e.value >= 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).map((e) => MapEntry(e.key, display(e.key))).toList();
  }

  /// Disambiguerer navne i ranglisterne — hvis flere spillere har samme
  /// displayName (typisk "Du" fra default-AI-opsætningen, ramt af brugere der
  /// har logget ind med både Google og email og dermed har to forskellige
  /// uids) tilføjes et kort uid-fragment så rækkerne kan kendes fra hinanden.
  String _disambiguatedName(UserStats s) {
    final bool isMe = s.uid == FirebaseAuth.instance.currentUser?.uid;
    final int dupes =
        _allStats.values.where((o) => o.displayName == s.displayName).length;
    if (dupes <= 1) return isMe ? '${s.displayName} (dig)' : s.displayName;
    final String tail =
        s.uid.length >= 4 ? s.uid.substring(s.uid.length - 4) : s.uid;
    // Markér den konto du er logget ind med LIGE NU, så to ens "Du"-rækker
    // (typisk to logins) kan skelnes.
    return '${s.displayName} (#$tail)${isMe ? ' — dig' : ''}';
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
                    Expanded(child: Text(_disambiguatedName(rows[i].key))),
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

  Future<void> _confirmReset() async {
    final choice = await showDialog<_ResetScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nulstil statistik'),
        content: const Text(
            'Vælg hvad der skal nulstilles. Handlingen kan ikke fortrydes.\n\n'
            '• Kun cache: sletter alt under userStats/ (kan genberegnes fra '
            'games-collection bagefter).\n'
            '• Cache + afsluttede spil: sletter også alle afsluttede spil '
            '(status="over"). Igangværende spil bevares.\n'
            '• Alt inkl. igangværende: rydder også lobby/playing — '
            'spillere mister adgang til deres aktive spil.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annullér')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _ResetScope.cacheOnly),
              child: const Text('Kun cache')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _ResetScope.cacheAndHistory),
              child: const Text('+ afsluttede')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx, _ResetScope.allGames),
              child: const Text('Alt inkl. igangværende')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await _performReset(choice);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Statistik nulstillet.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _performReset(_ResetScope scope) async {
    // Slet i batches af 400 (Firestore-grænse: 500 ops pr. batch).
    Future<void> deleteAll(String coll, {Map<String, dynamic>? where}) async {
      while (true) {
        Query q = firestore.collection(coll);
        if (where != null) {
          where.forEach((k, v) {
            q = q.where(k, isEqualTo: v);
          });
        }
        final snap = await q.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = firestore.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (snap.docs.length < 400) break;
      }
    }

    await deleteAll('userStats');
    if (scope == _ResetScope.cacheAndHistory) {
      await deleteAll('games', where: <String, dynamic>{'status': 'over'});
    } else if (scope == _ResetScope.allGames) {
      // Slet ALLE spil — også igangværende og lobbyer.
      await deleteAll('games');
    }
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

enum _ResetScope { cacheOnly, cacheAndHistory, allGames }

