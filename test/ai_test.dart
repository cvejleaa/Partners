import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';

import 'test_helpers.dart';

void main() {
  test('AI vælger Es til ud-af-start hvis brikker er i start', () {
    final state = makeState(
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          for (int s = 0; s < 4; s++) StartPosition(0, s),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard(Rank.ace, Suit.hearts),
          PlayingCard(Rank.two, Suit.clubs),
          PlayingCard(Rank.three, Suit.spades),
          PlayingCard(Rank.four, Suit.diamonds),
        ],
        for (int i = 1; i < 4; i++) <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    final Move? move = ai.chooseMove(state, 0);
    expect(move, isNotNull);
    expect(move!.exitsStart, true);
  });

  test('AI foretrækker slag over alm. fremad-træk', () {
    final state = makeState(
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(10),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(13),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        for (int i = 2; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard(Rank.three, Suit.hearts),
        ],
        for (int i = 1; i < 4; i++) <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    final Move? move = ai.chooseMove(state, 0);
    expect(move, isNotNull);
    expect(move!.steps.first.capturedPieceId, isNotNull);
  });

  // -------------------------------------------------------------------------
  // BRUGERFUND: "jeg vil gerne have at ai'en bliver smart nok, så den følger
  // de regler jeg også spiller med."
  //
  // AI'en spillede altid LOVLIGT — lovligheden kommer fra regelmotoren. Men
  // den afgjorde "hvilket kort kan sætte ud" på RANGEN (es eller konge), og
  // det løj, så snart admin flyttede evnen. Her er evnen flyttet til
  // fireren og fjernet fra esset — præcis det admin-skærmen tillader.
  // -------------------------------------------------------------------------

  /// Ud-af-start ligger på FIREREN, ikke på esset.
  final CardRules exitOnFour = CardRules.defaults()
      .withRank(Rank.four,
          const CardRuleConfig(exitStart: true, forwardSteps: <int>[4]))
      .withRank(Rank.ace, const CardRuleConfig(forwardSteps: <int>[1, 11]));

  const PlayingCard four = PlayingCard(Rank.four, Suit.clubs);
  const PlayingCard ace = PlayingCard(Rank.ace, Suit.spades);

  test('byttet: makkeren skal have det kort der FAKTISK kan sætte ud', () {
    // Makkeren (plads 2) har brikker i start; jeg har ingen, så jeg har et
    // udgangskort i overskud og skal give det væk.
    final state = makeState(
      cardRules: exitOnFour,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          for (int s = 0; s < 4; s++) TrackPosition(3 + s * 7),
        ],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(1, s)],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(2, s)],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[four, ace],
        for (int i = 1; i < 4; i++) const <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    // FØR: AI'en gav ESSET — som under disse regler ikke kan sætte ud. Makkeren
    // fik et kort, der ikke løser hans problem, og blev siddende i start.
    expect(ai.chooseExchangeCard(state, 0), four,
        reason: 'makkeren skal have kortet der kan sætte ud — her fireren');
  });

  test('byttet: AI\'en forærer ikke sit EGET eneste udgangskort væk', () {
    // Både makkeren og jeg har brikker i start, og jeg har kun ét
    // udgangskort. Så skal jeg beholde det og give noget andet.
    final state = makeState(
      cardRules: exitOnFour,
      piecePositions: <List<PiecePosition>>[
        for (int i = 0; i < 4; i++)
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[four, ace],
        for (int i = 1; i < 4; i++) const <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    // FØR: AI'en troede esset var dens udgang, beholdt det, og gav FIREREN
    // væk — altså netop den eneste vej ud af start. Den sad så over i runder.
    expect(ai.chooseExchangeCard(state, 0), ace,
        reason: 'fireren er min eneste vej ud — den må ikke gives væk');
  });

  final CardRules twoExitCards = CardRules.defaults()
      .withRank(
          Rank.three, const CardRuleConfig(exitStart: true, forwardSteps: <int>[3]))
      .withRank(Rank.ten, const CardRuleConfig(exitStart: true, forwardSteps: <int>[]));

  test('byttet: mellem to udgangskort gives det MINST alsidige væk', () {
    final state = makeState(
      cardRules: twoExitCards,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          for (int s = 0; s < 4; s++) TrackPosition(3 + s * 7),
        ],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(1, s)],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(2, s)],
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
      ],
      hands: <List<PlayingCard>>[
        const <PlayingCard>[
          PlayingCard(Rank.three, Suit.hearts),
          PlayingCard(Rank.ten, Suit.clubs),
        ],
        for (int i = 1; i < 4; i++) const <PlayingCard>[],
      ],
    );
    final ai = HeuristicAi(rng: Random(0));
    expect(
        ai.chooseExchangeCard(state, 0), const PlayingCard(Rank.ten, Suit.clubs),
        reason: 'det mindst alsidige udgangskort (tieren) skal gives væk — '
            'ikke treeren, som også kan rykke frem');
  });
}
