import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';
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
  }) =>
      <String, dynamic>{
        'status': 'over',
        'uids': uids,
        'names': names,
        'winningTeamIndex': winningTeam,
        'state': <String, dynamic>{'hn': hands},
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
}
