import 'package:flutter_test/flutter_test.dart';
import 'package:partners/stats/badges.dart';
import 'package:partners/stats/records.dart';
import 'package:partners/stats/user_stats.dart';

void main() {
  UserStats stats({
    int gamesPlayed = 0,
    int gamesWon = 0,
    int? shortestWin,
    int maxCapturesInGame = 0,
    int totalCaptures = 0,
    int split7Count = 0,
    int solid7Count = 0,
    int swapCount = 0,
    int homeStretchEntries = 0,
    int longestWinStreak = 0,
    int gamesAsHost = 0,
    int passCount = 0,
    double? fastestThinkSeconds,
  }) =>
      UserStats(
        uid: 'u',
        displayName: 'Test',
        gamesPlayed: gamesPlayed,
        gamesWon: gamesWon,
        shortestWin: shortestWin,
        maxCapturesInGame: maxCapturesInGame,
        totalCaptures: totalCaptures,
        split7Count: split7Count,
        solid7Count: solid7Count,
        swapCount: swapCount,
        homeStretchEntries: homeStretchEntries,
        longestWinStreak: longestWinStreak,
        gamesAsHost: gamesAsHost,
        passCount: passCount,
        fastestThinkSeconds: fastestThinkSeconds,
      );

  group('badge unlock-prædikater', () {
    test('Førstegangs-sejr låser op ved første sejr', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'first_win');
      expect(b.isUnlocked(stats(gamesWon: 0)), isFalse);
      expect(b.isUnlocked(stats(gamesWon: 1)), isTrue);
    });

    test('Veteran-tiers', () {
      final b10 = kAllBadges.firstWhere((b) => b.id == 'veteran_10');
      final b25 = kAllBadges.firstWhere((b) => b.id == 'veteran_25');
      expect(b10.isUnlocked(stats(gamesPlayed: 9)), isFalse);
      expect(b10.isUnlocked(stats(gamesPlayed: 10)), isTrue);
      expect(b25.isUnlocked(stats(gamesPlayed: 24)), isFalse);
      expect(b25.isUnlocked(stats(gamesPlayed: 25)), isTrue);
    });

    test('Bordet brænder (stat #40) ved 5 slag i ét spil', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'table_on_fire');
      expect(b.isUnlocked(stats(maxCapturesInGame: 4)), isFalse);
      expect(b.isUnlocked(stats(maxCapturesInGame: 5)), isTrue);
    });

    test('Split-mester kræver ratio OG nok syvere', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'split_master');
      // høj ratio men for få syvere
      expect(b.isUnlocked(stats(split7Count: 3, solid7Count: 0)), isFalse);
      // nok syvere og ratio >= 0.7 (4/5 = 0.8)
      expect(b.isUnlocked(stats(split7Count: 4, solid7Count: 1)), isTrue);
      // nok syvere men for lav ratio (3/6 = 0.5)
      expect(b.isUnlocked(stats(split7Count: 3, solid7Count: 3)), isFalse);
    });

    test('Sejrsstime og Uovervindelig', () {
      final b3 = kAllBadges.firstWhere((b) => b.id == 'streak_3');
      final b5 = kAllBadges.firstWhere((b) => b.id == 'streak_5');
      expect(b3.isUnlocked(stats(longestWinStreak: 3)), isTrue);
      expect(b5.isUnlocked(stats(longestWinStreak: 4)), isFalse);
      expect(b5.isUnlocked(stats(longestWinStreak: 5)), isTrue);
    });

    test('Lynhurtig sejr ved kort spil', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'quick_win');
      expect(b.isUnlocked(stats(shortestWin: null)), isFalse);
      expect(b.isUnlocked(stats(shortestWin: 9)), isFalse);
      expect(b.isUnlocked(stats(shortestWin: 8)), isTrue);
    });

    test('Byttejunkie, Hjem-mester og Vært', () {
      expect(
          kAllBadges
              .firstWhere((b) => b.id == 'swap_junkie')
              .isUnlocked(stats(swapCount: 10)),
          isTrue);
      expect(
          kAllBadges
              .firstWhere((b) => b.id == 'home_master')
              .isUnlocked(stats(homeStretchEntries: 8)),
          isTrue);
      expect(
          kAllBadges
              .firstWhere((b) => b.id == 'host_5')
              .isUnlocked(stats(gamesAsHost: 5)),
          isTrue);
    });

    test('Lyn-træk ved hurtigt træk', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'lightning_move');
      expect(b.isUnlocked(stats(fastestThinkSeconds: null)), isFalse);
      expect(b.isUnlocked(stats(fastestThinkSeconds: 2.5)), isFalse);
      expect(b.isUnlocked(stats(fastestThinkSeconds: 1.2)), isTrue);
    });
  });

  group('progress', () {
    test('progressFor er 1.0 når låst op', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'veteran_10');
      expect(b.progressFor(stats(gamesPlayed: 10)), 1.0);
    });

    test('progressFor er clampet til 0..1', () {
      final b = kAllBadges.firstWhere((b) => b.id == 'veteran_10');
      expect(b.progressFor(stats(gamesPlayed: 5)), 0.5);
      expect(b.progressFor(stats(gamesPlayed: 0)), 0.0);
    });
  });

  group('aggregering', () {
    test('unlockedBadgeCount tæller korrekt', () {
      final s = stats(gamesWon: 1, gamesPlayed: 10, gamesAsHost: 5);
      // first_win + veteran_10 + host_5 = 3
      expect(unlockedBadgeCount(s), 3);
      expect(unlockedBadges(s).map((b) => b.id),
          containsAll(<String>['first_win', 'veteran_10', 'host_5']));
    });

    test('badgesByCategory dækker alle badges', () {
      final groups = badgesByCategory();
      final total = groups.values.fold<int>(0, (a, l) => a + l.length);
      expect(total, kAllBadges.length);
    });

    test('badge-id\'er er unikke', () {
      final ids = kAllBadges.map((b) => b.id).toSet();
      expect(ids.length, kAllBadges.length);
    });
  });

  group('rekorder fra seneste spil (variant-scopede)', () {
    test('hurtigste sejr giver rekord når sidste spil matcher bedste', () {
      final aggregate = stats(gamesWon: 5, shortestWin: 7);
      final lastGame = stats(gamesWon: 1, shortestWin: 7);
      final records = recordsFromLastGame(
          aggregate: aggregate, lastGame: lastGame, variantLabel: '25 år');
      expect(records.any((r) => r.id == 'fastest_win'), isTrue);
      // Etiketten SKAL stå i teksten — det er den, der adskiller "rekord i
      // 25 år" fra den samlede historik.
      expect(records.firstWhere((r) => r.id == 'fastest_win').message,
          contains('25 år'));
    });

    test('ingen hurtigste-sejr-rekord hvis sidste spil var langsommere', () {
      final aggregate = stats(gamesWon: 5, shortestWin: 5);
      final lastGame = stats(gamesWon: 1, shortestWin: 9);
      final records = recordsFromLastGame(
          aggregate: aggregate, lastGame: lastGame, variantLabel: 'Klassisk');
      expect(records.any((r) => r.id == 'fastest_win'), isFalse);
    });

    test('første sejr i en variant fejres som FØRSTE sejr, ikke rekord', () {
      // Aggregatet rummer allerede sidste spil (recompute-rækkefølgen), så
      // 1 sejr i varianten = det var den første.
      final aggregate = stats(gamesWon: 1, shortestWin: 8);
      final lastGame = stats(gamesWon: 1, shortestWin: 8);
      final records = recordsFromLastGame(
          aggregate: aggregate, lastGame: lastGame, variantLabel: '25 år');
      expect(records.any((r) => r.id == 'first_win'), isTrue);
      expect(records.firstWhere((r) => r.id == 'first_win').message,
          contains('25 år'));
      expect(records.any((r) => r.id == 'fastest_win'), isFalse);
    });

    test('sejr nr. 2 giver INTET hurtigste-sejr-banner (småstikprøve)', () {
      // 2. sejr slår næsten altid "rekorden" fra 1. sejr — et banner her er
      // støj. Den GAMLE opførsel (banner ved hver hurtigste sejr, uanset
      // stikprøve) ville give fastest_win her → denne test bliver rød.
      final aggregate = stats(gamesWon: 2, shortestWin: 6);
      final lastGame = stats(gamesWon: 1, shortestWin: 6);
      final records = recordsFromLastGame(
          aggregate: aggregate, lastGame: lastGame, variantLabel: 'Klassisk');
      expect(records.any((r) => r.id == 'fastest_win'), isFalse);
      expect(records.any((r) => r.id == 'first_win'), isFalse);
    });

    test('flest slag i ét spil giver rekord', () {
      final aggregate = stats(maxCapturesInGame: 6);
      final lastGame = stats(maxCapturesInGame: 6);
      final records = recordsFromLastGame(
          aggregate: aggregate, lastGame: lastGame, variantLabel: 'Klassisk');
      expect(records.any((r) => r.id == 'most_captures'), isTrue);
    });

    test('ingen rekorder for et helt almindeligt spil', () {
      final aggregate = stats(gamesWon: 5, shortestWin: 5, maxCapturesInGame: 6);
      final lastGame = stats(gamesWon: 0, maxCapturesInGame: 1);
      final records = recordsFromLastGame(
          aggregate: aggregate, lastGame: lastGame, variantLabel: 'Klassisk');
      expect(records, isEmpty);
    });

    test('alle 4 brikker i mål fejres', () {
      final records = recordsFromLastGame(
        aggregate: stats(),
        lastGame: stats(homeStretchEntries: 4),
        variantLabel: 'Klassisk',
      );
      expect(records.any((r) => r.id == 'all_home'), isTrue);
    });
  });
}
