// Stats-repository — læser `games`-collection og opdaterer `userStats/{uid}`-cache.
//
// Beregning kører klient-side (foreløbig). Kaldes typisk når spil afsluttes,
// eller manuelt fra profilskærmen (pull-to-refresh).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../online/online_service.dart';
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
}
