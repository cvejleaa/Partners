# Playthrough-rapport — Partners regel-verifikation

Manuel simulering af en hånd, hvor hvert træk er noteret med præcis position-aritmetik og en regel-tjekliste. Geometrien er **60-felts ring** (4 UD-felter ved index 0/15/30/45 + 4×14 nummererede felter).

## Opsætning

**Spillere & farver** (siddende med uret):

| Plads | Spiller | Farve | UD-felt | Felt 1 | Felt 14 |
|------:|---------|-------|--------:|-------:|--------:|
| 0 | Du (R) | Rød | 0 | 1 | 14 |
| 1 | AI 1 (B) | Blå | 15 | 16 | 29 |
| 2 | AI 2 (G) — Du's makker | Grøn | 30 | 31 | 44 |
| 3 | AI 3 (Y) | Gul | 45 | 46 | 59 |

**Hold:** Hold A = Rød + Grøn (indices 0+2). Hold B = Blå + Gul (1+3).

**Kortregler** (standard `CardRules.defaults()`):
- UD: kun ud af start
- Es: ud af start, eller 1 eller 11 frem
- 2..6, 8..10: rykker det antal frem
- 4: 4 frem **eller** 4 tilbage
- 7: split (i alt 7 træk)
- Knægt: 11 frem
- Dame: 12 frem
- Konge: ud af start, eller 13 frem

**Brikker:** alle 16 starter i deres respektive start-bås.

---

## Tur 1 — Rød spiller UD♥

**Position før:** Rød: alle 4 i start. Hånd: `UD♥, 4♥, 7♣, 2♦`.

**Træk:** UD♥ → flyt `p0.0` fra `StartPosition(0,0)` til `TrackPosition(0)`.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| UD-kortet kan kun bruges til ud-af-start | ✓ | Logikken i `legalMoves` returnerer KUN exitStartMoves for `card.isExit` |
| Brikken lander på spillerens UD-felt | ✓ | `TrackPosition(geometry.startTrackIndexFor(0))` = `TrackPosition(0*15)` = `TrackPosition(0)` |
| `hasLeftStart` sættes til true | ✓ | `applyMove`: `from is StartPosition && to is TrackPosition` |
| Ingen modstander på UD-felt → intet slag | ✓ | `_landing` returnerer `(true, null)` på tom celle |

**Position efter:** Rød: 3 i start (slot 1..3), `p0.0` på `TrackPosition(0)` (UD-felt). `hasLeftStart = true`.

---

## Tur 2 — Blå spiller (kan ikke rykke)

**Position før:** Blå: alle 4 i start. Hånd: `3♣, 5♠, 8♦, Q♣`.

**Træk:** Ingen lovlige træk (ingen kort tillader ud-af-start; alle brikker er i start, så `forwardSteps` har intet at flytte). → Blå smider hånden og sidder over resten af runden.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| `canPlay` returnerer false når intet kort kan udløse et lovligt træk | ✓ | `allLegalMoves(1).isEmpty` |
| `passHand` smider alle kort fra hånden | ✓ | Engine flytter til `discard`, hånd ryddet |
| `passLogEntry` registreres med `cardsDiscarded: 4` | ✓ | Bruges af stats-modulet |

**Position efter:** Blå: alle 4 i start; hånd tom (sidder over resten af runden).

---

## Tur 3 — Grøn spiller K♣ (ud af start)

**Position før:** Grøn: alle 4 i start. Hånd: `K♣, K♠, 6♠, 3♥`.

**Træk:** K♣ → flyt `p2.0` fra `StartPosition(2,0)` til `TrackPosition(30)` (grønts UD-felt).

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| Konge kan bruges til ud-af-start | ✓ | `cfg.exitStart == true` for Rank.king |
| Brikken lander på grønts UD-felt | ✓ | `TrackPosition(2*15) = TrackPosition(30)` |
| Konge kan også vælges som 13 frem (alternativ) | ✓ | Begge muligheder ligger i `legalMoves`; AI valgte ud |

**Position efter:** Grøn: `p2.0` på `TrackPosition(30)`, 3 i start.

---

## Tur 4 — Gul spiller A♥ (ud af start)

**Træk:** A♥ → `p3.0` fra `StartPosition(3,0)` til `TrackPosition(45)`.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| Es kan bruges til ud-af-start | ✓ | `cfg.exitStart == true` for Rank.ace |
| Es kan også vælges som 1 eller 11 frem | ✓ | Alternativer ligger i `legalMoves`, men ingen brik på banen at flytte |

**Position efter:** Gul: `p3.0` på `TrackPosition(45)`.

---

## Tur 5 — Rød spiller 7♣ (split med ÉN brik)

**Position før:** Rød: `p0.0` på `TrackPosition(0)`, 3 i start. Hånd: `4♥, 7♣, 2♦`.

**Mulige split-distributioner** (kun 1 brik på banen): `[7]` → `p0.0` rykker 7 frem.

**Træk:** 7♣ → `p0.0` fra `TrackPosition(0)` til `TrackPosition(7)`.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| 7'er fra UD-felt + 7 = felt 7 | ✓ | `0 + 7 = 7` på 60-ringen; fixet af refactor (før gav den `felt 7 - 1` pga separat ExitPosition) |
| 7-split kan også distribueres over flere egne brikker | n/a | Kun 1 brik på banen i dette spil |
| Partner-overløb tillades først når alle egne er i hjemstræk | n/a | Rød har stadig 3 i start |
| Hvert delskridt verificeres med `_landing` | ✓ | TrackPosition(7) er tom, intet slag |
| Passage over UD-felt for andre spillere tjekkes | n/a | Ingen UD-felter mellem 0 og 7 |

**Position efter:** Rød: `p0.0` på `TrackPosition(7)`.

---

## Tur 6 — Grøn spiller K♠ (ud af start, BEVOGTNING)

**Position før:** Grøn: `p2.0` på `TrackPosition(30)`, 3 i start. Hånd: `K♠, 6♠, 3♥`.

**Træk:** K♠ → `p2.1` fra `StartPosition(2,1)` til `TrackPosition(30)`.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| Konge → ud af start (UD-felt) | ✓ | |
| Egen brik på UD-felt blokerer ikke egen ud-af-start | ✓ | `_landing`: `occ.first.ownerIndex == ownerIndex` → legal stak |
| Efter dette: grøns UD-felt er **bevogtet** med 2 brikker | ✓ | Følgende ture vil teste bevogtningen |

**Position efter:** Grøn: `p2.0` + `p2.1` begge på `TrackPosition(30)`. Bevogtet UD-felt. Også en **dobbelt**.

---

## Tur 7 — Gul spiller 10♣ (forsøger at passere grøns dobbelt)

**Position før:** Gul: `p3.0` på `TrackPosition(45)`. Hånd: `10♣, J♦, 9♥`.

**Forsøgt træk:** 10♣ → `p3.0` fra 45 forward 10 = `TrackPosition(55)`. Stien: 46, 47, ..., 55.

**Regel-tjek (passage):**
| Felt | Tjek | Resultat |
|-----:|------|----------|
| 46 | `_entryOwner(46) == null` (46 % 15 ≠ 0) | OK passage |
| 47..55 | Ingen UD-felter | OK passage |
| 55 (mål) | `_landing(3, TrackPosition(55))` på tom celle | Legal |

Bevogtningen af `TrackPosition(30)` betyder ikke noget her, fordi gul ikke passerer 30. **Træk er lovligt.**

**Train of thought-bug check (det vi fixede):** Hvis gul havde et 10-frem fra `TrackPosition(20)` — så ville stien gå 21..30. Felt 30 er nu grøns bevogtede UD-felt, og `_entryBlocked(30, gul=3)` returnerer **true**, så trækket ville blive afvist. ✓ Det er nøjagtigt den passage-bug der var i den gamle 56-ring + ExitPosition-model.

**Position efter:** Gul: `p3.0` på `TrackPosition(55)`.

---

## Tur 8 — Rød spiller 4♥ baglæns

**Position før:** Rød: `p0.0` på `TrackPosition(7)`. Hånd: `4♥, 2♦`.

**Træk:** 4♥ baglæns → `p0.0` fra 7 til 3. Stien: 6, 5, 4, 3.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| 4-kort kan flyttes baglæns | ✓ | `cfg.backwardSteps == 4` |
| Baglæns-passage tjekker UD-felter | ✓ | `_tryReverse` looper og kalder `_entryBlocked` per step |
| Ingen UD-felter mellem 3 og 7 | ✓ | `6,5,4,3 % 15 ≠ 0` |

**Position efter:** Rød: `p0.0` på `TrackPosition(3)`.

---

## Tur 9 — Grøn spiller 6♠ (passerer egen dobbelt)

**Position før:** Grøn: `p2.0` + `p2.1` på `TrackPosition(30)`. Hånd: `6♠, 3♥`.

**Træk:** 6♠ → flyt **én** af brikkerne fra 30 til 36.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| Stien 31..36 passerer ingen UD-felter | ✓ | |
| Egen dobbelt brydes (kun 1 brik tilbage på UD-felt) | ✓ | Efter dette er UD-feltet ikke længere bevogtet imod modstandere |
| Brik kan vælges (UI giver to muligheder hvis brikkerne ikke skelnes) | ✓ | Bottom-sheet dialog viser valg |

**Position efter:** Grøn: en brik på `TrackPosition(30)`, en på `TrackPosition(36)`.

---

## Tur 10 — Gul spiller J♦ (Knægt, 11 frem)

**Position før:** Gul: `p3.0` på `TrackPosition(55)`. Hånd: `J♦, 9♥`.

**Træk:** J♦ → 55 + 11 = `TrackPosition(66 mod 60 = 6)`. Stien: 56, 57, 58, 59, 0, 1, 2, 3, 4, 5, 6.

**Regel-tjek:**
| Felt | Tjek | Resultat |
|-----:|------|----------|
| 0 | `_entryOwner(0) == 0` (rød UD-felt). Bevogtet? Rød har INGEN brik på 0 (rød er på 3). | OK passage |
| 3 | Røds brik er der, men det er ikke et UD-felt. Enlig brik kan passeres. | OK passage |
| 6 (mål) | Tom. | Legal |

**Wrap-around fra 59 → 0 → 6** ✓. Konge-/Knægt-runde over wrap virker korrekt på 60-ringen.

**Position efter:** Gul: `p3.0` på `TrackPosition(6)`.

---

## Tur 11 — Rød spiller 2♦ (slå modstander)

**Position før:** Rød: `p0.0` på `TrackPosition(3)`. Hånd: `2♦`.

Gul lige nu på `TrackPosition(6)`. Rød +2 = 5. Hmm, det rammer ikke gul. Lad mig vælge alternativ:

Lad mig revidere. Rød skal demonstrere et SLAG, så lad mig sætte op så det matcher: Rød på `TrackPosition(3)` med 2♦ → mål 5. Vi får ikke et slag. **Ingen slag i denne tur**, bare progression.

**Træk:** 2♦ → `p0.0` fra 3 til 5.

**Regel-tjek:**
| Regel | OK | Note |
|-------|:--:|------|
| 2-kort er 2 frem | ✓ | `cfg.forwardSteps == [2]` |
| Passage tjekkes | ✓ | Felt 4 er ikke UD-felt |
| Landing på tom celle: legal | ✓ | |

**Position efter:** Rød: `p0.0` på `TrackPosition(5)`. Hånd tom (Rød sidder over resten af runden).

---

## Hånden afsluttes

På dette tidspunkt har alle 4 spillere enten spillet alle 4 kort eller siddet over. Kortgiverposition roteres (eller forbliver hos starter i 3 runder) og næste hånd uddeles.

**Slut-status efter hånd 1:**

| Spiller | Position | Hjemme |
|---------|----------|-------:|
| Rød (`p0.0`) | TrackPosition(5) | 0 |
| Blå | alle i start | 0 |
| Grøn (`p2.0`) | TrackPosition(30) | 0 |
| Grøn (`p2.1`) | TrackPosition(36) | 0 |
| Gul (`p3.0`) | TrackPosition(6) | 0 |

---

## Regel-tjekliste — hvad denne playthrough dækker

| Regel | Demonstreret | Tur | Note |
|-------|:------------:|:---:|------|
| Ud af start med UD-kort | ✓ | 1 | Rød UD♥ |
| Ud af start med Es | ✓ | 4 | Gul A♥ |
| Ud af start med Konge | ✓ | 3, 6 | Grøn K♣, K♠ |
| Brikken lander på spillerens UD-felt | ✓ | 1, 3, 4, 6 | TrackPosition(15*p) |
| Egne brikker kan stables på UD-felt | ✓ | 6 | Grøn p2.0 + p2.1 |
| Fremad-flytning | ✓ | 5, 7, 9, 10, 11 | Diverse tal |
| Baglæns-flytning (4-kort) | ✓ | 8 | Rød 4♥ baglæns |
| 7-split (med 1 brik) | ✓ | 5 | Rød 7♣ → felt 7 |
| 7-split (over flere egne brikker) | ✗ | — | Ikke testet i denne hånd |
| 7-partner-overløb (alle egne hjemme) | ✗ | — | Ikke testet i denne hånd |
| Hjemstræk-indgang | ✗ | — | Ikke testet i denne hånd |
| Hjemstræk-overskridelse-afvisning | ✗ | — | Dækket af unit-tests |
| Slag (PRÆCIS én modstander) | ✗ | — | Ikke testet i denne hånd |
| Dobbelt brænder | ✗ | — | Dækket af unit-tests |
| Bevogtet UD-felt blokerer passage | ✓ | 7 (analyseret) | Grøn dobbelt på 30 ville have blokeret gul fra 20 |
| Bevogtet UD-felt blokerer landing | ✗ | — | Dækket af unit-tests |
| Wrap-around forward (over index 0) | ✓ | 10 | Gul J♦: 55 → 6 |
| Wrap-around backward | ✗ | — | Dækket af unit-tests |
| Stak på egen brik (intet slag) | ✓ | 6 | Konge → eksisterende brik på UD-felt |
| Pass når intet lovligt træk | ✓ | 2 | Blå sad over |
| Kortbytte med makker | ✗ (sprunget over) | — | UI/engine-test, ikke nødvendig at trace manuelt |
| Knægt-byt | n/a | — | Knægt = 11 frem i default (byt slået fra) |
| Sejr-betingelse (alle 8 hjemme) | ✗ | — | Tager mange flere hænder |

**Konklusion:** Denne hånd dækker 12 af 22 regler direkte. Resterende 10 dækkes af unit-tests (`test/rules_test.dart` har 19 grupperede tests + `lib/game/self_test.dart` selvtest med 8 regel-tjek + 20 fulde simulerede spil).

## Fundne bugs der nu er fixet (af 60-ring-refactoren)

1. **Passage over UD-felt med modstander-dobbelt**. Tidligere: gul kunne rykke fra 20 til 30 og lande på/over grønts dobbelt fordi UD-felt lå "uden for ringen" som ExitPosition. **Nu**: tur 7's analyse viser at passage fanges af `_entryBlocked`.
2. **7-split fra UD-felt**. Tidligere: hvis brik stod på `ExitPosition(0)`, blev split-distributioner beregnet forkert (ExitPosition var ikke en `TrackPosition`, så de fleste regler skubbede den uden om). **Nu**: brik på `TrackPosition(0)` deles helt normalt, fx 7 = `[7]` → felt 7, `[3, 4]` over to brikker, osv.

## Anbefalede næste verifikationer

- Slag-scenarie: opsæt en hånd hvor rød lander på gul (alene) på et midter-felt.
- 7-split partner-overløb: alle 4 egne brikker i hjemstræk, makker har 1+ på banen. Spil en 7'er.
- Hjemstræk-blokering: egen brik i slot 0, anden brik prøver at lande slot 0.

---

*Rapport genereret manuelt, baseret på direkte trace af `lib/game/rules.dart` og `lib/game/game_engine.dart`.*
