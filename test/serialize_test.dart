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

  group('describeReplayStep — "mens du var væk"-tekst', () {
    Map<String, dynamic> step(
            {required String pieceId,
            required PiecePosition from,
            required PiecePosition to,
            bool cap = false,
            bool burn = false}) =>
        <String, dynamic>{
          'pieceId': pieceId,
          'from': posToMap(from),
          'to': posToMap(to),
          if (cap) 'cap': true,
          if (burn) 'burn': true,
        };

    test('ingen steps → "sad over"', () {
      expect(describeReplayStep(<String, dynamic>{'steps': <dynamic>[]}),
          'sad over');
    });

    test('ét step til et ringfelt → "rykkede en brik til felt N"', () {
      final m = <String, dynamic>{
        'steps': <dynamic>[
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(3),
              to: const TrackPosition(7)),
        ],
      };
      expect(describeReplayStep(m), 'rykkede en brik til felt 7');
    });

    test('ét step ind i hjemstrækket → "rykkede en brik i hjemstrækket"', () {
      final m = <String, dynamic>{
        'steps': <dynamic>[
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(58),
              to: const HomeStretchPosition(0, 1)),
        ],
      };
      expect(describeReplayStep(m), 'rykkede en brik i hjemstrækket');
    });

    test('byt genkendes POSITIVT (A↔B), ikke bare "2 steps"', () {
      final m = <String, dynamic>{
        'steps': <dynamic>[
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(3),
              to: const TrackPosition(9)),
          step(
              pieceId: 'p1.0',
              from: const TrackPosition(9),
              to: const TrackPosition(3)),
        ],
      };
      expect(describeReplayStep(m), 'byttede to brikker');
    });

    test(
        'sekvens (samme brik, 2 steps) uden slag → "rykkede frem og '
        'tilbage med samme brik" (INGEN byt-tekst)', () {
      final m = <String, dynamic>{
        'steps': <dynamic>[
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(11),
              to: const TrackPosition(13)),
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(13),
              to: const TrackPosition(20)),
        ],
      };
      final desc = describeReplayStep(m);
      expect(desc, 'rykkede frem og tilbage med samme brik');
      expect(desc, isNot(contains('byttede')));
    });

    test('sekvens MED to slag → "...med samme brik — slog 2 brikker hjem"',
        () {
      // Mutation der bare tæller cap-flag forkert (fx altid 0 eller altid 1)
      // gør denne rød: facit skal være PRÆCIS "2 brikker", ikke "en brik".
      final m = <String, dynamic>{
        'steps': <dynamic>[
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(11),
              to: const TrackPosition(13),
              cap: true),
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(13),
              to: const TrackPosition(8),
              cap: true),
        ],
      };
      expect(describeReplayStep(m),
          'rykkede frem og tilbage med samme brik — slog 2 brikker hjem');
    });

    test(
        'multi (to FORSKELLIGE brikker, ikke byt) MED ét slag → '
        '"flyttede to brikker — slog en brik hjem"', () {
      final m = <String, dynamic>{
        'steps': <dynamic>[
          step(
              pieceId: 'p0.0',
              from: const TrackPosition(11),
              to: const TrackPosition(12),
              cap: true),
          step(
              pieceId: 'p0.1',
              from: const TrackPosition(20),
              to: const TrackPosition(21)),
        ],
      };
      expect(describeReplayStep(m), 'flyttede to brikker — slog en brik hjem');
    });
  });
}
