import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/ai/ai_player.dart';
import '../game/ai/heuristic_ai.dart';
import '../game/card_rules.dart';
import '../game/deck.dart';
import '../game/game_engine.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import '../models/variant_config.dart';
import 'friends_service.dart';
import 'serialize.dart';

/// Navnet på Firestore-databasen i projekt partners-8d4aa.
/// (Standardværdien er "(default)" — vores database er oprettet med navn
/// "partners", så vi targeter den eksplicit).
const String firestoreDatabaseId = 'partners';

/// Fælles Firestore-instans der targeter den navngivne database.
FirebaseFirestore get firestore =>
    FirebaseFirestore.instanceFor(
        app: Firebase.app(), databaseId: firestoreDatabaseId);

/// Email-adresser der har admin-rettigheder (kan ændre kortregler).
const Set<String> kAdminEmails = <String>{
  'cvejleaa@gmail.com',
};

bool isAdmin(User? user) {
  final email = user?.email?.toLowerCase();
  return email != null && kAdminEmails.contains(email);
}

final onlineServiceProvider = Provider<OnlineService>((ref) => OnlineService());

/// Strøm der følger den aktuelle loginstatus.
final authStateProvider = StreamProvider<User?>(
    (ref) => ref.read(onlineServiceProvider).authChanges());

/// Den aktuelle brugers profil (navn + avatar). Genberegnes når login skifter,
/// så et logout/skift ikke efterlader en gammel profil-strøm.
final myProfileProvider =
    StreamProvider<({String displayName, String? avatar})>((ref) {
  ref.watch(authStateProvider);
  return ref.read(onlineServiceProvider).myProfileStream();
});

/// Live-stream af ét online-spil.
final gameStreamProvider = StreamProvider.family<
    DocumentSnapshot<Map<String, dynamic>>, String>(
  (ref, code) => ref.read(onlineServiceProvider).watch(code),
);

/// Live-stream af presence-stempler for et online-spil: uid → millisekunder
/// (epoch) for seneste heartbeat.
///
/// Presence ligger i subcollection `games/{code}/presence/{uid}`, IKKE i selve
/// spil-dokumentet. Derfor trigger de hyppige heartbeats (hver ~7s pr. spiller)
/// hverken `onGameTurn` (Cloud Function på `games/{code}`) eller et snapshot på
/// [gameStreamProvider] — kun denne lette, separate stream opdateres.
final presenceStreamProvider =
    StreamProvider.family<Map<String, int>, String>(
  (ref, code) => ref.read(onlineServiceProvider).presenceStream(code),
);

/// Spil jeg er inviteret til eller deltager i (lobby/igangværende).
///
/// Bygges oven på [authStateProvider], så forespørgslen FØRST abonneres når
/// login er bekræftet (og auth-token'et er koblet på Firestore). Ellers kunne
/// et abonnement, der startede før token'et var propageret, få et forbigående
/// `permission-denied` ved allerførste snapshot — det var årsagen til
/// "Missing or insufficient permissions" lige efter login.
final myGamesProvider = StreamProvider<List<GameSummary>>((ref) {
  final User? user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return Stream<List<GameSummary>>.value(const <GameSummary>[]);
  }
  return ref.read(onlineServiceProvider).myGamesFor(user.uid);
});

/// Vandt sædet [mySeat] for hold [winningTeamIndex]? Ren funktion — makkerne
/// sidder diagonalt (plads 0+2 = hold 0, plads 1+3 = hold 1). Null når det
/// ikke kan afgøres.
bool? didIWin(int mySeat, int? winningTeamIndex) {
  if (winningTeamIndex == null || mySeat < 0) return null;
  return mySeat % 2 == winningTeamIndex;
}

/// Arkivet: de afsluttede ONLINE-spil, nyeste først.
///
/// Solospil mod computeren (isAi) holdes UDE — de gemmes også i
/// games-collectionen, og de er i flertal, så de ville skubbe de rigtige
/// partier ud af listen. De ses i profilen i stedet.
/// [limit] er et VISNINGS-loft; null = alle (når brugeren folder ud).
List<GameSummary> archiveOf(List<GameSummary> all, {int? limit}) {
  final List<GameSummary> out = all
      .where((GameSummary g) => g.isOver && !g.isAi)
      .toList()
    ..sort((GameSummary a, GameSummary b) =>
        (b.finishedAtMs ?? 0).compareTo(a.finishedAtMs ?? 0));
  if (limit == null || out.length <= limit) return out;
  return out.sublist(0, limit);
}

class GameSummary {
  GameSummary(this.code, this.hostName, this.status, this.playerNames,
      {this.hostUid,
      this.phase,
      this.currentName,
      this.isMyTurn = false,
      this.needsExchange = false,
      this.variantId = 'classic',
      this.variantLabel = '',
      this.variant = classicVariant,
      this.finishedAtMs,
      this.winningTeamIndex,
      this.mySeat = -1,
      this.unseen = false,
      this.isAi = false});
  final String code;
  final String hostName;
  final String status;
  final List<String> playerNames;
  final String? hostUid;

  /// Variant-identitet til "Mine spil"-badgen (kende forskel i LISTEN — det
  /// eneste sted man ser flere spil samtidig). [variantLabel] er det RESOLVEDE
  /// navn (admins evt. eget navn fra doc'ets cardRulesVariants-kopi).
  final String variantId;
  final String variantLabel;

  /// Den MATERIALISEREDE variant (navn/tema fra doc'ets cardRulesVariants-
  /// kopi) — badgen i listen skal vise custom-varianters farve/mærke uden
  /// registry-opslag.
  final VariantConfig variant;

  /// Spil-fase for igangværende spil ('play', 'exchange', …). Null = ukendt.
  final String? phase;

  /// Navnet på den spiller hvis tur det er (i play-fasen). Null hvis ukendt.
  final String? currentName;

  /// True hvis det er DENNE brugers tur netop nu (kun i play-fasen).
  final bool isMyTurn;

  /// True hvis spillet er i byttefasen OG brugeren endnu ikke har afgivet sit
  /// bytte-kort (dvs. brugeren skal handle).
  final bool needsExchange;

  /// Hvornår spillet sluttede (epoch-ms). Null for spil der ikke er slut.
  final int? finishedAtMs;

  /// Vinderholdet (0/1) for et afsluttet spil; null hvis ukendt.
  final int? winningTeamIndex;

  /// Min plads i spillet (-1 hvis jeg ikke sad med).
  final int mySeat;

  /// Sluttede spillet uden at jeg så det? (færre sete log-indlæg end der er).
  /// Bruges til at vise "Ny slutrapport" i stedet for at SPOILE udfaldet.
  final bool unseen;

  /// Solospil mod computeren (mode:'ai'). De gemmes også i games-collectionen,
  /// men hører hjemme i profilen — ikke i online-arkivet.
  final bool isAi;

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
  bool get isOver => status == 'over';

  /// Vandt jeg? Null når det ikke kan afgøres (ukendt vinder eller jeg sad
  /// ikke med). Makkerne sidder diagonalt: plads 0+2 mod 1+3.
  bool? get iWon => didIWin(mySeat, winningTeamIndex);
}

/// Hvor længe der maks. må gå uden handling/heartbeat fra en spiller, før en
/// AI overtager dennes tur. Holdes konfigurerbar ét sted.
///
/// Gælder KUN spil med mindst én AI-plads. I et spil med 4 rigtige spillere
/// er der ingen timeout overhovedet — der ventes på spilleren uanset hvor
/// længe de er væk (håndhævet både i _maybeHostAct og i aiTakeoverMove).
const Duration kAiTakeoverTimeout = Duration(seconds: 35);

/// Hvor ofte en aktiv klient opdaterer sit "presence"-stempel. Holdes lavere
/// end push-væk-grænsen (AWAY_MS i functions), så en aktiv spiller aldrig ser
/// "væk" ud og fejlagtigt får en tur-notifikation.
const Duration kPresenceInterval = Duration(seconds: 7);

/// Heuristisk AI til at drive computer-pladser fra værtens enhed.
final HeuristicAi onlineAi = HeuristicAi();

class OnlineService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  FirebaseFirestore get _db => firestore;

  CollectionReference<Map<String, dynamic>> get _games => _db.collection('games');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  Stream<User?> authChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  // -------------------------------------------------------------------------
  // Auth + profil
  // -------------------------------------------------------------------------

  Future<void> signUp(String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    final user = cred.user!;
    try {
      await user.updateDisplayName(displayName.trim());
      await _writeProfile(user.uid,
          displayName: displayName.trim(), email: email.trim());
      // Sørg for at de søgbare felter også er sat på den nye bruger.
      try {
        await FriendsService().ensureUserDoc();
      } catch (_) {}
    } catch (e) {
      // Profilen kunne ikke skrives — slet auth-brugeren igen, så samme
      // email kan bruges til at prøve igen (i stedet for at sidde fast i
      // "email already in use" uden profil).
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    // Backfill profil hvis den mangler (fx hvis en tidligere signup fejlede
    // efter Auth blev oprettet, eller hvis brugeren blev oprettet i konsollen).
    await _ensureProfile(cred.user!);
  }

  Future<UserCredential> signInWithGoogleViaPopup() async {
    final provider = GoogleAuthProvider();
    final cred = await _auth.signInWithPopup(provider);
    await _ensureProfile(cred.user!);
    return cred;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> _ensureProfile(User user) async {
    final doc = await _users.doc(user.uid).get();
    if (!doc.exists) {
      final email = user.email ?? '';
      final name = (user.displayName ?? '').isNotEmpty
          ? user.displayName!
          : (email.isNotEmpty ? email.split('@').first : 'Spiller');
      await _writeProfile(user.uid, displayName: name, email: email);
    }
    // Sørg også for at de søgbare felter (email, displayNameLower osv.) er
    // friske, så venne-søgning kan finde brugeren. Fejler stille.
    try {
      await FriendsService().ensureUserDoc();
    } catch (_) {
      // Ignorér — login må ikke fejle pga. dette skriv.
    }
  }

  Future<void> _writeProfile(String uid,
      {required String displayName, required String email}) async {
    await _users.doc(uid).set(<String, dynamic>{
      'displayName': displayName,
      'displayNameLower': displayName.toLowerCase(),
      'email': email,
      'emailLower': email.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Opdater brugerens visningsnavn og/eller avatar. Skriver til user-doc'et
  /// (kun ejeren må, jf. Firestore-reglerne) og synkroniserer Auth-displayName
  /// så navnet også slår igennem hvor vi læser fra Auth.
  Future<void> updateProfile({String? displayName, String? avatar}) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final Map<String, dynamic> data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final String? name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      data['displayName'] = name;
      data['displayNameLower'] = name.toLowerCase();
      await u.updateDisplayName(name);
    }
    if (avatar != null) data['avatar'] = avatar;
    await _users.doc(u.uid).set(data, SetOptions(merge: true));
  }

  /// Live-stream af den aktuelle brugers profil (navn + avatar).
  Stream<({String displayName, String? avatar})> myProfileStream() {
    final u = _auth.currentUser;
    if (u == null) {
      return Stream<({String displayName, String? avatar})>.value(
          (displayName: 'Spiller', avatar: null));
    }
    return _users.doc(u.uid).snapshots().map((s) {
      final d = s.data() ?? const <String, dynamic>{};
      final name = (d['displayName'] as String?) ??
          (u.displayName ?? '').trim();
      return (
        displayName: name.isEmpty ? 'Spiller' : name,
        avatar: d['avatar'] as String?,
      );
    });
  }

  Future<String> myDisplayName() async {
    final u = _auth.currentUser;
    if (u == null) return 'Spiller';
    if ((u.displayName ?? '').isNotEmpty) return u.displayName!;
    final doc = await _users.doc(u.uid).get();
    return (doc.data()?['displayName'] as String?) ?? 'Spiller';
  }

  Future<String?> myAvatar() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    final doc = await _users.doc(u.uid).get();
    return doc.data()?['avatar'] as String?;
  }

  /// Slå en oprettet spiller op via email. Returnerer {uid, displayName}.
  Future<Map<String, String>?> findUserByEmail(String email) async {
    final q = await _users
        .where('emailLower', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final d = q.docs.first;
    return <String, String>{
      'uid': d.id,
      'displayName': (d.data()['displayName'] as String?) ?? 'Spiller',
    };
  }

  // -------------------------------------------------------------------------
  // Spil: opret / invitér / join / start
  // -------------------------------------------------------------------------

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Standard-paletten (rød, blå, grøn, gul).
  static const List<int> kPalette = <int>[
    0xFFE53935,
    0xFF1E88E5,
    0xFF43A047,
    0xFFFDD835,
  ];

  /// Farverne på de fire pladser, med værtens [hostColor] på plads 0.
  ///
  /// Rækkefølgen er en ROTATION af paletten — aldrig en indsættelse. Makkerne
  /// sidder diagonalt (plads 0+2 og 1+3), og kun en rotation bevarer de par,
  /// spillerne kender fra bordet: rød+grøn og blå+gul. Skubbede man i stedet
  /// værtens farve forrest og fyldte resten på i palet-rækkefølge (som før),
  /// fik en vært med blå pladserne [blå, rød, grøn, gul] → makkerne blev
  /// blå+grøn og rød+gul. Det sker i praksis ved REVANCHE, hvor værten
  /// beholder sin farve fra forrige parti.
  ///
  /// Er [hostColor] ikke en af paletten (fx en fremtidig fri farvevælger),
  /// overtager den plads 0's rolle, og de tre øvrige følger paletten — så det
  /// andet par (blå+gul) stadig holder sammen. Resultatet er altid fire
  /// FORSKELLIGE farver (en vært med blå gav før to blå ved revanche).
  static List<int> seatColors(int hostColor) {
    final int i = kPalette.indexOf(hostColor);
    if (i < 0) {
      return <int>[hostColor, kPalette[1], kPalette[2], kPalette[3]];
    }
    return <int>[for (int k = 0; k < 4; k++) kPalette[(i + k) % 4]];
  }

  Future<String> createGame({
    required int colorValue,
    required CardRules rules,
    int aiLevel = kAiLevelDefault,
  }) async {
    final uid = _auth.currentUser!.uid;
    final name = await myDisplayName();
    final code = _genCode();
    // Læs den autoritative kort-konfiguration direkte fra Firestore i stedet
    // for at stole på den lokale [cardRulesProvider]. Provideren starter med
    // defaults og loader async, så hvis værten opretter et spil før loaden er
    // færdig, ville defaults blive gemt i spil-dokumentet — bug rapporteret
    // hvor en 8 ikke kunne rykke ud og en 7 ikke kunne deles selv om admin-
    // konfigurationen tilsagde det modsatte. Det globale doc i config/
    // cardRules er kilden til sandheden; vi falder tilbage til [rules] hvis
    // doc'et ikke findes eller fejler.
    CardRules effective = rules;
    // Admins variant-regler (variants-mappet) kopieres MED over i lobby-doc'et,
    // så startGameFromLobby kan opløse variantens kort af doc'et alene — også
    // hvis værten skifter variant i lobbyen efter oprettelsen. Fejler read'et,
    // skrives feltet ikke, og starten falder til variantens kode-seed (fx
    // Hopsakortet) — acceptabelt og navngivet.
    Map<String, dynamic>? variantsRaw;
    try {
      final snap = await firestore.collection('config').doc('cardRules').get();
      final data = snap.data();
      final remote = data?['rules'];
      if (remote is Map) {
        effective = CardRules.fromJson(Map<String, dynamic>.from(remote));
      }
      final vr = data?['variants'];
      if (vr is Map) {
        variantsRaw = Map<String, dynamic>.from(vr);
      }
    } catch (_) {
      // Tabt netværk / regel-fejl: behold værtens lokale rules som fallback.
    }
    await _games.doc(code).set(<String, dynamic>{
      'status': 'lobby',
      'hostUid': uid,
      'hostName': name,
      'names': <String>[name, 'Åben', 'Åben', 'Åben'],
      // Pladsernes farver: en ROTATION af paletten med værtens farve på
      // plads 0 — se seatColors (den bevarer makkerparrene rød+grøn og
      // blå+gul, som en indsættelse brød ved revanche).
      'colors': seatColors(colorValue),
      'uids': <String?>[uid, null, null, null],
      // Pladser markeret som AI fra lobbyen (true = computer-spiller).
      'aiSeats': <bool>[false, false, false, false],
      'invitedUids': <String>[],
      'members': <String>[uid],
      // Klar-markering pr. uid i lobbyen (vært tæller altid som klar).
      'ready': <String, dynamic>{uid: true},
      // Presence (heartbeat) ligger nu i subcollection games/{code}/presence,
      // ikke i selve doc'et — se heartbeat(). Værtens første stempel skrives af
      // lobby-skærmens heartbeat ved åbning.
      'cardRules': effective.toJson(),
      // Admins variant-regler/tekster (kopi af config-doc'ets variants-map),
      // så variantens kort kan opløses offline ved start. Udeladt hvis
      // config-read'et fejlede — så gælder kode-seedet.
      if (variantsRaw != null) 'cardRulesVariants': variantsRaw,
      // Valgt variant (default klassisk). Værten kan ændre den i lobbyen via
      // setVariant; startGameFromLobby resolver den defensivt (ukendt → klassisk).
      'variantId': classicVariant.id,
      // Spillerens valgte AI-sværhedsgrad (0=Begynder,1=Normal,2=Skarp).
      // Parametrene bag graderne sættes af admin (config/ai).
      'aiLevel': aiLevel,
      'seq': 0,
      'log': <dynamic>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  Future<void> invite(String code, String invitedUid) async {
    await _games.doc(code).update(<String, dynamic>{
      'invitedUids': FieldValue.arrayUnion(<String>[invitedUid]),
      'members': FieldValue.arrayUnion(<String>[invitedUid]),
    });
  }

  /// Revanche: opret et NYT spil med de samme menneskelige deltagere som
  /// [oldCode]. Kalderen (mig) bliver vært; de andre menneskelige spillere
  /// inviteres (så de får det i deres "Mine spil" + evt. push). Returnerer
  /// den nye spil-kode. AI-pladser genskabes ikke — de fyldes fra lobbyen.
  Future<String> createRematch(String oldCode) async {
    final me = _auth.currentUser;
    if (me == null) throw 'Du er ikke logget ind';
    final old = await _games.doc(oldCode).get();
    final d = old.data() ?? const <String, dynamic>{};
    final oldUids = (d['uids'] as List?)?.cast<dynamic>() ?? const <dynamic>[];
    final oldColors =
        (d['colors'] as List?)?.map((e) => (e as num).toInt()).toList() ??
            <int>[0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFDD835];
    final rulesMap = d['cardRules'];
    final rules = rulesMap is Map
        ? CardRules.fromJson(Map<String, dynamic>.from(rulesMap))
        : CardRules.defaults();

    // Min farve fra det gamle spil (fallback: første i paletten).
    int myColor = oldColors.isNotEmpty ? oldColors.first : 0xFFE53935;
    for (int i = 0; i < oldUids.length; i++) {
      if (oldUids[i] == me.uid && i < oldColors.length) myColor = oldColors[i];
    }

    final int oldAiLevel = (d['aiLevel'] as num?)?.toInt() ?? kAiLevelDefault;
    final code = await createGame(
        colorValue: myColor, rules: rules, aiLevel: oldAiLevel);

    // Bevar variant fra det gamle spil (en revanche af et 25 år-spil er 25
    // år; en custom forbliver den custom). Entryen tages med fra det GAMLE
    // docs kopi, så revanchen også virker for en variant der siden er
    // arkiveret/ændret. Skævt felt → klassisk.
    final String? oldVid =
        d['variantId'] is String ? d['variantId'] as String : null;
    if (oldVid != null && oldVid != classicVariant.id) {
      try {
        final dynamic oldCopy = d['cardRulesVariants'];
        final dynamic oldEntry = oldCopy is Map ? oldCopy[oldVid] : null;
        await setVariant(code, oldVid,
            entry: oldEntry is Map
                ? Map<String, dynamic>.from(oldEntry)
                : null);
      } catch (_) {
        // En fejlet variant-kopiering må ikke forhindre revanchen (falder til
        // klassisk, som createGame allerede har sat).
      }
    }

    // Invitér de øvrige menneskelige spillere fra det gamle spil.
    final friends = FriendsService();
    for (final u in oldUids) {
      if (u == null || u == me.uid) continue;
      try {
        await invite(code, u as String);
        await friends.sendGameInvite(u, code);
      } catch (_) {
        // Én fejlet invitation må ikke forhindre revanchen.
      }
    }
    return code;
  }

  Future<void> joinGame({
    required String code,
    required int seat,
    required int colorValue,
  }) async {
    final uid = _auth.currentUser!.uid;
    final name = await myDisplayName();
    await _db.runTransaction((tx) async {
      final ref = _games.doc(code);
      final snap = await tx.get(ref);
      if (!snap.exists) throw 'Spillet findes ikke';
      final d = snap.data()!;
      final uids = List<dynamic>.from(d['uids'] as List);
      final names = List<dynamic>.from(d['names'] as List);
      final colors = List<dynamic>.from(d['colors'] as List);
      if (uids[seat] != null && uids[seat] != uid) throw 'Pladsen er taget';
      // Frigør en evt. plads brugeren allerede sad på (skift af plads).
      for (int i = 0; i < uids.length; i++) {
        if (uids[i] == uid && i != seat) {
          uids[i] = null;
          names[i] = 'Åben';
        }
      }
      uids[seat] = uid;
      names[seat] = name;
      colors[seat] = colorValue;
      // En menneskelig spiller på pladsen ophæver evt. AI-markering.
      final aiSeats = d['aiSeats'] is List
          ? List<dynamic>.from(d['aiSeats'] as List)
          : <dynamic>[false, false, false, false];
      if (seat < aiSeats.length) aiSeats[seat] = false;
      tx.update(ref, <String, dynamic>{
        'uids': uids,
        'names': names,
        'colors': colors,
        'aiSeats': aiSeats,
        'members': FieldValue.arrayUnion(<String>[uid]),
        'ready.$uid': false,
      });
    });
    // Skriv et presence-stempel med det samme (subcollection), så pladsen
    // straks ser "online" ud hos de andre — uden at røre spil-doc'et.
    await heartbeat(code);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String code) =>
      _games.doc(code).snapshots();

  /// Tving web-SDK'en til at droppe en (evt. død) forbindelse og genoprette den
  /// STRAKS. Efter appen har været i baggrunden (fx åbnet fra en notifikation)
  /// kan Firestores WebChannel være død, og SDK'en bruger ellers 30-60s på selv
  /// at opdage det — imens leverer lytterne kun den cachede (frosne) state. Et
  /// disable+enable-toggle river den døde forbindelse ned og henter frisk
  /// server-state igen med det samme. Fejler stille (offline er ikke kritisk).
  bool _reconnecting = false;
  Future<void> reconnect() async {
    // Reentrancy-værn: to overlappende disable/enable-par kunne i uheldig
    // rækkefølge efterlade instansen disabled. onlineServiceProvider er en
    // cachet single-instans, så dette flag er en effektiv lås.
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      await _db.disableNetwork();
      await _db.enableNetwork();
    } catch (_) {
    } finally {
      _reconnecting = false;
    }
  }

  /// Live-stream af presence for et spil (uid → ms). Læser subcollection
  /// `games/{code}/presence`. Se [presenceStreamProvider].
  Stream<Map<String, int>> presenceStream(String code) {
    return _games.doc(code).collection('presence').snapshots().map((snap) {
      final out = <String, int>{};
      for (final doc in snap.docs) {
        final ts = doc.data()['t'];
        if (ts is Timestamp) out[doc.id] = ts.millisecondsSinceEpoch;
      }
      return out;
    });
  }

  /// Byg en [GameSummary] ud fra spil-dokumentet, inkl. hvis tur det er (for
  /// igangværende spil) set fra [uid]'s perspektiv.
  /// Byg en [GameSummary] ud fra spil-dokumentet, inkl. hvis tur det er (for
  /// igangværende spil) set fra [uid]'s perspektiv. Selve udledningen ligger
  /// i den top-level [gameSummaryFromDoc], så den kan testes uden Firebase.
  GameSummary _summaryFromDoc(String id, Map<String, dynamic> d, String uid) =>
      gameSummaryFromDoc(id, d, uid);

  /// Firestore-tidsstempel (eller rå int) → epoch-ms. Samme klampning som
  /// stats-laget bruger; null når feltet mangler.


  /// Spil hvor [uid] er medlem. Kaldes med et bekræftet uid fra
  /// [myGamesProvider], der venter på login før abonnementet startes.
  ///
  /// Selv efter login kan Firestore i et kort øjeblik afvise det aller-første
  /// snapshot med `permission-denied`, hvis auth-token'et endnu ikke er
  /// propageret til lytteren. Da et fejlet snapshot-listen ellers terminerer
  /// strømmen (og fejlen bliver hængende på skærmen), prøver vi et par gange
  /// igen med kort pause, før en ægte fejl får lov at boble op.
  Stream<List<GameSummary>> myGamesFor(String uid) async* {
    int attempt = 0;
    while (true) {
      try {
        yield* _games
            .where('members', arrayContains: uid)
            .snapshots()
            // BEMÆRK: afsluttede spil filtreres IKKE længere fra — arkiv-
            // sektionen viser dem (archiveOf sorterer og afgrænser). Det
            // koster ingen ekstra læsninger: forespørgslen hentede dem
            // allerede, filteret smed dem bare væk.
            // NAVNGIVET GRÆNSE: forespørgslen er stadig ubundet (alle spil
            // man er medlem af). At binde den kræver et sammensat indeks
            // (status + finishedAt), og der findes ingen firestore.indexes.json
            // i repoet endnu — det er en selvstændig opgave.
            .map((q) => q.docs
                .map((d) => _summaryFromDoc(d.id, d.data(), uid))
                .toList());
        return; // snapshots() afsluttes normalt aldrig.
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' && attempt < 3) {
          attempt++;
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue; // forbigående lige efter login — abonnér igen.
        }
        rethrow;
      }
    }
  }

  Future<void> start(String code) => startGameFromLobby(code);

  /// Start spillet fra lobbyen. Tomme pladser (uden uid) bliver automatisk
  /// computer-spillere. Bagudkompatibel med eksisterende kald af [start].
  Future<void> startGameFromLobby(String code) async {
    final ref = _games.doc(code);
    final snap = await ref.get();
    final d = snap.data()!;
    if (d['status'] == 'playing' || d['status'] == 'over') {
      // Allerede startet — undgå at nulstille et igangværende spil.
      return;
    }
    final names = (d['names'] as List).map((e) => e as String).toList();
    final colors = (d['colors'] as List).map((e) => (e as num).toInt()).toList();
    final uids = d['uids'] as List;
    final rules =
        CardRules.fromJson(Map<String, dynamic>.from(d['cardRules'] as Map));
    // Materialisér varianten fra doc'ets EGEN cardRulesVariants-kopi
    // (variantFromRaw): en custom variant bevarer sit id ind i state (og
    // dermed 'vid' → statistik-attributionen) og får navn/tema med. Skævt
    // felt fra en fjendtlig deltager → klassisk; velformet-men-ukendt id →
    // klassisk-formet med id bevaret (spilbart, kun navn/farve mangler).
    final VariantConfig variant = variantFromRaw(
        d['variantId'] is String ? d['variantId'] as String : null,
        d['cardRulesVariants']);
    // Opløs spillets faktiske kortregler ÉN gang her: klassisk (doc'ets
    // cardRules) + variantens overrides (admin-gemte fra cardRulesVariants
    // vinder over kode-seedet; manglende/skævt felt → seed). _initialState
    // opløser ikke selv.
    final CardRules resolved = effectiveCardRules(
      variant,
      rules,
      stored: storedOverridesFor(d['cardRulesVariants'], variant.id),
    );
    final state = _initialState(names, colors, uids, resolved, variant);
    await ref.update(<String, dynamic>{
      'status': 'playing',
      'state': gameStateToMap(state),
      'startedAt': FieldValue.serverTimestamp(),
      'lastActionAt': Timestamp.now(),
    });
  }

  /// Marker (eller fjern) klar-status for den aktuelle bruger i lobbyen.
  Future<void> setReady(String code, bool ready) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _games.doc(code).update(<String, dynamic>{
      'ready.$uid': ready,
    });
    // Presence opdateres separat (subcollection), så klar-markering og
    // heartbeat ikke er koblet sammen.
    await heartbeat(code);
  }

  /// Sæt AI-sværhedsgraden for spillet (vælges i lobbyen). Gemmes i doc'et og
  /// bruges når værtens klient driver AI-pladser.
  Future<void> setAiLevel(String code, int level) async {
    await _games.doc(code).update(<String, dynamic>{
      'aiLevel': level.clamp(0, kDefaultAiLevels.length - 1),
    });
  }

  /// Sæt spillets variant fra lobbyen (kun værten i UI'et). Indbyggede id'er
  /// skrives direkte; en CUSTOM variant skal have sit [entry] (config-doc'ets
  /// variants.{id}-værdi) med, som samtidig kopieres ind i doc'ets
  /// cardRulesVariants — kopien blev taget ved OPRETTELSEN, så en variant
  /// skabt/valgt senere ville ellers mangle navn/tema/regler for gæsterne og
  /// for startGameFromLobby (QC-fund). Vanformet id, eller ukendt id uden
  /// entry, klampes til klassisk, så doc'et aldrig får en variant der ikke
  /// kan resolves. startGameFromLobby læser feltet defensivt.
  ///
  /// NAVNGIVET HUL: kopien opdateres kun her (ved variant-VALG). Redigerer
  /// admin kortreglerne for en variant, der ALLEREDE er valgt i en åben
  /// lobby, slår ændringen ikke igennem i dét spil, før værten genvælger
  /// varianten (eller lobbyen genoprettes) — samme snapshot-semantik som
  /// klassisk cardRules, der også kopieres ved oprettelsen.
  Future<void> setVariant(String code, String variantId,
      {Map<String, dynamic>? entry}) async {
    final bool builtin =
        kAllVariants.any((VariantConfig v) => v.id == variantId);
    if (!isWellFormedVariantId(variantId) || (!builtin && entry == null)) {
      await _games.doc(code).update(<String, dynamic>{
        'variantId': classicVariant.id,
      });
      return;
    }
    await _games.doc(code).update(<Object, Object?>{
      'variantId': variantId,
      if (entry != null)
        FieldPath(<String>['cardRulesVariants', variantId]): entry,
    });
  }

  /// Værten markerer en åben plads til at blive en AI-spiller (eller fortryder).
  Future<void> fillSeatWithAi(String code, int seat, {bool ai = true}) async {
    await _db.runTransaction((tx) async {
      final ref = _games.doc(code);
      final snap = await tx.get(ref);
      if (!snap.exists) throw 'Spillet findes ikke';
      final d = snap.data()!;
      final uids = List<dynamic>.from(d['uids'] as List);
      if (uids[seat] != null) throw 'Pladsen er taget af en spiller';
      final aiSeats = d['aiSeats'] is List
          ? List<dynamic>.from(d['aiSeats'] as List)
          : <dynamic>[false, false, false, false];
      while (aiSeats.length < 4) {
        aiSeats.add(false);
      }
      aiSeats[seat] = ai;
      final names = List<dynamic>.from(d['names'] as List);
      names[seat] = ai ? 'Computer' : 'Åben';
      tx.update(ref, <String, dynamic>{'aiSeats': aiSeats, 'names': names});
    });
  }

  /// Opdater brugerens tilstedeværelses-stempel (heartbeat). Fejler stille.
  ///
  /// Skriver til subcollection `games/{code}/presence/{uid}` — IKKE til selve
  /// spil-dokumentet. Så en heartbeat hver ~7s pr. spiller trigger hverken
  /// `onGameTurn` (Cloud Function på `games/{code}`) eller et snapshot på
  /// spil-state'en. Det var den største kilde til unødige Cloud Function-
  /// invocations og rebuilds (forbrugs-fund #4).
  Future<void> heartbeat(String code) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _games
          .doc(code)
          .collection('presence')
          .doc(uid)
          .set(<String, dynamic>{'t': Timestamp.now()});
    } catch (_) {}
  }

  /// Afgør om en menneskelig spiller på [seat] regnes som "væk" ud fra
  /// [presenceMs] (uid → ms, fra [presenceStream]). En spiller er væk hvis:
  ///  - der ikke er noget presence-stempel (aldrig set / lige koblet af), ELLER
  ///  - seneste presence er ældre end [kAiTakeoverTimeout].
  /// Bruges sammen med tids-siden-sidste-handling i UI-laget.
  static bool seatIsAway(List<dynamic> uids, Map<String, int> presenceMs,
      int seat) {
    if (seat >= uids.length) return false;
    final uid = uids[seat];
    if (uid == null) return true; // tom plads = AI
    final ms = presenceMs[uid];
    if (ms == null) return true;
    return DateTime.now().millisecondsSinceEpoch - ms >
        kAiTakeoverTimeout.inMilliseconds;
  }

  /// Hjælper til UI: tid siden sidste handling i spillet (eller null).
  static Duration? timeSinceLastAction(Map<String, dynamic> d) {
    final ts = d['lastActionAt'];
    if (ts is! Timestamp) return null;
    return DateTime.now().difference(ts.toDate());
  }

  GameState _initialState(List<String> names, List<int> colors, List uids,
      CardRules rules, VariantConfig variant) {
    // NB: online-lobbyen er 4-sædet (names/colors/uids/aiSeats er 4-lange), så
    // spiller-loopet og start-spilleren er hardkodet til 4. Brik-antal og
    // geometri tages fra varianten. Klassisk og p25 er begge 4-spiller; en
    // variant med playerCount≠4 (fx Partners+ 6) kan derfor endnu ikke oprettes
    // online — det kræver en N-sædet lobby (fase 4).
    final players = <Player>[
      for (int i = 0; i < 4; i++)
        Player(
          index: i,
          name: uids[i] != null ? names[i] : 'AI ${i + 1}',
          color: Color(colors[i]),
          isHuman: uids[i] != null,
          pieces: <Piece>[
            for (int s = 0; s < variant.piecesPerPlayer; s++)
              Piece(id: 'p$i.$s', ownerIndex: i, position: StartPosition(i, s)),
          ],
        ),
    ];
    // Tilfældig start-spiller — ikke altid værten (plads 0/den der inviterede).
    final int starter = Random().nextInt(4);
    // [rules] er de FÆRDIGT opløste kortregler (startGameFromLobby har kørt
    // effectiveCardRules). Der opløses BEVIDST ikke igen her — én resolver, ét
    // sted, ellers genanvendes kode-seedet tavst oven på admins gemte valg.
    final s = GameState(
      players: players,
      geometry: variant.geometry,
      deck: Deck.fresh(),
      discard: <PlayingCard>[],
      dealerIndex: starter,
      currentPlayerIndex: starter,
      phase: GamePhase.setup,
      handNumber: 0,
      starterIndex: starter,
      cardRules: rules,
      variant: variant,
    );
    GameEngine(state: s).startNewHand();
    return s;
  }

  /// Marker at den aktuelle bruger har set indlæg op til (eksklusivt) [count].
  Future<void> markSeen(String code, int count) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _games.doc(code).update(<String, dynamic>{
      'seen.$uid': count,
    });
  }

  /// Slet et spil-dokument helt. Tilladt for værten eller en admin — Firestore-
  /// reglerne tjekker det. UI-laget viser kun knappen for relevante brugere.
  Future<void> deleteGame(String code) async {
    await _games.doc(code).delete();
  }

  /// Kør en handling på spillet i en transaktion (sikker mod samtidige skriv).
  Future<void> mutate(
    String code,
    void Function(GameEngine engine, GameState state) action, {
    Map<String, dynamic>? logEntry,
  }) async {
    await _db.runTransaction((tx) async {
      final ref = _games.doc(code);
      final snap = await tx.get(ref);
      final d = snap.data()!;
      final state =
          gameStateFromMap(Map<String, dynamic>.from(d['state'] as Map));
      final wasOver = state.winningTeamIndex != null;
      final engine = GameEngine(state: state);
      action(engine, state);
      final upd = <String, dynamic>{
        'state': gameStateToMap(state),
        // Nulstil inaktivitets-timeren: der er netop sket en handling.
        'lastActionAt': Timestamp.now(),
      };
      if (state.winningTeamIndex != null) {
        upd['status'] = 'over';
        if (!wasOver) {
          upd['finishedAt'] = FieldValue.serverTimestamp();
          upd['winningTeamIndex'] = state.winningTeamIndex;
        }
      }
      if (logEntry != null) {
        // Tilføj klient-side timestamp (server-timestamp virker ikke inde i
        // array-elementer — vi accepterer mindre clock-skew for stats-formål).
        final entry = Map<String, dynamic>.from(logEntry);
        // Undgå dublet: skriv IKKE et træk der er identisk med det seneste i
        // log'en (kan ske hvis samme handling skrives to gange). Da hvert
        // element har et unikt timestamp, ville arrayUnion ellers ikke fange
        // dubletten — så det tjekker vi selv mod den friske log.
        final List log = (d['log'] as List?) ?? const <dynamic>[];
        if (!isRecentDuplicateMove(log, entry)) {
          entry['t'] = Timestamp.now();
          upd['log'] = FieldValue.arrayUnion(<dynamic>[entry]);
        }
      }
      tx.update(ref, upd);
    });
  }

  /// Lad en AI tage trækket for [seat] (en fraværende spiller). Hele
  /// beslutningen sker INDE i transaktionen ud fra den friske state, og der
  /// skrives KUN hvis det stadig er [seat]'s tur i play-fasen. Det betyder:
  ///  - intet bogus log-indlæg hvis spilleren selv nåede at handle, og
  ///  - sikker mod at to klienter skriver samme træk (transaktionen aborterer
  ///    for taberen ved samtidig skrivning).
  /// Returnerer true hvis et træk faktisk blev udført.
  Future<bool> aiTakeoverMove(String code, int seat,
      {AiParams params = kAiNormal}) async {
    return _aiSeatMoveInternal(code, seat, asTakeover: true, params: params);
  }

  /// Lad en AI tage trækket for en almindelig AI-plads. Lige som
  /// [aiTakeoverMove] foretages beslutningen INDE i transaktionen ud fra
  /// frisk state — så vi undgår den klassiske "stale move"-fejl hvor AI'en
  /// vælger et træk på baggrund af en gammel snapshot, og applyMoves
  /// runtime-guard afviser det fordi friske state har bevæget sig videre.
  Future<bool> aiSeatMove(String code, int seat,
      {AiParams params = kAiNormal}) async {
    return _aiSeatMoveInternal(code, seat, asTakeover: false, params: params);
  }

  Future<bool> _aiSeatMoveInternal(String code, int seat,
      {required bool asTakeover, AiParams params = kAiNormal}) async {
    bool acted = false;
    await _db.runTransaction((tx) async {
      acted = false;
      final ref = _games.doc(code);
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null || d['state'] == null) return;
      final state =
          gameStateFromMap(Map<String, dynamic>.from(d['state'] as Map));
      if (state.winningTeamIndex != null) return;
      if (state.phase != GamePhase.play) return;
      if (state.currentPlayerIndex != seat) return;
      // AI-OVERTAGELSE af et menneske er kun tilladt i spil med mindst én
      // AI-plads. I et spil med 4 rigtige spillere er der ingen timeout —
      // værnet ligger her i transaktionen (ud over UI-tjekket), så selv en
      // gammel/stale klient ikke kan udløse en overtagelse.
      if (asTakeover && state.players.every((p) => p.isHuman)) return;

      final wasOver = state.winningTeamIndex != null;
      final engine = GameEngine(state: state);
      final Move? m = onlineAi.chooseMove(state, seat, params: params);
      final int discardedCount = state.players[seat].hand.length;
      final Map<String, dynamic> logEntry;
      if (m != null) {
        engine.applyMove(seat, m);
        logEntry = moveLogEntry(seat, m);
      } else {
        engine.passHand(seat);
        logEntry = passLogEntry(seat, discardedCount);
      }
      final upd = <String, dynamic>{
        'state': gameStateToMap(state),
        'lastActionAt': Timestamp.now(),
      };
      if (state.winningTeamIndex != null && !wasOver) {
        upd['status'] = 'over';
        upd['finishedAt'] = FieldValue.serverTimestamp();
        upd['winningTeamIndex'] = state.winningTeamIndex;
      }
      final entry = Map<String, dynamic>.from(logEntry);
      if (asTakeover) {
        // Marker at trækket blev lavet af AI på vegne af en fraværende spiller.
        entry['ai'] = true;
      }
      // Samme dublet-værn som i mutate: skriv ikke et træk identisk med det
      // seneste i log'en.
      final List log = (d['log'] as List?) ?? const <dynamic>[];
      if (!isRecentDuplicateMove(log, entry)) {
        entry['t'] = Timestamp.now();
        upd['log'] = FieldValue.arrayUnion(<dynamic>[entry]);
      }
      tx.update(ref, upd);
      acted = true;
    });
    return acted;
  }
}

Map<String, dynamic> moveLogEntry(int seat, Move move) => <String, dynamic>{
      'player': seat,
      'type': 'move',
      'card': cardToMap(move.card),
      'steps': move.steps
          .map((s) => <String, dynamic>{
                'pieceId': s.pieceId,
                'from': posToMap(s.from),
                'to': posToMap(s.to),
                // Kun skrevet når steppet slår/brænder — så "mens du var
                // væk"-replayen kan fortælle modstanderen HVAD der skete
                // (fx +2−5's to hjemslag). Gamle entries uden feltet læses
                // som "intet slag" (bagud-kompat).
                if (s.capturedPieceId != null) 'cap': true,
                if (s.burnsMover) 'burn': true,
              })
          .toList(),
    };

/// Log-entry for når en spiller smider hånden og sidder over runden.
Map<String, dynamic> passLogEntry(int seat, int cardsDiscarded) =>
    <String, dynamic>{
      'player': seat,
      'type': 'pass',
      'cardsDiscarded': cardsDiscarded,
    };

/// Log-entry for kortbytte mellem partnere ved rundens start.
Map<String, dynamic> exchangeLogEntry(int seat, PlayingCard givenCard) =>
    <String, dynamic>{
      'player': seat,
      'type': 'exchange',
      'card': cardToMap(givenCard),
    };

/// Udled en [GameSummary] af et RÅ spil-dokument — top-level, og dermed
/// testbar uden Firebase.
///
/// Her ligger de afledninger, arkivet hviler på: hvem vandt (state'ns 'wt' er
/// autoritet, topniveau-feltet er fallback for ældre docs), hvornår spillet
/// sluttede, og om JEG har set slutningen. De sad før på en privat metode i
/// en klasse, der ikke kan konstrueres i et testmiljø — og var derfor helt
/// udækkede.
GameSummary gameSummaryFromDoc(
    String id, Map<String, dynamic> d, String uid) {
    final List<String> names =
        (d['names'] as List? ?? const <dynamic>[]).map((e) => '$e').toList();
    final String status = d['status'] as String? ?? 'lobby';

    String? phase;
    String? currentName;
    bool isMyTurn = false;
    bool needsExchange = false;
    final state = d['state'];
    if (status == 'playing' && state is Map) {
      phase = state['ph'] as String?;
      final uids = d['uids'] as List?;
      if (phase == 'play') {
        // Kun i play-fasen er currentPlayerIndex en rigtig "tur".
        final int? cp = (state['cp'] as num?)?.toInt();
        if (cp != null) {
          if (cp >= 0 && cp < names.length) currentName = names[cp];
          if (uids != null && cp >= 0 && cp < uids.length) {
            isMyTurn = uids[cp] == uid;
          }
        }
      } else if (phase == 'exchange') {
        // I byttefasen skal brugeren handle hvis de endnu ikke har afgivet et
        // kort (samme signal som spillet selv: exchangeBuffer[seat]).
        final int mySeat = uids?.indexOf(uid) ?? -1;
        final eb = state['eb'];
        if (mySeat >= 0) {
          needsExchange = !(eb is Map && eb.containsKey('$mySeat'));
        }
      }
    }

    // Variant (defensivt; ukendt → klassisk) + resolvet navn — læses HER,
    // hvor doc'et er: GameSummary er det eneste liste-laget ser. Efter start
    // er STATE'ns 'vid' autoriteten (doc-feltet kan i princippet ændres af et
    // medlem midt i spillet uden at røre brættet) — foretræk den.
    // Materialiseret fra doc'ets kopi, så "Mine spil"-badgen viser custom-
    // varianters navn/farve. Under spillet er state.vid autoriteten.
    final VariantConfig variant = variantFromRaw(
        (status == 'playing' && state is Map && state['vid'] is String)
            ? state['vid'] as String
            : (d['variantId'] is String ? d['variantId'] as String : null),
        d['cardRulesVariants']);
    // Arkiv-felter. Vinderen læses fra STATE ('wt') som autoritet: topniveau-
    // feltet skrives kun ved selve overgangen, så ældre docs kan mangle det.
    final List<dynamic> uidsAll = (d['uids'] as List?) ?? const <dynamic>[];
    final int mySeat = uidsAll.indexOf(uid);
    int? winner;
    if (status == 'over') {
      if (state is Map && state['wt'] is num) {
        winner = (state['wt'] as num).toInt();
      } else if (d['winningTeamIndex'] is num) {
        winner = (d['winningTeamIndex'] as num).toInt();
      }
    }
    // "Så jeg slutningen?" — samme kilde som replay'en bruger: har jeg set
    // færre log-indlæg end der findes, sluttede spillet mens jeg var væk.
    final int logLen = (d['log'] as List?)?.length ?? 0;
    final dynamic seenRaw = d['seen'];
    final int mySeen = (seenRaw is Map && seenRaw[uid] is num)
        ? (seenRaw[uid] as num).toInt()
        : 0;
    return GameSummary(
      id,
      d['hostName'] as String? ?? '?',
      status,
      names,
      hostUid: d['hostUid'] as String?,
      phase: phase,
      currentName: currentName,
      isMyTurn: isMyTurn,
      needsExchange: needsExchange,
      variantId: variant.id,
      variantLabel: variantDisplayName(variant, d['cardRulesVariants']),
      variant: variant,
      finishedAtMs: _tsMs(d['finishedAt']) ?? _tsMs(d['createdAt']),
      winningTeamIndex: winner,
      mySeat: mySeat,
      unseen: status == 'over' && mySeen < logLen,
      isAi: d['mode'] == 'ai',
    );
  }

int? _tsMs(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    return null;
  }
