// Stats-repository — læser `games`-collection og opdaterer `userStats/{uid}`-cache.
//
// Beregning kører klient-side (foreløbig). Kaldes typisk når spil afsluttes,
// eller manuelt fra profilskærmen (pull-to-refresh).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../online/online_service.dart';
import 'records.dart';
import 'user_stats.dart';

class StatsRepository {
  StatsRepository();

  FirebaseFirestore get _db => firestore;

  /// Beregn stats for ALLE brugere ud fra alle afsluttede spil.
  /// Bruges af admin / batch-opdatering.
  Future<Map<String, UserStats>> computeAllUsers() async {
    final snap = await _db
        .collection('games')
        .where('status', isEqualTo: 'over')
        .get();
    final games = snap.docs
        .map((d) => Map<String, dynamic>.from(d.data()))
        .toList();
    return computeAllStats(games);
  }

  /// Skriv beregnede stats til userStats/{uid}.
  Future<void> save(Map<String, UserStats> all) async {
    final batch = _db.batch();
    for (final s in all.values) {
      batch.set(_db.collection('userStats').doc(s.uid), s.toJson());
    }
    await batch.commit();
  }

  /// Beregn + cache i én operation.
  Future<Map<String, UserStats>> recomputeAndSave() async {
    final stats = await computeAllUsers();
    await save(stats);
    return stats;
  }

  /// Hent én brugers stats fra cachen.
  Future<UserStats?> get(String uid) async {
    final doc = await _db.collection('userStats').doc(uid).get();
    final data = doc.data();
    if (data == null) return null;
    return UserStats.fromJson(Map<String, dynamic>.from(data));
  }

  /// Live-stream af én brugers stats.
  Stream<UserStats?> watch(String uid) {
    return _db.collection('userStats').doc(uid).snapshots().map((s) {
      final d = s.data();
      return d == null ? null : UserStats.fromJson(Map<String, dynamic>.from(d));
    });
  }

  /// Beregn stats for KUN det seneste afsluttede spil hvor [uid] var med.
  ///
  /// Bruges af profilskærmen til at vise "sidste spil" ved siden af det
  /// samlede billede. Returnerer null hvis spilleren ikke har færdige spil.
  Future<UserStats?> lastGameStatsFor(String uid) async {
    final snap = await _db
        .collection('games')
        .where('status', isEqualTo: 'over')
        .get();
    final docs = snap.docs
        .map((d) => Map<String, dynamic>.from(d.data()))
        .where((g) {
      final uids = (g['uids'] as List?)?.cast<dynamic>() ?? const <dynamic>[];
      return uids.contains(uid);
    }).toList();
    if (docs.isEmpty) return null;
    docs.sort((a, b) {
      final ta = _ts(a['finishedAt']) ?? _ts(a['createdAt']) ?? 0;
      final tb = _ts(b['finishedAt']) ?? _ts(b['createdAt']) ?? 0;
      return tb.compareTo(ta); // nyeste først
    });
    final latest = docs.first;
    final stats = computeAllStats(<Map<String, dynamic>>[latest]);
    return stats[uid];
  }

  /// Find personlige rekorder som [uid] satte i sit seneste afsluttede spil.
  ///
  /// Henter både brugerens aggregerede (gemte) stats og stats for det seneste
  /// spil, og sammenligner dem via [recordsFromLastGame]. Returnerer en tom
  /// liste hvis der mangler data (fx ingen færdige spil eller ingen cache) —
  /// kalderen kan dermed bare vise den normale skærm.
  Future<List<GameRecord>> lastGameRecordsFor(String uid) async {
    final last = await lastGameStatsFor(uid);
    if (last == null) return const <GameRecord>[];
    final aggregate = await get(uid);
    if (aggregate == null) return const <GameRecord>[];
    return recordsFromLastGame(aggregate: aggregate, lastGame: last);
  }

  static int? _ts(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    return null;
  }
}
