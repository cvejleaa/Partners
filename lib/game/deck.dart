import 'dart:math';

import '../models/playing_card.dart';

class Deck {
  Deck({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  static List<PlayingCard> fresh() {
    final List<PlayingCard> cards = <PlayingCard>[];
    for (final Suit s in Suit.values) {
      for (final Rank r in Rank.values) {
        cards.add(PlayingCard(r, s));
      }
    }
    // 4 rene ud-kort (markeres med hjerte).
    for (int i = 0; i < 4; i++) {
      cards.add(PlayingCard.exit(i));
    }
    return cards;
  }

  void shuffle(List<PlayingCard> cards) {
    cards.shuffle(_rng);
  }
}
