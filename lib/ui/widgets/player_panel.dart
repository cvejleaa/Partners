import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import 'card_view.dart';

class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.rules,
    required this.isCurrent,
    required this.cardCount,
    required this.starterCount,
    this.isStarter = false,
    this.satOut = false,
    this.lastCard,
    this.compact = false,
    this.colorOverride,
  });

  final Player player;
  final CardRules rules;
  final bool isCurrent;
  final int cardCount;
  final int starterCount;
  final bool isStarter;
  final bool satOut;
  final PlayingCard? lastCard;
  final bool compact;

  /// Lokal vis-farve der overstyrer [player.color] (farve-rotation). null =
  /// brug spillerens rigtige farve.
  final Color? colorOverride;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = colorOverride ?? player.color;
    final double dotSize = compact ? 12 : 16;
    final double nameSize = compact ? 13 : 14;
    final double countSize = compact ? 12 : 13;
    final double cardW = compact ? 28 : 36;

    final Widget infoCol = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isStarter) ...<Widget>[
              // Klar, lys stjerne på mørk baggrund — det brune flag forsvandt.
              Icon(Icons.star,
                  size: compact ? 13 : 15, color: const Color(0xFFFFD54F)),
              const SizedBox(width: 2),
            ],
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                player.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: nameSize,
                  color: Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (isStarter && !compact)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300), // klar amber
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.star, size: 14, color: Color(0xFF3A2A00)),
                  SizedBox(width: 3),
                  Text('STARTER',
                      style: TextStyle(
                          color: Color(0xFF3A2A00),
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        SizedBox(height: compact ? 2 : 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.filter_none,
                size: compact ? 11 : 12, color: Colors.white70),
            const SizedBox(width: 3),
            Text(satOut ? 'smidt' : '$cardCount',
                style: TextStyle(fontSize: countSize, color: Colors.white)),
            SizedBox(width: compact ? 8 : 10),
            // Start-tæller: lille flag + tal i stedet for den store blå
            // "start N"-pille, så start-info fylder mindre i panelet.
            Icon(Icons.outlined_flag,
                size: compact ? 11 : 12, color: const Color(0xFF8FBEFF)),
            const SizedBox(width: 2),
            Text('$starterCount',
                style: TextStyle(
                    fontSize: countSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );

    // Layout: info-kolonnen til venstre, sidst spillede kort som lille
    // "thumbnail" til højre — sparer vertikal plads.
    final Widget body = lastCard != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(child: infoCol),
              const SizedBox(width: 6),
              CardView(card: lastCard!, rules: rules, width: cardW),
            ],
          )
        : infoCol;

    // Starteren får en klar amber ramme + glød, så det er tydeligt hvem der
    // starter runden — også når det ikke er deres tur.
    const Color starterGold = Color(0xFFFFC107);
    final Color borderColor = isStarter ? starterGold : dotColor;
    final double borderWidth = isStarter ? 3 : (isCurrent ? 2.5 : 1.2);
    final List<BoxShadow>? glow = isStarter
        ? <BoxShadow>[
            BoxShadow(
                color: starterGold.withValues(alpha: 0.55), blurRadius: 9),
          ]
        : (isCurrent
            ? <BoxShadow>[
                BoxShadow(
                    color: dotColor.withValues(alpha: 0.6), blurRadius: 8),
              ]
            : null);
    return Container(
      padding: EdgeInsets.all(compact ? 5 : 8),
      decoration: BoxDecoration(
        color: dotColor.withValues(alpha: isCurrent ? 0.55 : 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: glow,
      ),
      child: body,
    );
  }
}
