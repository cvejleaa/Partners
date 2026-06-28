# Partners — regelspecifikation (den ene sandhed)

Dette dokument beskriver **alle spillets regler, én for én**. Det er vores fælles
kilde: vil du ændre en regel, så ret teksten her (gerne med `**ÆNDRING:**` foran),
så oversætter jeg den til koden og opdaterer tutorialen.

> ⚠️ Spillet **læser ikke** dette dokument automatisk. Kerne-reglerne er kode.
> Kun **kort-funktionerne** (afsnit 4) er data, du selv kan ændre i app'en.

For hver regel står der hvor den bor:
- 🟢 **DATA (admin)** — kan ændres live på Admin-skærmen i app'en, ingen kode.
- 🔧 **KODE** — kræver ændring i en Dart-funktion (af udvikler).

Status: opdateret efter "UD-felt: kun ejeren bruger det"-ændringen.

---

## 1. Spillere og hold

- 4 spillere sidder med uret: plads 0, 1, 2, 3.
- To hold: **Hold A = plads 0 + 2**, **Hold B = plads 1 + 3**.
- Din **makker** er spilleren **overfor** dig (plads + 2).
- 🔧 KODE: `Player.teamIndex` (`index % 2`), `Player.partnerIndex` (`(index+2) % 4`).

## 2. Mål og sejr

- Hver spiller har **4 brikker**. Et hold har altså 8 i alt.
- Et hold **vinder**, når **alle 8 holdbrikker** står i hjemstrækket.
- 🔧 KODE: `GameState.teamHasWon`.

## 3. Brættet (geometri)

- Banen er en **ring med 60 felter**.
- Hver spiller "ejer" et kvarter: **1 UD-felt + 14 nummererede felter (1–14)**.
- Ringindeks: spiller `p`'s **UD-felt = indeks `15·p`** (0, 15, 30, 45).
  Spiller `p`'s **felt 1–14 = indeks `15·p + 1` … `15·p + 14`**.
- Hver spiller har et **hjemstræk på 4 felter** (slot 0–3, 0 er nærmest indgangen).
- Hver spiller har en **startcirkel** (bås) med plads til 4 brikker.
- 🔧 KODE: `BoardGeometry` (`trackLength = 60`, `homeStretchLength = 4`),
  `startTrackIndexFor`.

## 4. Kortenes funktioner 🟢 DATA (admin)

Hvad hvert kort gør er **data** og kan ændres live på **Admin-skærmen**
(gemmes i Firestore `config/cardRules`; bruges af både motor og tutorial).
Standard-opsætningen (`CardRules.defaults()`):

| Kort | Funktion (standard) |
|------|---------------------|
| **UD-kort** (hjerter) | Kun ud af start |
| **Es (A)** | Ud af start **eller** ryk **1 eller 11** frem |
| **2** | 2 frem |
| **3** | 3 frem |
| **4** | 4 frem **eller** 4 tilbage |
| **5** | 5 frem |
| **6** | 6 frem |
| **7** | **Split**: 7 træk fordelt (se afsnit 9) |
| **8** | 8 frem |
| **9** | 9 frem |
| **10** | 10 frem |
| **Knægt (J)** | 11 frem *(byt kan slås til i admin — se afsnit 10)* |
| **Dame (Q)** | 12 frem |
| **Konge (K)** | Ud af start **eller** 13 frem |

Hver kort-konfiguration har disse knapper i admin: `exitStart` (ud af start),
`forwardSteps` (liste af fremad-tal), `backwardSteps` (tilbage-tal), `splitTotal`
(split-sum, fx 7), `swap` (byt to brikker).
🔧 KODE: strukturen i `CardRuleConfig` / `CardRules` (`lib/game/card_rules.dart`).

## 5. Ud af start 🔧 KODE

- For at få en brik ud af start skal du spille et **UD-kort, Es eller Konge**
  (alt med `exitStart`).
- Brikken sættes på **dit eget UD-felt** (indeks `15·p`).
- Hvis dit UD-felt allerede har **én af dine egne** brikker, stables den nye
  ovenpå. En modstander kan aldrig stå der (alle andre springer feltet over,
  jf. afsnit 6), så der er ikke noget slag eller brænd at håndtere ved exit.
- 🔧 KODE: `Rules._exitStartMoves`.

## 6. UD-feltets særregel (vigtig!) 🔧 KODE

> Dette er reglen vi har rettet flere gange — her er den endegyldige version.

- **UD-feltet kan kun bruges af den spiller det tilhører.**
- **Alle andre spillere springer et TOMT fremmed UD-felt over UDEN at tælle
  det** — dvs. de flytter fra **felt 14 direkte til felt 1** (gælder begge
  retninger).
- **Står der ≥1 brik på et fremmed UD-felt SPÆRRER feltet fuldstændigt** —
  ingen anden spiller kan passere det, hverken fremad eller bagud. Trækket
  er ulovligt. Denne regel gælder uanset om brikken på UD-feltet tilhører
  ejeren selv eller (i teorien) nogen andre — i praksis kan kun ejeren stå
  der, og deres brik gør feltet til en mur for alle andre.
- En anden spiller kan **aldrig lande på** et fremmed UD-felt — det er som
  om feltet ikke findes som landingsplads for dem.
- **Ejeren** bruger sit UD-felt **kun som exit-plads**: en brik der kommer ud
  af start placeres der, og en brik der under en bevægelse vender tilbage til
  UD-feltet efter en hel omgang **drejer ind i hjemstrækket**. Selve UD-feltet
  er IKKE et tællende ringfelt — det har ingen rolle for distancer.
- Konsekvens: en brik på sit eget UD-felt er reelt **sikker** og virker som
  en blokade for alle modstandere der prøver at passere.
- 🔧 KODE: `Rules._advanceFrom` (fremad), `Rules._tryReverse` (tilbage),
  `Rules._exitStartMoves` (exit), `Rules._entryOwner`.

**Eksempel 1 (TOMT fremmed UD springes over):** Rød (plads 0) har UD-felt på
indeks 0. Spiller 1's UD-felt (indeks 15) er tomt. Blå spiller en 5'er fra sit
felt 13: blå rykker forbi spiller 1's UD-felt uden at tælle det og lander 5
*tællende* felter fremme. Blå kan aldrig lande på indeks 15.

**Eksempel 1b (BESAT fremmed UD spærrer):** Røds UD-felt (indeks 0) har 2 røde
brikker stående. Gul står på sit felt 10 (indeks 55) og spiller en Konge (13
frem). Gul ville skulle: 55 → 56 → 57 → 58 → 59 → \[UD spærret\]. Trækket er
**ulovligt** — der bliver slet ikke genereret nogen forward-move for gul med
det kort. Lige så for tilbage-retning: en gul brik på rødt felt 5 kan ikke
rykke 6 baglæns gennem røds besatte UD.

**Eksempel 2 (eget UD springes over → drej ind i hjemstræk):** Spiller 0's brik
står på felt 56 og spiller en 7'er. Brikken besøger:

| Skridt | Position |
|-------:|----------|
| 1 | felt 57 |
| 2 | felt 58 |
| 3 | felt 59 |
| — | (UD-felt idx 0 springes over — ingen position landes) |
| 4 | hus 0 |
| 5 | hus 1 |
| 6 | hus 2 |
| 7 | hus 3 (slut) |

UD-feltet er aldrig en landings-position; det springes over og bevægelsen
fortsætter ind i hjemstrækket. En 8'er fra felt 56 ville kræve slot 4 — som
ikke findes — og er derfor ulovligt.

## 7. Bevægelse: frem og tilbage 🔧 KODE

- Et fremad-tal `N` flytter en brik `N` **tællende** felter frem (fremmede
  UD-felter tæller ikke, jf. afsnit 6).
- Et tilbage-tal flytter tilsvarende baglæns (fremmede UD-felter springes over).
- Man må gerne **passere** andres brikker (også stakke) — passage blokerer ikke.
- 🔧 KODE: `Rules._advanceFrom`, `Rules._tryReverse`.

## 8. Slag, stak og "dobbelt brænder" 🔧 KODE

- Lander du på et felt med **præcis én** anden brik (modstander **eller makker**):
  den brik slås **hjem** til sin startcirkel.
  - **Du må gerne slå din egen makkers brik hjem** — det er bare sjældent klogt.
- Lander du på et felt med en af **dine egne** brikker: I **stables** (ingen slås).
- Lander du på et felt med **2+ andre** brikker (en **"dobbelt"**): det er lovligt
  at lande, men **DIN egen brik slås hjem** — dobbelten "brænder" dig. De andres
  brikker bliver stående.
- En **dobbelt** (2+ brikker) kan ikke byttes (afsnit 10).
- 🔧 KODE: `Rules._landing` (felt-udfald), `GameEngine.applyMove` (udførsel),
  `MoveStep.burnsMover` (selv-brænd-flag).

## 9. 7'eren (split) 🔧 KODE

- En 7'er giver **7 træk** der kan **fordeles** over en eller flere af dine
  brikker i spil.
- Du **skal som udgangspunkt bruge alle 7 træk** — kan de ikke alle placeres,
  kan 7'eren ikke spilles sådan.
- **Undtagelse (afslut spillet):** Du **må** bruge **færre end 7** felter,
  hvis den kortere fordeling **afslutter spillet** — dvs. holdet (dine + din
  makkers 4 brikker = alle 8) derved står i hus. Eksempel: mangler I kun 4
  felter for at få de sidste brikker hjem, må I nøjes med at rykke 4 af de 7.
  Uden for denne situation SKAL alle 7 bruges.
- Hver brik flyttes **kun én gang** i et 7-træk; brikkerne flyttes efter hinanden.
- Hvert delskridt beregnes på brættet **efter** de foregående delskridt — fx
  frigør en brik der rykker ud af hjem-slot 1 pladsen, så en anden brik kan
  lande dér i samme 7-træk.
- Hvert delskridt skal være lovligt (slag, brænd osv. gælder pr. delskridt).
- **Partner-overløb:** Hvis du undervejs får **alle dine egne** brikker i mål
  (låst i hjemstrækket) ved kun at bruge nogle af de 7 træk, **må** de
  overskydende træk lægges på din **makkers** brikker.
- 🔧 KODE: `Rules._splitMoves`.

## 10. Knægt-byt (kun hvis slået til i admin) 🟢 DATA + 🔧 KODE

- Hvis `swap` er slået til på et kort (standard: **fra** — Knægt er 11 frem):
  kortet **bytter to brikker** på banen mellem **to forskellige spillere**
  (fx makker ↔ modstander). Man må aldrig bytte to af samme spillers brikker.
- Man kan **ikke** bytte:
  - en brik i startcirklen eller i hjemstrækket (kun brikker på banen),
  - en brik der indgår i en **dobbelt** (2+ på samme felt),
  - en brik der står på **sit eget UD-felt** (beskyttet, jf. afsnit 6).
- 🟢 DATA: om et kort kan bytte (admin). 🔧 KODE: `Rules._swapMoves`.

## 11. Hjemstræk 🔧 KODE

- En brik drejer ind i sit **eget** hjemstræk, når den efter en hel omgang når
  tilbage til sit eget UD-felt.
- Man kan **ikke** rykke længere end hjemstrækkets bagende (slot 3) — et træk der
  ville overskride, er ulovligt.
- En brik i hjemstrækket kan kun rykke **længere ind** (aldrig ud på banen igen)
  og kan ikke slås.
- En egen brik længere inde i hjemstrækket **blokerer** for at en anden egen brik
  rykker forbi/oveni.
- 🔧 KODE: `Rules._advanceFrom` (hjemstræk-grenen + indgangs-tjek).

## 12. Spil videre på makkeren 🔧 KODE

- Når **alle dine egne** brikker er i mål, spiller du videre på **makkerens**
  brikker, indtil holdet har alle 8 hjemme.
- 🔧 KODE: `Rules.legalMoves` (`allOwnHome` → spil på partner).

## 13. Runden: kortbytte og at sidde over 🔧 KODE

- Hver runde får alle **4 kort** på hånden.
- Ved rundens start vælger hver spiller **ét skjult kort**, som byttes med
  makkeren.
- Kan du **ikke** lave et lovligt træk med nogen af dine kort, **smider du hele
  hånden** og **sidder over** resten af runden.
- Samme spiller starter i **3 runder**, derefter roterer starteren med uret.
- 🔧 KODE: `GameEngine` (`startNewHand`, `passHand`, exchange-håndtering),
  `app.dart` (starter-rotation).

## 14. AI og online (kort) 🔧 KODE

- AI'en undgår at slå sin makker hjem og undgår at brænde sig selv (men gør det,
  hvis det er eneste lovlige træk).
- Online: hvis en spiller er væk, kan en AI overtage dens tur efter en timeout
  (kun værten skriver, så ingen dobbelt-træk).
- 🔧 KODE: `lib/game/ai/heuristic_ai.dart`, `lib/online/online_service.dart`.

---

## Sådan ændrer du en regel

1. **Kort-funktion** (afsnit 4 / 10): Gå til **Admin-skærmen** i app'en og ret
   kortet. Træder i kraft med det samme (også i tutorialen). Ingen kode.
2. **Kerne-regel** (alle 🔧): Skriv din ønskede ændring her i dokumentet (fx
   `**ÆNDRING:** UD-feltet skal …`), så retter jeg funktionen + tutorialen og
   opdaterer dette dokument.

## Hvor reglerne bor i koden (oversigt)

| Emne | Fil / funktion |
|------|----------------|
| Brætgeometri | `lib/models/board.dart` |
| Kort-data (admin) | `lib/game/card_rules.dart` + Admin-skærm → Firestore `config/cardRules` |
| Bevægelse, UD-skip, slag, brænd, hjemstræk | `lib/game/rules.dart` |
| Udførsel af træk | `lib/game/game_engine.dart` |
| 7-split | `Rules._splitMoves` |
| Byt | `Rules._swapMoves` |
| AI | `lib/game/ai/heuristic_ai.dart` |
| Online/overtagelse | `lib/online/online_service.dart` |
| Tutorial-tekst (vises til spillere) | `lib/ui/screens/tutorial_screen.dart` |
| Selvtest af regler | `lib/game/self_test.dart` + `test/rules_test.dart` |
