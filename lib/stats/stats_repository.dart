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
  ///
  /// ADVARSEL: dette er en FULD collection-scan (alle `games` i hele appen) og
  /// koster ét read pr. afsluttet spil. Må KUN bruges af admin-batch-
  /// genberegningen (`recomputeAndSave` fra admin-skærmen), aldrig i normale
  /// brugerflows — brug [recomputeAndSaveOwn]/[lastGameStatsFor], der kun læser
  /// den enkelte brugers egne spil.
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

  /// Hent KUN de afsluttede spil hvor [uid] selv var med.
  ///
  /// Bruger `where('uids', arrayContains: uid)`, som kører på Firestores
  /// automatiske array-indeks (intet sammensat indeks nødvendigt). Vi filtrerer
  /// `status == 'over'` klient-side, så vi undgår et sammensat indeks helt.
  ///
  /// Dette er kernen i forbrugs-fixet: en brugers egne stats afhænger kun af de
  /// spil brugeren selv deltog i, så vi behøver ALDRIG scanne hele
  /// `games`-collectionen for at opdatere én bruger. Reads pr. opdatering falder
  /// fra "alle spil i appen" til "denne brugers spil", og vokser dermed ikke
  /// længere kvadratisk med appens levetid.
  Future<List<Map<String, dynamic>>> _ownFinishedGames(String uid) async {
    final snap = await _db
        .collection('games')
        .where('uids', arrayContains: uid)
        .get();
    return snap.docs
        .map((d) => Map<String, dynamic>.from(d.data()))
        .where((g) => g['status'] == 'over')
        .toList();
  }

  /// Skriv beregnede stats til userStats/{uid}.
  Future<void> save(Map<String, UserStats> all) async {
    final batch = _db.batch();
    for (final s in all.values) {
      batch.set(_db.collection('userStats').doc(s.uid), s.toJson());
    }
    await batch.commit();
  }

  /// Beregn + cache ALLE brugere i én operation. Kræver admin-rettigheder mod
  /// Firestore-reglerne (kun admin må skrive andres `userStats`). Bruges af
  /// admin-skærmen.
  Future<Map<String, UserStats>> recomputeAndSave() async {
    final stats = await computeAllUsers();
    await save(stats);
    return stats;
  }

  /// Skriv KUN [uid]'s egen stats-doc. Bruges af almindelige klienter (fx ved
  /// spil-slut eller pull-to-refresh), fordi Firestore-reglerne kun tillader
  /// en bruger at skrive sin egen `userStats/{uid}` (admin må skrive alles).
  Future<void> saveOwn(String uid, Map<String, UserStats> all) async {
    final own = all[uid];
    if (own == null) return;
    await _db.collection('userStats').doc(uid).set(own.toJson());
  }

  /// Genberegn og gem KUN [uid]'s egen stats-doc — ud fra brugerens EGNE spil.
  ///
  /// Læser kun de spil hvor [uid] var med (via [_ownFinishedGames]), ikke hele
  /// `games`-collectionen. Beregningen er stadig en fuld (idempotent) recompute
  /// af brugerens tal fra bunden, så der er ingen risiko for dobbelt-tælling
  /// eller drift — kun langt færre reads.
  Future<void> recomputeAndSaveOwn(String uid) async {
    final games = await _ownFinishedGames(uid);
    final stats = computeAllStats(games);
    await saveOwn(uid, stats);
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
    // Kun brugerens egne spil — ikke en fuld collection-scan (se
    // [_ownFinishedGames]).
    final docs = await _ownFinishedGames(uid);
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
