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
    this.isStarter = false,
    this.satOut = false,
    this.lastCard,
    this.compact = false,
    this.colorOverride,
    this.online,
  });

  final Player player;
  final CardRules rules;
  final bool isCurrent;
  final int cardCount;

  final bool isStarter;
  final bool satOut;
  final PlayingCard? lastCard;
  final bool compact;

  /// Lokal vis-farve der overstyrer [player.color] (farve-rotation). null =
  /// brug spillerens rigtige farve.
  final Color? colorOverride;

  /// Online-status i et online-spil: true = til stede, false = væk, null =
  /// vis ingen markør (fx AI-plads eller lokalt spil).
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = colorOverride ?? player.color;
    final double dotSize = compact ? 12 : 16;
    final double nameSize = compact ? 12.5 : 14;
    final double countSize = compact ? 12 : 13;
    final double cardW = compact ? 22 : 34;

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
        if (online != null) ...<Widget>[
          const SizedBox(width: 5),
          _PresenceDot(online: online!),
        ],
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
    // Tur-markeringen er HUE-UAFHÆNGIG (hvid ramme+glød): en farvet markering
    // drukner når spillerens farve ligner bordet (grøn spiller på grøn flade —
    // og med variant-farver også blå på blå). Identiteten bæres af prikken ved
    // navnet, ikke af rammen.
    final Color borderColor =
        isStarter ? starterGold : (isCurrent ? Colors.white : dotColor);
    final double borderWidth = isStarter ? 3 : (isCurrent ? 2.5 : 1.2);
    final List<BoxShadow>? glow = isStarter
        ? <BoxShadow>[
            BoxShadow(
                color: starterGold.withValues(alpha: 0.55), blurRadius: 9),
          ]
        : (isCurrent
            ? <BoxShadow>[
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.45), blurRadius: 8),
              ]
            : null);

    // Starterens panel får en MØRK baggrund i stedet for spillerens (evt.
    // gyldne) farve, så den gyldne ramme ikke drukner i baggrunden. Farve-
    // identiteten bevares via prikken ved navnet + den centrale starter-chip.
    // Øvrige paneler: spillerens farve komponeret på en UGENNEMSIGTIG neutral
    // mørk bund — panelets kulør er dermed UAFHÆNGIG af bordfarven (samme
    // udseende på grøn og marineblå flade), i stedet for at bordet slog
    // igennem et gennemsigtigt fyld og åd farven, når spiller- og bordfarve
    // lignede hinanden (grøn på grøn / blå på blå).
    final Color panelFill = isStarter
        ? Colors.black.withValues(alpha: 0.42)
        : Color.alphaBlend(
            dotColor.withValues(alpha: isCurrent ? 0.55 : 0.28),
            const Color(0xFF16181C),
          );

    final Widget box = Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 5 : 8),
      decoration: BoxDecoration(
        color: panelFill,
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

    // Guldrammen markerer stadig HVEM der er starter; selve "Starter N/3"-
    // etiketten er flyttet op mellem panelerne (se game_play_view) for at
    // spare højde.
    return box;
  }
}

/// Lille online-markør: udfyldt grøn prik = til stede, hul grå prik = væk.
class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    const Color onColor = Color(0xFF4CAF50);
    final Color color = online ? onColor : const Color(0xFF9E9E9E);
    return Tooltip(
      message: online ? 'Online' : 'Væk',
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: online ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: online ? 0 : 1.5),
          boxShadow: online
              ? <BoxShadow>[
                  BoxShadow(
                      color: onColor.withValues(alpha: 0.7), blurRadius: 4),
                ]
              : null,
        ),
      ),
    );
  }
}
