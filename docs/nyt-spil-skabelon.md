# Sådan sætter du et nyt spil-projekt op med Claude

**Formål:** Dette dokument er en *briefing-skabelon* du kan udfylde og give
mig (eller en anden agent) når du vil bygge et nyt spil. Det samler det
gode fra Partners + de erfaringer vi lærte den hårde vej. Hvis du svarer
på spørgsmålene i sektion A og afkrydser sektion B, kan vi springe
1–2 dage med edge-case-iterationer over.

---

## A. Spil-briefen (du udfylder)

Kopier denne sektion til en ny fil (fx `docs/brief.md` i det nye repo) og
udfyld den. Jo mere konkret, jo færre runder.

### A1. Hvad er spillet?

- **Navn:**
- **Type:** (kortspil / brætspil / tile-laying / trick-taking / …)
- **Spillere:** (antal, hold/individuelt, partnerskaber?)
- **Vinder-betingelse:** (helt præcis, fx "alle 8 brikker i målbås" eller
  "først til 500 point" eller "sidste spiller med kort på hånden")
- **Gennemsnitlig spillængde:** (min, så vi ved om "gem og fortsæt" er
  vigtigt)

### A2. Spil-state — den vigtigste sektion

Beskriv hvad der findes på "brættet" eller i spil-state. Brug eksempler,
ikke prosa.

- **Komponenter:** (kort? brikker? terninger? markører?)
- **Plads/områder:** (antal felter, zoner, stakke)
- **Information per komponent:** (fx "et kort har: farve, værdi, evne")

> *Læring fra Partners: vi byggede "ringen" som flydende konstanter i
> board.dart og fortrød. Geometri skal være en funktion af spilleret antal
> fra dag 1.*

### A3. Reglerne — med konkrete eksempler

For **hver** regel, giv mindst ét eksempel med tal eller positioner. Ikke
"man rykker frem" — men "står min brik på 14 og jeg spiller 7, lander
jeg på 21". Eksempler du *bør* skrive ned:

- **Normal tur:** Hvad sker der i en almindelig tur, trin for trin?
- **Hver kort/komponent-type:** Hvilken effekt? Hvilke valg?
- **Slag/konflikt:** Hvad sker der når to brikker mødes? Egne vs. modspillere?
- **Specialregler:** Lister af "kun hvis", "undtagen når", "hvis ingen
  andre…". Disse er værd at give 2 eksempler hver — det er her bugs bor.
- **Endgame:** Hvordan slutter spillet? Hvad sker der i sidste tur?
- **Ulovlige træk:** Hvad må man IKKE gøre? Hvad sker der hvis spilleren
  ikke kan trække?

> *Læring fra Partners: vi rettede UD-felt-reglen 4–5 gange. Hver runde
> gættede jeg fra din naturlige sprog-beskrivelse, kodede, du fandt edge-
> casen. Hvis vi havde haft "ud-felt skal aldrig nås af andre — eksempel:
> felt 56 + 7 = hus 3" fra start, var koden rigtig første gang.*

### A4. Hvor skal det køre?

- [ ] Web (browser) — primært?
- [ ] iOS
- [ ] Android
- [ ] Desktop

### A5. Online eller kun lokalt?

- [ ] Kun lokal vs. AI (ingen backend nødvendig)
- [ ] Online mod venner (kræver Firebase eller lign.)
- [ ] Begge dele
- [ ] Skal kunne genoptages efter browser-luk?

### A6. Skal der være konti?

- [ ] Nej — bare et navn ved start
- [ ] Ja — så folk kan genfinde statistik, venner, igangværende spil
- [ ] Hvilke login-metoder? (Google? Email?)

### A7. Hvad skal *ikke* med?

Lige så vigtigt som hvad der skal med. Eksempler:

- "Ingen monetisering"
- "Ingen ranking/Elo"
- "Ingen chat"

---

## B. Default-stack (kopiér fra Partners — virker)

Disse valg holder vi medmindre du har en grund til at fravælge.
Afkryds for at bekræfte, eller skriv en grund til at ændre.

- [ ] **Flutter + Dart** (én kodebase, web/iOS/Android)
- [ ] **Riverpod** (state management)
- [ ] **Firebase Auth** (hvis konti)
- [ ] **Firestore navngiven database** (ikke default — vælg et navn op front)
- [ ] **Firebase Hosting** (custom domain via DNS)
- [ ] **GitHub Actions CI** (test + build + deploy i ét workflow)
- [ ] **Playwright** (browser-smoke-test, ikke fuld E2E)
- [ ] **Cloud Functions** (kun hvis push/server-logik kræves)
- [ ] **FCM** (kun hvis push kræves)

**Hvad fravælger vi som default?** Realtime via WebSocket (Firestore-
snapshots dækker turnbaseret), Stripe (ingen monetisering), egne mobile
app-store-udgivelser (PWA dækker), Tailwind/CSS (Flutter har egen render).

---

## C. Ground rules — lærdom fra Partners

Disse er ikke til debat. De er der fordi vi har brændt fingrene.

### C1. `docs/regler.md` SKAL skrives FØR koden

- Reglerne på dansk med konkrete eksempler (tal og positioner)
- Hver edge-case får mindst ét eksempel
- Hvis kode og `regler.md` modsiger hinanden, er det `regler.md` der er
  rigtig — koden rettes til
- Når du opdaterer `regler.md`, sig det eksplicit ("jeg har opdateret
  punkt 5") så vi ikke arbejder på forældet kontekst

### C2. Regel-tests FØR engine-implementation

For hver regel i `regler.md` skal der være mindst én `flutter test` der
asserter den. Eksemplerne i `regler.md` bliver tests direkte:

```dart
test('felt 56 + 7 ender i hus 3 (UD springes over)', () {
  final pos = rules.advance(BoardPosition(56), 7, player: 0);
  expect(pos, HomeStretchPosition(0, 3));
});
```

Dette er den eneste måde at undgå at jeg genintroducerer en bug du
allerede har påpeget i en anden runde.

### C3. Geometri/topologi er rene funktioner — ikke konstanter

Antal felter, positioner, vinkler beregnes fra `playerCount` og
`homeStretchLength`. Aldrig `const int kFelter = 60;` i board.dart.

### C4. `CLAUDE.md` med non-obvious facts i roden af repoet

Fra dag 1. Eksempel:

```
# Partners — non-obvious facts

- Firestore: navngiven database 'partners', ikke (default).
- Cloud Functions region: europe-west1.
- Branch: claude/partners-game-app-Z6NJW. Push hertil.
- Spil-state: 60-positions ring, 4 UD-felter på 0/15/30/45.
- UD-felt: kun ejeren bruger det; andre springer over.
```

Når context compacteres mister jeg ellers disse hver gang.

### C5. UI-iterationer kræver skærmbilleder

Tekst-beskrivelser af layout ("der er stadig tom luft", "kortet ser
forkert ud") koster mange runder. Send et screenshot + 1 pile-annotation
("her" / "denne knap skal til højre").

### C6. Agenter får smalle mandater

Når jeg spawner parallelle agenter, skal hver have:
- Én fil eller ét feature-område
- Én adfærdsændring beskrevet med eksempel
- Krav om at returnere diff'en, ikke en "rapport"

Ikke "fix online robusthed" — men "tilføj reconnect-logik til
online_service.dart, så watchGame() retries hvert 3. sek ved netværksfejl".

### C7. CI-pipeline fra første commit

Selv før der er noget at deploye:
- `flutter analyze --no-fatal-infos`
- `flutter test`
- (deploy-trin tilføjes når der er hosting-target)

Så enhver regel-regression fanges automatisk.

---

## D. Filer der oprettes ved projektstart

Når sektion A og B er udfyldt, bygger jeg disse i denne rækkefølge:

1. `CLAUDE.md` — non-obvious facts (sektion C4)
2. `docs/regler.md` — reglerne fra A3, formateret
3. `docs/teknologi.md` — kopi af Partners-versionen, justeret
4. `pubspec.yaml` + Flutter-skelet
5. `lib/models/` — domænemodeller for spil-state (A2)
6. `lib/game/rules.dart` — regel-engine med sealed `Move`-typer
7. `test/rules_test.dart` — én test per eksempel i `regler.md`
8. `lib/ui/screens/setup_screen.dart` + `game_screen.dart` — minimum UI
9. `.github/workflows/deploy.yml` — CI fra dag 1
10. Firebase-opsætning (kun hvis online valgt i A5/A6)

Vi venter med visuelt design indtil engine + tests virker. Det er den
billigste rækkefølge.

---

## E. Tjek inden vi koder

Før jeg trykker "go", skal du kunne svare ja til:

- [ ] Jeg har udfyldt sektion A med konkrete eksempler, ikke prosa
- [ ] Hver regel i A3 har mindst ét talt eksempel
- [ ] Jeg har afkrydset sektion B eller skrevet en grund til afvigelse
- [ ] Jeg har læst sektion C og er enig i ground rules
- [ ] Jeg ved hvad spillet *ikke* skal kunne (sektion A7)

Hvis ja → vi går i gang og er live med en spilbar prototype på 1–2
arbejdsdage.

---

## F. Hvis du senere ændrer mening

Det er fint. Men vær eksplicit:

- "Jeg har opdateret `regler.md` punkt 6" → så ved jeg at læse det igen
- "Drop sektion B-valget om Firestore — vi bruger Supabase i stedet" →
  klar besked, ikke "kan vi ikke prøve noget andet?"
- "Den her regel virker ikke i praksis, lad os ændre den til..." → så
  opdater vi `regler.md` *først*, så testen, så koden

Tre-trins-rytmen (regler → test → kode) er hvad der gør at vi ikke
genintroducerer gamle bugs.
