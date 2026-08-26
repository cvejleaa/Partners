// Stats-repository — læser `games`-collection og opdaterer `userStats/{uid}`-cache.
//
// Beregning kører klient-side (foreløbig). Kaldes typisk når spil afsluttes,
// eller manuelt fra profilskærmen (pull-to-refresh).
//
// Doc-form (både userStats og userStatsOnline):
//   top-niveau  = UserStats.toJson() for ALLE brugerens spil (bagudkompatibelt)
//   byVariant   = { vid: <UserStats-json for KUN den variants spil> }
// I userStats er byVariant-posterne den fulde form; i den OFFENTLIGE
// userStatsOnline er de den slanke ranglisteform (toSlimRankingJson) — se
// UserStats. Kun varianter med gamesPlayed > 0 skrives (ingen tomme nøgler).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../game/card_rules.dart';
import '../models/variant_config.dart';
import '../online/online_service.dart';
import 'records.dart';
import 'user_stats.dart';

/// Har serveren markeret brugerens statistik som forældet?
///
/// Markøren `staleSince` sættes af Cloud Function'en onGameOver, når et spil
/// slutter — for ALLE deltagere. Den findes, fordi en brugers tal kun kan
/// skrives af brugerens egen klient (Firestore-reglerne), og kun mens dén
/// klient ser spillet slutte: lå makkerens app i baggrunden, blev deres tal
/// aldrig opdateret, og de manglede i variant-toplisterne.
///
/// Manglende dokument = ingen spil endnu = intet at genberegne (markeringen
/// OPRETTER dokumentet med merge, så en spiller med spil har det altid).
bool statsNeedRecompute(Map<String, dynamic>? statsDoc) =>
    statsDoc != null && statsDoc['staleSince'] != null;

/// Tidsstemplet et spil-doc regnes efter (afsluttet, ellers oprettet, ellers 0).
int gameTimeMs(Map<String, dynamic> game) =>
    _tsMsOf(game['finishedAt']) ?? _tsMsOf(game['createdAt']) ?? 0;

int? _tsMsOf(dynamic v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is int) return v;
  return null;
}

/// Spillene "som verden så ud, da [code] blev spillet": alle spil afsluttet
/// FØR det, plus spillet selv. Bruges til at genskabe en gammel slutrapport
/// fra arkivet, så rekorderne er dem der gjaldt dengang — ikke dem der gælder
/// i dag.
///
/// Tie-bracket er EKSPLICIT: `t < cutoff || g['code'] == code`. Et rent
/// `t <= cutoff` ville trække ethvert FREMMED spil med præcis samme
/// millisekund med ind i "dengang" — og hvilket af to samtidige spil der så
/// talte med, ville afhænge af skrive-rækkefølgen i Firestore. Spillet selv er
/// altid med, uanset hvad dets tidsstempel er (også 0 for et doc uden
/// tidsstempler).
///
/// Ukendt [code] → tom liste (kalderen viser ingen rekorder frem for forkerte).
List<Map<String, dynamic>> gamesUpTo(
    List<Map<String, dynamic>> games, String code) {
  final Map<String, dynamic>? game = gameWithCode(games, code);
  if (game == null) return const <Map<String, dynamic>>[];
  final int cutoff = gameTimeMs(game);
  return games
      .where((g) => gameTimeMs(g) < cutoff || g['code'] == code)
      .toList();
}

/// Spil-doc'et med [code], eller null. (Ingen `firstOrNull` — den kræver en
/// extension-import, og et opslag her skal ikke kunne vælte oversættelsen.)
Map<String, dynamic>? gameWithCode(
    List<Map<String, dynamic>> games, String code) {
  for (final Map<String, dynamic> g in games) {
    if (g['code'] == code) return g;
  }
  return null;
}

/// Sidste spils stats + hvilken variant det blev spillet i. Varianten følger
/// med fra samme spil-doc, så UI/rekord-logikken ikke skal gætte den igen.
class LastGameStats {
  LastGameStats(this.stats, this.variantId, this.cardRules);
  final UserStats stats;
  final String variantId;

  /// De regler spillet FAKTISK blev spillet med. Følger med herfra, så
  /// kortregnskabets undertekst navngiver præcis de kort der blev talt — ikke
  /// dem en anden opløsning ville have givet.
  final CardRules cardRules;
}

class StatsRepository {
  StatsRepository();

  FirebaseFirestore get _db => firestore;

  /// FULD scan af alle afsluttede spil.
  ///
  /// ADVARSEL: koster ét read pr. afsluttet spil i HELE appen. Må KUN bruges af
  /// admin-batch-genberegningen ([recomputeAndSave] fra admin-skærmen), aldrig i
  /// normale brugerflows — de bruger [recomputeAndSaveOwn]/[lastGameStatsFor],
  /// der kun læser den enkelte brugers egne spil.
  Future<List<Map<String, dynamic>>> _allFinishedGames() async {
    final snap = await _db
        .collection('games')
        .where('status', isEqualTo: 'over')
        .get();
    return snap.docs
        .map((d) => Map<String, dynamic>.from(d.data()))
        .toList();
  }

  /// AI-solospil markeres med `mode: 'ai'` (se app.dart). De skal KUN tælle i
  /// brugerens egen profil, ikke i den offentlige rangliste — så online-cachen
  /// beregnes af spil UDEN den markør.
  ///
  /// BEVIDST afgrænsning: dette udelukker kun det lokale solo-praksis-flow
  /// (den nemme "spil mod computeren"-genvej). Online-lobbyspil med en eller
  /// flere AI-pladser har ingen `mode` og tæller derfor stadig med — de er
  /// rigtige spil sat op mellem mennesker. Vil man også holde dem ude, skal
  /// filteret skifte til "kun 4 menneskelige uids" (isFullyOnline).
  static List<Map<String, dynamic>> _onlineOnly(
          List<Map<String, dynamic>> games) =>
      games.where((g) => g['mode'] != 'ai').toList();

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
        // Doc-id'et (spilkoden) med, så et BESTEMT spil kan slås op igen —
        // fx når en gammel slutrapport åbnes fra arkivet.
        .map((d) => <String, dynamic>{...d.data(), 'code': d.id})
        .where((g) => g['status'] == 'over')
        .toList();
  }

  /// Byg hele doc-json'en for ÉN bruger: top-niveau (alle spil) + byVariant.
  /// [slim] vælger den slanke ranglisteform for byVariant-posterne (til den
  /// offentlige userStatsOnline). Doc'en skrives med set() UDEN merge, så et
  /// udeladt byVariant-felt også rydder evt. forældede variant-nøgler.
  static Map<String, dynamic> docJsonFor(
    UserStats total,
    Map<String, Map<String, UserStats>> byVariant, {
    required bool slim,
  }) {
    final Map<String, dynamic> json = total.toJson();
    final by = <String, dynamic>{};
    for (final e in byVariant.entries) {
      final UserStats? v = e.value[total.uid];
      if (v == null || v.gamesPlayed == 0) continue;
      by[e.key] = slim ? v.toSlimRankingJson() : v.toJson(withTimestamp: false);
    }
    if (by.isNotEmpty) json['byVariant'] = by;
    return json;
  }

  /// Ren chunk-hjælper — udskilt så batch-grænsen kan mutationstestes uden
  /// Firestore (501 brugere → flere batches, ingen tabes).
  static List<List<T>> chunked<T>(List<T> items, int size) {
    final out = <List<T>>[];
    for (int i = 0; i < items.length; i += size) {
      out.add(items.sublist(
          i, i + size > items.length ? items.length : i + size));
    }
    return out;
  }

  /// Skriv færdigbyggede doc-jsons til [collection] i batches.
  ///
  /// Batch-størrelsen er IKKE Firestores 500-ops-grænse men request-STØRRELSEN:
  /// en tung brugers doc med byVariant-kopier kan runde ~16 KB, og 500 × 16 KB
  /// ≈ 8 MB nærmer sig API'ets 10 MiB-grænse. 150 pr. batch holder worst-case
  /// ≈ 2,4 MB med god margin — og koster kun få ekstra commits.
  static const int kSaveBatchSize = 150;

  Future<void> _saveAllTo(
      String collection, Map<String, Map<String, dynamic>> docs) async {
    for (final chunk in chunked(docs.entries.toList(), kSaveBatchSize)) {
      final batch = _db.batch();
      for (final e in chunk) {
        batch.set(_db.collection(collection).doc(e.key), e.value);
      }
      await batch.commit();
    }
  }

  /// Beregn + cache ALLE brugere i én operation — BÅDE samlet (userStats, til
  /// profilerne) og online-kun (userStatsOnline, til ranglisten), begge med
  /// byVariant. Admin-only (kun admin må skrive andres stats-docs). Bruges af
  /// admin-skærmen — og er også den godkendte vej til at FYLDE byVariant for
  /// historiske spil (state.vid har altid været skrevet, så attributionen er
  /// 100 % retroaktiv).
  Future<Map<String, UserStats>> recomputeAndSave() async {
    final games = await _allFinishedGames();
    final combined = computePartitionedStats(games);
    final online = computePartitionedStats(_onlineOnly(games));
    await _saveAllTo('userStats', <String, Map<String, dynamic>>{
      for (final s in combined.total.values)
        s.uid: docJsonFor(s, combined.byVariant, slim: false),
    });
    await _saveAllTo('userStatsOnline', <String, Map<String, dynamic>>{
      for (final s in online.total.values)
        s.uid: docJsonFor(s, online.byVariant, slim: true),
    });
    return combined.total;
  }

  /// Genberegn og gem KUN [uid]'s egen stats-doc — ud fra brugerens EGNE spil.
  ///
  /// Læser kun de spil hvor [uid] var med (via [_ownFinishedGames]), ikke hele
  /// `games`-collectionen. Beregningen er stadig en fuld (idempotent) recompute
  /// af brugerens tal fra bunden — inkl. byVariant — så der er ingen risiko for
  /// dobbelt-tælling eller drift.
  Future<void> recomputeAndSaveOwn(String uid) async {
    final games = await _ownFinishedGames(uid);
    final combined = computePartitionedStats(games);
    final UserStats? own = combined.total[uid];
    // Online-kun cache til ranglisten. Hvis brugeren ingen online-spil har,
    // skrives 0-stats (med rigtigt navn), så evt. gamle online-tal ryddes og
    // brugeren ikke fejlagtigt bliver hængende på ranglisten.
    final online = computePartitionedStats(_onlineOnly(games));
    final UserStats onlineOwn = online.total[uid] ??
        UserStats(uid: uid, displayName: own?.displayName ?? 'Spiller');
    // ÉN batch for BEGGE dokumenter (QC-fund): det er userStats-skrivningen
    // der rydder `staleSince`-markøren. Blev de skrevet hver for sig og det
    // andet kald fejlede (netværksdrop på mobil), ville markøren være væk,
    // mens den OFFENTLIGE rangliste stod tilbage med forældede tal — og
    // intet ville nogensinde prøve igen. Atomisk: enten begge eller ingen.
    final batch = _db.batch();
    // Skriv ALTID userStats — også når brugeren ingen afsluttede spil har
    // (0-stats med kendt navn). Sprang vi skrivningen over, ville
    // `staleSince`-markøren aldrig blive ryddet, og hver app-start ville
    // koste et forgæves læs + genberegning for evigt (security-fund: kan
    // fremprovokeres ved at markere nogen og derefter slette spillet).
    final UserStats ownOrEmpty = own ??
        UserStats(uid: uid, displayName: onlineOwn.displayName);
    batch.set(_db.collection('userStats').doc(uid),
        docJsonFor(ownOrEmpty, combined.byVariant, slim: false));
    batch.set(_db.collection('userStatsOnline').doc(uid),
        docJsonFor(onlineOwn, online.byVariant, slim: true));
    await batch.commit();
  }

  /// Selvhelbredelse ved app-start: ét dokument-læs, og kun en genberegning
  /// hvis serveren har markeret tallene forældede. Genberegningen skriver
  /// dokumentet med set() UDEN merge, så markøren ryddes af sig selv — ingen
  /// ekstra skrivning, ingen mulighed for at hænge fast i "forældet".
  ///
  /// Returnerer true hvis der faktisk blev genberegnet.
  Future<bool> recomputeOwnIfStale(String uid) async {
    final doc = await _db.collection('userStats').doc(uid).get();
    if (!statsNeedRecompute(doc.data())) return false;
    await recomputeAndSaveOwn(uid);
    return true;
  }

  /// Hent én brugers samlede stats fra cachen (top-niveau, alle varianter).
  Future<UserStats?> get(String uid) async {
    final doc = await getDoc(uid);
    return doc?.total;
  }

  /// Hent hele doc'en inkl. byVariant.
  Future<UserStatsDoc?> getDoc(String uid) async {
    final doc = await _db.collection('userStats').doc(uid).get();
    final data = doc.data();
    if (data == null) return null;
    return UserStatsDoc.fromJson(Map<String, dynamic>.from(data));
  }

  /// Live-stream af én brugers stats-doc (top-niveau + byVariant).
  Stream<UserStatsDoc?> watchDoc(String uid) {
    return _db.collection('userStats').doc(uid).snapshots().map((s) {
      final d = s.data();
      return d == null
          ? null
          : UserStatsDoc.fromJson(Map<String, dynamic>.from(d));
    });
  }

  /// Beregn stats for KUN det seneste afsluttede spil hvor [uid] var med —
  /// plus spillets variant-id (fra state.vid, rå attributions-nøgle).
  ///
  /// Bruges af profilskærmen til at vise "sidste spil" ved siden af det
  /// samlede billede. Returnerer null hvis spilleren ikke har færdige spil.
  Future<LastGameStats?> lastGameStatsFor(String uid) async {
    // Kun brugerens egne spil — ikke en fuld collection-scan (se
    // [_ownFinishedGames]).
    final docs = await _ownFinishedGames(uid);
    if (docs.isEmpty) return null;
    // nyeste først
    docs.sort((a, b) => gameTimeMs(b).compareTo(gameTimeMs(a)));
    final latest = docs.first;
    final stats = computeAllStats(<Map<String, dynamic>>[latest])[uid];
    if (stats == null) return null;
    final String vid = variantIdOfGameDoc(latest);
    return LastGameStats(
        stats, vid, cardRulesOfGameDoc(latest, variantForState(vid)));
  }

  /// Langtids-kortregnskabet for [uid] i [variantId] — ankeret et enkelt
  /// partis tal måles MOD. Uden det ligner en helt normal kortfordeling et
  /// overgreb: to rå tal har ingen målestok.
  ///
  /// VARIANT-SCOPET med vilje. Kortmixet er vidt forskelligt fra variant til
  /// variant (25 år har langt flere specialkort end klassisk), så et snit på
  /// tværs ville sammenligne et parti med noget det ikke er.
  ///
  /// Læser cachen (ét doc) frem for at udlede ankeret af de rå spil, som
  /// [recordsForGame] gør. Det er bevidst forskelligt: slutrapporten replayer
  /// alligevel alle brugerens spil for rekorderne, så dér er ankeret gratis.
  /// Profilens "Sidste spil" gør IKKE det — den beregner kun det seneste spil
  /// — og en udledning fra de rå spil ville tvinge en fuld replay af hele
  /// historikken ved hver åbning. Ét cache-read er billigere. Prisen er, at en
  /// bruger med en ikke-genberegnet cache ser tallene UDEN snit (aldrig
  /// forkerte tal: cardMixGames == 0 → intet snit).
  Future<UserStats?> cardMixAnchorFor(String uid, String variantId) async {
    final UserStatsDoc? doc = await getDoc(uid);
    if (doc == null) return null;
    return recordAggregateFor(doc, variantId);
  }

  /// Find personlige rekorder som [uid] satte i sit seneste afsluttede spil.
  ///
  /// Rekorderne er VARIANT-SCOPEDE: sidste spils tal sammenlignes med
  /// byVariant-aggregatet for netop det spils variant — aldrig med det samlede
  /// aggregat (dér ville en variant med langsommere spil være rekord-umulig).
  /// Mangler byVariant-nøglen, men brugeren HAR spil i cachen, er cachen bare
  /// ikke variant-opdelt endnu (genberegning mangler) → vis INGEN rekorder
  /// frem for falske. Returnerer tom liste ved manglende data.
  /// [labelFor] kan opløse custom-varianters mærke (fx via config-doc'ets
  /// variants-map i UI-laget); uden den vises id'et — ærligt, aldrig
  /// 'Klassisk' om en custom.
  Future<List<GameRecord>> lastGameRecordsFor(String uid,
      {String Function(String variantId)? labelFor}) async {
    final last = await lastGameStatsFor(uid);
    if (last == null) return const <GameRecord>[];
    final doc = await getDoc(uid);
    if (doc == null) return const <GameRecord>[];
    final UserStats? aggregate = recordAggregateFor(doc, last.variantId);
    if (aggregate == null) return const <GameRecord>[];
    return recordsFromLastGame(
      aggregate: aggregate,
      lastGame: last.stats,
      variantLabel: labelFor != null
          ? labelFor(last.variantId)
          : variantForState(last.variantId).shortLabel,
    );
  }

  /// Ren beslutning: hvilket aggregat måles sidste spils rekorder mod?
  ///
  /// - byVariant har spillets variant → dét aggregat (variant-scoped rekord).
  /// - Nøglen mangler, men brugeren HAR spil i cachen → null = vis INGEN
  ///   rekorder: cachen er bare ikke variant-opdelt endnu (genberegning
  ///   mangler). Fald ALDRIG tilbage til top-niveau-aggregatet — så ville en
  ///   variant med langsommere spil være rekord-umulig, præcis den fejl
  ///   variant-scopingen fjerner.
  /// - Helt tom cache (0 spil) → tomt aggregat = førstegangs-logik.
  static UserStats? recordAggregateFor(UserStatsDoc doc, String variantId) {
    final UserStats? scoped = doc.byVariant[variantId];
    if (scoped != null) return scoped;
    if (doc.total.gamesPlayed > 0) return null;
    return UserStats(uid: doc.total.uid, displayName: doc.total.displayName);
  }

  /// Rekorder for ÉT bestemt spil ([code]) — målt som de så ud DENGANG.
  ///
  /// Aggregatet bygges kun af de spil der var afsluttet på det tidspunkt
  /// (inklusive spillet selv, præcis som live-stien hvor cachen allerede er
  /// genberegnet med det nye spil). Ellers ville en gammel slutrapport
  /// påstå "ny rekord" ud fra tal, der først kom senere — eller tie om en
  /// rekord, der faktisk blev sat dengang.
  ///
  /// Koster samme ENE forespørgsel som en almindelig genberegning: alle
  /// brugerens spil er allerede hentet.
  Future<GameReport> recordsForGame(String uid, String code,
      {String Function(String variantId)? labelFor}) async {
    final List<Map<String, dynamic>> games = await _ownFinishedGames(uid);
    final Map<String, dynamic>? game = gameWithCode(games, code);
    if (game == null) return const GameReport();
    final String vid = variantIdOfGameDoc(game);
    // Kortregnskabets anker kommer ud af DE SAMME spil, der lige er hentet —
    // ikke af et ekstra getDoc på userStats-cachen (QC-fund). Det sparer en
    // læsning, og det fjerner en staleness-risiko: cachen kan være ældre end
    // spillene, de rå spil kan ikke.
    final UserStats? anchor =
        computePartitionedStats(games).byVariant[vid]?[uid];
    final PartitionedStats then =
        computePartitionedStats(gamesUpTo(games, code));
    final UserStats? aggregate = then.byVariant[vid]?[uid];
    final UserStats? lastGame =
        computeAllStats(<Map<String, dynamic>>[game])[uid];
    if (aggregate == null || lastGame == null) {
      return GameReport(anchor: anchor);
    }
    return GameReport(
      records: recordsFromLastGame(
        aggregate: aggregate,
        lastGame: lastGame,
        variantLabel:
            labelFor != null ? labelFor(vid) : variantForState(vid).shortLabel,
      ),
      anchor: anchor,
    );
  }
}

/// Alt slutrapporten skal bruge om ét spil, ud af ÉN hentning: rekorderne som
/// de så ud DENGANG, og langtids-ankeret kortregnskabet måles MOD.
///
/// De to bruger bevidst forskellige udsnit af de samme spil: rekorderne må kun
/// se spil til og med dette (ellers viser en gammel rapport et senere partis
/// rekord), mens ankeret skal se ALT — spørgsmålet "var det her normalt for
/// os?" besvares bedst af alt hvad man har spillet.
class GameReport {
  const GameReport({this.records = const <GameRecord>[], this.anchor});
  final List<GameRecord> records;
  final UserStats? anchor;
}
