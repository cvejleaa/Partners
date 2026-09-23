import 'dart:math';

import '../models/playing_card.dart';
import '../models/variant_config.dart';

class Deck {
  Deck({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  /// Klassisk bunke: 56 kort (4 kulører × 13 + 4 UD).
  static List<PlayingCard> fresh() => forVariant(classicVariant);

  /// Bunken for [v] efter dens opskrift — se `VariantConfig.deckRanks`.
  static List<PlayingCard> forVariant(VariantConfig v) {
    // Ikke en assert: den forsvinder i den udgivne app, og så ville
    // `Suit.values.take(n)` lydløst give færre kopier end opskriften siger.
    if (v.copiesPerRank < 1 || v.copiesPerRank > Suit.values.length) {
      throw ArgumentError.value(v.copiesPerRank, 'copiesPerRank',
          'kulør er kopi-nummer: 1..${Suit.values.length} kopier pr. rang');
    }
    final Set<Rank>? only = v.deckRanks?.toSet();
    final List<PlayingCard> cards = <PlayingCard>[];
    for (final Suit s in Suit.values.take(v.copiesPerRank)) {
      for (final Rank r in Rank.values) {
        if (only != null && !only.contains(r)) continue;
        cards.add(PlayingCard(r, s));
      }
    }
    // Rene ud-kort (markeres med hjerte).
    for (int i = 0; i < v.exitCardCount; i++) {
      cards.add(PlayingCard.exit(i));
    }
    return cards;
  }

  void shuffle(List<PlayingCard> cards) {
    cards.shuffle(_rng);
  }
}
