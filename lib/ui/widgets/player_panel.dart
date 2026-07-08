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
    this.starterStreak = 0,
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

  /// 0/1/2 gennem starterens tre hænder; nulstilles ved rotation. Vises kun
  /// (som "Starter N/3", N = streak+1) for den spiller der ER starter.
  final int starterStreak;
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
    final double cardW = compact ? 28 : 34;

    // Linje 1: farveprik + navn.
    final Widget nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(width: 5),
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
    );

    // Linje 2: antal kort tilbage (🂠 N / "smidt") og — skubbet til højre —
    // det sidst spillede kort som lille thumbnail.
    final Widget countRow = Row(
      children: <Widget>[
        Icon(Icons.filter_none, size: compact ? 11 : 12, color: Colors.white70),
        const SizedBox(width: 4),
        Text(satOut ? 'smidt' : '$cardCount',
            style: TextStyle(fontSize: countSize, color: Colors.white)),
        if (lastCard != null) ...<Widget>[
          const Spacer(),
          CardView(card: lastCard!, rules: rules, width: cardW),
        ],
      ],
    );

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

    final Widget box = Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: dotColor.withValues(alpha: isCurrent ? 0.55 : 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: glow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          nameRow,
          SizedBox(height: compact ? 4 : 5),
          countRow,
        ],
      ),
    );

    // "Starter N/3"-etikette UNDER panelet — kun for den faktiske starter.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        box,
        if (isStarter)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _StarterLabel(streak: starterStreak),
          ),
      ],
    );
  }
}

class _StarterLabel extends StatelessWidget {
  const _StarterLabel({required this.streak});

  /// 0/1/2 → vises som 1/3, 2/3, 3/3.
  final int streak;

  @override
  Widget build(BuildContext context) {
    final int n = (streak % 3) + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.outlined_flag, size: 12, color: Color(0xFF3A2A00)),
          const SizedBox(width: 4),
          Text('Starter $n/3',
              style: const TextStyle(
                  color: Color(0xFF3A2A00),
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
