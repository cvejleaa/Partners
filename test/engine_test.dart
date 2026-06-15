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
    final engine = GameEngine(state: state, rng: Random(7));
    final ai = HeuristicAi(rng: Random(7));

    engine.startNewHand();
    int guard = 0;
    while (state.handNumber < 6 &&
        state.phase != GamePhase.gameOver &&
        guard++ < 3000) {
      if (state.phase == GamePhase.exchange) {
        for (int i = 0; i < 4; i++) {
          engine.submitExchangeCard(i, ai.chooseExchangeCard(state, i));
        }
      } else if (state.phase == GamePhase.play) {
        final m = ai.chooseMove(state, state.currentPlayerIndex);
        if (m != null) {
          engine.applyMove(state.currentPlayerIndex, m);
        } else {
          engine.passHand(state.currentPlayerIndex);
        }
      }
    }
    expect(guard, lessThan(3000));
  });

  test('56 kort pr. kortgiver-cyklus; blandes om når starter skifter', () {
    final state = makeState();
    final engine = GameEngine(state: state, rng: Random(11));

    engine.startNewHand();
    final List<int> deckAfterDeal = <int>[];
    bool everyHandHas4OfEachKind = true;
    int lastHand = -1;

    void maybeRecord() {
      if (state.handNumber == lastHand) return;
      lastHand = state.handNumber;
      deckAfterDeal.add(state.deck.length);
      final all = <PlayingCard>[
        ...state.deck,
        ...state.discard,
        ...state.players.expand<PlayingCard>((p) => p.hand),
      ];
      if (all.length != 56) everyHandHas4OfEachKind = false;
      final counts = <String, int>{};
      for (final c in all) {
        final key = c.isExit ? 'UD' : c.rank!.name;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      if (counts.length != 14 || counts.values.any((v) => v != 4)) {
        everyHandHas4OfEachKind = false;
      }
    }

    maybeRecord();
    int guard = 0;
    while (deckAfterDeal.length < 4 && guard++ < 500) {
      if (state.phase == GamePhase.exchange) {
        for (int i = 0; i < 4; i++) {
          engine.submitExchangeCard(i, state.players[i].hand.first);
        }
      } else if (state.phase == GamePhase.play) {
        engine.passHand(state.currentPlayerIndex);
      }
      maybeRecord();
    }

    // Samme cyklus: deles videre fra de 56 (40 → 24 → 8). Ny starter: blandes
    // om til 56 igen → 40 efter uddeling.
    expect(deckAfterDeal[0], 40);
    expect(deckAfterDeal[1], 24);
    expect(deckAfterDeal[2], 8);
    expect(deckAfterDeal[3], 40);
    expect(everyHandHas4OfEachKind, isTrue);
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
    final List<int> starters = <int>[];
    int lastHand = -1;
    void maybeRecord() {
      if (state.handNumber == lastHand) return;
      lastHand = state.handNumber;
      starters.add(state.starterIndex);
    }

    maybeRecord();
    int guard = 0;
    while (starters.length < 4 && guard++ < 500) {
      if (state.phase == GamePhase.exchange) {
        for (int i = 0; i < 4; i++) {
          engine.submitExchangeCard(i, state.players[i].hand.first);
        }
      } else if (state.phase == GamePhase.play) {
        // Alle passer på skift → runden slutter, og motoren starter næste.
        engine.passHand(state.currentPlayerIndex);
      }
      maybeRecord();
    }
    // 3 runder med samme startende, derefter rotation med uret.
    expect(starters[0], 0);
    expect(starters[1], 0);
    expect(starters[2], 0);
    expect(starters[3], 1);
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
