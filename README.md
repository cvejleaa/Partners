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

## Admin — justér kortfunktioner

På forsiden er der et **tandhjuls-ikon** (Admin). Her kan du for hvert kort
markere hvilke funktioner det har: *rykke en brik ud*, *rykke frem* (med antal
felter, fx `1, 11`), *rykke tilbage*, *7-split (deles)* og *byt to brikker*.
Ændringer gemmes lokalt og bruges næste gang du starter et spil. Reglerne kan
nulstilles til standard.

Brikker kan stå flere på samme felt (også ud-feltet). Står der **2+ egne
brikker** på et felt ude, er det en *beskyttet dobbelt* — de kan ikke slås hjem
eller byttes (modstandere må gerne passere forbi). Brikker der er nået i mål
(hjemstrækket) kan ikke komme ud på banen igen, og en brik der kommer ud af
start lander altid på sit eget ud-felt.

**Ud-felter:** Man kan ikke lande på en *anden* spillers ud-felt — derfor kan en
brik på sit eget ud-felt aldrig slås hjem. Et **besat ud-felt spærrer**: ingen
kan passere forbi det, så længe der står en brik på det.

**Sidde over:** Kan man ikke rykke nogen brik med kortene på hånden, smider man
hele hånden og sidder over resten af runden.

## Selvtest fra brugerfladen (ingen kode/terminal)

Appen har en indbygget **Selvtest**-skærm. På forsiden (opsætning) er der et
ikon øverst til højre (✓). Den kører hele spil med 4 AI-spillere direkte i
browseren og viser grøn/rød resultat med statistik — uden at du skal røre kode
eller terminal. Den ligger med i den deployede app på partners.vejleaa.dk.

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

### 3) Playwright (browser smoke-test)

Bygger appen til web, server den lokalt, og verificerer at appen booter og
renderer i en rigtig browser uden console-fejl. Tager screenshots på desktop-
og mobil-viewport.

```bash
# Engang: installer Node-deps
npm install
npx playwright install --with-deps chromium

# Byg web + kør Playwright
flutter build web --release --base-href "/"
npm test

# Eller separat
npm run build:web
npm run serve:web &              # i baggrunden på :8080
npx playwright test               # i et andet terminal-vindue
npx playwright show-report        # se HTML-rapport
```

Tests:
- `tests/playwright/smoke.spec.ts` — app booter, ingen console-fejl, manifest
  tilgængelig, screenshots på desktop + mobile viewport

> Hele spillet gennemspilles i `flutter test` (5 spil) og kan desuden køres
> direkte i browseren via in-app **Selvtest**-skærmen — det er den anbefalede
> måde at se et helt spil verificeret i en UI.

### Hvad lagene dækker

| Niveau | Verificerer | Når noget fejler her... |
|--------|-------------|--------------------------|
| `flutter test` | Spillogik, regler, AI, 5 hele spil, vinder | Bug i `lib/game/` |
| Integration | UI-flow, navigation | Bug i `lib/ui/` widget-træ |
| Playwright | Web build booter og renderer i browser | Bug i build/deploy |
| In-app Selvtest | Hele spil + regler i browseren (synligt resultat) | Bug i `lib/game/` |

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

Projektet er allerede konfigureret mod Firebase-projektet `partners-8d4aa`
(`.firebaserc` + workflow). Den anbefalede vej er **auto-deploy via GitHub
Actions** (se nederst). Manuel deploy beskrives også herunder.

### Manuel deploy fra din maskine (valgfrit)

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

### Auto-deploy ved push (GitHub Actions) — det automatiske flow

Workflow'et `.github/workflows/deploy.yml` gør **alt automatisk**:
1. `flutter analyze` + `flutter test` (med JUnit-rapport som vises i Actions-UI)
2. `flutter build web --release`
3. Playwright end-to-end (rapport som artefakt + på `/test-report/`)
4. Deploy til Firebase Hosting (live → partners.vejleaa.dk)

Det kører ved push til `main` (og udviklingsgrenen) samt via **"Run workflow"**-
knappen i GitHub (Actions → Test & Deploy → Run workflow).

**Det eneste der mangler for at deploy virker:** ét repository secret i GitHub
(Settings → Secrets and variables → Actions → New repository secret):

- Navn: `FIREBASE_SERVICE_ACCOUNT`
- Værdi: hele JSON-indholdet af en service-account-nøgle fra
  Firebase Console → ⚙ Project Settings → Service accounts →
  "Generate new private key".

Project ID (`partners-8d4aa`) er allerede sat i workflow'et og `.firebaserc`.
Uden secret'en kører testene stadig (synlige i Actions-UI), men deploy springes
over.
