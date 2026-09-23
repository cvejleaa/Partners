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

  /// Hvor mange kort af hver SLAGS [v]'s bunke rummer — nøglen er 'UD' for
  /// rene ud-kort, ellers rangens etiket. I bunkens rækkefølge (rangene i
  /// `Rank.values`-orden, UD sidst). Afledt af [forVariant], så legenden og
  /// kort-tælleren aldrig kan love kort, bunken ikke har (fx J/D/K i Duo).
  static Map<String, int> countsByKind(VariantConfig v) {
    final Map<String, int> m = <String, int>{};
    for (final Rank r in Rank.values) {
      for (final PlayingCard c in forVariant(v)) {
        if (!c.isExit && c.rank == r) m[c.rankLabel] = (m[c.rankLabel] ?? 0) + 1;
      }
    }
    if (v.exitCardCount > 0) m['UD'] = v.exitCardCount;
    return m;
  }

  /// Ét repræsentativt kort pr. slags i [v]'s bunke (til legenden).
  static List<PlayingCard> kindsFor(VariantConfig v) => <PlayingCard>[
        if (v.exitCardCount > 0) const PlayingCard.exit(0),
        for (final Rank r in Rank.values)
          if (v.deckRanks == null || v.deckRanks!.contains(r))
            PlayingCard(r, Suit.hearts),
      ];

  void shuffle(List<PlayingCard> cards) {
    cards.shuffle(_rng);
  }
}
