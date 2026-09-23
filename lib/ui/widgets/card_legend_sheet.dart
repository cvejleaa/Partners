import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../game/deck.dart';
import '../../models/variant_config.dart';
import '../../models/playing_card.dart';
import 'card_view.dart';

/// "Kortene i dette spil" — legenden for kortenes token-sprog (`4×1`, `5↷`,
/// `+2−5`, `⇄`), åbnet fra spil-skærmenes topbar.
///
/// Bygget af spillets OPLØSTE regler ([rules] = state.cardRules), så et
/// 25 år-/custom-spil viser præcis de kort, man faktisk har i hånden —
/// tutorial-skærmens kortside viser de klassiske regler og kan derfor ikke
/// være opslagsvejen midt i et variant-spil. Kort + forklaring side om side
/// er dét sted, token-sproget LÆRES; long-press-tooltippen er kun backup
/// (den er uopdagelig for nye spillere).
///
/// [variant] afgør HVILKE kort der vises: kun dem, bunken faktisk har (Duo har
/// hverken UD, J, D eller K).
void showCardLegendSheet(BuildContext context, CardRules rules,
    {VariantConfig variant = classicVariant}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext ctx, ScrollController scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          const Text('Kortene i dette spil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Sort = frem, rødt = tilbage. ×1 = del skridtene frit over dine '
            'brikker. Hold et kort nede under spillet for samme forklaring.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          // Én række pr. slags i bunken — kulør er ligegyldig for funktionen.
          for (final PlayingCard c in Deck.kindsFor(variant)) _row(c, rules),
        ],
      ),
    ),
  );
}

Widget _row(PlayingCard card, CardRules rules) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // Bredt kort (64 px): tokens er store, og sammen med teksten til
        // højre er rækken en indbygget ordbog for token-sproget.
        CardView(card: card, rules: rules, width: 64),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            cardFunctionSummary(card, rules),
            style: const TextStyle(fontSize: 13, height: 1.3),
          ),
        ),
      ],
    ),
  );
}
