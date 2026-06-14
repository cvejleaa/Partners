// Firebase-konfiguration til Partners. Gemt på forhånd så online async
// multiplayer er klar at koble på.
//
// Aktivér ved at:
//   1) tilføj `firebase_core: ^3.x` (og fx `cloud_firestore`) til pubspec.yaml
//   2) i main.dart: `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);`
//
// Indtil da bruges denne fil ikke af koden.

class DefaultFirebaseOptions {
  static const Map<String, String> web = <String, String>{
    'apiKey': 'AIzaSyBuqpI50RSaTSsRD_rrOvlxTIX7P3JJnUk',
    'authDomain': 'partners-8d4aa.firebaseapp.com',
    'projectId': 'partners-8d4aa',
    'storageBucket': 'partners-8d4aa.firebasestorage.app',
    'messagingSenderId': '705156280664',
    'appId': '1:705156280664:web:23715a6e10e012ee1f352d',
  };
}
