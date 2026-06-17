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

// Vises når en push lander mens app'en er lukket / i baggrunden.
messaging.onBackgroundMessage(function (payload) {
  const notif = (payload && payload.notification) || {};
  const data = (payload && payload.data) || {};
  const title = notif.title || 'Partners';
  const body = notif.body || 'Du har en ny besked';
  const gameCode = data.gameCode || '';
  self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: gameCode ? 'partners-invite-' + gameCode : 'partners',
    data: {
      gameCode: gameCode,
      click_action: data.click_action || '/',
    },
  });
});

// Klik på notifikation: åbn (eller fokusér) Partners-fanen, og send
// gameCode med så app'en kan navigere ind i spillets lobby.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  const gameCode = (event.notification.data && event.notification.data.gameCode) || '';
  const target = gameCode ? '/?invite=' + encodeURIComponent(gameCode) : '/';
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clientList) {
        for (let i = 0; i < clientList.length; i++) {
          const c = clientList[i];
          // Hvis en Partners-fane allerede er åben: fokusér den og post
          // gameCode så Flutter-app'en kan reagere.
          if ('focus' in c) {
            try {
              c.postMessage({ type: 'partners-invite', gameCode: gameCode });
            } catch (_) {}
            return c.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(target);
        }
        return null;
      })
  );
});
