import 'package:flutter/material.dart';

import '../../models/player.dart';

class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.isCurrent,
    required this.cardCount,
    required this.starterCount,
    this.isStarter = false,
    this.satOut = false,
    this.lastCardLabel,
  });

  final Player player;
  final bool isCurrent;
  final int cardCount;
  final int starterCount;
  final bool isStarter;
  final bool satOut;
  final String? lastCardLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrent ? player.color.withOpacity(0.20) : Colors.white70,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? player.color : Colors.black26,
          width: isCurrent ? 2.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 14,
                height: 14,
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
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isStarter) ...<Widget>[
                const SizedBox(width: 4),
                const Icon(Icons.flag, size: 13, color: Color(0xFF8B5E3C)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.style, size: 13, color: Colors.grey.shade700),
              const SizedBox(width: 2),
              Text(satOut ? 'over' : '$cardCount',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Text('start: $starterCount',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ],
          ),
          if (lastCardLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('spillede: $lastCardLabel',
                  style: const TextStyle(
                      fontSize: 11, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}
