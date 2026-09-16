// MÅLINGEN bag "AI'en blev bedre til at vurdere kort".
//
// Husreglen: et tal uden kode er en påstand. Scriptet ligger derfor her,
// committet og kørbart:
//     flutter test test/ai_card_value_measure_test.dart
//
// Den sætter NY kortvurdering (udledt af kortets evner) mod den GAMLE faste
// rang-tabel i tre opsætninger — klassisk, 25 år, og en "kun baglæns"-firer
// som admin kan sætte den.
//
// HVAD MÅLINGEN IKKE DÆKKER: Deck.fresh() er appens egen kortfordeling
// (4 kulører × 13 + 4 UD). Antallet af hvert korttype i den fysiske æske er
// markeret [HUL] i docs/partners-varianter.md. Tallene gælder altså under
// appens fordeling — ikke under den kasse, der står på bordet.
//
// Vinderandel er bevidst IKKE hovedtallet: to AI'er der deler den samme
// træk-vurdering lander tæt på 50/50, og forskellen drukner i støj længe
// efter en forringelse ville være synlig i de andre tal.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'harness/full_game.dart';

const int kSeeds = 100;

class Tally {
  int games = 0;
  int hands = 0;
  int discards = 0;
  int drought = 0;
  int illegal = 0;
  final Map<String, int> given = <String, int>{};

  void add(GameResult r) {
    games++;
    hands += r.handsPlayed;
    discards += r.discards;
    drought += r.exitDrought;
    illegal += r.illegalMoves;
    r.givenByRank.forEach((String k, int n) => given[k] = (given[k] ?? 0) + n);
  }

  double get avgHands => hands / games;
  double get avgDiscards => discards / games;
  double get avgDrought => drought / games;
  double givenAvg(String rank) => (given[rank] ?? 0) / games;
}

void main() {
  final Map<String, CardRules> setups = <String, CardRules>{
    'klassisk': CardRules.defaults(),
    '25 år': effectiveCardRules(partners25, CardRules.defaults()),
    // Brugerens egen: fireren kan KUN baglæns.
    'firer kun baglæns': CardRules.defaults()
        .withRank(Rank.four, const CardRuleConfig(backwardSteps: 4)),
  };

  test('MÅLING: ny kortvurdering mod den gamle rang-tabel', () {
    final StringBuffer out = StringBuffer();
    out.writeln('');
    out.writeln('=== Kortvurdering: NY (evne-udledt) mod GAMMEL (rang-tabel) ===');
    out.writeln('$kSeeds seeds pr. opsætning. Alle fire spillere ens i A/B;');
    out.writeln('derefter hold mod hold med sædebytte.');

    setups.forEach((String navn, CardRules rules) {
      final Tally gammel = Tally();
      final Tally ny = Tally();
      for (int seed = 0; seed < kSeeds; seed++) {
        gammel.add(playFullGame(
          seed: seed,
          cardRules: rules,
          aiFor: (int _) =>
              HeuristicAi(rng: Random(seed), useLegacyCardScore: true),
        ));
        ny.add(playFullGame(
          seed: seed,
          cardRules: rules,
          aiFor: (int _) => HeuristicAi(rng: Random(seed)),
        ));
      }

      // Hold mod hold, med sædebytte: sæde 0 giver kort og starter, så en
      // ensidig placering ville måle sædet i stedet for AI'en.
      int nyVandt = 0;
      int afgjorte = 0;
      for (int seed = 0; seed < kSeeds; seed++) {
        for (final bool nyPaaHold0 in <bool>[true, false]) {
          final GameResult r = playFullGame(
            seed: seed,
            cardRules: rules,
            aiFor: (int seat) {
              final bool hold0 = seat == 0 || seat == 2;
              final bool brugNy = hold0 == nyPaaHold0;
              return HeuristicAi(
                  rng: Random(seed + seat), useLegacyCardScore: !brugNy);
            },
          );
          if (r.winningTeam == null) continue;
          afgjorte++;
          final int nyHold = nyPaaHold0 ? 0 : 1;
          if (r.winningTeam == nyHold) nyVandt++;
        }
      }

      out.writeln('');
      out.writeln('--- $navn ---');
      out.writeln('                     gammel      ny');
      out.writeln('hænder pr. spil    ${gammel.avgHands.toStringAsFixed(1).padLeft(8)}'
          '${ny.avgHands.toStringAsFixed(1).padLeft(8)}');
      out.writeln('smidte hænder      ${gammel.avgDiscards.toStringAsFixed(1).padLeft(8)}'
          '${ny.avgDiscards.toStringAsFixed(1).padLeft(8)}');
      out.writeln('exit-tørke         ${gammel.avgDrought.toStringAsFixed(1).padLeft(8)}'
          '${ny.avgDrought.toStringAsFixed(1).padLeft(8)}');
      out.writeln('gav firer væk      ${gammel.givenAvg('four').toStringAsFixed(2).padLeft(8)}'
          '${ny.givenAvg('four').toStringAsFixed(2).padLeft(8)}');
      out.writeln('gav syver væk      ${gammel.givenAvg('seven').toStringAsFixed(2).padLeft(8)}'
          '${ny.givenAvg('seven').toStringAsFixed(2).padLeft(8)}');
      out.writeln('gav dame væk       ${gammel.givenAvg('queen').toStringAsFixed(2).padLeft(8)}'
          '${ny.givenAvg('queen').toStringAsFixed(2).padLeft(8)}');
      out.writeln('hold mod hold: ny vandt $nyVandt af $afgjorte');

      expect(gammel.illegal, 0, reason: '$navn: gammel AI lavede ulovlige træk');
      expect(ny.illegal, 0, reason: '$navn: ny AI lavede ulovlige træk');
    });

    // ignore: avoid_print
    print(out.toString());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
