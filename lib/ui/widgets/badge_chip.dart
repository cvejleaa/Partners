import 'package:flutter/material.dart';

import '../../stats/badges.dart';
import '../../stats/user_stats.dart';

/// En lille chip der viser én badge. Optjente badges vises farverigt; låste
/// badges vises nedtonet (gråtonet) med en kort hint-tekst og evt. fremgang.
class BadgeChip extends StatelessWidget {
  const BadgeChip({super.key, required this.badge, required this.stats});

  final AchievementBadge badge;
  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocked = badge.isUnlocked(stats);
    final progress = badge.progressFor(stats);

    final Color bg = unlocked
        ? theme.colorScheme.primaryContainer
        : Colors.grey.shade200;
    final Color fg = unlocked
        ? theme.colorScheme.onPrimaryContainer
        : Colors.grey.shade600;

    final hint = unlocked
        ? badge.description
        : (progress > 0 && progress < 1
            ? '${(progress * 100).toStringAsFixed(0)}% · ${badge.description}'
            : badge.description);

    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: unlocked
              ? Border.all(color: theme.colorScheme.primary, width: 1)
              : Border.all(color: Colors.grey.shade400),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Opacity(
                  opacity: unlocked ? 1 : 0.4,
                  child: Text(badge.emoji,
                      style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 6),
                Text(
                  badge.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                if (!unlocked) ...<Widget>[
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline, size: 14, color: fg),
                ],
              ],
            ),
            if (!unlocked && progress > 0 && progress < 1) ...<Widget>[
              const SizedBox(height: 6),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
