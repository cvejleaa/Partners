# Push-notifikationer (FCM) — opsætning

Fase B af venner/invitationer giver browser-push, så modtageren får besked
selv når fanen er lukket. Denne fil samler de manuelle skridt som ikke er
automatiseret.

## 1. VAPID-nøgle (Web Push certificate)

FCM på web kræver en VAPID public-key som klienten sender med i
`getToken(vapidKey: ...)`. Den genereres én gang pr. Firebase-projekt:

1. Åbn Firebase Console for projekt `partners-8d4aa`.
2. Project Settings → fanen **Cloud Messaging**.
3. Find sektionen **Web configuration** → **Web Push certificates**.
4. Klik **Generate key pair**.
5. Kopiér public-nøglen.
6. Indsæt den i `lib/online/push_service.dart` som strengen i konstanten
   `_kVapidKey`.
7. Commit, push, og lad CI redeployere web-build'et.

Indtil nøglen er sat logger klienten en advarsel og springer
token-registrering over — appen crasher ikke.

## 2. Service worker

`web/firebase-messaging-sw.js` håndterer baggrunds-push. Den hostes
automatisk af Firebase Hosting fordi `flutter build web` kopierer alt under
`web/` til `build/web/`. Ingen ekstra opsætning.

Hvis du ændrer Firebase-konfigurationen (`lib/firebase_options.dart`) skal
samme felter også opdateres i `firebase-messaging-sw.js` — de to er
manuelle kopier.

## 3. Cloud Function — manuel opfølgning

FCM-token alene sender ingenting. Der skal stå en server (typisk en
Cloud Function) som lytter på `users/{uid}/inbox/{x}` og kalder FCM Admin
SDK med modtagerens tokens.

**Status: ikke automatiseret. Hoved-sessionen sætter dette op manuelt.**
CI'en deployer IKKE Cloud Functions i denne fase.

Skitse (Node.js, Firestore-triggered):

```js
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Brug den navngivne database 'partners' — IKKE (default).
const db = admin.firestore();
db.settings({ databaseId: 'partners' });

exports.onInboxCreate = functions
  .firestore
  .document('users/{uid}/inbox/{inviteId}')
  .onCreate(async (snap, ctx) => {
    const invite = snap.data() || {};
    if (invite.type !== 'gameInvite') return;

    const uid = ctx.params.uid;
    const userDoc = await db.collection('users').doc(uid).get();
    const tokens = (userDoc.data() || {}).fcmTokens || [];
    if (!tokens.length) return;

    const fromName = invite.fromName || 'En ven';
    const gameCode = invite.gameCode || '';

    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Partners — invitation',
        body: `${fromName} har inviteret dig til et spil`,
      },
      data: {
        gameCode,
        click_action: '/',
      },
      webpush: {
        fcmOptions: { link: gameCode ? `/?invite=${gameCode}` : '/' },
      },
    });

    // Ryd op i tokens der ikke længere er gyldige.
    const stale = [];
    res.responses.forEach((r, i) => {
      if (!r.success && (
        r.error?.code === 'messaging/registration-token-not-registered' ||
        r.error?.code === 'messaging/invalid-registration-token')) {
        stale.push(tokens[i]);
      }
    });
    if (stale.length) {
      await db.collection('users').doc(uid).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...stale),
      });
    }
  });
```

Deploy senere med `firebase deploy --only functions` (kræver `functions/`-
mappe med `package.json`). Tilføj `functions` til `firebase.json` når
funktionen er klar.

## 4. Test

Når VAPID-nøglen er sat og Cloud Function er deployet:

1. Log ind som bruger A på partners.vejleaa.dk.
2. Gå til Indstillinger → slå **Push-notifikationer (browser)** til.
3. Accepter browser-prompten. Tjek at `users/{A}` i Firestore har
   `fcmTokens` med et element.
4. Log ind som bruger B i en anden browser. Inviter A til et spil.
5. Luk A's fane. Funktionen skal afsende push og en system-notifikation
   skal poppe op hos A.
