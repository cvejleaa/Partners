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
/// [aggregate] er brugerens samlede (gemte) stats; [lastGame] er stats for KUN
/// det seneste afsluttede spil. Begge skal være for samme bruger. Returnerer en
/// (muligvis tom) liste af rekorder.
List<GameRecord> recordsFromLastGame({
  required UserStats aggregate,
  required UserStats lastGame,
}) {
  final records = <GameRecord>[];

  // 🏁 Hurtigste sejr nogensinde.
  final lastWin = lastGame.shortestWin;
  final bestWin = aggregate.shortestWin;
  if (lastWin != null && lastGame.gamesWon > 0 && bestWin != null) {
    // Sidste spil satte rekorden hvis dens hand-tal matcher aggregatets bedste.
    if (lastWin <= bestWin) {
      records.add(GameRecord(
        id: 'fastest_win',
        emoji: '🏁',
        message: 'Ny rekord! Hurtigste sejr nogensinde ($lastWin hænder)',
      ));
    }
  }

  // 🔥 Flest slag i ét spil. Kræver mindst 2 for ikke at fejre trivielt.
  final lastMax = lastGame.maxCapturesInGame;
  final bestMax = aggregate.maxCapturesInGame;
  if (lastMax >= 2 && lastMax >= bestMax) {
    records.add(GameRecord(
      id: 'most_captures',
      emoji: '🔥',
      message: 'Ny rekord: flest slag i ét spil ($lastMax)',
    ));
  }

  // 🏠 Flest brikker i mål i ét spil. (Aggregatet summerer over alle spil, så
  // vi kan ikke aflæse "bedste enkeltspil" derfra — vi viser kun et banner hvis
  // spilleren fik alle 4 brikker i mål i dette spil, hvilket altid er flot.)
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
