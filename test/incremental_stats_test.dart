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

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
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

    test('ALLE felter overlever JSON-round-trippet seedingen bygger på', () {
      // Test Manager-fund: equivalence-testene ovenfor har tomme logs, så ca.
      // halvdelen af UserStats' felter er altid 0 dér — et glemt felt i
      // fromJson() ville ikke gøre dem røde. Her har HVERT felt en værdi
      // forskellig fra sin default. MUTATION: fjern en linje i fromJson() →
      // round-trip'et taber feltet → rød. Fjern en linje i toJson() →
      // nøgle-tjekket nederst → rød (dét fanger equivalence-testene aldrig,
      // fordi begge sider går gennem samme toJson()).
      final full = UserStats(
        uid: 'u0',
        displayName: 'Alice',
        gamesPlayed: 11,
        gamesWon: 7,
        shortestWin: 3,
        totalCaptures: 21,
        captureGames: 10,
        maxCapturesInGame: 5,
        timesCaptured: 13,
        split7Count: 4,
        solid7Count: 6,
        swapCount: 2,
        protectionCount: 8,
        homeStretchEntries: 9,
        favoriteStarter: <String, int>{'A': 3, 'K': 1},
        handsPerWinSum: 40,
        gamesAsHost: 5,
        gamesOnline: 8,
        gamesAiOnly: 3,
        partnerStats: <String, PairStats>{
          'u2': PairStats(displayName: 'Carol', games: 6, wins: 4),
        },
        rivalStats: <String, PairStats>{
          'u1': PairStats(displayName: 'Bob', games: 5, wins: 2),
        },
        totalThinkSeconds: 123.5,
        thinkCount: 77,
        fastestThinkSeconds: 0.8,
        passCount: 4,
        totalCardsDiscarded: 12,
        totalMinutesPlayed: 310.25,
        playedGamesWithDuration: 9,
        currentWinStreak: 2,
        longestWinStreak: 4,
        winMarginSum: 17,
        winMarginGames: 6,
        lossMarginSum: 9,
        lossMarginGames: 3,
        maxWinMargin: 6,
        minWinMargin: 1,
        myExitCards: 14,
        mySpecialCards: 15,
        myPlainCards: 16,
        myUnseenCards: 17,
        oppExitCards: 18,
        oppSpecialCards: 19,
        oppPlainCards: 20,
        oppUnseenCards: 22,
        cardMixGames: 10,
        myPiecesSentHome: 23,
        oppPiecesSentHome: 24,
      );
      final Map<String, dynamic> json = full.toJson(withTimestamp: false);
      final Map<String, dynamic> roundTripped =
          UserStats.fromJson(json).toJson(withTimestamp: false);
      expect(roundTripped, json);

      // Bevidst dubleret feltliste: den ENESTE måde at fange et felt der
      // aldrig SKRIVES (toJson) — round-trip'et ovenfor ser kun det der
      // både skrives og læses.
      const fields = <String>[
        'uid', 'displayName', 'gamesPlayed', 'gamesWon', 'shortestWin',
        'totalCaptures', 'captureGames', 'maxCapturesInGame', 'timesCaptured',
        'split7Count', 'solid7Count', 'swapCount', 'protectionCount',
        'homeStretchEntries', 'favoriteStarter', 'handsPerWinSum',
        'gamesAsHost', 'gamesOnline', 'gamesAiOnly', 'partnerStats',
        'rivalStats', 'totalThinkSeconds', 'thinkCount', 'fastestThinkSeconds',
        'passCount', 'totalCardsDiscarded', 'totalMinutesPlayed',
        'playedGamesWithDuration', 'currentWinStreak', 'longestWinStreak',
        'winMarginSum', 'winMarginGames', 'lossMarginSum', 'lossMarginGames',
        'maxWinMargin', 'minWinMargin', 'myExitCards', 'mySpecialCards',
        'myPlainCards', 'myUnseenCards', 'oppExitCards', 'oppSpecialCards',
        'oppPlainCards', 'oppUnseenCards', 'cardMixGames', 'myPiecesSentHome',
        'oppPiecesSentHome',
      ];
      for (final f in fields) {
        expect(json.containsKey(f), isTrue, reason: 'toJson mangler $f');
      }
    });

    test('seedet muteres IKKE — kalderens objekter er urørte bagefter', () {
      // QC-fund: kontrakten "ren funktion" håndhæves af klonen i
      // computePartitionedStats, ikke af en kommentar. MUTATION: fjern
      // klonen (brug seed-objekterne direkte) → seed.gamesPlayed bliver 2.
      final first = computePartitionedStats(<Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 5, finishedMs: 100),
      ]);
      final UserStats seed = first.total['u0']!;
      computePartitionedStats(
        <Map<String, dynamic>>[
          _game(uids: uids, names: names, winningTeam: 1, hands: 4, finishedMs: 200),
        ],
        seedTotal: <String, UserStats>{'u0': seed},
      );
      expect(seed.gamesPlayed, 1);
      expect(seed.currentWinStreak, 1);
    });
  });

  group('nextStatsCursor — cursor-fremrykning', () {
    final Timestamp t500 = Timestamp.fromMillisecondsSinceEpoch(500);

    test('ingen nye spil → cursor uændret', () {
      expect(nextStatsCursor(t500, const <Map<String, dynamic>>[]), t500);
    });

    test('nye spil → cursor rykker til det NYESTE, ikke det sidste i listen', () {
      // MUTATION: brug games.last i stedet for max → forkert hvis listen ikke
      // allerede er sorteret.
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 900),
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 700),
      ];
      expect(nextStatsCursor(t500, games),
          Timestamp.fromMillisecondsSinceEpoch(900));
    });

    test('cursoren regresserer aldrig, selv med en (unormal) ældre dato', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 100),
      ];
      expect(nextStatsCursor(t500, games), t500);
    });

    test('FULD præcision bevares — ingen afrunding til millisekunder', () {
      // Selve fejlen QC fandt: serverTimestamp har mikrosekunder. Afrundes
      // cursoren til ms (1000), matcher et spil afsluttet 1000,5 ms
      // `finishedAt > 1000 ms` IGEN næste gang og tælles to gange.
      // MUTATION: gå via millisecondsSinceEpoch → nanosekunderne tabes → rød.
      final Timestamp halfMs = Timestamp(1, 500000); // 1 s + 0,5 ms
      final game = _game(uids: uids, names: names, winningTeam: 0, hands: 1);
      game['finishedAt'] = halfMs;
      final Timestamp cursor =
          nextStatsCursor(Timestamp.fromMillisecondsSinceEpoch(0), [game]);
      expect(cursor, halfMs);
      expect(cursor.nanoseconds, 500000);
    });

    test('spil UDEN finishedAt kan aldrig blive cursor', () {
      // Spil fra før 2026-08-21 har ikke feltet — de tælles i bootstrap'en,
      // men må ikke skubbe cursoren (createdAt er IKKE forespørgslens felt).
      final game = _game(
          uids: uids, names: names, winningTeam: 0, hands: 1, createdMs: 999);
      expect(nextStatsCursor(t500, [game]), t500);
    });
  });

  group('statsCursorOf — læsning af cursor-feltet', () {
    test('mangler feltet → null (bootstrap)', () {
      expect(statsCursorOf(null), isNull);
      expect(statsCursorOf(<String, dynamic>{'gamesPlayed': 3}), isNull);
    });

    test('findes feltet → dets Timestamp', () {
      final t = Timestamp(12, 34);
      expect(statsCursorOf(<String, dynamic>{kStatsCursorField: t}), t);
    });

    test('Timestamp har værdi-lighed — kapløbs-tjekket sammenligner værdier', () {
      // recomputeAndSaveOwn afgør "vandt et andet kald kapløbet?" med
      // `fresh != cursor`. Var Timestamp identitets-lignet, ville tjekket
      // ALTID slå fejl og ingen opdatering nogensinde blive skrevet.
      expect(Timestamp(12, 34) == Timestamp(12, 34), isTrue);
      expect(Timestamp(12, 34) == Timestamp(12, 35), isFalse);
      expect(statsCursorOf(null) == statsCursorOf(null), isTrue);
    });
  });

  group('statsCursorsByUid — cursor efter en fuld admin-genberegning', () {
    test('hver deltager får det nyeste finishedAt blandt SINE spil', () {
      // QC-fund: uden dette sletter "genberegn alt" cursoren for alle og
      // sender dem tilbage til bootstrap. MUTATION: returnér {} → rød.
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 1, finishedMs: 100),
        _game(
            uids: <String>['u0', 'x1', 'x2', 'x3'],
            names: names,
            winningTeam: 0,
            hands: 1,
            finishedMs: 300),
      ];
      final cursors = statsCursorsByUid(games);
      expect(cursors['u0'], Timestamp.fromMillisecondsSinceEpoch(300));
      expect(cursors['u1'], Timestamp.fromMillisecondsSinceEpoch(100));
      expect(cursors['x1'], Timestamp.fromMillisecondsSinceEpoch(300));
    });

    test('spil uden finishedAt bidrager ikke (deltageren får ingen cursor)', () {
      final games = <Map<String, dynamic>>[
        _game(uids: uids, names: names, winningTeam: 0, hands: 1),
      ];
      expect(statsCursorsByUid(games), isEmpty);
    });
  });
}
