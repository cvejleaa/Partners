import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'online_service.dart';

/// VAPID-nøgle (Web Push certificate public key) til at registrere FCM-tokens
/// fra browseren.
///
/// TODO(admin): Generér nøglen i Firebase Console (én gang pr. projekt):
///   1. Project Settings → Cloud Messaging.
///   2. Find sektionen "Web configuration" → "Web Push certificates".
///   3. Klik "Generate key pair" og kopiér public-nøglen.
///   4. Indsæt den her som strengen mellem anførselstegnene.
///
/// Mens nøglen er tom logges en advarsel og [PushService.registerTokenForCurrentUser]
/// undlader at hente token — appen crasher IKKE.
const String _kVapidKey = '';

/// Letvægts-besked vist når der kommer en foregrund-push (browser-fanen er åben).
@immutable
class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    required this.gameCode,
    required this.receivedAt,
  });

  final String title;
  final String body;
  final String gameCode;
  final DateTime receivedAt;
}

/// Service der håndterer browser-push-notifikationer (FCM).
///
/// Lever af [FirebaseMessaging] på web; ingen-op på andre platforme.
/// Tokens skrives ind under `users/{uid}.fcmTokens` (arrayUnion / arrayRemove)
/// så en Cloud Function kan slå dem op og kalde FCM Admin SDK når der
/// dukker en ny invitation op i `users/{uid}/inbox`.
///
/// Singleton — én instans pr. app via [pushServiceProvider].
class PushService {
  PushService();

  bool _initDone = false;
  String? _lastToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<User?>? _authSub;

  /// Seneste foregrund-besked. UI lytter via [pushMessageProvider] (som er
  /// en stream-provider ovenpå denne).
  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();
  Stream<PushMessage> get messages => _messages.stream;

  FirebaseFirestore get _db => firestore;

  /// True hvis platformen overhovedet kan håndtere FCM-web-push. På andre
  /// platforme er det no-op (Android/iOS bruger ikke service worker, og
  /// her kører vi kun web).
  bool get _supported => kIsWeb;

  /// Initialiser foregrund-listeners og auth-watcher. Kald én gang fra
  /// [main]. Tom på ikke-web-platforme.
  Future<void> init() async {
    if (_initDone) return;
    _initDone = true;
    if (!_supported) return;
    try {
      // Foregrund-push: vis som besked i app'en (system-notifikationer
      // håndteres af service worker'en når fanen er lukket).
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForeground);
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen(_handleTokenRefresh);

      // Når brugeren logger ind: hvis browseren allerede har givet
      // notifikations-tilladelse (fra en tidligere session), så hent og
      // skriv tokenen igen — så fcmTokens-arrayet under users/{uid} altid
      // afspejler den aktuelle bruger/enhed. Vi prompt'er IKKE her;
      // permission-prompt'en sker kun fra settings-toggle.
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user == null) return;
        if (_lastToken != null) {
          // ignore: discarded_futures
          _writeTokenForUser(user.uid, _lastToken!);
          return;
        }
        // ignore: discarded_futures
        _maybeRegisterIfAlreadyGranted();
      });
    } catch (e) {
      debugPrint('[push] init fejlede: $e');
    }
  }

  void _handleForeground(RemoteMessage msg) {
    final notif = msg.notification;
    final data = msg.data;
    _messages.add(PushMessage(
      title: notif?.title ?? 'Partners',
      body: notif?.body ?? 'Du har en ny besked',
      gameCode: (data['gameCode'] as String?) ?? '',
      receivedAt: DateTime.now(),
    ));
  }

  /// Spørg brugeren om browser-tilladelse til notifikationer. Returnerer
  /// true hvis givet (eller allerede givet).
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[push] requestPermission fejlede: $e');
      return false;
    }
  }

  /// Aktuel tilladelses-status — uden at spørge brugeren igen.
  Future<AuthorizationStatus> currentPermission() async {
    if (!_supported) return AuthorizationStatus.notDetermined;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus;
    } catch (_) {
      return AuthorizationStatus.notDetermined;
    }
  }

  /// Hent FCM-token og skriv den til `users/{uid}.fcmTokens` (arrayUnion).
  /// Kræver at brugeren er logget ind og har givet tilladelse. Hvis VAPID
  /// mangler eller noget fejler, logges det stille.
  Future<void> registerTokenForCurrentUser() async {
    if (!_supported) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint(
          '[push] ingen bruger logget ind — token-registrering springes over');
      return;
    }
    if (_kVapidKey.isEmpty) {
      debugPrint(
          '[push] VAPID-nøgle mangler — se push_service.dart for instruktioner. Springer token-registrering over.');
      return;
    }
    try {
      final token =
          await FirebaseMessaging.instance.getToken(vapidKey: _kVapidKey);
      if (token == null || token.isEmpty) {
        debugPrint('[push] getToken returnerede tom — springer over');
        return;
      }
      _lastToken = token;
      await _writeTokenForUser(uid, token);
    } catch (e) {
      debugPrint('[push] registerToken fejlede: $e');
    }
  }

  /// Hent og registrér token — men KUN hvis browseren allerede har givet
  /// tilladelse (dvs. vi prompt'er ikke). Ingen-op hvis VAPID mangler.
  Future<void> _maybeRegisterIfAlreadyGranted() async {
    if (!_supported || _kVapidKey.isEmpty) return;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      if (s.authorizationStatus != AuthorizationStatus.authorized &&
          s.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      await registerTokenForCurrentUser();
    } catch (e) {
      debugPrint('[push] auto-register fejlede: $e');
    }
  }

  Future<void> _writeTokenForUser(String uid, String token) async {
    try {
      await _db.collection('users').doc(uid).set(<String, dynamic>{
        'fcmTokens': FieldValue.arrayUnion(<String>[token]),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[push] skriv af token fejlede: $e');
    }
  }

  void _handleTokenRefresh(String token) {
    _lastToken = token;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // ignore: discarded_futures
    _writeTokenForUser(uid, token);
  }

  /// Fjern den senest kendte token fra brugerens `fcmTokens`-array. Brug ved
  /// "slå push fra"-toggle og før logout.
  Future<void> unregisterTokenForCurrentUser() async {
    if (!_supported) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    String? token = _lastToken;
    if (token == null && _kVapidKey.isNotEmpty) {
      try {
        token =
            await FirebaseMessaging.instance.getToken(vapidKey: _kVapidKey);
      } catch (_) {
        // Ignorér — vi prøver så at fjerne det vi havde i forvejen.
      }
    }
    if (token != null && token.isNotEmpty) {
      try {
        await _db.collection('users').doc(uid).set(<String, dynamic>{
          'fcmTokens': FieldValue.arrayRemove(<String>[token]),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[push] fjern af token fejlede: $e');
      }
    }
    _lastToken = null;
    // Forsøg desuden at slette tokenen fra browseren helt — så den ikke
    // bare bliver hentet igen ved næste getToken-kald.
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _authSub?.cancel();
    _messages.close();
  }
}

/// Hoved-provider for [PushService]. Init kaldes fra `main()`.
final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  final svc = PushService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Stream af foregrund-push. UI kan watchke denne for at vise SnackBars.
final StreamProvider<PushMessage> pushMessageProvider =
    StreamProvider<PushMessage>(
        (ref) => ref.watch(pushServiceProvider).messages);
