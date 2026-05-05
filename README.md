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
