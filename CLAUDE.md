# Partners — arbejds- og gennemgangsmodel

Vi arbejder efter en fast gennemgangs-model. Hver eneste ændring — også "bare
en lille fejlrettelse" — skal igennem tre faste roller, før den landes. Kør dem
som separate, uafhængige gennemgange (subagenter), når ændringen er skrevet og
committet. Eneste undtagelse: rene tekstrettelser i dokumentation uden
kodeændring (fx denne fil, `docs/`, agent-definitioner).

Rollerne er vores eksisterende manager-agenter i `.claude/agents/`. Modellen er
tilpasset vores faktiske pipeline (main-baseret, deploy fra push), men er ikke
gjort svagere end den oprindelige model — hvor vores miljø sætter grænser, er
grænsen NAVNGIVET (se "Kendte huller" nederst), ikke skjult.

## De tre faste roller

| Rolle | Vores agent | Model | Spørger | Kan blokere for |
|---|---|---|---|---|
| **Test Manager** | `test-manager` | sonnet | Er ændringen bevist? Mutationstest kernen — en grøn suite beviser intet i sig selv | at lande uden reel dækning |
| **Quality Control** | `quality-manager` | sonnet (kør på **opus** ved PLAN-gennemgange af ny brugerflade — sig det ved invokationen) | Løser den det RIGTIGE problem — og hvad rører den ellers ved? Kan brugerne forstå den? | at lande med en halv rettelse |
| **Release Manager** | `release-manager` | haiku | Hvad skal deployes, i hvilken rækkefølge, og hvad tjekkes bagefter? | en forkert udrulning |

Dertil to roller, der kun køres når ændringen kalder på det:

- **Security Reviewer** (`security-manager`, opus): køres når ændringen rører
  adgangskontrol, auth, Firestore-regler, Cloud Functions, push, deep-links,
  invitationer — eller noget andet, der afgør hvem der ser hvad. Den skal
  ANGRIBE ændringen: konkrete skridt en fjendtlig bruger ville tage, efterprøvet
  mod den rigtige adgangsmodel (emulator/testmiljø), ikke ræsonneret. (Vi har
  endnu ikke emulator-harness'en — se "Kendte huller".)
- **Spil-rådgiver** (`spil-raadgiver`, opus): domæne-rådgiveren, tilpasset at
  Partners er et brætspil. Vurderer om ændringen gør spillet bedre eller
  dårligere at SPILLE — og køres kun på PLANEN, før koden skrives. Rådgivende,
  ikke blokerende: et "det her gør spillet dårligere" skal besvares i planen,
  ikke nødvendigvis adlydes.

## Rækkefølgen i praksis

Tilpasset vores flow: vi udvikler på `main`, og et push udløser **Test &
Deploy** (`.github/workflows/deploy.yml`), som kører analyze → tests → build →
e2e og FØRST derefter deployer. Test-trinnene ligger før deploy-trinnene, så en
rød test springer udrulningen over — det er vores CI-grønt-gate. Claude
håndterer alle deploys; brugeren er ikke involveret.

0. Tilføjer ændringen ny brugerflade eller nye tal på skærmen: kør Quality
   Control på PLANEN først (på opus). De dyreste fund er designfejl, ikke
   kodefejl — to minutter dér sparer en omskrivning. Rører ændringen spillets
   oplevelse: kør også Spil-rådgiveren på planen.
0b. Får ændringen en knap eller en fane: afgør FØRST hvor den hører hjemme — det
   sted en bruger ville lede, ikke det sted der er nemmest at bygge. Spørg: hvad
   ville jeg selv klikke på, hvis jeg ikke havde skrevet koden? Intern
   konsistens taber til genfindelighed.
1. Skriv ændringen. `flutter` er IKKE installeret lokalt i dette miljø, så lint/
   test/build køres i CI — kontrollér til gengæld statisk at hver ændring
   faktisk landede (en tekst-erstatning der ikke matcher fejler tavst, og så
   står testfilen grøn uden at dække noget). `node --check functions/index.js`
   kan køres lokalt for Cloud Functions.
2. **Commit FØRST (lokalt) — kør så Test Manager og Quality Control parallelt**
   (plus Security hvis ændringen rører adgang). En gennemgang ser kun det
   committede: en ukommitteret ændring bliver aldrig gennemgået — og
   mutationstest, der ruller filer tilbage, kan slette ukommitteret arbejde.
   Nævn branchen (`main`) og commit-SHA'en, når rollerne startes, så de
   gennemgår den rigtige kode. Ret det, rollerne finder, og modbevis hver
   rettelse (se Testprincipper).
   - **Emulator-tunge roller køres SEKVENTIELT, ikke parallelt.** To roller, der
     begge kører `npm run test:rules` (fx Security der angriber reglerne og Test
     Manager der mutationstester dem), deler Firestore-emulatorens port (8080) og
     hænger hvis de kører samtidig. Kør dem én ad gangen; kun rent læsende/
     statiske roller (fx Quality Control) må køre parallelt med dem.
3. Når de er grønne: kør Release Manager. Den kommer sidst, fordi planen
   afhænger af hvad der faktisk lander — inklusive rollernes afkrævede
   rettelser.
4. Push til `main` → grøn Test & Deploy → udrulningen sker fra pipelinen efter
   Release Managers plan. Spørg ikke om lov ved grøn CI og ingen blokerende
   fund. UNDTAGELSER hvor der altid spørges først: alt der skriver i
   produktionsdata (Firestore-migreringer, bagfyldninger, seed/reset-scripts),
   tilbagerulninger, og udrulninger med et blokerende fund.
5. Verificér i produktion (bekræft det grønne run INKL. at Cloud Functions-
   deploy-trinnet faktisk kørte, hvis `functions/` blev rørt) og fortæl
   brugeren, hvad der er live.

Rapportér rollernes konklusioner til brugeren, før der landes. Er en rolle
uenig, så løs det først — eller sig klart, hvad der landes med og hvorfor.

## Testprincipper (det vigtigste afsnit)

**Antag, at dine egne tests bekræfter sig selv.** Kode og tests skrives af den
samme i samme åndedrag og indkoder samme forståelse — også når den er forkert.
Derfor er mutationstest ikke ekstra grundighed, men den eneste måde at vide om
noget er dækket: lav en målrettet, realistisk fejl i kernen og se suiten blive
RØD. Forbliver den grøn, er ændringen ikke bevist. Rul mutationen tilbage
bagefter — og kun mod committet kode. (Miljø: suiten kører i CI, ikke lokalt —
se "Kendte huller" for hvordan mutationen faktisk verificeres.)

Kendte måder, ubevist kode slipper igennem med grøn suite:

- **Et bånd, der rummer både før og efter, måler ingenting.** En test, der
  accepterer et interval, som både den gamle og den nye værdi ligger i, består
  med præcis den fejl, den skulle fange. Skriv båndet så den GAMLE værdi gør det
  rødt, og skriv begge tal i kommentaren.
- **En test, der kun tjekker at noget blev VIST, beviser ikke hvad der stod.**
  Assertér på indholdet — og på det, der IKKE må stå.
- **To vagter om samme regel betyder, at den ene kan fjernes med grøn suite.**
  Én vagt pr. sikkerhedsregel, samlet ét sted, så en mutation af den bliver rød.
- **En vagt, der genkendes på FRAVÆR af noget, kan fjernes helt uden at nogen
  test opdager det.** Genkend på positiv tilstedeværelse.
- **En test uden data beviser ingenting.** En test på et tomt fixture er grøn
  med logikken helt fjernet.

## Faste regler

- **Serveren er eneste autoritet.** Validering i klienten kan omgås. Server-
  adgangstjek (Firestore-regler, Cloud Functions/transaktioner) må aldrig være
  mere gavmilde end klientens regler — og de skal ligge FØR de dyre operationer,
  så en afvisning er billig.
- **Et tal uden kode er en påstand.** Begrunder en måling en ændring, så commit
  måle-scriptet og henvis til det. Tal, der ikke kan efterprøves, gælder ikke.
- **Efterprøv begrundelsen på dét, den rammer — ikke på gennemsnittet.** En
  rettelse, der er rigtig i snit, kan gøre skade lokalt.
- **Ny funktionalitet, der kun kan startes af en tilfældig hændelse, er ikke
  færdig.** Spørg: hvordan starter jeg det her med vilje? Svaret er ofte en
  knap.
- **Ny funktionalitet, der kun kan fejle tavst, er heller ikke færdig.** Peg på
  loggen, alarmen eller admin-siden, hvor fejlen ville stå. Release Manager
  spørger efter det; svaret skal findes i planen, ikke opfindes ved deployet.
- **"Alle" er sjældent den rigtige modtagerkreds.** Rører en udsendelse ét spil/
  én gruppe/ét produkt (fx en FCM-push, en genberegning), så vælg netop dén
  kreds.
- **Tør-kørsel først** på alt, der skriver i produktionsdata — og vis før/efter,
  før skrive-knappen overhovedet dukker op.

## Modelvalg (frontmatter)

De hyppige roller kører på billigere modeller, de sjældne på de stærkeste — et
bevidst valg, der kan justeres i hver agents frontmatter (`model:`):

| Rolle | Default | Hvorfor |
|---|---|---|
| `test-manager` | sonnet | køres på hver ændring; mutationstest er mekanisk |
| `quality-manager` | sonnet (opus ved PLAN-gennemgange af ny brugerflade — sig det ved invokationen) | designfejl er de dyreste fund |
| `release-manager` | haiku | tjekliste-arbejde på diff'en |
| `security-manager` | opus | sjælden, og fund skal EFTERPRØVES, ikke gættes |
| `spil-raadgiver` | opus | sjælden, og dommen kræver helhedsblik |

## Kendte huller (hvor vores miljø endnu ikke lever helt op til modellen)

Disse er navngivet, ikke skjult — modellen er ikke gjort svagere; infrastruktur
mangler for at honorere den fuldt ud:

1. **Emulator-baseret sikkerhedstest — LUKKET.** Security Reviewer ANGRIBER nu
   de faktiske `firestore.rules` i Firestore-emulatoren i stedet for at
   ræsonnere. Harnessen: `firestore-tests/rules.test.mjs`
   (`@firebase/rules-unit-testing`), køres med `npm run test:rules`, og er en
   HÅRD gate i `deploy.yml` (samt fuld test-gate på PR/dispatch i `tests.yml`).
   Hvert angreb er mutationstestet: en for-løs regel gør et angreb rødt. Rør en
   ændring adgangskontrollen, skal et angreb tilføjes her — og et fund, der ikke
   er efterprøvet mod emulatoren, regnes stadig som uafsluttet.
2. **Mutationstest verificeres i CI, ikke lokalt.** `flutter` er ikke
   installeret i udviklingsmiljøet. Indtil det er, verificeres en mutation ved
   at Test Manager (a) designer den konkrete fejl + den assertion der fanger
   den, og (b) bekræfter fangsten via CI (fx et kortlivet mutations-tjek), i
   stedet for en lokal rød/grøn-cyklus. Målet er uændret: ingen ændring landes
   som "dækket", uden at en realistisk fejl bevisligt ville gøre suiten rød.
