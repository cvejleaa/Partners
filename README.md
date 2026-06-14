# Partners

En digital udgave af det danske brætspil **Partners** til iOS og Android.
Du spiller alene mod 3 AI-modstandere.

Status: **MVP / spilbar prototype**.

## Funktioner

- Indtast navn og vælg farve for hver af de 4 spillere.
- 4 brikker pr. spiller, 4 kort pr. hånd.
- Inden hver runde bytter partnere 1 kort skjult.
- Klassiske kortregler (Es, Konge, Dame, Knægt, 4 frem/tilbage, 7 splittes,
  m.fl.). Detaljerede defaults er listet i `lib/game/rules.dart`.
- Slag, hjemstræk, og vinder-detektion.
- AI-modstandere (heuristisk strategi).

## Projektstruktur

```
lib/
├── main.dart            App entry
├── app.dart             MaterialApp + Riverpod state controller
├── models/              Domænemodeller (kort, brik, bræt, spil-state)
├── game/                Spillogik
│   ├── deck.dart
│   ├── rules.dart       Generering af lovlige træk
│   ├── game_engine.dart Hånd-lifecycle, anvendelse af træk
│   └── ai/              Heuristisk AI
└── ui/
    ├── screens/         Setup-, spil- og slut-skærme
    └── widgets/         BoardView (CustomPainter), kort, paneler
test/                    Unit-tests for regler, engine og AI
```

## Kom i gang

Kræver [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.19.

```bash
flutter pub get
flutter analyze
flutter test
```

## Test-pakken (komplet verifikation af MVP)

Spillets logik testes på 3 niveauer.

### 1) Engine-/regel-tests (Dart, hurtig)

Verificerer regler, vinder-detektion, kortbytte og at AI kan spille **et helt
spil til ende** uden ulovlige træk. Kører på få sekunder.

```bash
flutter test
```

Bemærk: `test/full_game_test.dart` simulerer **5 komplette spil** med 4 AI-spillere
og verificerer hver hånd. Dette er den mest pålidelige test af spillogikken.

### 2) Flutter UI integration test

Driver setup-skærmen via det rigtige widget-træ og verificerer flow til
spilskærmen. Kører som et embedded device test.

```bash
flutter test integration_test/full_game_walkthrough_test.dart
```

### 3) Playwright (browser end-to-end, hele spillet via JS-bridge)

Bygger appen til web, server den lokalt, og lader Playwright spille et helt
spil via en JS test-bridge — `window.partnersTest` aktiveres når URL'en
indeholder `?test=1`. Tager screenshots ved exchange-, play- og game-over-faser.

```bash
# Engang: installer Node-deps
npm install
npx playwright install --with-deps chromium

# Byg web + kør alle Playwright tests
flutter build web --release --base-href "/"
npm test

# Eller separat
npm run build:web
npm run serve:web &              # i baggrunden på :8080
npx playwright test               # i et andet terminal-vindue
npx playwright show-report        # se HTML-rapport
```

Tests:
- `tests/playwright/smoke.spec.ts` — app booter, ingen console-fejl, screenshots
  på desktop + mobile viewport
- `tests/playwright/full-game.spec.ts` — bridge er eksponeret, AI spiller et
  helt spil til ende, vinderens 8 brikker er alle i hjemstrækket, screenshots

### Hvad de tre niveauer dækker

| Niveau | Verificerer | Når noget fejler her... |
|--------|-------------|--------------------------|
| `flutter test` | Spillogik, regler, AI, vinder | Bug i `lib/game/` |
| Integration | UI-flow, navigation | Bug i `lib/ui/` widget-træ |
| Playwright | Web build, JS-bridge, browser-renderering | Bug i build/deploy eller test-bridge |

### Kør på iOS-simulator (kræver macOS + Xcode)

```bash
flutter run -d ios
```

### Kør på Android-emulator

```bash
flutter run -d android
```

### Kør i browser (hurtigt sanity check)

```bash
flutter run -d chrome
```

### Byg release

```bash
flutter build apk --release        # Android
flutter build ios --release         # iOS (kræver Mac/Xcode)
```

## Regler (default i denne MVP)

- 4 spillere, 2 hold à 2. Partnere sidder overfor hinanden (indeks 0+2 og 1+3).
- 4 brikker pr. spiller, 4 kort pr. hånd.
- Inden hvert "play"-fase bytter partnere 1 kort skjult.
- Es: 1 eller 11 frem, eller ud af start.
- Konge: 13 frem, eller ud af start.
- Dame: 12, Knægt: 11, 10–6 og 3–2: tilsvarende skridt frem.
- 5: 5 frem.
- 4: 4 frem eller 4 baglæns.
- 7: total 7 felter splittet over en eller flere af spillerens egne brikker.
- Lander man på modstanderbrik → den ryger retur til start.
- Lander man på egen brik → ulovligt.
- I hjemstrækket må man ikke springe over egne brikker.
- Kan man ikke spille noget kort, smides ét kort uden effekt.
- Når dine 4 brikker er hjemme, spiller du videre på din makkers brikker.
- Et hold vinder, når alle 8 brikker er i målbåsene.

Hvis I lokalt spiller med andre detaljer (knægt = byt brikker, 8 = spring,
5 = flyt modstander), kan reglerne let justeres i `lib/game/rules.dart`.

## Deploy til Firebase Hosting (partners.vejleaa.dk)

### Engangsopsætning

1. **Opret Firebase-projekt** (eller brug eksisterende):
   - Gå til https://console.firebase.google.com → "Add project".
   - Når projektet er oprettet, find **Project ID** (fx `partners-vejleaa`).
2. **Indsæt Project ID** i `.firebaserc`:
   ```bash
   # Erstat REPLACE-WITH-YOUR-FIREBASE-PROJECT-ID med dit Project ID
   ```
3. **Aktivér Hosting** i Firebase-konsollen (Build → Hosting → Get started).
4. **Installer Firebase CLI** lokalt (engang pr. maskine):
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

### Manuel deploy fra din maskine

```bash
flutter pub get
flutter build web --release --base-href "/"
firebase deploy --only hosting
```

Outputtet viser et midlertidigt URL som `https://<project-id>.web.app`. Test
spillet der først.

### Custom domain — partners.vejleaa.dk

1. I Firebase Console → Hosting → **Add custom domain** → indtast
   `partners.vejleaa.dk`.
2. Firebase viser et TXT-record til ejerskabsverifikation (læg det på
   `vejleaa.dk` hos din DNS-udbyder).
3. Når TXT'en er bekræftet, viser Firebase **to A-records** (eller en CNAME).
   Læg dem på `partners`-subdomænet:
   ```
   partners.vejleaa.dk.   A   151.101.1.195
   partners.vejleaa.dk.   A   151.101.65.195
   ```
   (Brug de eksakte IP'er Firebase viser dig — de kan ændre sig.)
4. Vent på DNS-propagering (få minutter til et par timer). Firebase udsteder
   automatisk SSL-certifikat.

### Auto-deploy ved push (GitHub Actions)

Workflow'et `.github/workflows/deploy.yml` deployer automatisk ved push til
`main`. Det kræver to repository secrets i GitHub (Settings → Secrets and
variables → Actions):

- `FIREBASE_SERVICE_ACCOUNT` — JSON-indholdet af en service-account-nøgle.
  Lav den i Firebase Console → Project Settings → Service accounts →
  "Generate new private key".
- `FIREBASE_PROJECT_ID` — dit Project ID (samme som i `.firebaserc`).

Når begge secrets er sat, deployer hvert push til `main` automatisk til
`https://partners.vejleaa.dk`.
