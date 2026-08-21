import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';

/// Kort-typernes accentfarver (bånd i toppen).
const Color _cMove = Color(0xFF334155); // flyt
const Color _cStart = Color(0xFF2F7D34); // ud af start
const Color _cSpecial = Color(0xFFB7791F); // 7 / byt
const Color _cExit = Color(0xFFC62828); // UD-kort

/// Hvad et kort viser — udledt fra de aktuelle regler (ikke hardkodet, så
/// admin-ændringer slår igennem). Ingen pile, ingen kulør, ingen A/K/Q/J: kun
/// hvad kortet gør i spillet. "Ud af start" markeres med et hjerte.
class CardFace {
  const CardFace({
    required this.eyebrow,
    required this.accent,
    this.bigNumber,
    this.icon,
    this.unit,
    this.sub,
    this.startChip = false,
    this.extraChips = const <String>[],
    this.canForward = false,
    this.canBackward = false,
  });

  final String eyebrow;
  final Color accent;
  final String? bigNumber; // fx "4", "1 / 11", "13", "7"
  final String? icon; // emoji når der ikke er et tal (UD, byt)
  final String? unit; // fx "frem"
  final String? sub; // fx "frem eller tilbage"
  final bool startChip; // vis "♥ Ud af start"

  /// Ekstra evne-chips (fx "Byt to brikker", "↷ Hopper over blokade") — liste,
  /// så et kort med FLERE ekstra evner viser dem alle (ikke farve alene:
  /// ikon+tekst, så det også kan aflæses farveblindt og i tooltippen).
  final List<String> extraChips;

  /// Retning — styrer tallets farve: kun tilbage = rødt, kun frem = sort,
  /// begge = delt sort/rødt.
  final bool canForward;
  final bool canBackward;
}

CardFace describeCardFace(PlayingCard card, CardRules rules) {
  if (card.isExit) {
    return const CardFace(
      eyebrow: 'Ud-kort',
      accent: _cExit,
      icon: '♥',
      sub: 'Sæt en brik ud',
    );
  }
  final CardRuleConfig c = rules.forRank(card.rank!);
  // Ekstra evner vises som chips — HOP skal kunne ses på kortet, ellers ligner
  // et Hopsakort et almindeligt talkort, og modstanderen forstår ikke hvorfor
  // blokaden blev passeret. Samme ordlyd som i admin ("hop"). Hop gælder KUN
  // fremad-skridt i motoren (rules.dart), så chippen vises kun når kortet
  // faktisk HAR fremad-skridt — ellers ville kortet love en evne, der ingen
  // effekt har.
  final List<String> extraChips = <String>[
    if (c.swap) 'Byt to brikker',
    if (c.jumpsBlockade && c.forwardSteps.isNotEmpty) '↷ Hopper over blokade',
    // Sekvens/multi vises med samme ordlyd som i valg-arket og admin, så
    // spilleren møder det samme sprog alle steder.
    if (c.hasFwdThenBack) '${c.seqForward} frem → ${c.seqBackward} tilbage',
    if (c.hasMultiForward) '${c.multiSteps} frem × ${c.multiPieces} brikker',
  ];
  final bool hasForward = c.forwardSteps.isNotEmpty;
  final bool hasBackward = c.backwardSteps != null;
  final String forwardText = c.forwardSteps.join(' / ');
  final bool sameFwdBack = hasForward &&
      hasBackward &&
      c.forwardSteps.length == 1 &&
      c.forwardSteps.first == c.backwardSteps;

  // 7'er / split.
  if (c.splitTotal != null) {
    return CardFace(
      eyebrow: 'Special',
      accent: _cSpecial,
      bigNumber: '${c.splitTotal}',
      sub: 'del over dine brikker',
      startChip: c.exitStart,
      extraChips: extraChips,
    );
  }

  // Kort med bevægelse (frem og/eller tilbage). Teksten følger den AKTUELLE
  // konfiguration — ikke hardkodet.
  if (hasForward || hasBackward) {
    // Beregn stort tal + retningstekst ud fra hvad kortet faktisk kan.
    final String bigNumber =
        hasForward ? forwardText : '${c.backwardSteps}';
    String? unit;
    String? sub;
    if (sameFwdBack) {
      // Fx 4: samme antal frem eller tilbage.
      sub = 'frem eller tilbage';
    } else if (hasForward && hasBackward) {
      // Forskellige tal frem/tilbage.
      unit = 'frem';
      sub = 'eller ${c.backwardSteps} tilbage';
    } else if (hasForward) {
      unit = 'frem';
    } else {
      unit = 'tilbage';
    }
    return CardFace(
      // Ud af start → grøn accent + hjerte-chip; ellers grå "Flyt".
      eyebrow: 'Flyt',
      accent: c.exitStart ? _cStart : _cMove,
      bigNumber: bigNumber,
      unit: unit,
      sub: sub,
      startChip: c.exitStart,
      extraChips: extraChips,
      canForward: hasForward,
      canBackward: hasBackward,
    );
  }

  // Rent ud-af-start-kort (ingen bevægelse) → stort hjerte.
  if (c.exitStart) {
    return CardFace(
      eyebrow: 'Start',
      accent: _cStart,
      icon: '♥',
      sub: 'Ud af start',
      extraChips: extraChips,
    );
  }

  // Ren byt (fx en Knægt sat til byt).
  if (c.swap) {
    return const CardFace(
      eyebrow: 'Special',
      accent: _cSpecial,
      icon: '🔁',
      sub: 'byt to brikker',
    );
  }

  return const CardFace(eyebrow: '—', accent: _cMove, sub: 'ingen effekt');
}

class CardView extends StatelessWidget {
  const CardView({
    super.key,
    required this.card,
    required this.rules,
    this.faceUp = true,
    this.selected = false,
    this.onTap,
    this.width = 66,
  });

  final PlayingCard card;
  final CardRules rules;
  final bool faceUp;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  /// Kort tekst-opsummering af hvad kortet gør — bruges som tooltip (hold nede/
  /// hover), så man ALTID kan se kortets funktion, selv når kortet vises småt.
  String _functionSummary() {
    final CardFace f = describeCardFace(card, rules);
    final StringBuffer b = StringBuffer(f.eyebrow);
    if (f.bigNumber != null) b.write(' ${f.bigNumber}');
    if (f.unit != null) b.write(' ${f.unit}');
    if (f.sub != null) b.write(' — ${f.sub}');
    if (f.startChip) b.write(' · ♥ Ud af start');
    for (final String chip in f.extraChips) {
      b.write(' · $chip');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final double height = width * 1.5;
    final Widget cardWidget = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        margin: EdgeInsets.only(bottom: selected ? 14 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.amber.shade700 : Colors.black26,
            width: selected ? 3 : 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: faceUp ? _buildFace() : _buildBack(),
        ),
      ),
    );
    // Kun for face-up-kort: hold nede (eller hover) viser en tooltip med
    // kortets funktion, så man altid kan se hvad kortet kan — også når det
    // vises småt på en lille skærm.
    if (!faceUp) return cardWidget;
    return Tooltip(
      message: _functionSummary(),
      triggerMode: TooltipTriggerMode.longPress,
      preferBelow: false,
      showDuration: const Duration(seconds: 3),
      child: cardWidget,
    );
  }

  Widget _buildBack() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1B5E8A), Color(0xFF0D3B5C)],
        ),
      ),
    );
  }

  Widget _buildFace() {
    final CardFace f = describeCardFace(card, rules);
    final double band = (width * 0.06).clamp(3.0, 7.0);
    // Meget små kort (fx "sidst spillede"-thumbnail i spiller-panelet, ~32 px)
    // har ikke plads til eyebrow/chips — vis en kompakt udgave: bånd +
    // det store tal eller ikon i typens farve. Grænsen holdes lav (40 px), så
    // hånd-kort så vidt muligt viser den fulde funktion.
    if (width < 40) {
      final String glyph = f.bigNumber ?? f.icon ?? '·';
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Colors.white, Color(0xFFEEF0F2)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(height: band, color: f.accent),
            Expanded(
              child: Center(
                child: f.bigNumber != null
                    ? _bigNumber(f, f.bigNumber!.contains('/'))
                    : Text(
                        glyph,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: glyph.contains('/')
                              ? width * 0.34
                              : width * 0.52,
                          fontWeight: FontWeight.w800,
                          height: 0.95,
                          color: f.icon != null
                              ? f.accent
                              : const Color(0xFF1F2933),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Colors.white, Color(0xFFEEF0F2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Farvet type-bånd i toppen.
          Container(height: band, color: f.accent),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: width * 0.09, vertical: width * 0.07),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                    f.eyebrow.toUpperCase(),
                    style: TextStyle(
                      fontSize: (width * 0.135).clamp(7.0, 13.0),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: f.accent,
                    ),
                  ),
                  Expanded(child: _center(f)),
                  if (f.startChip) _startChip(),
                  for (int i = 0; i < f.extraChips.length; i++) ...<Widget>[
                    if (f.startChip || i > 0) SizedBox(height: width * 0.04),
                    _chip(f.extraChips[i], _cSpecial),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _center(CardFace f) {
    final bool dual = f.bigNumber != null && f.bigNumber!.contains('/');
    // FittedBox(scaleDown) sikrer at tal + tekst ALTID skaleres ned til den
    // plads Expanded giver — så en hjerte-/byt-chip nedenunder aldrig
    // overlappes, uanset korthøjde.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (f.icon != null)
              Text(f.icon!,
                  style: TextStyle(
                      fontSize: width * 0.5,
                      color: f.accent,
                      height: 1.0)),
            if (f.bigNumber != null) _bigNumber(f, dual),
            if (f.unit != null)
              Text(
                f.unit!,
                style: TextStyle(
                  fontSize: (width * 0.17).clamp(9.0, 18.0),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2933),
                ),
              ),
            if (f.sub != null)
              Padding(
                padding: EdgeInsets.only(top: width * 0.03),
                child: Text(
                  f.sub!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: (width * 0.14).clamp(8.0, 15.0),
                    height: 1.2,
                    color: const Color(0xFF5B6670),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Det store tal, farvet efter retning:
  ///  - kun frem → sort
  ///  - kun tilbage → rødt
  ///  - begge → delt sort (venstre) / rødt (højre)
  Widget _bigNumber(CardFace f, bool dual) {
    const Color black = Color(0xFF1F2933);
    const Color red = Color(0xFFC62828);
    final TextStyle style = TextStyle(
      fontSize: dual ? width * 0.34 : width * 0.52,
      fontWeight: FontWeight.w800,
      height: 0.95,
      letterSpacing: -0.5,
      color: Colors.white, // males af ShaderMask nedenfor
    );
    final Text text = Text(f.bigNumber!, textAlign: TextAlign.center, style: style);

    if (f.canBackward && f.canForward) {
      // Delt sort/rødt: hård overgang ved midten.
      return ShaderMask(
        shaderCallback: (Rect r) => const LinearGradient(
          colors: <Color>[black, black, red, red],
          stops: <double>[0.0, 0.5, 0.5, 1.0],
        ).createShader(r),
        child: text,
      );
    }
    final Color solid = f.canBackward ? red : black;
    return Text(
      f.bigNumber!,
      textAlign: TextAlign.center,
      style: style.copyWith(color: solid),
    );
  }

  /// "♥ Ud af start"-chip på grøn bund — hjertet er ALTID rødt, teksten hvid.
  Widget _startChip() {
    final double fs = (width * 0.125).clamp(7.0, 13.0);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: width * 0.09, vertical: width * 0.03),
      decoration: BoxDecoration(
        color: _cStart,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
                text: '♥',
                style: TextStyle(
                    // Altid rødt hjerte. En lysere rød så det popper klart på
                    // den grønne chip (mørk rød ville drukne).
                    color: const Color(0xFFFF5A5A),
                    fontSize: fs)),
            TextSpan(
                text: ' Ud af start',
                style: TextStyle(color: Colors.white, fontSize: fs)),
          ],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: width * 0.09, vertical: width * 0.03),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: (width * 0.125).clamp(7.0, 13.0),
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
