// MÅLINGEN bag AI'ens kortvurdering — committet og kørbar:
//     flutter test test/ai_card_value_measure_test.dart
//
// Husreglen: et tal uden kode er en påstand.
//
// HVAD DER BLEV MÅLT, OG HVAD DER BLEV BESLUTTET
// Den gamle faste rang-tabel blev sat mod den nye evne-udledte vurdering,
// 100 seeds pr. opsætning, hold mod hold med sædebytte (200 partier):
//
//                      gammel      ny
//   klassisk    hænder    10.8    10.8   smidte 20.0 → 19.6   ny vandt 106/200
//   25 år       hænder     7.0     7.2   smidte 12.6 → 12.6   ny vandt 107/200
//   kun baglæns hænder    11.1    10.8   smidte 20.4 → 19.6   ny vandt 107/200
//
// En FØRSTE kørsel på 20 seeds pegede på en forringelse (flere hænder, flere
// smidte). Den forsvandt ved 100 seeds — det var støj. Samlet vandt den nye
// 320 af 600 (53,3 %, z=+1,63): en konsekvent retning, men på kanten af det
// signifikante. Konklusionen er derfor IKKE "AI'en er blevet stærkere", men
// "adfærden er rettet, og intet mål blev dårligere".
//
// HVAD MÅLINGEN IKKE DÆKKER: Deck.fresh() er appens egen kortfordeling
// (4 kulører × 13 + 4 UD). Antallet pr. korttype i den fysiske æske er
// markeret [HUL] i docs/partners-varianter.md. Tallene gælder under appens
// fordeling — ikke under kassen på bordet.
//
// Vinderandel er bevidst ikke hovedtallet: to AI'er der deler den samme
// TRÆK-vurdering lander tæt på 50/50, længe efter en forringelse ville være
// synlig i de andre tal.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'harness/full_game.dart';

/// Lavt nok til at køre med i hver CI-kørsel. Den beslutning målingen bar,
/// blev truffet på 100 — se tallene øverst.
const int kSeeds = 20;

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
    // Brugerens egen admin-opsætning: fireren kan KUN baglæns.
    'firer kun baglæns': CardRules.defaults()
        .withRank(Rank.four, const CardRuleConfig(backwardSteps: 4)),
  };

  test('MÅLING: AI\'ens kortvurdering, pr. opsætning', () {
    final StringBuffer out = StringBuffer('\n=== AI-kortvurdering ===\n');
    setups.forEach((String navn, CardRules rules) {
      final Tally t = Tally();
      for (int seed = 0; seed < kSeeds; seed++) {
        t.add(playFullGame(
          seed: seed,
          cardRules: rules,
          aiFor: (int seat) => HeuristicAi(rng: Random(seed + seat)),
        ));
      }
      out.writeln('$navn: hænder ${t.avgHands.toStringAsFixed(1)}  '
          'smidte ${t.avgDiscards.toStringAsFixed(1)}  '
          'exit-tørke ${t.avgDrought.toStringAsFixed(1)}  '
          'gav firer væk ${t.givenAvg('four').toStringAsFixed(2)}');

      expect(t.illegal, 0, reason: '$navn: ingen ulovlige træk');

      // VAGTEN, ikke bare et tal. Med den gamle rang-tabel gav AI'en fireren
      // væk 2,67-4,36 gange pr. spil; med den evne-udledte 0,01-0,22.
      // Båndet er valgt så den GAMLE værdi gør testen rød — et bånd der
      // rummede begge tal ville ikke måle noget.
      expect(t.givenAvg('four'), lessThan(0.5),
          reason: '$navn: fireren er et topkort (baglæns fra eget UD er '
              'spillets største tempo) og må ikke foræres væk — '
              'gammel tabel gav 2,67-4,36 pr. spil');
    });
    // ignore: avoid_print
    print(out.toString());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
