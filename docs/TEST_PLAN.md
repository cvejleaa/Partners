# Partners — Testplan

Dette dokument lister alle test der køres for Partners-appen, hvilke
API'er/funktioner de dækker, og hvor resultaterne kan findes. Planen
opdateres ved hver feature.

## Hvor ser jeg testresultaterne?

| Kanal | Hvad | Hvor |
|-------|------|------|
| GitHub Actions | Hver kørsel af `Test & Deploy` viser alle steps grøn/rød | https://github.com/cvejleaa/partners/actions |
| Playwright-rapport (live) | Browser-tests for den seneste deploy | https://partners.vejleaa.dk/test-report/ |
| Playwright-rapport (artefakt) | HTML + skærmbilleder fra hvert run, 14 dages opbevaring | Actions-kørsel → "Artifacts" → `test-report` |
| In-app Selvtest | Live i den deployede app — kører hele spil + alle regeltjek og viser grøn/rød | partners.vejleaa.dk → ✓-ikon (forsiden) |
| `flutter test` lokalt | Alle Dart-tests | `flutter test` i repoet |

## Testniveauer

### 1. Unit-tests (Dart, `test/`)

Hurtige, deterministiske tjek af individuelle funktioner/regler.

| Fil | Dækker |
|-----|--------|
| `test/rules_test.dart` | Hver kortregel: ud-af-start, blokerede ud-felter, slag, beskyttet dobbelt, stak på egen brik, 7-split, hjemstræk, byt to forskellige spilleres brikker, ud-kort |
| `test/engine_test.dart` | Hånd-lifecycle (dele, bytte, tur-fremgang), pass-reglen (smid hånd hvis intet træk er muligt), startende-rotation efter 3 runder, 56-kort-kortgiver-cyklus med 4 af hver slags, vinder-detektion |
| `test/ai_test.dart` | AI-strategi: foretrækker ud-af-start når brikker er i start, foretrækker slag, vælger gyldige træk |
| `test/serialize_test.dart` | Round-trip af `GameState` gennem (de)serialisering (sikrer at synkronisering til/fra Firestore bevarer alt) |
| `test/full_game_test.dart` | **5 komplette spil** fra start til vinder med 4 AI; verificerer at alle træk er lovlige og spillet altid slutter |

### 2. In-app Selvtest (Dart, kørt i browseren)

Den deployede app kører de samme test som `flutter test` direkte i
browseren via ✓-ikonet på forsiden. Resultatet vises som grøn/rød med
statistik (hold A vs B, gennemsnit hænder, ulovlige træk, etc.).

### 3. Browser-tests (Playwright, `tests/playwright/`)

| Fil | Dækker |
|-----|--------|
| `tests/playwright/smoke.spec.ts` | App booter i Chromium uden console-fejl; manifest tilgængelig; screenshots på desktop + mobil viewport |

### 4. Manuel verifikation pr. feature

Følgende skal manuelt valideres efter hver større deploy:

- [ ] **Forsiden viser login-status korrekt** (rød "Ikke logget ind" vs grøn "Logget ind som …")
- [ ] **Spil-knapper er kun synlige når logget ind**
- [ ] **Admin-tandhjul er kun synligt for admin-konti** (`cvejleaa@gmail.com`)
- [ ] **Opret konto** → ny bruger oprettes i Auth + profil i Firestore (`users/{uid}`)
- [ ] **Google-login** virker via popup
- [ ] **Log ind/log ud** → forsiden opdaterer status
- [ ] **Admin: ændr kortregel** → ændring overlever genindlæsning
- [ ] **Admin: ændr på enhed A, åbn på enhed B** → ændringen følger med (Firestore-persistens)
- [ ] **Opret online-spil** → spillet vises i Firestore-collection `games`
- [ ] **Invitér 1-3 spillere** → de ser invitationen under "Mine spil"
- [ ] **Start spil med tomme pladser** → de bliver AI
- [ ] **Spil et helt online-spil til ende** med min. 2 menneskelige spillere
- [ ] **Catch-up replay**: log ud, modspil sker, log ind igen, replay-overlay vises med kort

## CI-pipeline pr. push

Hvert push til udviklingsgrenen kører:

1. `flutter analyze --no-fatal-infos`
2. `flutter test` — alle Dart-tests inkl. 5 komplette AI-spil
3. `flutter build web --release`
4. Playwright (smoke + screenshots)
5. Deploy til Firebase Hosting (live → partners.vejleaa.dk)
6. Deploy af Firestore-regler (mod named-database `partners`)

Pipelinen blokerer alle steps gennem til deploy hvis bare ét trin
fejler.

## Hvad der mangler — planlagt

Når du har bekræftet hovedflowet virker, tilføjes:

- Online-service-tests med `fake_cloud_firestore` (mock af Firestore +
  Auth, så hele opret/invitér/join/spil-flowet testes uden netværk)
- Flutter `integration_test/` der spiller et helt UI-flow (login →
  opret spil → tag plads → spil til ende)
- Playwright-test der gennemfører et helt spil med to browser-instanser
- Synkronisering: test af samtidighed (to klienter spiller samtidigt)
- Firestore-rules-test (Firebase rules-emulator)
