// Duo-trin 11: computerens bytte, når modtageren er MODSTANDEREN.
//
// Begge plan-gennemgange kaldte det uacceptabelt selv i en første version:
// AI'en læste `me.partnerIndex`, som i Duo er ens EGET andet sæt. Havde det
// sæt brikker i start, forærede den sit udgangskort væk for at "hjælpe" — og
// kortet landede hos modstanderen.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'test_helpers.dart';

const VariantConfig duoForm = VariantConfig(
  id: 'duo-test',
  name: 'Duo-test',
  onePlayerPerTeam: true,
  exchangeRule: ExchangeRule.opponentSwap,
);

List<PiecePosition> startOf(int seat) =>
    <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(seat, s)];
List<PiecePosition> ude(int base) =>
    <PiecePosition>[for (int s = 0; s < 4; s++) TrackPosition(base + s * 3)];

const PlayingCard esS = PlayingCard(Rank.ace, Suit.spades);
const PlayingCard esH = PlayingCard(Rank.ace, Suit.hearts);
const PlayingCard to = PlayingCard(Rank.two, Suit.clubs);
const PlayingCard syv = PlayingCard(Rank.seven, Suit.clubs);

PlayingCard giver(List<List<PiecePosition>> pos, List<PlayingCard> haand) {
  final GameState s = makeState(
    variant: duoForm,
    cardRules: effectiveCardRules(duoForm, CardRules.defaults()),
    piecePositions: pos,
    hands: <List<PlayingCard>>[haand, <PlayingCard>[], <PlayingCard>[], <PlayingCard>[]],
    phase: GamePhase.exchange,
  );
  return HeuristicAi(rng: Random(0)).chooseExchangeCard(s, 0);
}

void main() {
  test('forærer IKKE modstanderen et udgangskort for at "hjælpe" sit eget andet sæt',
      () {
    // Mit sæt 0 er ude, mit sæt 2 står i start. Modstanderen står i start.
    // Jeg har to esser: det gamle "hjælp makkeren ud" gav et af dem væk —
    // til modstanderen.
    final PlayingCard c = giver(
      <List<PiecePosition>>[ude(4), startOf(1), startOf(2), startOf(3)],
      <PlayingCard>[esS, esH, to],
    );
    expect(c, to, reason: 'kortet går til MODSTANDEREN — ikke et es');
  });

  test('"har jeg brug for at komme ud" tæller BEGGE mine sæt', () {
    // Sæt 0 er ude, sæt 2 står i start: jeg har brug for mit ene es. En syver
    // er mere værd end et es, så uden hensynet ville esset blive givet væk.
    final PlayingCard c = giver(
      <List<PiecePosition>>[ude(4), ude(16), startOf(2), ude(34)],
      <PlayingCard>[esS, syv],
    );
    expect(c, syv,
        reason: 'mit andet sæt står i start — esset er min eneste vej ud');
  });
}
