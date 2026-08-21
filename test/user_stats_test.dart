import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/stats/stats_repository.dart';
import 'package:partners/stats/user_stats.dart';

void main() {
  Map<String, dynamic> moveEntry(int player, PlayingCard card,
          List<({String id, PiecePosition from, PiecePosition to})> steps,
          {int? tMs}) =>
      <String, dynamic>{
        'player': player,
        'type': 'move',
        'card': cardToMap(card),
        'steps': steps
            .map((s) => <String, dynamic>{
                  'pieceId': s.id,
                  'from': posToMap(s.from),
                  'to': posToMap(s.to),
                })
            .toList(),
        if (tMs != null) 't': tMs,
      };

  Map<String, dynamic> passEntry(int player, int cards) => <String, dynamic>{
        'player': player,
        'type': 'pass',
        'cardsDiscarded': cards,
      };

  Map<String, dynamic> game({
    required List<String> uids,
    required List<String> names,
    required int winningTeam,
    required int hands,
    String? hostUid,
    int createdMs = 0,
    int? finishedMs,
    List<Map<String, dynamic>> log = const <Map<String, dynamic>>[],
    Map<String, dynamic>? cardRules,
    String? vid,
  }) =>
      <String, dynamic>{
        'status': 'over',
        'uids': uids,
        'names': names,
        'winningTeamIndex': winningTeam,
        // vid ligger i state (som gameStateToMap skriver det) — attributions-
        // nøglen læses derfra, aldrig fra topniveau.
        'state': <String, dynamic>{'hn': hands, if (vid != null) 'vid': vid},
        'hostUid': hostUid ?? uids.first,
        'cardRules': cardRules ?? CardRules.defaults().toJson(),
        'log': log,
        'createdAt': createdMs,
        if (finishedMs != null) 'finishedAt': finishedMs,
      };

  test('en simpel sejr tæller korrekt', () {
    final result = computeAllStats(<Map<String, dynamic>>[
      game(
        uids: <String>['u0', 'u1', 'u2', 'u3'],
        names: <String>['Alice', 'Bob', 'Carol', 'Dave'],
        winningTeam: 0,
        hands: 5,
      ),
    ]);
    expect(result['u0']!.gamesPlayed, 1);
    expect(result['u0']!.gamesWon, 1);
    expect(result['u0']!.winRate, 1.0);
    expect(result['u2']!.gamesWon, 1); // makker
    expect(result['u1']!.gamesWon, 0);
    expect(result['u0']!.shortestWin, 5);
    expect(result['u0']!.currentWinStreak, 1);
    expect(result['u0']!.longestWinStreak, 1);
  });

  test('split-7 vs samlet-7 tælles korrekt', () {
    final result = computeAllStats(<Map<String, dynamic>>[
      game(
        uids: <String>['u0', 'u1', 'u2', 'u3'],
        names: <String>['A', 'B', 'C', 'D'],
        winningTeam: 0,
        hands: 3,
        log: <Map<String, dynamic>>[
          // Først bringer vi to brikker ud
          moveEntry(0, const PlayingCard.exit(0), [
            (id: 'p0.0', from: const StartPosition(0, 0), to: const TrackPosition(0)),
          ]),
          moveEntry(0, const PlayingCard.exit(1), [
            (id: 'p0.1', from: const StartPosition(0, 1), to: const TrackPosition(0)),
          ]),
          // Split-7 (2 steps)
          moveEntry(0, const PlayingCard(Rank.seven, Suit.hearts), [
            (id: 'p0.0', from: const TrackPosition(0), to: const TrackPosition(3)),
            (id: 'p0.1', from: const TrackPosition(0), to: const TrackPosition(4)),
          ]),
          // Samlet 7 (1 step)
          moveEntry(0, const PlayingCard(Rank.seven, Suit.spades), [
            (id: 'p0.0', from: const TrackPosition(3), to: const TrackPosition(10)),
          ]),
        ],
      ),
    ]);
    final s = result['u0']!;
    expect(s.split7Count, 1);
    expect(s.solid7Count, 1);
    expect(s.split7Ratio, 0.5);
  });

  test('yndlingsåbner identificeres', () {
    final result = computeAllStats(<Map<String, dynamic>>[
      game(
        uids: <String>['u0', 'u1', 'u2', 'u3'],
        names: <String>['A', 'B', 'C', 'D'],
        winningTeam: 0,
        hands: 2,
        log: <Map<String, dynamic>>[
          // 2 gange Es ud, 1 gang UD-kort
          moveEntry(0, const PlayingCard(Rank.ace, Suit.hearts), [
            (id: 'p0.0', from: const StartPosition(0, 0), to: const TrackPosition(0)),
          ]),
          moveEntry(0, const PlayingCard(Rank.ace, Suit.clubs), [
            (id: 'p0.1', from: const StartPosition(0, 1), to: const TrackPosition(0)),
          ]),
          moveEntry(0, const PlayingCard.exit(0), [
            (id: 'p0.2', from: const StartPosition(0, 2), to: const TrackPosition(0)),
          ]),
        ],
      ),
    ]);
    expect(result['u0']!.favoriteOpener, 'A');
    expect(result['u0']!.favoriteStarter['A'], 2);
    expect(result['u0']!.favoriteStarter['UD'], 1);
  });

  test('pass-events tælles per spiller', () {
    final result = computeAllStats(<Map<String, dynamic>>[
      game(
        uids: <String>['u0', 'u1', 'u2', 'u3'],
        names: <String>['A', 'B', 'C', 'D'],
        winningTeam: 0,
        hands: 2,
        log: <Map<String, dynamic>>[
          passEntry(1, 3),
          passEntry(1, 2),
        ],
      ),
    ]);
    expect(result['u1']!.passCount, 2);
    expect(result['u1']!.totalCardsDiscarded, 5);
  });

  test('bedste makker udvælges som højest win-rate', () {
    final games = <Map<String, dynamic>>[
      // u0 + u2 makkere — 2 sejre
      game(
        uids: <String>['u0', 'u1', 'u2', 'u3'],
        names: <String>['A', 'B', 'C', 'D'],
        winningTeam: 0,
        hands: 5,
      ),
      game(
        uids: <String>['u0', 'u1', 'u2', 'u3'],
        names: <String>['A', 'B', 'C', 'D'],
        winningTeam: 0,
        hands: 6,
      ),
      // u0 + u4 makkere — 1 sejr, 1 tab
      game(
        uids: <String>['u0', 'u1', 'u4', 'u3'],
        names: <String>['A', 'B', 'E', 'D'],
        winningTeam: 0,
        hands: 7,
      ),
      game(
        uids: <String>['u0', 'u1', 'u4', 'u3'],
        names: <String>['A', 'B', 'E', 'D'],
        winningTeam: 1,
        hands: 8,
      ),
    ];
    final r = computeAllStats(games);
    final best = r['u0']!.bestPartner;
    expect(best, isNotNull);
    expect(best!.key, 'u2');
    expect(best.value.games, 2);
    expect(best.value.wins, 2);
  });

  test('chronologisk sortering giver korrekt win-streak', () {
    final games = <Map<String, dynamic>>[
      // ældst først (lav createdMs)
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 0, hands: 3, createdMs: 100),
      // u0 taber næste
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 1, hands: 4, createdMs: 200),
      // vinder igen
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 0, hands: 5, createdMs: 300),
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 0, hands: 6, createdMs: 400),
    ];
    final r = computeAllStats(games);
    expect(r['u0']!.gamesWon, 3);
    expect(r['u0']!.gamesPlayed, 4);
    expect(r['u0']!.currentWinStreak, 2);
    expect(r['u0']!.longestWinStreak, 2);
  });

  test('toJson/fromJson round-trip', () {
    final games = <Map<String, dynamic>>[
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 0, hands: 3),
    ];
    final r = computeAllStats(games);
    final original = r['u0']!;
    final round = UserStats.fromJson(original.toJson()..remove('updatedAt'));
    expect(round.gamesPlayed, original.gamesPlayed);
    expect(round.gamesWon, original.gamesWon);
    expect(round.displayName, original.displayName);
    expect(round.shortestWin, original.shortestWin);
  });

  test(
      'en brugers stats er uafhængige af spil brugeren ikke selv deltog i '
      '(dækker forbrugs-fixet: kun egne spil læses, se stats_repository.dart)',
      () {
    // Spil hvor u0 selv deltager.
    final ownGames = <Map<String, dynamic>>[
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 0, hands: 5, createdMs: 100),
      game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
          winningTeam: 1, hands: 4, createdMs: 300),
    ];
    // Fremmede spil, hvor u0 IKKE er med — skal ikke påvirke u0's tal, uanset
    // hvornår de er spillet (før, imellem eller efter u0's egne spil).
    final foreignGames = <Map<String, dynamic>>[
      game(uids: ['u5', 'u6', 'u7', 'u8'], names: ['E', 'F', 'G', 'H'],
          winningTeam: 0, hands: 9, createdMs: 50),
      game(uids: ['u5', 'u6', 'u7', 'u8'], names: ['E', 'F', 'G', 'H'],
          winningTeam: 1, hands: 2, createdMs: 200),
      game(uids: ['u5', 'u6', 'u7', 'u8'], names: ['E', 'F', 'G', 'H'],
          winningTeam: 0, hands: 3, createdMs: 400),
    ];

    final statsOwnOnly = computeAllStats(ownGames);
    final statsWithForeign =
        computeAllStats(<Map<String, dynamic>>[...ownGames, ...foreignGames]);

    final u0Only = statsOwnOnly['u0']!;
    final u0WithForeign = statsWithForeign['u0']!;

    // Sammenlign hele det serialiserede billede (minus server-timestampet)
    // for at fange enhver afvigelse, ikke kun et par udvalgte felter.
    final jsonOnly = u0Only.toJson()..remove('updatedAt');
    final jsonWithForeign = u0WithForeign.toJson()..remove('updatedAt');
    expect(jsonWithForeign, jsonOnly);

    // Sanity: de fremmede uids optræder slet ikke i resultatet fra det
    // fulde sæt af spil, når kun u0's egne spil filtreres frem.
    expect(statsOwnOnly.containsKey('u5'), isFalse);
  });

  group('statistik pr. variant', () {
    test('byVariant partitionerer korrekt OG top-niveau er summen', () {
      final r = computePartitionedStats(<Map<String, dynamic>>[
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 0, hands: 5, createdMs: 100, vid: 'classic'),
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 1, hands: 4, createdMs: 200, vid: 'classic'),
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 0, hands: 7, createdMs: 300, vid: 'p25'),
      ]);
      // Nøjagtigt de to varianter der har spil — ingen tomme nøgler.
      expect(r.byVariant.keys.toSet(), <String>{'classic', 'p25'});
      expect(r.byVariant['classic']!['u0']!.gamesPlayed, 2);
      expect(r.byVariant['classic']!['u0']!.gamesWon, 1);
      expect(r.byVariant['p25']!['u0']!.gamesPlayed, 1);
      expect(r.byVariant['p25']!['u0']!.gamesWon, 1);
      // Top-niveau = alle spil (2 + 1), IKKE en kopi af en enkelt spand.
      expect(r.total['u0']!.gamesPlayed, 3);
      expect(r.total['u0']!.gamesWon, 2);
      // Spil uden vid (historisk doc) attribueres classic.
      final r2 = computePartitionedStats(<Map<String, dynamic>>[
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 0, hands: 5),
      ]);
      expect(r2.byVariant.keys.toSet(), <String>{'classic'});
    });

    test('streaks er PR. VARIANT: et p25-nederlag bryder ikke klassisk-stimen',
        () {
      final r = computePartitionedStats(<Map<String, dynamic>>[
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 0, hands: 5, createdMs: 100, vid: 'classic'),
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 1, hands: 4, createdMs: 200, vid: 'p25'),
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 0, hands: 6, createdMs: 300, vid: 'classic'),
      ]);
      // Samlet: sejr, nederlag, sejr → stime 1.
      expect(r.total['u0']!.currentWinStreak, 1);
      // Klassisk-spanden ser kun de to klassiske sejre → stime 2. (En
      // implementation der deler streak-tilstand på tværs af spande ville
      // give 1 her → rød.)
      expect(r.byVariant['classic']!['u0']!.currentWinStreak, 2);
    });

    test('delekort tælles på reglens FORM — i 25 år er det 4-kortet', () {
      // Effektive 25 år-regler: split ligger på Rank.four (4×1); 7'eren er
      // 7-frem/+2−5 og har INTET splitTotal.
      final p25Rules = CardRules.defaults()
          .withOverrides(partners25.cardRuleOverrides!)
          .toJson();
      final r = computeAllStats(<Map<String, dynamic>>[
        game(
          uids: <String>['u0', 'u1', 'u2', 'u3'],
          names: <String>['A', 'B', 'C', 'D'],
          winningTeam: 0,
          hands: 3,
          vid: 'p25',
          cardRules: p25Rules,
          log: <Map<String, dynamic>>[
            moveEntry(0, const PlayingCard.exit(0), [
              (id: 'p0.0', from: const StartPosition(0, 0), to: const TrackPosition(0)),
            ]),
            moveEntry(0, const PlayingCard.exit(1), [
              (id: 'p0.1', from: const StartPosition(0, 1), to: const TrackPosition(0)),
            ]),
            // 4×1 delt over to brikker → tæller som DELT.
            moveEntry(0, const PlayingCard(Rank.four, Suit.hearts), [
              (id: 'p0.0', from: const TrackPosition(0), to: const TrackPosition(2)),
              (id: 'p0.1', from: const TrackPosition(0), to: const TrackPosition(2)),
            ]),
            // 4×1 spillet på én brik → tæller som SAMLET.
            moveEntry(0, const PlayingCard(Rank.four, Suit.spades), [
              (id: 'p0.0', from: const TrackPosition(2), to: const TrackPosition(6)),
            ]),
            // 25 år-7'eren (7 frem, ét step) er IKKE et delekort — den gamle
            // rang-bundne tæller (`rank == seven`) talte den som "samlet 7"
            // og gav dermed falsk statistik i varianten → denne linje + de to
            // ovenfor gør den implementation rød (den ville give 0 delt/2
            // samlet i stedet for 1/1).
            moveEntry(0, const PlayingCard(Rank.seven, Suit.clubs), [
              (id: 'p0.1', from: const TrackPosition(2), to: const TrackPosition(9)),
            ]),
          ],
        ),
      ]);
      final s = r['u0']!;
      expect(s.split7Count, 1);
      expect(s.solid7Count, 1);
      // +2−5-sekvensen (2 steps, SAMME brik) tæller som samlet, ikke delt —
      // kun hvis rangen overhovedet har splitTotal (det har 7'eren ikke i
      // 25 år, så den tælles slet ikke).
    });

    test('docJsonFor: kun spillede varianter, nested uden timestamp, slim form',
        () {
      final r = computePartitionedStats(<Map<String, dynamic>>[
        game(uids: ['u0', 'u1', 'u2', 'u3'], names: ['A', 'B', 'C', 'D'],
            winningTeam: 0, hands: 5, vid: 'p25'),
      ]);
      final full = StatsRepository.docJsonFor(r.total['u0']!, r.byVariant,
          slim: false);
      // Top-niveau har timestamp; nested har IKKE (N+1-sentinel-fælden).
      expect(full.containsKey('updatedAt'), isTrue);
      final by = full['byVariant'] as Map<String, dynamic>;
      expect(by.keys.toSet(), <String>{'p25'});
      expect((by['p25'] as Map).containsKey('updatedAt'), isFalse);
      expect((by['p25'] as Map)['gamesPlayed'], 1);

      final slim = StatsRepository.docJsonFor(r.total['u0']!, r.byVariant,
          slim: true);
      final slimBy = (slim['byVariant'] as Map)['p25'] as Map;
      // Slank ranglisteform: bærer toplisternes felter, men IKKE de tunge
      // maps (payload-loftet for den offentlige userStatsOnline).
      expect(slimBy['gamesPlayed'], 1);
      expect(slimBy['gamesWon'], 1);
      expect(slimBy.containsKey('partnerStats'), isFalse);
      expect(slimBy.containsKey('rivalStats'), isFalse);
      expect(slimBy.containsKey('favoriteStarter'), isFalse);
    });

    test('UserStatsDoc.fromJson: gamle docs uden byVariant → tom map', () {
      final doc = UserStatsDoc.fromJson(<String, dynamic>{
        'uid': 'u0',
        'displayName': 'A',
        'gamesPlayed': 7,
      });
      expect(doc.total.gamesPlayed, 7);
      expect(doc.byVariant, isEmpty);
      // Skævt byVariant (fjendtligt/korrupt) → ignoreres defensivt.
      final skew = UserStatsDoc.fromJson(<String, dynamic>{
        'uid': 'u0',
        'byVariant': 42,
      });
      expect(skew.byVariant, isEmpty);
    });

    test('recordAggregateFor: manglende byVariant hos aktiv bruger → INGEN '
        'rekorder (aldrig top-niveau-fallback)', () {
      // Bruger med 40 spil i cachen, men cachen er endnu ikke variant-opdelt
      // (genberegning mangler). En implementation der falder tilbage til
      // top-niveau-aggregatet ville returnere doc.total her → rød. (Det var
      // netop fejlen: en langsom variant kunne aldrig slå den samlede rekord.)
      final active = UserStatsDoc.fromJson(<String, dynamic>{
        'uid': 'u0',
        'displayName': 'A',
        'gamesPlayed': 40,
        'shortestWin': 3,
      });
      expect(StatsRepository.recordAggregateFor(active, 'p25'), isNull);

      // byVariant HAR varianten → præcis dét aggregat.
      final scoped = UserStatsDoc.fromJson(<String, dynamic>{
        'uid': 'u0',
        'gamesPlayed': 40,
        'shortestWin': 3,
        'byVariant': <String, dynamic>{
          'p25': <String, dynamic>{'uid': 'u0', 'gamesPlayed': 2, 'shortestWin': 9},
        },
      });
      expect(
          StatsRepository.recordAggregateFor(scoped, 'p25')!.shortestWin, 9);

      // Helt tom cache (0 spil) → tomt aggregat (førstegangs-logik).
      final empty = UserStatsDoc.fromJson(
          <String, dynamic>{'uid': 'u0', 'displayName': 'A'});
      final agg = StatsRepository.recordAggregateFor(empty, 'classic');
      expect(agg, isNotNull);
      expect(agg!.gamesPlayed, 0);
    });

    test('chunked: 501 docs → flere batches, ingen tabes, rækkefølgen holder',
        () {
      final items = List<int>.generate(501, (i) => i);
      final chunks = StatsRepository.chunked(items, 150);
      expect(chunks.map((c) => c.length).toList(), <int>[150, 150, 150, 51]);
      expect(chunks.expand((c) => c).toList(), items);
      // Grænsetilfælde: præcis delelig og tom liste.
      expect(StatsRepository.chunked(List<int>.generate(300, (i) => i), 150)
          .map((c) => c.length), <int>[150, 150]);
      expect(StatsRepository.chunked(<int>[], 150), isEmpty);
    });
  });
}
