// Personlige rekorder (statistik Fase 4) — bruges til rekord-banneret på
// sejrsskærmen.
//
// Vigtigt om datamodellen: når et AI-spil afsluttes, persisteres det og
// stats-cachen GENBEREGNES med det netop spillede spil inkluderet. Derfor kan
// vi ikke "sammenligne mod en aggregeret værdi UDEN det sidste spil".
//
// I stedet sammenligner vi det seneste spils værdi mod den AGGREGEREDE rekord:
// hvis det seneste spil leverede en værdi der er lig med (og dermed satte) den
// aggregerede rekord, så er det en ny personlig rekord. Det er robust: hvis
// stats endnu ikke er genberegnet, vil [lastGame]-værdien stadig matche når den
// faktisk er ny.

import 'user_stats.dart';

/// En enkelt opnået rekord, klar til visning.
class GameRecord {
  const GameRecord({
    required this.id,
    required this.emoji,
    required this.message,
  });

  final String id;
  final String emoji;
  final String message;
}

/// Find personlige rekorder sat i det seneste spil.
///
/// [aggregate] er brugerens VARIANT-SCOPEDE (gemte) stats for det spils
/// variant; [lastGame] er stats for KUN det seneste afsluttede spil. Begge
/// skal være for samme bruger. [variantLabel] er variantens korte etiket
/// ("Klassisk"/"25 år"/custom-navn) og indgår i rekord-teksten, så "Ny
/// rekord i 25 år!" ikke kan forveksles med den samlede historik. Returnerer
/// en (muligvis tom) liste af rekorder.
List<GameRecord> recordsFromLastGame({
  required UserStats aggregate,
  required UserStats lastGame,
  required String variantLabel,
}) {
  final records = <GameRecord>[];

  // 🏁 Hurtigste sejr i varianten.
  final lastWin = lastGame.shortestWin;
  final bestWin = aggregate.shortestWin;
  if (lastWin != null && lastGame.gamesWon > 0 && bestWin != null) {
    // Småstikprøve-regel: med under 3 sejre i varianten er "rekord" et tomt
    // ord (2. sejr slår næsten altid noget). Præcis: 1 sejr → "Første sejr",
    // 2 sejre → intet banner, ≥3 sejre → ægte rekord-sammenligning. (Grænsen
    // 3 er valgt så den GAMLE opførsel — banner ved hver hurtigste sejr fra
    // spil ét — ville fejle en test på netop sejr nr. 2.)
    if (aggregate.gamesWon <= 1) {
      records.add(GameRecord(
        id: 'first_win',
        emoji: '🎉',
        message: 'Første sejr i $variantLabel!',
      ));
    } else if (aggregate.gamesWon >= 3 && lastWin <= bestWin) {
      // Sidste spil satte rekorden hvis dens hand-tal matcher aggregatets
      // bedste.
      records.add(GameRecord(
        id: 'fastest_win',
        emoji: '🏁',
        message:
            'Ny rekord i $variantLabel! Hurtigste sejr ($lastWin hænder)',
      ));
    }
  }

  // 🔥 Flest slag i ét spil. Kræver mindst 2 for ikke at fejre trivielt.
  // Sammenligningen er variant-scoped (aggregatet er det), så etiketten skal
  // med — ellers læses banneret som en all-time-rekord.
  final lastMax = lastGame.maxCapturesInGame;
  final bestMax = aggregate.maxCapturesInGame;
  if (lastMax >= 2 && lastMax >= bestMax) {
    records.add(GameRecord(
      id: 'most_captures',
      emoji: '🔥',
      message: 'Ny rekord i $variantLabel: flest slag i ét spil ($lastMax)',
    ));
  }

  // 🏠 Flest brikker i mål i ét spil. (Aggregatet summerer over alle spil, så
  // vi kan ikke aflæse "bedste enkeltspil" derfra — vi viser kun et banner hvis
  // spilleren fik alle 4 brikker i mål i dette spil, hvilket altid er flot.
  // BEVIDST uden variant-etiket: banneret sammenligner ikke mod aggregatet —
  // det fejrer en enkeltspils-bedrift, som er ens i alle varianter.)
  if (lastGame.homeStretchEntries >= 4) {
    records.add(GameRecord(
      id: 'all_home',
      emoji: '🏠',
      message:
          'Flot! ${lastGame.homeStretchEntries} brikker hele vejen i mål',
    ));
  }

  return records;
}
