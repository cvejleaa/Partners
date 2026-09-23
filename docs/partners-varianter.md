# Partners — officielle varianter og kortspecifikationer

Research-grundlag til at implementere de officielle Partners-varianter i appen.
Alt indhold er baseret på offentligt tilgængelige kilder (webshops, regelsider,
anmeldelser samt Game InVentorS' officielle DM-guide, 4. udgave 2023, 17 sider —
den mest autoritative offentlige kilde). Kilder er angivet pr. afsnit; kendte
huller i det offentlige materiale er markeret med **[HUL]**.

Vigtig overordnet pointe: det officielle Partners bruger **ikke** almindelige
spillekort (ingen Es/Konge/Dame/Knægt/Joker). Alle udgaver har deres eget
specialkortspil. Netguider der beskriver Es/Konge/Joker-regler (fx Bog & Idé)
beskriver reelt den internationale Tock/DOG-familie og skal ikke bruges som
kilde til de officielle varianter.

## Oversigt

| Udgave | År | Spillere | Hold | Brikker | Kort |
|---|---|---|---|---|---|
| Partners (klassisk) | 1998 | 4 | 2 hold á 2 (diagonal makker) | 4 pr. spiller (16) | 56 |
| Partners Travel | 2025 | 4 | 2 hold á 2 | 4 pr. spiller (16) | Som klassisk |
| Partners+ | 2018 | 6 | 2v2v2 eller 3v3 | 4 pr. spiller (24) | 78 |
| Partners Duo | 2022 | 2 | Ingen (1 mod 1) | 6 pr. spiller (12) | 30 |
| Partners Trio | 2026 | 3 | Ingen (alle mod alle) | 4 pr. spiller (12) | 40 |
| Partners 25 år | 2023 | 4 | 2 hold á 2 | 4 pr. spiller (16) | Mix + nye kort |

---

## Fælles kernemekanik (grundmotoren)

Gælder alle udgaver, medmindre variantafsnittet siger andet.

### Bræt og brikker

- Cirkulær bane. Pr. spillerfarve: **14 nummererede felter**, en **startcirkel**
  (hjem/venteområde), et **startfelt** (unummereret indgangsfelt på banen) og et
  **slutfelt med 4 målcirkler**. Klassisk plade = 56 nummererede felter + 4
  unummererede startfelter (60 positioner på banen i alt). Partners+ afviger:
  13 nummererede felter pr. segment (84 positioner).
- **Startfeltet tæller aldrig med som felt**, når der flyttes — hverken på vej
  rundt eller på vej ind i slutfeltet (det har ikke noget nummer).
- Der spilles **med uret**. Kort erstatter terninger.

### At slå hjem og fredning

- Lander man på et felt med **én** modstanderbrik, slås den hjem til sin
  startcirkel.
- Lander man på et felt med **2+ brikker i samme farve**, er det ens **egen**
  brik, der slås hjem (de stående brikker er fredede).
- **To brikker i hver sin farve må aldrig dele felt** (DM-guiden s. 10).
- **Fredet** er: brikker i målcirklerne, og 2+ ens brikker på samme felt.
  Fredede brikker kan hverken slås hjem eller byttes. Der må gerne stå flere
  end to egne brikker på samme felt.
- Man må gerne slå sin egen brik hjem med vilje, selv om andre træk findes.

### Blokade

- En brik på sit **eget startfelt** spærrer passage i **begge retninger** for
  alle andres brikker (også baglæns med −4). Én brik er nok. Den spærrer ikke
  for ejeren selv. En brik i eget startfelt kan ikke byttes og kan reelt ikke
  røres af modstandere.
- 2+ ens brikker på et almindeligt felt spærrer **ikke** passage — de er kun
  fredede.

### Mål (slutfelt og målcirkler)

- Målcirklerne fyldes **indefra og ud**: første brik i inderste cirkel osv.
  En brik, der er "låst fast", er inaktiv resten af spillet.
- I målcirklerne kan brikker **ikke** springe over hinanden.
- −4-kortet og byttekortet kan **aldrig** bruges på brikker i målcirklerne.
- Det følgende om at rykke baglæns i hjemmefeltet er fra de oprindelige regler.
  Det bruges IKKE i klassisk, 25 år eller de øvrige varianter — men **Partners
  Duo følger æsken og HAR det** (ejer-valgt, se `regler.md` §11 og Duo-afsnittet).
- Passer kortets værdi ikke, **skal** de overskydende træk rykkes **baglæns**
  ("vende" på en fri målcirkel) — fx 5'er hvor 2 rækker: 2 frem + 3 tilbage.
- Turneringspræcisering (2023): flyttes en brik, der allerede står i
  slutfeltet, skal den enten kunne låses fast eller flyttes helt ud af
  slutfeltet — ellers må den slet ikke flyttes.

### Kortuddeling og bytte

- Hver spiller får **4 kort pr. runde** (alle udgaver, inkl. Partners+ —
  påstanden om 5 kort ved 6 spillere er en fejl fra unoregler.com).
- Samme kortgiver deler **3 gange i træk**, derefter går kortgiverrollen videre
  (med uret). Resterende kort blandes med de brugte af næste kortgiver.
- Første kortgiver: alle trækker ét kort; højeste værdi bliver kortgiver
  (byttekort og hjerter tæller 0; på flerværdikort tæller højeste værdi).
- **Makkerbyt**: efter hver uddeling **skal** partnerne bytte 1 kort, skjult og
  samtidigt. Ingen kommunikation/signalering om ønsker ("ikke fair play").
  Variant-afhængigt i Partners+ (se afsnittet) og erstattet af
  modstander-videregivelse i Trio.
- Spilleren til venstre for kortgiveren starter; derefter med uret, ét kort og
  ét træk pr. tur.

### Spillepligt og aflægning

- Har man et brugbart kort, **skal** man spille et. Byttekortet tæller som
  brugbart, selv uden egne brikker i spil.
- Kan intet kort bruges, smides **hele hånden**, og man sidder over til næste
  uddeling.
- "Bordet fanger": et spillet kort skal bruges, hvis muligt; er det umuligt,
  tages det tilbage og et andet brugbart kort spilles. En brik regnes for
  flyttet, når den er løftet fra sit felt.
- Spilles et kort før ens tur ved en fejl, skal samme kort spilles i egen tur,
  hvis muligt.

### Ud af start og vinderbetingelse

- **Kun kort med hjertesymbol** kan flytte en brik fra startcirklen ud på
  startfeltet. Ingen andre træk kan bringe brikker i spil.
- Når en spillers 4 brikker er i mål, spiller spilleren videre og må bruge
  **alle** sine kort på makkerens brikker (og byttekortet på modstanderne).
  Makkerbyt fortsætter.
- Holdet vinder, når **alle holdets brikker** er i mål (klassisk: 8).

---

## Partners (klassisk, 4 spillere)

- **Spillere/hold**: præcis 4, to hold á 2; makkeren sidder diagonalt overfor
  (fx rød+grøn og gul+blå).
- **Brikker**: 4 pr. spiller (16 i alt).
- **Kort**: 56 specialkort, **12 forskellige korttyper**, i alt
  **17 flyttemuligheder** (nogle kort har flere funktioner).
- Alder 8+, spilletid ca. 30-45 min.

### Kortliste

| Kort | Funktion(er) |
|---|---|
| Hjerterkort | KUN: flyt en brik fra startcirkel til startfelt. Ingen andre muligheder |
| 8 med hjerter | Valg: ud af start ELLER flyt en brik 8 felter frem |
| 13 med hjerter | Valg: ud af start ELLER flyt en brik 13 felter frem |
| Nummerkort | Flyt ÉN brik kortets værdi frem (med uret) |
| 1/14-kortet | Valg: flyt en brik 1 ELLER 14 felter frem |
| 7'eren (7×1) | 7 enkelttræk fordelt frit på én eller flere brikker i spil. ALLE 7 skal bruges. Hver brik må kun flyttes én gang pr. 7'er (aldrig fx 2+2+3 på samme brik). Undtagelse: kan sidste egen brik låses fast med færre træk, må/skal resten bruges på makkerens brikker |
| −4-kortet | Flyt en brik 4 felter baglæns (mod uret). Kan ikke bruges i målcirklerne. Kun egne brikker (og makkerens, når man selv er i mål) |
| Byttekortet | Byt to vilkårlige brikker (egne, makkers, modstanderes). Kan bruges uden egne brikker i spil. IKKE på: fredede brikker, brikker i startfelt eller startcirkel. Byttet må aldrig efterlade to forskelligfarvede brikker på samme felt. To egne brikker må byttes, hvis begge er i spil og hverken låst, fredet eller i eget startfelt |

- **[HUL]** Ingen offentlig kilde (heller ikke DM-guiden) dokumenterer
  **antallet af hvert kort** i 56-korts-bunken eller præcis hvilke tal, der
  findes som rene nummerkort. Fordelingen kan kun fastslås ved at tælle et
  fysisk sæt. I appen bør fordelingen derfor være konfigurerbar (det er den
  allerede via admin-skærmen).
- **[UAFKLARET]** ludo.dk beskriver et 5↷-kort ("5 frem, kan passere
  blokeringer") som del af det nuværende klassiske spil. Det stemmer ikke med
  DM-guiden og er sandsynligvis en sammenblanding med Partners+/Duo — men det
  kan ikke udelukkes, at nyere oplag af klassisk har fået kortet med. Tjek et
  fysisk sæt.
- **[UAFKLARET]** spilregler.dk skriver "4 kort tilovers" efter 3 uddelinger,
  men 56 − 3×16 = 8. Uoverensstemmelsen (56 kort vs. regelteksten) er ikke
  forklaret nogen steder.

Kilder: gameinventors.dk/filarkiv/filer/Partners_DM-guide.pdf ·
hygli.dk/partners-spil/ · spilregler.dk/partners/ ·
dansk7kabale.dk/partners-regler/ · legebyen.dk/blogs/blog/partners-spilanmeldelse ·
ultraboardgames.com/partners/game-rules.php

---

## Partners Travel (4 spillere, rejseudgave)

- Udgivet 1. juli 2025. **Reglerne og kortsættet er identiske med klassisk
  Partners** (æskens indholdsliste er ordret den samme: 56 kort, 16 brikker;
  producenten: "præcis det samme sjove spil som originalen"). Eneste forskel
  er fysisk: foldbart plastetui og magnetiske brikker.
- Produktfotos bekræfter klassisk banelayout (felter 1-14 mellem
  startfelterne) og klassiske kortdesigns.
- Til appen: ingen selvstændig variant — evt. blot et tema/skin.

Kilder: gameinventors.dk/PARTNERS-TRAVEL ·
lad-os-spille.dk/spil/partners-travel-4-personer/ ·
bog-ide.dk/produkt/5441749/partners-travel · hyggeonkel.dk/produkt/partners-travel

---

## Partners+ (6 spillere)

Udgivet 2018 (Årets Familiespil 2018). Præcis 6 spillere, alder 8+,
spilletid 45-60 min. Indhold: spilleplade (58×58 cm), **78 kort**,
**24 brikker** (4 pr. farve, 6 farver).

### Holdopsætning og turrækkefølge

- To spilformer: **3 par (2v2v2)** eller **2 hold á 3 (3v3)**.
- 2v2v2-parrene er farverne diagonalt overfor hinanden:
  **grøn+rød, blå+orange, lilla+gul**.
- 3v3: **rød+gul+blå mod orange+grøn+lilla**.
- Farvernes rækkefølge rundt om pladen (med uret): grøn → blå → lilla → rød →
  orange → gul — i 3v3 skifter turen dermed mellem holdene hver gang.
- Spilleren til venstre for kortgiveren starter; derefter med uret.

### Bræt

- **84 banefelter** i alt: 6 segmenter á (1 unummereret startfelt + **13
  nummererede felter**) — bemærk 13 pr. segment mod klassisk udgaves 14.
- Pr. farve desuden: startcirkel (hjem) og slutfelt med 4 målcirkler.
- Målregler som klassisk: fyldes indefra, ingen overspringning, overskydende
  træk rykkes baglæns.

### Kortliste (78 kort, 13 korttyper, 17 trækmuligheder)

| Kort | Funktion(er) |
|---|---|
| 2♥♥ (dobbelt-hjerter, værdi 2) | NYT. Valg: 2 frem med én brik / 2 egne brikker ud af start / 1 egen + 1 partnerbrik ud / 2 af partnerens ud / 1 fra hver af to partnere ud (kun 3v3). Kan spilles uden egne brikker i spil |
| 3 | 3 frem |
| ÷4 (minus 4) | 4 baglæns; ikke i målcirkler |
| 5↷ ("Hopsakortet") | NYT. 5 frem — det ENESTE kort, der må springe over en anden spillers blokerede startfelt |
| 6 | 6 frem |
| 7×1 | 7 enkelttræk fordelt frit; alle 7 skal bruges; hver brik kun én gang; rest til partner ved sidste brik i mål |
| 8♥ | Valg: ud af start ELLER 8 frem |
| 9 | 9 frem |
| 10 | 10 frem |
| Byt plads | Byt to vilkårlige brikker (også samme farve); kan bruges uden egne brikker i spil; ikke på fredede brikker |
| 12 | 12 frem |
| 13♥ | Valg: ud af start ELLER 13 frem |
| 1/14 | Valg: 1 ELLER 14 frem (intet startsymbol) |

- Startkort = kort med hjertesymbol: **2♥♥, 8♥ og 13♥**.
- **[HUL]** Antal pr. korttype er ikke offentliggjort (78/13 = 6 pr. type ved
  ligelig fordeling — ren udledning, ubekræftet).

### Uddeling og kortbytte

- **4 kort pr. spiller** pr. runde (24 pr. uddeling); samme kortgiver deler
  3 gange, derefter går rollen videre med uret.
  **[HUL]** 3×24 = 72 < 78 — håndteringen af de 6 tiloversblevne kort er ikke
  beskrevet i online-kilder (blandes formentlig ind ved næste kortgiver som i
  klassisk).
- Kortbytte før hver runde afhænger af spilform:
  - **2v2v2**: byt samtidigt 1 kort med makkeren, skjult.
  - **3v3**: send samtidigt 1 kort til holdkammeraten **nærmest i urets
    retning** (giver 1, modtager 1), skjult.

### Afvigelser fra klassisk og vinderbetingelse

- Slag, fredning, blokade og spillepligt som klassisk — men blokade kan
  passeres af 5↷-kortet.
- Spiller i mål: i 2v2v2 bruges kortene på makkerens brikker; i 3v3 vælger
  man pr. kort, hvilken holdkammerats brikker der flyttes. Har kun én
  holdkammerat brikker i spil, hjælper begge de andre denne.
- Vinder: parret/holdet med ALLE brikker i mål — **8 brikker (2v2v2)** eller
  **12 brikker (3v3)**. Videre spil om placeringer er valgfrit.

Kilder: spilregler.dk/partners-plus/ · legebyen.dk (Partners+-anmeldelser) ·
gameinventors.dk/PARTNERS_plus · lad-os-spille.dk/spil/partners-6-personer/ ·
hyggeonkel.dk

## Partners Duo (2 spillere)

Udgivet 2022 (Årets Familiespil 2022, nomineret til Guldbrikken). Alder 8+,
spilletid ca. 15-45 min. 1 mod 1, ingen hold — "man er sin egen partner".

**KILDE: æskens egen regelbog (side 3-4) og pladen, fotograferet af ejeren
2026-09-23.** Alt nedenfor uden markering står i den tekst. Det, der stadig er
et gæt eller en tolkning, er markeret.

### Brikker og plade

- **6 brikker pr. spiller** (rød / gul), delt i **2 sæt á 3**: "tre med dut
  og tre med en fordybning". Hvert sæt har sin egen startcirkel (3 pladser),
  og "brikkerne starter og slutter ved den samme start/målcirkel".
- **Hvert sæt er en plads, præcis som en spiller i klassisk** — eget
  startfelt, egne målcirkler. Den eneste forskel: én spiller råder over to
  pladser fra starten og "kan frit vælge mellem brikker fra begge sine
  startcirkler".
- **Ringen:** hver kvart består af **♥ (startfeltet)** og felterne **1-10**.
  ↻-mærket ved siden af felt 10 er kun en pil, der viser hvor man drejer ind
  — ikke et felt (ejer-bekræftet). Egen eg (spoke) krydser ringen ved ♥: en
  brik kommer ud fra startcirklen på ♥, og efter en omgang drejer den ind mod
  sine målcirkler, når den når sit eget ♥ igen.
  - **♥ tæller ikke som et felt ved passage** (ejer-bekræftet) — præcis
    klassisk §6. **Geometrien er derfor klassisk-formet:** 4 segmenter × (10
    tællende + UD) = **44 felter**, indgang til målet ved eget UD. Ingen ny
    parameter i motoren; `BoardGeometry(trackLength: 44, homeStretchLength:
    3, segments: 4)`.
- **3 målcirkler pr. plads**, på egen eg inde i ringen. "Målcirklerne fyldes
  op fra midten af spillepladen": første brik er i mål på den INDERSTE, anden
  på den midterste, tredje på den yderste. **En brik i mål er låst** og kan
  ikke flyttes.

### Kort (30 kort, 10 værdier — alle navngivet i regelbogen)

| Kort | Funktion |
|---|---|
| 3, 7, 10 | Flyt én brik det antal felter frem |
| ♥/1, ♥/6, ♥/8 | Ud af startcirklen på ♥ — ELLER 1/6/8 frem |
| +2− | 2 frem ELLER 2 baglæns ("kan komme tæt på mål" fra startfeltet eller de to første felter) |
| byt/9 | 9 frem — ELLER byt to VILKÅRLIGE brikker (egne som modstanderens; kan bruges uden selv at have brikker i spil). Må IKKE bytte fredede brikker: på målcirkel, i startcirkel, eller hvor brikker fra SAMME startcirkel står på samme felt |
| 4×1 | Én eller flere brikker i alt 4 felter — **fordelt mellem brikker fra SAMME startcirkel**, alle 4 SKAL bruges, hver brik højst én gang. Undtagelse: kan sidste brik fra ét sæt komme i mål med færre, må resten bruges på det modsatte sæts brikker |
| 5↻ | 5 frem, må springe over et blokeret startfelt — modstanderens OG eget modsatte sæts |

- **3 af hver værdi** (10 × 3 = 30) — **ejer-talt i det fysiske sæt**.

### Uddeling, bytte og spillet

- Kortgiveren deler 4 til sig selv og modstanderen; resten i en bunke. Efter
  hånden deles 4 nye fra bunken. **Efter tre uddelinger skifter kortgiveren og
  samler og blander ALLE kortene.** 3×8 = 24 af 30 — de sidste 6 bruges ikke
  i den cyklus. Præcis den mekanisme appen allerede har (`startNewHand` ved
  `starterStreak == 0`).
- **Byttet:** de to spillere bytter ét kort "samtidigt og med bagsiden opad".
  Efter HVER uddeling.
- **Den spiller, der ikke delte, starter.**
- **Slag:** lander en brik på et felt med ÉN af modstanderens brikker **eller
  én brik fra spillerens egen modsatte startcirkel**, slås dén hjem. Står der
  MERE END ÉN (af modstanderens eller fra eget modsatte sæt), er det den
  flyttende brik, der slås hjem. → "egen/anden" afgøres PR. PLADS overalt,
  præcis som klassisk. (Ejerens beslutning "slag" står ordret i teksten.)
- **Blokade:** brik(ker) på eget ♥ kan ikke passeres af modstanderen — "heller
  ikke spillerens egne brikker fra den anden startcirkel" — kun 5↻ kan.
- **Kan intet kort bruges** ("for eksempel fordi man mangler et startkort"):
  læg alle kort ned uden træk; med igen ved næste uddeling. = `passHand`.
- **Bounce-back:** "Hvis kortværdien ikke passer, så brikken kan blive låst,
  skal den flyttes det overskydende antal felter baglæns. Det er dog KUN på en
  målcirkel, at brikken kan skifte retning. Når en brik står på en målcirkel,
  er brikken fredet."
  - **[TOLKNING]** Brikken går ind til den dybeste frie målcirkel og vender
    dér med overskuddet. Rækker overskuddet ud over yderste målcirkel,
    fortsætter den ud på ringen (ejer-valgt, og teksten sætter ingen grænse).
  - En brik på en målcirkel, der endnu ikke er i sin rette plads (fx efter
    bounce), er fredet men IKKE låst.

### Vinderbetingelse

Den spiller, der først får alle sine seks brikker i mål på målcirklerne.

Kilder: dansk7kabale.dk/partners-duo-regler/ ·
legebyen.dk (Duo-spilanmeldelse 1+2) · gameinventors.dk/PARTNERS-DUO ·
lad-os-spille.dk/spil/partners-duo/ · boardgamegeek.com/boardgame/356559 ·
partnersboardgame.com/products/partners-duo-1

---

## Partners Trio (3 spillere)

Udgivet feb./marts 2026 — nyeste udgave, udviklet over 2 år. Præcis 3
spillere, **alle mod alle** ("Ingen alliancer. Ingen nåde. Kun én vinder!").
Alder 8+, spilletid ca. 20-30 min.

- **Indhold**: spilleplade, **40 kort**, **12 brikker** (4 pr. farve).
- **Kort-videregivelse i stedet for makkerbyt**: efter hver kortgivning
  sender man ét kort videre til én modstander og modtager samtidig ét fra den
  anden — cirkulær videregivelse, ikke parvist bytte.
- Kortene er "helt nye kortvariationer, som ikke tidligere er set i
  Partners-serien".
- Der spilles reelt om placeringerne 1-2-3 ("kampen om pladserne fra 1 til 3
  er intens hele vejen").
- Vinder: først med alle 4 egne brikker i mål.
- **[HUL]** Spillet er så nyt, at hverken de konkrete korttyper, antal kort
  pr. hånd, banelayoutet eller slag-/frednings-/blokaderegler er offentligt
  dokumenteret endnu (ingen regel-PDF, ingen BGG-side, ingen detaljeret
  anmeldelse fundet). Denne variant kan p.t. kun implementeres ud fra et
  fysisk eksemplar af spillet.

Kilder: gameinventors.dk/PARTNERS-TRIO · lad-os-spille.dk/spil/partners-trio/ ·
legebyen.dk (produktside) · bog-ide.dk (produktside) ·
hyggeonkel.dk/overblik/partners-spil/

## Partners 25 år (jubilæumsudgave)

Udgivet september 2023 i begrænset oplag (kun udvalgte forhandlere). Præcis 4
spillere i 2 hold á 2, alder 8+, spilletid 30-45 min. Indhold: spilleplade,
**56 kort**, 16 brikker i klar akryl.

- **Bræt**: klassisk 4-farvet bane i nyt "hjul"-design (felter 1-14 mellem
  startfelterne som klassisk, 4 målcirkler pr. farve).
- **Grundmekanik som klassisk**: 2v2, makkerbyt efter hver uddeling, spil for
  makkeren når man er i mål, vinder ved 8 brikker i mål.
- **Kortbunken** er en blanding af kort fra klassisk, Duo og Partners+ plus
  helt nye kort. Specialkortene, BEKRÆFTET mod et fysisk eksemplar (ejerens
  aflæsning af kortene, 2026 — se foto-referencen i denne repos historik):

| Kort | Funktion(er) — bekræftet |
|---|---|
| 7 ELLER +2−5 | Flyt én brik 7 frem, ELLER først 2 frem og derefter 5 tilbage MED SAMME BRIK — kan være heldig at slå 2 brikker hjem i samme træk (landing både på mellem- og slutfeltet) |
| Byt plads ELLER 9 | Byt to brikker ELLER flyt én brik 9 frem |
| 11 ELLER 1×1 | Flyt én brik 11 frem, ELLER flyt TO brikker 1 felt frem hver |
| 4×1 | 4 enkelttræk fordelt på flere brikker — samme mekanik som klassisk 7×1, blot 4 |
| 5↷ | 5 frem, springer over blokeret startfelt (Hopsakortet, fra Partners+/Duo) |

- **Bekræftet (ejer):** der er IKKE længere et −4/÷4-kort i 25 år — 4×1
  erstatter det klassiske 4-kort. Baglæns-bevægelse findes i 25 år kun som
  −5-delen af "7 ELLER +2−5".
- **Bekræftet (ejer-foto, 2026):** æsken og kortryggene er MØRK MARINEBLÅ med
  regnbue-hjul — kilden til appens 25 år-tema (variantens tableColor/feltColor
  i variant_config.dart).
- **[HUL — reduceret]** Antal pr. korttype og den fulde liste af ALMINDELIGE
  kort er stadig ikke talt op; specialkortene ovenfor er bekræftet. 2♥♥ er
  fortsat ubekræftet.
- App-status: 5↷ (hop) er implementeret som motor-mekanik; "Byt ELLER 9" og
  4×1 kan udtrykkes med eksisterende mekanikker (swap+frem, split) via
  admin-skærmens variant-kolonne. "+2−5" (sekvens-træk) og "1×1 med to
  brikker" (multi-brik-træk) kræver nye motor-mekanikker.

Kilder: gameinventors.dk/PARTNERS-25-AaR · hyggeonkel.dk/produkt/partners-25
(inkl. æske- og kortfotos) · lad-os-spille.dk/spil/partners-25-aar/ ·
gameinventors-shop.dk (ekstra kortsæt)

---

## Implementeringsnoter til appen

### Hvad motoren faktisk læser af `VariantConfig` (opdateret under Duo-arbejdet)

Før Duo-arbejdet læste motoren kun 4 af 12 felter; resten var en PÅSTAND om
parathed. Status nu:

| Felt | Læses af koden? |
|---|---|
| `piecesPerPlayer`, `segments` | ja (bræt og brikker) |
| `teams` | ja — hold, makker og nu også hvem der råder over hvad |
| `exchangeRule` | ja — `exchangeReceiver`, brugt af motor OG chippen "kortet du gav" |
| `onePlayerPerTeam` | ja (Duo trin 2) — `controllerOf`, `hasHand`, `handCount`, starter-rotation |
| `deckRanks`, `copiesPerRank`, `exitCardCount` | ja (Duo trin 1) — `Deck.forVariant` |
| `goalBounce` | ja (Duo trin 7) — bounce-back i `_advanceFrom` |
| `playerCount`, `fieldsPerSegment`, `goalCircles`*, `handSize`, `dealsPerDealer` | **nej** — stadig kun påstande |

*`goalCircles` indgår i `geometry` (antal målcirkler), men ikke andre steder.

`forcedPlay`, `destinationsPerPlayer` og `WinCondition.ownAllHome` er
FJERNET (Duo trin 0): de beskrev en Duo-model, ejeren afviste, og intet læste
dem. Streng spillepligt findes allerede (`passHand` afviser, når man kan
spille), og vinderen falder ud af hold-betingelsen.

**RETTET:** Her stod, at `HomeStretchPosition` skulle bære en tredje
oplysning (hvilken destination), og at det var den dybeste ændring. Det var
forkert, og det byggede på en misforståelse af pladen. Hvert sæt i Duo ER en
plads (`ownerIndex`) med eget start- og målområde — modellen kan det
allerede. Den reelle ændring er en anden: **to hænder og to ture, men fire
pladser** — ét menneske råder over to pladsers brikker fra starten. Det er
`activePool`-logikken (spil videre på makkeren) gjort permanent, plus en
turrækkefølge der kun går over de to menneskers pladser.

Forslag: modellér hver udgave som en deklarativ variant-konfiguration oven på
den fælles motor, fx:

```
VariantConfig {
  id, navn,
  playerCount,            // 2, 3, 4, 6
  teams,                  // [[0,2],[1,3]] / [[0,2],[1,4],[3,5]] / 3v3 / [] (alle mod alle)
  piecesPerPlayer,        // 4 eller 6 (Duo: 2 briktyper á 3 med hver sit mål)
  trackFieldsPerSegment,  // 14 (klassisk/25 år/Travel), 13 (Partners+), Duo/Trio ukendt
  goalCircles: 4,
  deck: [ { cardType, count } ],     // konfigurerbar pga. [HUL] om antal
  handSize: 4,
  dealsPerDealer: 3,
  exchangeRule,           // makkerByt | sendTilHoldkammeratMedUret (3v3)
                          //   | modstanderByt (Duo) | cirkulærVideregivelse (Trio)
  forcedPlay,             // Duo: streng spillepligt (kan tvinges til selvslag)
  blockadeJumpCard,       // 5↷ findes: Partners+/Duo/25 år (klassisk: uafklaret)
  winCondition,           // holdetsBrikkerIMaal (8/12) | egneBrikkerIMaal (Duo: 6, Trio: 4)
}
```

Korttyperne bør være data (funktionsflag + parametre), ikke hårdkodede klasser:
`{ enter, forwardSteps: [..], backwardSteps: [..], splitSteps, swap, ... }` —
det matcher appens eksisterende admin-konfiguration og gør nye udgaver (fx
25 år-kortene med kombinationstræk) mulige at udtrykke.

## Samlede kilder

- Game InVentorS (officiel udgiver): gameinventors.dk — produktsider for alle
  udgaver + DM-guiden (PDF, 4. udgave 2023)
- spilregler.dk/partners/ og spilregler.dk/partners-plus/
- hygli.dk/partners-spil/ · dansk7kabale.dk/partners-regler/ og /partners-duo-regler/
- legebyen.dk (anmeldelser af Partners og Partners+)
- lad-os-spille.dk/partners/ (produktoverblik for alle udgaver)
- spillemagasinet.dk/spil/partners-braetspil/ (regeldebat/præciseringer)
- ultraboardgames.com/partners/game-rules.php (engelsk regeloversættelse)
- hyggeonkel.dk/overblik/partners-spil/ (sortimentsoverblik)

## Husets egne varianter (admin-definerede, app-funktion)

Fra Del B kan admin definere EGNE varianter i appen — altid klassisk-formede
(4 spillere, 2v2 diagonalt, samme bræt); kun navn, kort mærke, beskrivelse,
farvetema og kort-opsætning (indenfor de eksisterende korttyper) kan vælges.

- **Id**: `cv-<slug>` af navnet ved oprettelsen, permanent (står i historiske
  spil-docs og statistik-nøgler). Omdøbning ændrer ikke id'et.
- **Temaer**: fire kuraterede, kontrast-efterprøvede tripler (Rubin, Rav,
  Violet, Grafit) i samme luminans-bånd som klassisk grøn/25 år-navy. Grøn og
  marineblå er reserveret til de indbyggede.
- **Kortregler**: en ny variant FØLGER klassisk (tomme overrides), til admin
  redigerer den — eller trykker "Kopiér klassisk" for et uafhængigt snapshot.
- **Arkivering i stedet for sletning**: en arkiveret variant forsvinder fra
  vælgerne, men historik/statistik beholder navn og farve, og igangværende
  spil spilles færdige. Id'er genbruges aldrig.
- **Forbehold**: alle egne varianter bærer automatisk teksten "Husets egen
  variant, lavet af admin — ikke en officiel Partners-udgave."
