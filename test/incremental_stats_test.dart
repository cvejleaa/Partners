// StatsRepository.recomputeAndSaveOwn er gjort inkrementel (forbrugs-fund
// #17): i stedet for at genlæse og genberegne en brugers FULDE spilhistorik
// ved hver opdatering, fortsætter den fra den cachede UserStats + kun de
// NYE spil siden sidst. Her testes den kritiske påstand: det inkrementelle
// resultat er PRÆCIS det samme som en fuld genberegning ville give — inkl.
// streaks, som afhænger af rækkefølgen, og byVariant, som er en separat
// spand pr. variant.
//
// Testene ruller games/computePartitionedStats gennem et RIGTIGT JSON-
// round-trip (toJson → fromJson) ved seedingen, ligesom
// recomputeAndSaveOwn gør mod det cachede Firestore-doc — en test der kun
// seedede med de rå UserStats-objekter ville ikke fange et felt der glemtes
// i toJson()/fromJson().

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/stats/stats_repository.dart';
import 'package:partners/stats/user_stats.dart';

Map<String, dynamic> _game({
  required List<String> uids,
  required List<String> names,
  required int winningTeam,
  required int hands,
  String? hostUid,
  int createdMs = 0,
  int? finishedMs,
  String? vid,
}) =>
    <String, dynamic>{
      'status': 'over',
      'uids': uids,
      'names': names,
      'winningTeamIndex': winningTeam,
      'state': <String, dynamic>{'hn': hands, if (vid != null) 'vid': vid},
      'hostUid': hostUid ?? uids.first,
      'cardRules': CardRules.defaults().toJson(),
      'log': const <Map<String, dynamic>>[],
      'createdAt': createdMs,
      if (finishedMs != null) 'finishedAt': finishedMs,
    };

/// Seeder [computePartitionedStats] som recomputeAndSaveOwn reelt gør: et
/// JSON-round-trip af det tidligere resultat, ikke de rå objekter.
PartitionedStats _continueFrom(
    PartitionedStats previous, String uid, List<Map<String, dynamic>> newGames) {
  final UserStats? cachedTotal = previous.total[uid];
  final seedTotal = <String, UserStats>{
    if (cachedTotal != null) uid: UserStats.fromJson(cachedTotal.toJson()),
  };
  final seedByVariant = <String, Map<String, UserStats>>{
    for (final e in previous.byVariant.entries)
      if (e.value[uid] != null)
        e.key: {uid: UserStats.fromJson(e.value[uid]!.toJson())},
  };
  return computePartitionedStats(newGames,
      seedTotal: seedTotal, seedByVariant: seedByVariant);
}

void main() {
  const uids = <String>['u0', 'u1', 'u2', 'u3'];
  const names = <String>['Alice', 'Bob', 'Carol', 'Dave'];

  group('computePartitionedStats — inkrementel seeding == fuld genberegning', () {
    test('tre spil, ét ad gangen inkrementelt, matcher én fuld beregning', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 5, finishedMs: 100),
        _game(uids: uids, names: names, winningTeam: 0, hands: 4, finishedMs: 200),
        _game(uids: uids, names: names, winningTeam: 1, hands: 6, finishedMs: 300),
      ];

      final full = computePartitionedStats(games).total['u0']!.toJson();

      // Inkrementelt: ét spil ad gangen, seedet fra det forrige resultat.
      var step = computePartitionedStats(<Map<String, dynamic>>[games[0]]);
      step = _continueFrom(step, 'u0', <Map<String, dynamic>>[games[1]]);
      step = _continueFrom(step, 'u0', <Map<String, dynamic>>[games[2]]);
      final incremental = step.total['u0']!.toJson();

      expect(incremental, full);
    });

    test('win-streak fortsætter korrekt over cursor-grænsen', () {
      // MUTATION: seed uden currentWinStreak (fx glemt felt i toJson/fromJson)
      // → longestWinStreak ville stoppe ved 2 i stedet for 3.
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 5, finishedMs: 100), // sejr
        _game(uids: uids, names: names, winningTeam: 0, hands: 4, finishedMs: 200), // sejr
        _game(uids: uids, names: names, winningTeam: 0, hands: 3, finishedMs: 300), // sejr — stime på 3
      ];
      final full = computePartitionedStats(games).total['u0']!;

      final afterFirstTwo =
          computePartitionedStats(<Map<String, dynamic>>[games[0], games[1]]);
      final incremental =
          _continueFrom(afterFirstTwo, 'u0', <Map<String, dynamic>>[games[2]])
              .total['u0']!;

      expect(incremental.currentWinStreak, full.currentWinStreak);
      expect(incremental.longestWinStreak, full.longestWinStreak);
      expect(incremental.currentWinStreak, 3);
    });

    test('et nederlag nulstiller streak-fortsættelsen ligesom fuld genberegning', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 5, finishedMs: 100), // sejr
        _game(uids: uids, names: names, winningTeam: 1, hands: 4, finishedMs: 200), // tab
      ];
      final full = computePartitionedStats(games).total['u0']!;

      final afterFirst = computePartitionedStats(<Map<String, dynamic>>[games[0]]);
      final incremental =
          _continueFrom(afterFirst, 'u0', <Map<String, dynamic>>[games[1]]).total['u0']!;

      expect(incremental.currentWinStreak, 0);
      expect(incremental.currentWinStreak, full.currentWinStreak);
      expect(incremental.longestWinStreak, full.longestWinStreak);
    });

    test('byVariant fortsætter pr. variant, uden at blande variant-tal sammen', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 5, finishedMs: 100, vid: 'classic'),
        _game(uids: uids, names: names, winningTeam: 0, hands: 4, finishedMs: 200, vid: '25aar'),
        _game(uids: uids, names: names, winningTeam: 1, hands: 3, finishedMs: 300, vid: 'classic'),
      ];
      final full = computePartitionedStats(games);

      final afterFirstTwo =
          computePartitionedStats(<Map<String, dynamic>>[games[0], games[1]]);
      final incremental =
          _continueFrom(afterFirstTwo, 'u0', <Map<String, dynamic>>[games[2]]);

      expect(incremental.byVariant['classic']!['u0']!.toJson(),
          full.byVariant['classic']!['u0']!.toJson());
      expect(incremental.byVariant['25aar']!['u0']!.toJson(),
          full.byVariant['25aar']!['u0']!.toJson());
      // MUTATION: seed BEGGE varianter fra samme cachede spand (i stedet for
      // hver sin) → classic-stimen ville forurenes af 25aar-spillet.
      expect(incremental.byVariant['classic']!['u0']!.gamesPlayed, 2);
      expect(incremental.byVariant['25aar']!['u0']!.gamesPlayed, 1);
    });

    test('ingen nye spil giver det seedede resultat uændret (no-op)', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 5, finishedMs: 100),
      ];
      final seeded = computePartitionedStats(games);
      final result = _continueFrom(seeded, 'u0', const <Map<String, dynamic>>[]);
      expect(result.total['u0']!.toJson(), seeded.total['u0']!.toJson());
    });
  });

  group('nextStatsCursorMs — cursor-fremrykning', () {
    test('ingen nye spil → cursor uændret', () {
      expect(nextStatsCursorMs(500, const <Map<String, dynamic>>[]), 500);
    });

    test('nye spil → cursor rykker til det NYESTE, ikke det seneste i listen', () {
      // MUTATION: brug games.last i stedet for max → forkert hvis listen ikke
      // allerede er sorteret.
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 900),
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 700),
      ];
      expect(nextStatsCursorMs(500, games), 900);
    });

    test('cursoren regresserer aldrig, selv med en (unormal) ældre dato i listen', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 100),
      ];
      expect(nextStatsCursorMs(500, games), 500);
    });
  });

  group('statsCursorUnchanged — kapløbs-beskyttelsen', () {
    test('samme cursor-tilstand → true (skriv)', () {
      expect(
          statsCursorUnchanged(
              freshHasCursor: true,
              freshCursorMs: 200,
              expectedHasCursor: true,
              expectedCursorMs: 200),
          isTrue);
    });

    test('cursor-VÆRDIEN har ændret sig → false (spring over)', () {
      // MUTATION: sammenlign kun expectedHasCursor/freshHasCursor → et andet
      // kalds nyere cursor ville ikke blive opdaget.
      expect(
          statsCursorUnchanged(
              freshHasCursor: true,
              freshCursorMs: 300,
              expectedHasCursor: true,
              expectedCursorMs: 200),
          isFalse);
    });

    test('cursoren findes nu, men gjorde ikke da vi læste → false (spring over)', () {
      expect(
          statsCursorUnchanged(
              freshHasCursor: true,
              freshCursorMs: 0,
              expectedHasCursor: false,
              expectedCursorMs: 0),
          isFalse);
    });
  });
}
