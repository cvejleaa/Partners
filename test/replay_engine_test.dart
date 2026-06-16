import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/stats/replay_engine.dart';

void main() {
  const colors = <int>[0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFDD835];
  const names = <String>['P0', 'P1', 'P2', 'P3'];
  const human = <bool>[true, true, true, true];
  final rules = CardRules.defaults();

  Map<String, dynamic> moveEntry(
    int player,
    PlayingCard card,
    List<({String id, PiecePosition from, PiecePosition to})> steps,
  ) =>
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
      };

  test('move uden capture registreres som move uden captured', () {
    final result = replayGame(
      playerNames: names,
      isHuman: human,
      playerColors: colors,
      cardRules: rules,
      log: <Map<String, dynamic>>[
        moveEntry(0, const PlayingCard.exit(0), [
          (id: 'p0.0', from: const StartPosition(0, 0), to: const TrackPosition(0)),
        ]),
        moveEntry(0, const PlayingCard(Rank.three, Suit.hearts), [
          (id: 'p0.0', from: const TrackPosition(0), to: const TrackPosition(3)),
        ]),
      ],
    );
    expect(result.events.length, 2);
    expect(result.events.every((e) => e.captured.isEmpty), isTrue);
    expect(result.events[0].movedFromStart, 1);
  });

  test('capture detekteres når modstanderbrik står på target', () {
    final result = replayGame(
      playerNames: names,
      isHuman: human,
      playerColors: colors,
      cardRules: rules,
      log: <Map<String, dynamic>>[
        // P0 går ud → felt 0
        moveEntry(0, const PlayingCard.exit(0), [
          (id: 'p0.0', from: const StartPosition(0, 0), to: const TrackPosition(0)),
        ]),
        // P0 rykker 10 frem → felt 10
        moveEntry(0, const PlayingCard(Rank.ten, Suit.hearts), [
          (id: 'p0.0', from: const TrackPosition(0), to: const TrackPosition(10)),
        ]),
        // P1 går ud → felt 15 (deres ud-felt)
        moveEntry(1, const PlayingCard.exit(0), [
          (id: 'p1.0', from: const StartPosition(1, 0), to: const TrackPosition(15)),
        ]),
        // P1 rykker 5 baglæns → felt 10 (slår P0's brik på 10)
        moveEntry(1, const PlayingCard(Rank.four, Suit.clubs), [
          (id: 'p1.0', from: const TrackPosition(15), to: const TrackPosition(10)),
        ]),
      ],
    );
    expect(result.events.length, 4);
    final lastEvent = result.events.last;
    expect(lastEvent.captured, contains('p0.0'));
    expect(lastEvent.captured.length, 1);
    // P0's brik er nu sendt tilbage til start.
    final p0piece = result.finalState.players[0].pieces
        .firstWhere((p) => p.id == 'p0.0');
    expect(p0piece.position, isA<StartPosition>());
  });

  test('pass-event registreres med antal smidte kort', () {
    final result = replayGame(
      playerNames: names,
      isHuman: human,
      playerColors: colors,
      cardRules: rules,
      log: <Map<String, dynamic>>[
        <String, dynamic>{
          'player': 2,
          'type': 'pass',
          'cardsDiscarded': 3,
        },
      ],
    );
    expect(result.events.length, 1);
    expect(result.events.first.kind, ReplayKind.pass);
    expect(result.events.first.player, 2);
    expect(result.events.first.passedCards, 3);
  });

  test('movedToHomeStretch tæller når brik går i mål', () {
    final result = replayGame(
      playerNames: names,
      isHuman: human,
      playerColors: colors,
      cardRules: rules,
      log: <Map<String, dynamic>>[
        moveEntry(0, const PlayingCard(Rank.five, Suit.hearts), [
          (id: 'p0.0', from: const TrackPosition(55), to: const HomeStretchPosition(0, 0)),
        ]),
      ],
    );
    expect(result.events.first.movedToHomeStretch, 1);
  });
}
