import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../stats/user_stats.dart';

/// "Sådan faldt kortene": hvad fik MIT par, og hvad fik modstanderparret?
///
/// Svarer på det spørgsmål der bliver stillet ved bordet efter et nederlag —
/// "fik de alle esserne?". Fire ting gør tallet læseligt og ærligt frem for
/// at være en undskyldnings-maskine:
///
/// 1. **Kolonnerne har navne.** "17 mod 17" på én linje siger ikke hvem det
///    første tal tilhører — brugerfund. Nu står tallene i en Jer/Dem-tabel.
/// 2. **Et anker.** To rå tal uden målestok får en helt normal kortfordeling
///    til at ligne et overgreb. Derfor står langtidssnittet under tabellen —
///    ÉN gang, ikke i hver række, hvor det druknede tallene.
/// 3. **Underteksten siger hvad der tælles** — de faktiske kort for DEN
///    variant, udledt af reglerne selv ([CardRules.labelsFor]), så tallet ikke
///    kan komme til at love noget andet end det, der blev talt.
/// 4. **De usete kort skjules ikke.** Hele hånden smides ved et pas, og kun
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
  /// null = intet anker og INGEN snit-linje (fx i "I alt"-fanen, hvor tallet
  /// SELV er snittet).
  ///
  /// Ankeret er dagens snit, også når man ser en gammel rapport fra arkivet:
  /// spørgsmålet "var det her partis kort normale for os?" besvares bedst af
  /// alt hvad man har spillet, ikke af hvad man havde spillet dengang.
  final UserStats? anchor;

  /// Har spillet/spillene overhovedet et kortregnskab? Kun spil hvor alle fire
  /// pladser er mennesker tælles med, så et solospil mod computeren har ingen
  /// (og et heldregnskab mod en maskine siger heller ikke noget).
  static bool hasData(UserStats s) => s.cardMixGames > 0;

  /// Kortene i [cat] for DENNE variant, som undertekst: "UD · A · K".
  String _sub(CardCategory cat) {
    final CardRules? r = rules;
    if (r == null) return '';
    return r.labelsFor(cat).join(' · ');
  }

  /// Dansk decimaltegn. "17.8" er engelsk og læses forkert her.
  static String _num1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  static const double _colWidth = 54;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final int unseen = stats.myUnseenCards + stats.oppUnseenCards;
    final double? avgExit = anchor?.avgMyExitCards;
    final double? avgSpecial = anchor?.avgMySpecialCards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Overskrifts-rækken er hele pointen: uden den siger "17 mod 17"
        // ikke HVEM det første tal tilhører.
        Row(
          children: <Widget>[
            const Expanded(child: SizedBox()),
            _head(context, 'Jer'),
            _head(context, 'Dem'),
          ],
        ),
        const SizedBox(height: 2),
        const Divider(height: 9),
        _row(
          context,
          title: 'Ud af start',
          subtitle: _sub(CardCategory.exit),
          mine: stats.myExitCards,
          theirs: stats.oppExitCards,
        ),
        const SizedBox(height: 10),
        _row(
          context,
          title: 'Specialkort',
          subtitle: _sub(CardCategory.special),
          mine: stats.mySpecialCards,
          theirs: stats.oppSpecialCards,
        ),
        // Ankeret ÉN gang nederst frem for i hver række: to gange "jeres snit
        // er …" midt i tallene gjorde rækkerne til en støjvæg.
        if (avgExit != null && avgSpecial != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Jeres snit pr. spil: ${_num1(avgExit)} ud af start · '
            '${_num1(avgSpecial)} specialkort',
            style: t.bodySmall,
          ),
        ],
        if (unseen > 0) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '$unseen kort nåede aldrig at blive spillet — de blev smidt, da '
            'nogen måtte sidde over, så ingen så hvad de var.',
            style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _head(BuildContext context, String label) => SizedBox(
        width: _colWidth,
        child: Text(
          label,
          textAlign: TextAlign.right,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Widget _row(
    BuildContext context, {
    required String title,
    required String subtitle,
    required int mine,
    required int theirs,
  }) {
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle? number =
        t.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: Text(title,
                  style:
                      t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
                width: _colWidth,
                child: Text('$mine',
                    textAlign: TextAlign.right, style: number)),
            SizedBox(
                width: _colWidth,
                child: Text('$theirs',
                    textAlign: TextAlign.right, style: number)),
          ],
        ),
        if (subtitle.isNotEmpty) Text(subtitle, style: t.bodySmall),
        // Konklusionen skrives ud. En tabel med fire tal beder læseren regne
        // selv — og en læser der regner selv, regner i sin egen favør.
        Text(_verdict(mine, theirs), style: t.bodySmall),
      ],
    );
  }

  /// Sætningen under tallene — forskellen sagt med ord.
  static String _verdict(int mine, int theirs) {
    final int diff = mine - theirs;
    if (diff == 0) return 'Lige mange';
    return diff > 0 ? '$diff flere til jer' : '${-diff} flere til dem';
  }
}
