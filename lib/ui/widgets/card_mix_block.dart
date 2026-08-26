import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../stats/user_stats.dart';

/// "Sådan faldt kortene": hvad fik MIT par, og hvad fik modstanderparret?
///
/// Svarer på det spørgsmål der bliver stillet ved bordet efter et nederlag —
/// "fik de alle esserne?". Tre ting gør tallet ærligt frem for at være en
/// undskyldnings-maskine:
///
/// 1. **Et anker.** To rå tal uden målestok får en helt normal kortfordeling
///    til at ligne et overgreb. Derfor står dit eget langtidssnit ved siden af,
///    når det findes ([UserStats.avgMyExitCards]).
/// 2. **Underteksten siger hvad der tælles** — de faktiske kort for DEN
///    variant, udledt af reglerne selv ([CardRules.labelsFor]), så tallet ikke
///    kan komme til at love noget andet end det, der blev talt.
/// 3. **De usete kort skjules ikke.** Hele hånden smides ved et pas, og kun
///    ANTALLET logges. Den rest er skæv — man passer netop når man ikke kunne
///    bruge noget — så den står som en sætning under tabellen, aldrig som en
///    ordløs kolonne i den.
class CardMixBlock extends StatelessWidget {
  const CardMixBlock({
    super.key,
    required this.stats,
    this.rules,
    this.anchor,
  });

  /// Tallene. Ét spil (fra `computeAllStats([game])`) eller en livstid — det
  /// er samme felter, så blokken kan begge dele uden en tilstand at forveksle.
  final UserStats stats;

  /// Spillets opløste regler — bruges KUN til underteksten. null = ingen
  /// undertekst (tallene står stadig).
  final CardRules? rules;

  /// Langtids-tallene at måle [stats] MOD — typisk brugerens variant-spand.
  /// null = intet anker (fx i "I alt"-fanen, hvor tallet SELV er snittet).
  ///
  /// Ankeret er dagens snit, også når man ser en gammel rapport fra arkivet:
  /// spørgsmålet "var det her partis kort normale for os?" besvares bedst af
  /// alt hvad man har spillet, ikke af hvad man havde spillet dengang.
  final UserStats? anchor;

  /// Har spillet/spillene overhovedet et kortregnskab? Kun spil hvor alle fire
  /// pladser er mennesker tælles med, så et solospil mod computeren har ingen
  /// (og et heldregnskab mod en maskine siger heller ikke noget).
  static bool hasData(UserStats s) => s.cardMixGames > 0;

  String _sub(CardCategory cat) {
    final CardRules? r = rules;
    if (r == null) return '';
    final List<String> labels = r.labelsFor(cat);
    return labels.isEmpty ? '' : labels.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle? small = Theme.of(context).textTheme.bodySmall;
    final int unseen = stats.myUnseenCards + stats.oppUnseenCards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _row(
          context,
          title: 'Ud af start',
          subtitle: _sub(CardCategory.exit),
          mine: stats.myExitCards,
          theirs: stats.oppExitCards,
          average: anchor?.avgMyExitCards,
        ),
        const SizedBox(height: 10),
        _row(
          context,
          title: 'Specialkort',
          subtitle: _sub(CardCategory.special),
          mine: stats.mySpecialCards,
          theirs: stats.oppSpecialCards,
          average: anchor?.avgMySpecialCards,
        ),
        if (unseen > 0) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '$unseen kort nåede aldrig at blive spillet — de blev smidt, da '
            'nogen måtte sidde over, så ingen så hvad de var. Man sidder over, '
            'når man ikke kan bruge noget af det man har.',
            style: small?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String subtitle,
    required int mine,
    required int theirs,
    required double? average,
  }) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: t.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: t.bodySmall),
                ],
              ),
            ),
            Text('$mine mod $theirs',
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        // Konklusionen skrives ud. En tabel med fire tal beder læseren regne
        // selv — og en læser der regner selv, regner i sin egen favør.
        Text(_verdict(mine, theirs, average), style: t.bodySmall),
      ],
    );
  }

  /// Sætningen under tallene. Ankeret nævnes kun når der ER et snit at måle
  /// mod — ellers står der bare hvad forskellen var.
  static String _verdict(int mine, int theirs, double? average) {
    final int diff = mine - theirs;
    final String base = diff == 0
        ? 'Lige mange'
        : diff > 0
            ? '$diff flere til jer'
            : '${-diff} flere til dem';
    if (average == null) return base;
    return '$base · jeres snit er ${average.toStringAsFixed(1)}';
  }
}
