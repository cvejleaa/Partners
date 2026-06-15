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
  });

  final Player player;
  final CardRules rules;
  final bool isCurrent;
  final int cardCount;
  final int starterCount;
  final bool isStarter;
  final bool satOut;
  final PlayingCard? lastCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isCurrent ? player.color.withOpacity(0.22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? player.color : Colors.black26,
          width: isCurrent ? 3 : 1,
        ),
        boxShadow: isCurrent
            ? <BoxShadow>[
                BoxShadow(
                  color: player.color.withOpacity(0.6),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: player.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  player.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Tydeligt STARTER-mærke.
          if (isStarter)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Antal kort.
              Icon(Icons.style, size: 14, color: Colors.grey.shade700),
              const SizedBox(width: 2),
              Text(satOut ? 'over' : '$cardCount',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 10),
              // Tydeligt antal-starter-mærke.
              _StartBadge(count: starterCount),
            ],
          ),
          // Spillede kort ligger synligt under spilleren.
          const SizedBox(height: 6),
          SizedBox(
            height: 58,
            child: lastCard != null
                ? CardView(card: lastCard!, rules: rules, width: 38)
                : (satOut
                    ? const Text('sad over',
                        style: TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic))
                    : const SizedBox.shrink()),
          ),
        ],
      ),
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
