# Teknologiske valg — Partners

Dette dokument samler hvilke teknologier vi har valgt til Partners, og
hvorfor. Tænkt som "tro og love"-dokument for fremtidige beslutninger:
før vi udskifter noget, skal vi kunne argumentere imod begrundelsen her.

Spillet i ét billede: et dansk brætspil med 4 spillere, 2 hold, lokal AI
*eller* online mod venner. Skal kunne tilgås øjeblikkeligt på telefon, tablet
og PC uden installation, gemme statistik pr. konto, og kunne invitere venner
med push-besked.

---

## 1. Flutter (klient)

**Valgt:** Flutter ≥ 3.19 med Dart 3.

**Hvorfor:**

- **Én kodebase, tre platforme.** Vi rammer web (primært), iOS og Android
  fra samme `lib/`-træ. React Native ville have krævet en separat web-build
  (Next.js eller lignende); native Swift/Kotlin tre fulde kodebaser.
- **CustomPainter giver fuld kontrol over brættet.** `BoardView` tegner 60
  felter, UD-felter, hjemstræk, brikker og animationer i én Canvas. Et HTML/
  SVG-board ville have været både langsommere og sværere at få pixel-perfect
  på små skærme.
- **Stærk typesikkerhed.** Spillogikken (`lib/game/rules.dart`,
  `game_engine.dart`) bygger på sealed-lignende klasser (`MoveStep`,
  `BoardPosition`, `HomeStretchPosition`). Reglerne kan ikke skrives forkert
  uden at compileren brokker sig.
- **Hot reload** gør regel-eksperimenter (UD-felt, split-7, knægt-byt)
  trivielle at iterere.

**Trade-offs vi accepterer:**

- Web-bundle'en er stor (~3–4 MB). Mitigeret af aggressiv cache i
  `firebase.json` (`max-age=31536000, immutable` på `.js/.wasm`).
- Tekst-rendering på web er ikke perfekt på alle browsere. Vi har accepteret
  Noto-fonts-advarslen i konsollen som kosmetisk.

---

## 2. Riverpod (state management)

**Valgt:** `flutter_riverpod` 2.x.

**Hvorfor:**

- `StateNotifierProvider` matcher vores spil-state 1:1: en enkelt
  `GameController` ejer hele `GameState`, og UI'en re-renderer på
  diff. Provider/BLoC ville have krævet mere boilerplate.
- `StreamProvider` og `FutureProvider` lader os blande lokal AI-state og
  Firestore-snapshots uden ekstra glue. Friends-listen (`friendsStreamProvider`)
  og inbox-banneret (`inboxStreamProvider`) bruger samme pattern.
- Compile-tids-afhængighed mellem providere fanger fejl der i Provider
  først dukker op i runtime.

**Alternativer overvejet:**

- `bloc` — for tung til en kort-baseret turn engine.
- `setState` — fint til prototyper, men spil-state spreder sig over for
  mange skærme (board, hånd, panel, banner) til at det skalerer.

---

## 3. Firebase som backend

**Valgt:** Firebase Auth + Firestore + Hosting + Cloud Functions + FCM.

**Hvorfor samlet pakke fremfor egen server:**

- Vi har **ingen server-drift**. Spillet er hobby-skala; en VM med Node
  ville være konstant cost + opdateringer.
- Auth, database, hosting og push deler ét login og ét projekt-ID
  (`partners-8d4aa`).
- Free tier dækker det meste; Blaze-plan tilkøbt kun fordi Cloud Functions
  kræver det.

### 3a. Firebase Auth

Email + Google login. Google fordi næsten alle test-brugere har en
Gmail-konto; email som fallback. Vi bruger ikke anonym login — kontoer
skal være persistent for at venne-features og statistik virker på tværs af
enheder.

### 3b. Firestore — *navngiven database* `partners`

**Vigtigt:** Vi bruger ikke `(default)`-databasen. Vi har en
**navngiven** Firestore-database kaldet `partners`. Det betyder:

- `firebase.json` har `"firestore": [{ "database": "partners", ... }]`.
- CI deployer regler med `--only "firestore:partners:rules"`.
- Cloud Function initialiserer `getFirestore("partners")` — ikke default.

Grunden: projektet havde allerede en `(default)` database brugt til en anden
prototype. At lægge Partners i en navngiven database isolerer regler,
kvoter og backup-politikker.

**Konsekvens:** Hver gang vi tilføjer en ny Firestore-klient
(Cloud Function, admin script), skal vi eksplicit navngive `partners`.
Glemmer vi det, rammer vi en tom default-database og tror bare data
mangler. Dette er den hyppigste fejlkilde — derfor det fremhævede afsnit.

### 3c. Firebase Hosting + custom domain

`partners.vejleaa.dk` peger på Firebase Hosting via to A-records.
SSL håndteres automatisk. Vi har specifikke `Cache-Control`-headers per
fil-type i `firebase.json`:

| Fil | Cache | Begrundelse |
|-----|-------|-------------|
| `*.js / *.json / *.wasm` | 1 år, immutable | Flutter web hash'er filnavne |
| `/index.html` | no-cache | Pege på nyeste assets ved hver load |
| `/firebase-messaging-sw.js` | no-cache + `Service-Worker-Allowed: /` | Service workers må aldrig caches |

### 3d. Cloud Functions (Node.js 20)

**Hvorfor Node frem for at lade klienten kalde FCM:** Klienten kan *ikke*
sende FCM-beskeder — Admin SDK kræver service-account credentials. En
Cloud Function lytter på `users/{uid}/inbox/{x}` i Firestore og sender
push via `getMessaging().sendEachForMulticast()`. Reaktiv arkitektur:
klienten skriver en doc, function reagerer. Ingen ekstra API at vedligeholde.

Vi kører i **region `europe-west1`** for at minimere latency for danske
brugere.

### 3e. FCM (Firebase Cloud Messaging)

Browser-push så modtageren ser invitationen selv med lukket fane.
Krav:

1. **VAPID-nøgle** genereret i Firebase Console, indsat i
   `lib/online/push_service.dart` som `_kVapidKey`.
2. **Service worker** i `web/firebase-messaging-sw.js` håndterer
   baggrunds-events.
3. **Token registreres** i `users/{uid}.fcmTokens` ved opt-in.
4. **Cloud Function** afsender og rydder op i ugyldige tokens.

Vi valgte browser-push (FCM) fremfor email fordi:

- Hurtigere — invitation rammer låseskærmen, ikke en indbakke.
- Email kræver SMTP-konfiguration og DNS (SPF/DKIM).
- I-app-banner dækker brugere uden push-tilladelse.

---

## 4. Build & deploy — GitHub Actions

**Valgt:** Single workflow `.github/workflows/deploy.yml` der både tester
og deployer.

**Pipeline:**

1. `flutter analyze --no-fatal-infos` (info-niveau lints fælder ikke build)
2. `flutter test` — inkl. 5 hele spil simuleret af AI
3. `flutter build web --release`
4. Playwright end-to-end (artefakt + `/test-report/` på hosting)
5. `firebase deploy --only hosting`
6. `firebase deploy --only firestore:partners:rules`
7. `npm --prefix functions install` → `firebase deploy --only functions`

**Hvorfor ét workflow:** Tre separate workflows ville have skullet dele
build-output; her bygger vi én gang og deployer i samme job. Total tid:
~6–8 minutter.

**Hvorfor `--no-fatal-infos`:** Flutter info-lints (fx `withOpacity`
deprecation) ændrer sig pr. SDK-version. Vi vil ikke have at en SDK-bump
fælder produktion.

**Service account:** `FIREBASE_SERVICE_ACCOUNT` som GitHub secret. Skal have
*Firebase Admin*, *Cloud Functions Admin* og *Service Account User* roller
for at functions-deploy virker.

---

## 5. Test-strategi (tre niveauer)

| Niveau | Værktøj | Dækker | Tid |
|--------|---------|--------|-----|
| Engine | `flutter test` | Regler, AI, 5 fulde spil | ~10 s |
| Integration | `flutter test integration_test/` | Widget-tree, navigation | ~30 s |
| End-to-end | Playwright + Chromium | Booter i rigtig browser, ingen console-fejl | ~60 s |

**Hvorfor tre niveauer:** Hver fanger en specifik fejlklasse:

- Engine-tests opdager regel-fejl uden at åbne en browser. Hurtigt
  feedback-loop ved regel-iterationer (UD-felt, split-7).
- Integration fanger Widget-træ-fejl (provider scoping, navigator stack).
- Playwright fanger byggefejl der kun manifesterer i en rigtig browser
  (CORS-headers, service worker, manifest).

In-app **Selvtest**-skærmen kører samme engine-tests live på
partners.vejleaa.dk — så man kan verificere produktion fra telefonen
uden adgang til CI.

---

## 6. Spillogik — egne valg

### Sealed-lignende `MoveStep`

Træk er værdiobjekter (`AdvanceMove`, `ReverseMove`, `ExitMove`,
`SwapMove`, `HomeStretchMove`). Spillets engine accepterer kun
forud-genererede træk fra `Rules.generateMoves()`. Konsekvens: UI'en
kan ikke konstruere et ulovligt træk — det compilerer fint, men engine
afviser det.

### 60-positions ring + 4 UD-felter

Brættet er en cirkulær buffer med 60 felter (indeks 0..59). UD-felterne
sidder på 0, 15, 30, 45. Hver spiller har 14 nummererede felter mellem
sit eget UD-felt og næste spillers UD-felt.

**UD-feltets særregel:** Kun ejeren kan bruge sit UD-felt. Andre spillere
"springer over" feltet uden at det tæller. Dette er kodet i `_advanceFrom`
og `_tryReverse` i `lib/game/rules.dart`, og er den vigtigste regel at
forstå før man retter brik-bevægelse.

### `regler.md` som "ene sandhed"

Alle reglerne er beskrevet i `docs/regler.md` med konkrete eksempler.
Det er kilde-dokumentet — hvis koden og `regler.md` modsiger hinanden,
er det `regler.md` der er retfærdig, og koden skal rettes.

---

## 7. Hvad vi *ikke* valgte

- **WebSocket-server til realtime-online.** Firestore-snapshots dækker
  realtime fint for et turn-baseret spil. Latency på 200–500 ms er ikke
  mærkbar når du venter på modspillerens tur.
- **Stripe/payment.** Ingen monetisering planlagt.
- **Egen mobil-app i App Store / Play Store.** Web som PWA dækker behovet
  — installation via "Add to Home Screen".
- **Egen analytics-stack.** Firebase Analytics er gratis og findes allerede.
- **Tailwind/CSS-framework.** Flutter web bruger ikke CSS for komponenter.

---

## 8. Når noget skal udskiftes

Før vi udskifter noget i denne stack, skal vi kunne svare ja til mindst ét:

1. Den nuværende løsning er i sit slut-loop (deprecated, ikke længere
   vedligeholdt).
2. Et konkret krav (ikke "nice to have") er ikke længere muligt.
3. Vi har målt et performance- eller cost-problem som ikke kan mitigeres.

Et "den nye X er smartere"-argument tæller ikke alene. Vi har bygget op
omkring denne stack og hver udskiftning koster mere end den giver.
