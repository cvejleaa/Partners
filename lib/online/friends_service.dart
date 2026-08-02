import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'online_service.dart';

/// Letvægts-data for en ven (kopi i vores eget `users/{uid}/friends/{x}`-doc).
class FriendRef {
  FriendRef({
    required this.uid,
    required this.displayName,
    required this.email,
    this.avatar,
    this.addedAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? avatar;
  final DateTime? addedAt;

  factory FriendRef.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['addedAt'];
    return FriendRef(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? 'Spiller',
      email: (d['email'] as String?) ?? '',
      avatar: d['avatar'] as String?,
      addedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Letvægts-data for en bruger fundet i søgning (læser fra `users/{uid}`).
class UserRef {
  UserRef({
    required this.uid,
    required this.displayName,
    required this.email,
    this.avatar,
    this.photoURL,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? avatar;
  final String? photoURL;

  factory UserRef.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return UserRef(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? 'Spiller',
      email: (d['email'] as String?) ??
          (d['emailLower'] as String?) ??
          '',
      avatar: d['avatar'] as String?,
      photoURL: d['photoURL'] as String?,
    );
  }
}

/// En invitation i indbakken (`users/{uid}/inbox/{inviteId}`).
class InboxInvite {
  InboxInvite({
    required this.id,
    required this.type,
    required this.fromUid,
    required this.fromName,
    required this.gameCode,
    required this.seen,
    this.createdAt,
  });

  final String id;
  final String type;
  final String fromUid;
  final String fromName;
  final String gameCode;
  final bool seen;
  final DateTime? createdAt;

  factory InboxInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['createdAt'];
    return InboxInvite(
      id: doc.id,
      type: (d['type'] as String?) ?? 'gameInvite',
      fromUid: (d['fromUid'] as String?) ?? '',
      fromName: (d['fromName'] as String?) ?? 'Spiller',
      gameCode: (d['gameCode'] as String?) ?? '',
      seen: (d['seen'] as bool?) ?? false,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Service for venner og in-app invitationer.
///
/// Datamodel:
///  * `users/{uid}` — offentlig profil til søgning (læsbar af alle signed-in).
///  * `users/{uid}/friends/{friendUid}` — den lokale vennekopi (kun ejer).
///  * `users/{uid}/inbox/{inviteId}` — invitationer; ejer læser/sletter,
///    andre signed-in må oprette.
class FriendsService {
  FriendsService();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  FirebaseFirestore get _db => firestore;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  String? get _uid => _auth.currentUser?.uid;

  /// Sørg for at den aktuelle brugers profil-doc findes/er opdateret. Skriver
  /// `displayName`, `email`, `emailLower`, `photoURL` og `updatedAt` så
  /// søgning på navn/email virker. Fejler stille — login skal stadig kunne
  /// gennemføres selv hvis Firestore-skriv slår fejl (offline, regler osv.).
  Future<void> ensureUserDoc() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final email = user.email ?? '';
    final name = (user.displayName ?? '').isNotEmpty
        ? user.displayName!
        : (email.isNotEmpty ? email.split('@').first : 'Spiller');
    try {
      await _users.doc(user.uid).set(<String, dynamic>{
        'displayName': name,
        'displayNameLower': name.toLowerCase(),
        'email': email,
        'emailLower': email.toLowerCase(),
        if (user.photoURL != null) 'photoURL': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignorér — login må ikke fejle pga. dette skriv.
    }
  }

  /// Case-insensitiv søgning på e-mail eller displayName. Max 10 resultater.
  /// Returnerer en tom liste hvis søgestrengen er for kort.
  Future<List<UserRef>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const <UserRef>[];

    // Prefix-søgning a la "begynder med": [q, q + ] er Firestore-mønsteret.
    final String end = '$q';

    // To parallelle queries: email-prefix og displayName-prefix. Vi flettes
    // sammen, deduper på uid, og filtrerer egen bruger fra.
    final emailFut = _users
        .orderBy('emailLower')
        .startAt(<dynamic>[q])
        .endAt(<dynamic>[end])
        .limit(10)
        .get();
    final nameFut = _users
        .orderBy('displayNameLower')
        .startAt(<dynamic>[q])
        .endAt(<dynamic>[end])
        .limit(10)
        .get();

    final results = <String, UserRef>{};
    try {
      final snaps = await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
        emailFut,
        nameFut,
      ]);
      for (final qs in snaps) {
        for (final d in qs.docs) {
          if (d.id == _uid) continue; // ikke vis sig selv
          results.putIfAbsent(d.id, () => UserRef.fromDoc(d));
        }
      }
    } catch (_) {
      // Hvis displayNameLower-feltet ikke findes på gamle docs vil orderBy
      // springe dem over. Det er ok — vi falder tilbage på email-resultater.
    }

    final list = results.values.toList();
    if (list.length > 10) return list.sublist(0, 10);
    return list;
  }

  /// Stream over alle venner for den aktuelle bruger.
  Stream<List<FriendRef>> watchFriends() {
    final uid = _uid;
    if (uid == null) return Stream<List<FriendRef>>.value(const <FriendRef>[]);
    return _users
        .doc(uid)
        .collection('friends')
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((q) => q.docs.map(FriendRef.fromDoc).toList());
  }

  /// Tilføj en ven (kopi af basal profil-info i vores eget friends-subcollection).
  /// Slår profilen op først så vi får navn/email med.
  Future<void> addFriend(String friendUid) async {
    final uid = _uid;
    if (uid == null) throw 'Du er ikke logget ind';
    if (friendUid == uid) throw 'Du kan ikke tilføje dig selv';
    final profile = await _users.doc(friendUid).get();
    final p = profile.data() ?? const <String, dynamic>{};
    await _users
        .doc(uid)
        .collection('friends')
        .doc(friendUid)
        .set(<String, dynamic>{
      'displayName': (p['displayName'] as String?) ?? 'Spiller',
      'email': (p['email'] as String?) ??
          (p['emailLower'] as String?) ??
          '',
      if (p['avatar'] != null) 'avatar': p['avatar'],
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fjern en ven fra vennelisten.
  Future<void> removeFriend(String friendUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _users.doc(uid).collection('friends').doc(friendUid).delete();
  }

  /// Send en spil-invitation til en bruger. Lægger et dokument i modtagerens
  /// `inbox`-subcollection. Bruger auto-id så flere invitationer ikke skriver
  /// oven i hinanden.
  Future<void> sendGameInvite(String toUid, String gameCode) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Du er ikke logget ind';
    final rawName = (user.displayName ?? '').isNotEmpty
        ? user.displayName!
        : (user.email ?? 'Spiller');
    // Trim til ≤60 tegn — matcher Firestore-reglens grænse, så lange emails
    // ikke får invitationen afvist.
    final fromName =
        rawName.length > 60 ? rawName.substring(0, 60) : rawName;
    await _users.doc(toUid).collection('inbox').add(<String, dynamic>{
      'type': 'gameInvite',
      'fromUid': user.uid,
      'fromName': fromName,
      'gameCode': gameCode,
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream over indbakken for den aktuelle bruger (nyeste først).
  Stream<List<InboxInvite>> watchInbox() {
    final uid = _uid;
    if (uid == null) return Stream<List<InboxInvite>>.value(const <InboxInvite>[]);
    return _users
        .doc(uid)
        .collection('inbox')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((q) => q.docs.map(InboxInvite.fromDoc).toList());
  }

  /// Marker en invitation som set (`seen: true`).
  Future<void> markSeen(String inviteId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _users
          .doc(uid)
          .collection('inbox')
          .doc(inviteId)
          .update(<String, dynamic>{'seen': true});
    } catch (_) {
      // Doc kan være slettet samtidigt — ignorér.
    }
  }

  /// Slet en invitation fra indbakken.
  Future<void> deleteInvite(String inviteId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _users.doc(uid).collection('inbox').doc(inviteId).delete();
    } catch (_) {
      // Ignorér — er måske allerede slettet.
    }
  }
}

final Provider<FriendsService> friendsServiceProvider =
    Provider<FriendsService>((ref) => FriendsService());

/// Live-stream af venner for den aktuelle bruger.
final StreamProvider<List<FriendRef>> friendsStreamProvider =
    StreamProvider<List<FriendRef>>((ref) {
  // Re-resolve når auth ændrer sig så vi rammer den korrekte uid.
  ref.watch(authStateProvider);
  return ref.read(friendsServiceProvider).watchFriends();
});

/// Live-stream af indbakke (invitationer) for den aktuelle bruger.
final StreamProvider<List<InboxInvite>> inboxStreamProvider =
    StreamProvider<List<InboxInvite>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(friendsServiceProvider).watchInbox();
});
