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

  @override
  Widget build(BuildContext context) {
    final double dotSize = compact ? 12 : 16;
    final double nameSize = compact ? 12 : 14;
    final double countSize = compact ? 11 : 13;
    final double cardW = compact ? 28 : 36;

    final Widget infoCol = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isStarter) ...<Widget>[
              const Icon(Icons.flag, size: 14, color: Color(0xFF8B5E3C)),
              const SizedBox(width: 2),
            ],
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: player.color,
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
                color: const Color(0xFF8B5E3C),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.flag, size: 14, color: Colors.white),
                  SizedBox(width: 3),
                  Text('STARTER',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.style, size: 12, color: Colors.grey.shade700),
            const SizedBox(width: 2),
            Text(satOut ? 'over' : '$cardCount',
                style: TextStyle(fontSize: countSize)),
            const SizedBox(width: 6),
            _StartBadge(count: starterCount),
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

    return Container(
      padding: EdgeInsets.all(compact ? 5 : 8),
      decoration: BoxDecoration(
        color: player.color.withValues(alpha: isCurrent ? 0.55 : 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: player.color,
          width: isCurrent ? 2.5 : 1.2,
        ),
        boxShadow: isCurrent
            ? <BoxShadow>[
                BoxShadow(
                    color: player.color.withValues(alpha: 0.6), blurRadius: 8),
              ]
            : null,
      ),
      child: body,
    );
  }
}

class _StartBadge extends StatelessWidget {
  const _StartBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('start ',
              style: TextStyle(color: Colors.white, fontSize: 10)),
          Text('$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
