import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/playing_card.dart';

import 'test_helpers.dart';

void main() {
  test('startNewHand giver 4 kort til hver spiller og går til exchange', () {
    final state = makeState();
    state.deck.addAll(List<PlayingCard>.from(<PlayingCard>[
      for (int i = 0; i < 52; i++)
        PlayingCard(
          Rank.values[i % Rank.values.length],
          Suit.values[i % Suit.values.length],
        ),
    ]));
    final engine = GameEngine(state: state, rng: Random(1));
    engine.startNewHand();
    expect(state.phase, GamePhase.exchange);
    for (final p in state.players) {
      expect(p.hand.length, 4);
    }
  });

  test('alle 4 partnere bytter samtidig — kortet ender hos partneren', () {
    final state = makeState();
    state.deck.addAll(List<PlayingCard>.from(<PlayingCard>[
      for (int i = 0; i < 52; i++)
        PlayingCard(
          Rank.values[i % Rank.values.length],
          Suit.values[i % Suit.values.length],
        ),
    ]));
    final engine = GameEngine(state: state, rng: Random(1));
    engine.startNewHand();

    // Simulér at alle vælger første kort på hånden
    final originalChoices = <int, PlayingCard>{};
    for (int i = 0; i < 4; i++) {
      originalChoices[i] = state.players[i].hand.first;
      engine.submitExchangeCard(i, state.players[i].hand.first);
    }
    expect(state.phase, GamePhase.play);
    // Spiller 0's kort skal nu være på spiller 2's hånd
    expect(state.players[2].hand.contains(originalChoices[0]!), true);
    expect(state.players[0].hand.contains(originalChoices[2]!), true);
  });

  test('vinderdetektion når alle holdets brikker er i hjem', () {
    final state = makeState(
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 0),
          const HomeStretchPosition(0, 1),
          const HomeStretchPosition(0, 2),
          const HomeStretchPosition(0, 3),
        ],
        <PiecePosition>[
          for (int s = 0; s < 4; s++) StartPosition(1, s),
        ],
        <PiecePosition>[
          const HomeStretchPosition(2, 0),
          const HomeStretchPosition(2, 1),
          const HomeStretchPosition(2, 2),
          const HomeStretchPosition(2, 3),
        ],
        <PiecePosition>[
          for (int s = 0; s < 4; s++) StartPosition(3, s),
        ],
      ],
    );
    expect(state.teamHasWon(0), true);
    expect(state.teamHasWon(1), false);
  });
}
