import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/playing_card.dart';

import 'test_helpers.dart';

void main() {
  test('startNewHand giver 4 kort til hver spiller og går til exchange', () {
    final state = makeState();
    state.deck.addAll(_freshDeck());
    final engine = GameEngine(state: state, rng: Random(1));
    engine.startNewHand();
    expect(state.phase, GamePhase.exchange);
    for (final p in state.players) {
      expect(p.hand.length, 4);
    }
  });

  test('alle 4 partnere bytter samtidig — kortet ender hos partneren', () {
    final state = makeState();
    state.deck.addAll(_freshDeck());
    final engine = GameEngine(state: state, rng: Random(1));
    engine.startNewHand();

    final originalChoices = <int, PlayingCard>{};
    for (int i = 0; i < 4; i++) {
      originalChoices[i] = state.players[i].hand.first;
      engine.submitExchangeCard(i, state.players[i].hand.first);
    }
    expect(state.phase, GamePhase.play);
    expect(state.players[2].hand.contains(originalChoices[0]!), true);
    expect(state.players[0].hand.contains(originalChoices[2]!), true);
    expect(state.players[3].hand.contains(originalChoices[1]!), true);
    expect(state.players[1].hand.contains(originalChoices[3]!), true);
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
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(1, s)],
        <PiecePosition>[
          const HomeStretchPosition(2, 0),
          const HomeStretchPosition(2, 1),
          const HomeStretchPosition(2, 2),
          const HomeStretchPosition(2, 3),
        ],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
      ],
    );
    expect(state.teamHasWon(0), true);
    expect(state.teamHasWon(1), false);
  });

  test('flere hænder spilles efter hinanden uden at hænge', () {
    final state = makeState();
    state.deck.addAll(_freshDeck());
    final engine = GameEngine(state: state, rng: Random(7));
    final ai = HeuristicAi(rng: Random(7));

    for (int hand = 0; hand < 10; hand++) {
      engine.startNewHand();
      for (int i = 0; i < 4; i++) {
        engine.submitExchangeCard(i, ai.chooseExchangeCard(state, i));
      }
      int safety = 100;
      while (state.phase == GamePhase.play && safety-- > 0) {
        final m = ai.chooseMove(state, state.currentPlayerIndex);
        if (m != null) {
          engine.applyMove(state.currentPlayerIndex, m);
        } else {
          engine.discardCard(state.currentPlayerIndex,
              ai.chooseDiscard(state, state.currentPlayerIndex));
        }
      }
      expect(safety, greaterThan(0));
      if (state.phase == GamePhase.gameOver) break;
    }
  });

  test('spiller uden lovligt træk smider hånden og sidder over', () {
    // Alle brikker i start; hånd uden ud-kort → ingen lovlige træk.
    final state = makeState(
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard(Rank.two, Suit.hearts),
          PlayingCard(Rank.three, Suit.clubs),
        ],
        const <PlayingCard>[PlayingCard(Rank.ace, Suit.spades)],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
      currentPlayerIndex: 0,
    );
    final engine = GameEngine(state: state, rng: Random(3));
    expect(engine.canPlay(0), isFalse);
    engine.passHand(0);
    expect(state.players[0].hand, isEmpty);
    // Turen går videre til en spiller med kort (ikke den der sad over).
    expect(state.currentPlayerIndex, isNot(0));
    expect(state.players[state.currentPlayerIndex].hand, isNotEmpty);
  });

  test('startende spiller roterer med uret efter 3 runder', () {
    final state = makeState();
    state.deck.addAll(_freshDeck());
    final engine = GameEngine(state: state, rng: Random(5));

    engine.startNewHand();
    final Map<int, int> starterByHand = <int, int>{};
    starterByHand[state.handNumber] = state.starterIndex;

    int guard = 0;
    while (state.handNumber < 4 && guard++ < 500) {
      if (state.phase == GamePhase.exchange) {
        for (int i = 0; i < 4; i++) {
          engine.submitExchangeCard(i, state.players[i].hand.first);
        }
      } else if (state.phase == GamePhase.play) {
        // Alle passer på skift → runden slutter, og motoren starter næste.
        engine.passHand(state.currentPlayerIndex);
      }
      starterByHand[state.handNumber] = state.starterIndex;
    }
    expect(starterByHand[1], 0);
    expect(starterByHand[2], 0);
    expect(starterByHand[3], 0);
    expect(starterByHand[4], 1);
  });

  test('discardCard fjerner kort og avancerer spiller', () {
    final state = makeState();
    state.deck.addAll(_freshDeck());
    final engine = GameEngine(state: state, rng: Random(2));
    engine.startNewHand();
    // Hop direkte forbi exchange — bare for at få play-fase
    for (int i = 0; i < 4; i++) {
      engine.submitExchangeCard(i, state.players[i].hand.first);
    }
    final beforeHand = state.players[state.currentPlayerIndex].hand.length;
    final beforePlayer = state.currentPlayerIndex;
    engine.discardCard(beforePlayer, state.players[beforePlayer].hand.first);
    expect(state.players[beforePlayer].hand.length, beforeHand - 1);
    expect(state.currentPlayerIndex, isNot(beforePlayer));
  });
}

List<PlayingCard> _freshDeck() {
  final out = <PlayingCard>[];
  for (final s in Suit.values) {
    for (final r in Rank.values) {
      out.add(PlayingCard(r, s));
    }
  }
  return out;
}
