// Duo-trin 1: bunken kommer fra varianten.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/deck.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

void main() {
  test('klassisk bunke er ELEMENT FOR ELEMENT som den håndskrevne opskrift', () {
    // Uafhængig reference — ikke Deck.fresh(), som nu selv går gennem
    // forVariant. En sammenligning med sig selv ville være grøn uanset hvad.
    final List<PlayingCard> expected = <PlayingCard>[
      for (final Suit s in Suit.values)
        for (final Rank r in Rank.values) PlayingCard(r, s),
      for (int i = 0; i < 4; i++) PlayingCard.exit(i),
    ];
    expect(Deck.forVariant(classicVariant), expected);
    expect(Deck.forVariant(partners25), expected,
        reason: '25 år ændrer kortenes REGLER, ikke bunken');
  });

  test('en Duo-formet opskrift: 30 kort, 3 af hver af 10, ingen UD, alle unikke',
      () {
    // Test-lokal variant: Duo-varianten findes ikke endnu (trin 10), men
    // grenen skal være bevist, før den lander.
    const List<Rank> ti = <Rank>[
      Rank.ace, Rank.two, Rank.three, Rank.four, Rank.five,
      Rank.six, Rank.seven, Rank.eight, Rank.nine, Rank.ten,
    ];
    const VariantConfig duoForm = VariantConfig(
        id: 'duo-test',
        name: 'Duo-test',
        deckRanks: ti,
        copiesPerRank: 3,
        exitCardCount: 0);
    final List<PlayingCard> d = Deck.forVariant(duoForm);
    expect(d, hasLength(30));
    expect(d.toSet(), hasLength(30), reason: 'kulør er kopi-nummer — ingen dubletter');
    expect(d.where((PlayingCard c) => c.isExit), isEmpty);
    for (final Rank r in ti) {
      expect(d.where((PlayingCard c) => c.rank == r), hasLength(3), reason: '$r');
    }
    expect(d.any((PlayingCard c) => c.rank == Rank.queen), isFalse,
        reason: 'rang uden for opskriften må ikke snige sig med');
  });
}
