// Service worker for Firebase Cloud Messaging i Partners.
//
// Denne fil hostes på samme origin som spillet (Firebase Hosting) og bliver
// registreret automatisk af firebase_messaging-pakken på web. Den modtager
// baggrunds-push fra FCM — dvs. når browser-fanen er lukket eller skjult —
// og viser en system-notifikation som brugeren kan klikke på.
//
// Versionen af compat-SDK'erne skal matche den firebase-js-sdk-familie som
// firebase_messaging bundler. Holdes på 10.13.2 (stable, kompatibel).

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

// Samme config som lib/firebase_options.dart (web). Hold de to filer i sync.
firebase.initializeApp({
  apiKey: 'AIzaSyBuqpI50RSaTSsRD_rrOvlxTIX7P3JJnUk',
  authDomain: 'partners-8d4aa.firebaseapp.com',
  projectId: 'partners-8d4aa',
  storageBucket: 'partners-8d4aa.firebasestorage.app',
  messagingSenderId: '705156280664',
  appId: '1:705156280664:web:23715a6e10e012ee1f352d',
});

const messaging = firebase.messaging();

// Byg mål-URL'en ud fra notifikationstypen: en "din tur"-push åbner selve
// spillet (/?game=<code>), en invitation åbner invitations-flowet
// (/?invite=<code>).
function targetFor(type, gameCode) {
  if (!gameCode) return '/';
  const code = encodeURIComponent(gameCode);
  return type === 'turn' ? '/?game=' + code : '/?invite=' + code;
}

// Beskederne sendes DATA-only, så browseren IKKE selv viser en notifikation.
// Vi viser den her (præcis én gang) ud fra data-feltet.
messaging.onBackgroundMessage(function (payload) {
  const data = (payload && payload.data) || {};
  const title = data.title || 'Partners';
  const body = data.body || 'Du har en ny besked';
  const type = data.type || '';
  const gameCode = data.gameCode || '';
  // Tag pr. type+spil, så en ny "din tur" erstatter den forrige for samme spil
  // i stedet for at hobe sig op.
  const tag = gameCode ? 'partners-' + (type || 'msg') + '-' + gameCode : 'partners';
  self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: tag,
    renotify: true,
    data: { type: type, gameCode: gameCode, url: targetFor(type, gameCode) },
  });
});

// Klik: fokusér (og naviger) en åben Partners-fane ind i spillet — ellers åbn
// et nyt vindue direkte på spillet.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  const d = event.notification.data || {};
  const url = d.url || targetFor(d.type, d.gameCode);
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clientList) {
        for (let i = 0; i < clientList.length; i++) {
          const c = clientList[i];
          if ('focus' in c) {
            // Naviger den eksisterende fane ind i spillet, så app'en læser
            // ?game=/?invite= og hopper direkte derhen; fokusér bagefter.
            if ('navigate' in c) {
              return c.navigate(url).then(function (nc) {
                return (nc || c).focus();
              }).catch(function () {
                return c.focus();
              });
            }
            return c.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(url);
        }
        return null;
      })
  );
});
