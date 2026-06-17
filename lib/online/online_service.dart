import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Live-stream af ét online-spil.
final gameStreamProvider = StreamProvider.family<
    DocumentSnapshot<Map<String, dynamic>>, String>(
  (ref, code) => ref.read(onlineServiceProvider).watch(code),
);

/// Spil jeg er inviteret til eller deltager i (lobby/igangværende).
final myGamesProvider = StreamProvider<List<GameSummary>>(
    (ref) => ref.read(onlineServiceProvider).myGames());

class GameSummary {
  GameSummary(this.code, this.hostName, this.status, this.playerNames);
  final String code;
  final String hostName;
  final String status;
  final List<String> playerNames;

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
}

/// Hvor længe der maks. må gå uden handling/heartbeat fra en spiller, før en
/// AI overtager dennes tur. Holdes konfigurerbar ét sted.
const Duration kAiTakeoverTimeout = Duration(seconds: 35);

/// Hvor ofte en aktiv klient opdaterer sit "presence"-stempel.
const Duration kPresenceInterval = Duration(seconds: 15);

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

  Future<String> myDisplayName() async {
    final u = _auth.currentUser;
    if (u == null) return 'Spiller';
    if ((u.displayName ?? '').isNotEmpty) return u.displayName!;
    final doc = await _users.doc(u.uid).get();
    return (doc.data()?['displayName'] as String?) ?? 'Spiller';
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

  Future<String> createGame({
    required int colorValue,
    required CardRules rules,
  }) async {
    final uid = _auth.currentUser!.uid;
    final name = await myDisplayName();
    final code = _genCode();
    await _games.doc(code).set(<String, dynamic>{
      'status': 'lobby',
      'hostUid': uid,
      'hostName': name,
      'names': <String>[name, 'Åben', 'Åben', 'Åben'],
      'colors': <int>[colorValue, 0xFF1E88E5, 0xFF43A047, 0xFFFDD835],
      'uids': <String?>[uid, null, null, null],
      // Pladser markeret som AI fra lobbyen (true = computer-spiller).
      'aiSeats': <bool>[false, false, false, false],
      'invitedUids': <String>[],
      'members': <String>[uid],
      // Klar-markering pr. uid i lobbyen (vært tæller altid som klar).
      'ready': <String, dynamic>{uid: true},
      // Tilstedeværelses-stempel pr. uid (heartbeat) til reconnect/AI-overtag.
      'presence': <String, dynamic>{uid: Timestamp.now()},
      'cardRules': rules.toJson(),
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
        'presence.$uid': Timestamp.now(),
      });
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String code) =>
      _games.doc(code).snapshots();

  Stream<List<GameSummary>> myGames() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream<List<GameSummary>>.value(const <GameSummary>[]);
    }
    return _games
        .where('members', arrayContains: uid)
        .snapshots()
        .map((q) => q.docs
            .map((d) => GameSummary(
                  d.id,
                  d.data()['hostName'] as String? ?? '?',
                  d.data()['status'] as String? ?? 'lobby',
                  (d.data()['names'] as List).map((e) => e as String).toList(),
                ))
            .where((g) => g.status != 'over')
            .toList());
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
    final state = _initialState(names, colors, uids, rules);
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
      'presence.$uid': Timestamp.now(),
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
  Future<void> heartbeat(String code) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _games.doc(code).update(<String, dynamic>{
        'presence.$uid': Timestamp.now(),
      });
    } catch (_) {}
  }

  /// Afgør om en menneskelig spiller på [seat] regnes som "væk" ud fra
  /// dokumentets felter. En spiller er væk hvis:
  ///  - der ikke er noget presence-stempel (aldrig set / gammelt skema), ELLER
  ///  - seneste presence er ældre end [kAiTakeoverTimeout].
  /// Bruges sammen med tids-siden-sidste-handling i UI-laget.
  static bool seatLooksAway(Map<String, dynamic> d, int seat) {
    final uids = d['uids'] as List?;
    if (uids == null || seat >= uids.length) return false;
    final uid = uids[seat];
    if (uid == null) return true; // tom plads = AI
    final presence = d['presence'];
    if (presence is! Map) return true;
    final ts = presence[uid];
    if (ts is! Timestamp) return true;
    return DateTime.now().difference(ts.toDate()) > kAiTakeoverTimeout;
  }

  /// Hjælper til UI: tid siden sidste handling i spillet (eller null).
  static Duration? timeSinceLastAction(Map<String, dynamic> d) {
    final ts = d['lastActionAt'];
    if (ts is! Timestamp) return null;
    return DateTime.now().difference(ts.toDate());
  }

  GameState _initialState(
      List<String> names, List<int> colors, List uids, CardRules rules) {
    final players = <Player>[
      for (int i = 0; i < 4; i++)
        Player(
          index: i,
          name: uids[i] != null ? names[i] : 'AI ${i + 1}',
          color: Color(colors[i]),
          isHuman: uids[i] != null,
          pieces: <Piece>[
            for (int s = 0; s < 4; s++)
              Piece(id: 'p$i.$s', ownerIndex: i, position: StartPosition(i, s)),
          ],
        ),
    ];
    final s = GameState(
      players: players,
      geometry: const BoardGeometry(),
      deck: Deck.fresh(),
      discard: <PlayingCard>[],
      dealerIndex: 0,
      currentPlayerIndex: 0,
      phase: GamePhase.setup,
      handNumber: 0,
      cardRules: rules,
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
        entry['t'] = Timestamp.now();
        upd['log'] = FieldValue.arrayUnion(<dynamic>[entry]);
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
  Future<bool> aiTakeoverMove(String code, int seat) async {
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

      final wasOver = state.winningTeamIndex != null;
      final engine = GameEngine(state: state);
      final Move? m = onlineAi.chooseMove(state, seat);
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
      entry['t'] = Timestamp.now();
      // Marker at trækket blev lavet af AI på vegne af en fraværende spiller.
      entry['ai'] = true;
      upd['log'] = FieldValue.arrayUnion(<dynamic>[entry]);
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
