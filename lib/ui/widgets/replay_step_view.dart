import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';
import '../../online/replay_story.dart';
import 'card_view.dart';

/// Ét træk i "mens du var væk": kortet i lille udgave til venstre, og hvad
/// det betød til højre.
///
/// Tonen bæres VISUELT (en farvet stribe og en baggrundstone), ikke af
/// tillægsord om en navngiven spillers træk. Appen må gerne være ked af det
/// på spillerens vegne; den skal ikke dømme modspilleren.
class ReplayStepView extends StatelessWidget {
  const ReplayStepView({
    super.key,
    required this.story,
    required this.rules,
    this.card,
  });

  final ReplayStory story;

  /// Spillets opløste regler — kortet skal tegnes med de kort partiet
  /// faktisk blev spillet med, ikke med klassiske.
  final CardRules rules;

  /// null for et pas (der blev ikke spillet et kort).
  final PlayingCard? card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? accent = switch (story.tone) {
      ReplayTone.sad => theme.colorScheme.error,
      ReplayTone.good => theme.colorScheme.primary,
      ReplayTone.neutral => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: accent == null
          ? null
          : BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Kortet i HÅNDKORT-størrelse. Før fyldte det 70 px over teksten;
          // her står det ved siden af, så et træk kan læses i ét blik.
          SizedBox(
            width: 48,
            child: card == null
                ? const SizedBox.shrink()
                : CardView(card: card!, rules: rules, width: 44),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(children: <InlineSpan>[
                    TextSpan(
                        text: story.actor,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: ' ${story.action}'),
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
                if (story.outcome != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      story.outcome!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
