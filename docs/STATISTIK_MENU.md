# Partners — Statistik-menu

35 forslag organiseret i 6 kategorier. Hvert forslag har effort-vurdering
(✅ Triviel / ⚙️ Medium / 🔧 Større), sjov-faktor (1-5 ⭐), og hvor den
typisk vises.

> **Hvordan vælger du?** Marker dem du vil have ved at sætte `[x]` foran
> navnet, eller skriv numrene til mig. Mit forslag til MVP står nederst.

---

## Hvilke data har vi allerede?

Pr. spil (`games/{kode}`):
- `state`: hele spiltilstanden (4 spillere, brikker, hænder, hjemstræk, dæk)
- `log`: alle træk i orden — hver entry: `player`, `card`, `steps[]{pieceId, from, to}`
- `status`: lobby / playing / over
- `winningTeamIndex` ved slut
- `starterCounts[]`, `starterIndex`, `starterStreak`
- `members[]`, `hostUid`, `hostName`, `cardRules`, `createdAt`

Pr. bruger (`users/{uid}`):
- `displayName`, `emailLower`, `updatedAt`

**Det vi ikke har endnu** (markeret 🔧 i tabellerne nedenfor):
- Tidsstempel pr. træk (`t`) → tænketid-stats
- Pass-events i log → "sad over"-stats
- `finishedAt` på spillet → spilletid i minutter
- Eksplicit capture-flag på move-steps → kræver replay af regelmotor

---

## 1. Sejre & resultater

| # | Navn | Beskrivelse | Beregning | Effort | Sjov | Hvor |
|---|------|-------------|-----------|--------|------|------|
| 1 | Vundne spil | Total antal sejre | Tæl `games` hvor `winningTeamIndex == seat%2` | ✅ | ⭐⭐ | profil, ranking |
| 2 | **Win-rate** | Andel afsluttede spil vundet | Sejre / færdige spil | ✅ | ⭐⭐⭐ | profil, ranking |
| 3 | **Bedste makker** | Partner med højest win-rate sammen med dig | Gruppér pr. (uid, partnerUid) | ⚙️ | ⭐⭐⭐⭐⭐ | profil |
| 4 | Værste rival | Modstander du taber mest til | Som ovenfor med tab | ⚙️ | ⭐⭐⭐⭐ | profil |
| 5 | Hvor jeg sad | Fordeling af 0/1/2/3-plads | Tæl `seat` | ✅ | ⭐ | profil |
| 6 | **Kortest sejr** 🏁 | Færreste hænder for at vinde | min(`handNumber`) ved sejr | ✅ | ⭐⭐⭐⭐ | site, slut |
| 7 | Comeback Kid 🔄 | Vundet fra 0 vs 3 brikker hjem | Replay → max-modstander-leading | 🔧 | ⭐⭐⭐⭐⭐ | profil, slut |

## 2. Stil & strategi

| # | Navn | Beskrivelse | Beregning | Effort | Sjov | Hvor |
|---|------|-------------|-----------|--------|------|------|
| 8 | **Slag pr. spil** ⚔️ | Gennemsnitlige modstanderslag | Replay log | ⚙️ | ⭐⭐⭐⭐⭐ | profil, slut |
| 9 | Slag modtaget | Hvor ofte dine brikker ryger hjem | Replay log | ⚙️ | ⭐⭐⭐⭐ | profil |
| 10 | **Split-7 vs Saml-7** ✂️ | Er du splitter eller samler? | `card.rank='seven'`, `steps.length>1` | ✅ | ⭐⭐⭐⭐⭐ | profil, slut |
| 11 | Byttejunkie 🔀 | Hvor ofte du bruger Knægt-byt | `card.rank='jack'`, 2-step swap | ✅ | ⭐⭐⭐⭐ | profil |
| 12 | Backwards-fan 4️⃣ | Andel 4'ere spillet baglæns | Sammenlign from→to-afstand | ⚙️ | ⭐⭐⭐ | profil |
| 13 | Dobbelt-byggeren 🛡️ | Hvor ofte du danner beskyttede dobbelter | Replay log | ⚙️ | ⭐⭐⭐⭐ | profil |
| 14 | **Hjem-mester** 🏠 | Egne brikker bragt hjem pr. spil | Tæl `to is HomeStretchPosition` | ✅ | ⭐⭐⭐ | profil, slut |
| 15 | **Yndlingsåbner** 🎴 | Kort du oftest går ud af start med | `from is StartPosition` → tæl `card.rankLabel` | ✅ | ⭐⭐⭐⭐ | profil |
| 16 | Partner-feed 🎁 | Kort du oftest giver makker | Kræver ny exchange-event i log | 🔧 | ⭐⭐⭐⭐ | profil |

## 3. Held & uheld

| # | Navn | Beskrivelse | Beregning | Effort | Sjov | Hvor |
|---|------|-------------|-----------|--------|------|------|
| 17 | Sad over runder 😴 | Hvor ofte du måtte smide hånden | Kræver pass-event i log | 🔧 | ⭐⭐⭐⭐ | profil |
| 18 | Døde kort ☠️ | Snit-kort tilbage ved pass | Som ovenfor | 🔧 | ⭐⭐⭐ | profil |
| 19 | Es-pose 🍀 | Hænder med Es eller Konge | Kræver "hand dealt"-event | 🔧 | ⭐⭐⭐⭐ | profil |
| 20 | Slag-hat trick 🎩 | Spil hvor du blev slået 3+ gange | Replay log | ⚙️ | ⭐⭐⭐⭐ | profil, slut |
| 21 | Startdyrlæge 🐎 | Hvor ofte du har været startende | `starterCounts[seat]` | ✅ | ⭐⭐ | profil |

## 4. Tempo & adfærd

| # | Navn | Beskrivelse | Beregning | Effort | Sjov | Hvor |
|---|------|-------------|-----------|--------|------|------|
| 22 | Tænketid pr. træk ⏱️ | Median sekunder mellem træk | Kræver `t` på log-entry | 🔧 | ⭐⭐⭐⭐ | profil, slut |
| 23 | Lyn-træk ⚡ | Hurtigste træk nogensinde | Som ovenfor | 🔧 | ⭐⭐⭐⭐ | profil |
| 24 | Hænder pr. spil | Snit-antal hænder før afgørelse | `handNumber` ved slut | ✅ | ⭐⭐ | site, slut |
| 25 | Online vs AI | Andel spil mod menneske vs computer | Tæl uids-fulde spil | ✅ | ⭐⭐ | profil |
| 26 | Værts-rate 👑 | Hvor ofte du er host | `hostUid==uid` / totale spil | ✅ | ⭐⭐ | profil |
| 27 | Total spilletid | Sum af spil-varighed | Kræver `finishedAt` | 🔧 | ⭐⭐⭐ | profil |

## 5. Sjove badges (engangs-præstationer)

| # | Navn | Beskrivelse | Beregning | Effort | Sjov | Hvor |
|---|------|-------------|-----------|--------|------|------|
| 28 | **Brand-mester** 🔥 | Flest slag i ét spil (rekord) | Replay → max slag pr. spil | ⚙️ | ⭐⭐⭐⭐⭐ | profil, slut |
| 29 | Defensiv 🛡️ | Alle 4 hjem uden at blive slået | Replay → 0 slag modtaget + 4 hjemme | ⚙️ | ⭐⭐⭐⭐⭐ | profil, slut |
| 30 | Snigløb 🥷 | Knægt-byt af brik der lige er kommet ud | Modstanderbrik ≤ 2 felter fra ud-felt | ⚙️ | ⭐⭐⭐⭐⭐ | profil |
| 31 | Lemming 🐹 | Vandt spil hvor du blev slået ≥ 5 gange | Replay-tæller + vinder-check | ⚙️ | ⭐⭐⭐⭐⭐ | profil |
| 32 | Knivskarp 7️⃣ | Split-7 der slår 2 brikker i samme træk | `card.rank='seven'`, 2+ capture | ⚙️ | ⭐⭐⭐⭐⭐ | profil, slut |
| 33 | Hjemmedreng 🏡 | Vundet uden at slå nogen | Replay → 0 slag givet + vundet | ⚙️ | ⭐⭐⭐⭐ | profil |
| 34 | Cliffhanger 🎢 | Vundet med kort tilbage på hånden | Sidste træk i log, hånd > 0 | ✅ | ⭐⭐⭐ | slut |
| 35 | Trofast 💍 | Vundet 5+ spil med samme makker | Tæl pr. makkerskab | ⚙️ | ⭐⭐⭐⭐ | profil |

## 6. Site-level engagement

| # | Navn | Beskrivelse | Beregning | Effort | Sjov | Hvor |
|---|------|-------------|-----------|--------|------|------|
| 36 | Spil i gang lige nu | Lobbyer + igangværende spil | `count where status in (lobby, playing)` | ✅ | ⭐⭐ | site |
| 37 | Spillere online (7 dage) | Distinkte uids med nyligt træk | `users where updatedAt > now-7d` | ⚙️ | ⭐⭐⭐ | site |
| 38 | Gns. spil-længde | Snit i hænder | snit(`handNumber`) over afsluttede | ✅ | ⭐⭐ | site |
| 39 | **Mest populære regelvariant** 🃏 | Hvilken cardRules-config bruges mest | Hash `cardRules` pr. spil, tæl | ⚙️ | ⭐⭐⭐⭐ | site |
| 40 | Bordet brænder 🔥 | Top-10 mest-slagne spil | Replay alle nylige spil | 🔧 | ⭐⭐⭐⭐ | site |
| 41 | Hot streak 📈 | Spiller med længste aktuelle sejrsstime | Sortér + tæl running sejre | ⚙️ | ⭐⭐⭐⭐⭐ | ranking |
| 42 | Seat-konstellationer | Hvilke seat-par vinder oftest | Gruppér pr. seat-par | ✅ | ⭐⭐ | site |

---

## Min anbefaling: MVP-1 (top 5 at bygge først)

Prioriteret efter **lav effort × høj sjov-faktor × tværgående værdi**:

1. **#2 Win-rate + #1 Vundne spil + #3 Bedste makker** — én sammenhængende
   profil-blok. Bedste makker er det sjove der gør profilen levende.
2. **#10 Split-7 vs Saml-7** ✂️ — ren log-aggregering, ⭐⭐⭐⭐⭐, alle
   ELSKER at se om de er splitter eller samler.
3. **#15 Yndlingsåbner** 🎴 — hvilket kort foretrækker du at gå ud med.
   Personligt og let.
4. **#14 Hjem-mester + #6 Kortest sejr** 🏠🏁 — to rekord-tal til
   slut-skærmen der gør hvert spil mindeværdigt.
5. **#8 Slag pr. spil + #28 Brand-mester-badge** ⚔️🔥 — slag er det folk
   husker fra et spil. Kræver replay af loggen, men ingen skema-ændringer.

## Strategisk anbefaling før badge-stats (kategori 5)

Inden MVP-2 anbefaler statistik-nørden to billige skema-tilføjelser der
åbner halvdelen af tabellen:

- `finishedAt: serverTimestamp()` når et spil afsluttes (åbner #27)
- `pass`-event i log + `t`-timestamp på hver move-entry (åbner #17, #18,
  #22, #23)

Det er små ændringer i `online_service.dart` / `game_engine.dart` og giver
enorm fremtidig fleksibilitet.

---

*Send mig en kort liste over hvilke numre du vil have først — eller bare
"MVP-1" hvis du vil starte med top 5.*
