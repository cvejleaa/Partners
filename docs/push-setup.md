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

## 3. Cloud Function

FCM-token alene sender ingenting. En Cloud Function (`functions/index.js`)
lytter på `users/{uid}/inbox/{x}` og kalder FCM Admin SDK med modtagerens
tokens. CI deployer den automatisk efter hosting (`firebase deploy --only
functions` i `.github/workflows/deploy.yml`). Kræver Blaze-plan.

Region: `europe-west1`. Runtime: `nodejs20`. Database: `partners` (navngiven).

Funktionen ligger i `functions/index.js`. CI installerer dependencies og
deployer den automatisk via `firebase deploy --only functions`.

Hvis du vil teste lokalt med Firebase Emulator:

```sh
cd functions && npm install
firebase emulators:start --only functions,firestore
```

## 4. Test

Når VAPID-nøglen er sat og Cloud Function er deployet:

1. Log ind som bruger A på partners.vejleaa.dk.
2. Gå til Indstillinger → slå **Push-notifikationer (browser)** til.
3. Accepter browser-prompten. Tjek at `users/{A}` i Firestore har
   `fcmTokens` med et element.
4. Log ind som bruger B i en anden browser. Inviter A til et spil.
5. Luk A's fane. Funktionen skal afsende push og en system-notifikation
   skal poppe op hos A.
