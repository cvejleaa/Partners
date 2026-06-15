import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';

import 'test_helpers.dart';

void main() {
  test('GameState round-trip gennem (de)serialisering', () {
    final s = makeState(
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(7),
          const HomeStretchPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int sl = 0; sl < 4; sl++) StartPosition(i, sl)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard.exit(0),
          PlayingCard(Rank.seven, Suit.hearts),
        ],
        const <PlayingCard>[PlayingCard(Rank.king, Suit.spades)],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
      currentPlayerIndex: 2,
    );

    final s2 = gameStateFromMap(gameStateToMap(s));

    expect(s2.players.length, 4);
    expect(s2.currentPlayerIndex, 2);
    expect(s2.geometry.trackLength, s.geometry.trackLength);
    expect(s2.players[0].pieces[0].position, const TrackPosition(7));
    expect(s2.players[0].pieces[1].position, const HomeStretchPosition(0, 1));
    expect(s2.players[0].hand[0], const PlayingCard.exit(0));
    expect(s2.players[0].hand[1], const PlayingCard(Rank.seven, Suit.hearts));
    expect(s2.players[1].hand[0], const PlayingCard(Rank.king, Suit.spades));
    // Farve og navn bevares.
    expect(s2.players[0].color, s.players[0].color);
    expect(s2.players[0].name, s.players[0].name);
  });
}
