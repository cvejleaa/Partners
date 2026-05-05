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
    return cards;
  }

  void shuffle(List<PlayingCard> cards) {
    cards.shuffle(_rng);
  }
}
