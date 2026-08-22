import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';

/// Kort-typernes accentfarver (bånd i toppen).
const Color _cMove = Color(0xFF334155); // flyt
const Color _cStart = Color(0xFF2F7D34); // ud af start
const Color _cSpecial = Color(0xFFB7791F); // 7 / byt
const Color _cExit = Color(0xFFC62828); // UD-kort

/// Retningsfarver — SAMME sprog som brættet/loggen: sort = frem, rød =
/// tilbage. Retningen bæres primært af TEGNET (pil/fortegn), farven er kun
/// forstærkning (rød ≈ sort ved protanopi).
const Color _cInkFwd = Color(0xFF1F2933);
const Color _cInkBack = Color(0xFFC62828);

/// Én mekanik-token på kortet. Kortenes sprog er de FYSISKE korts notation
/// (stort tal + operator-token: `4×1`, `5↷`, `+2−5`, `⇄`), ikke tegnede
/// illustrationer — to af de oplagte tegninger ville lyve om reglerne
/// (split KAN spilles med én brik; en blokade er ÉN brik på sit UD-felt).
/// Kun de TAL-FRIE mekanikker (byt, hop) tegnes som vektor-glyffer.
///
/// Listen er den ENE kilde: tooltip, maler og tests læser alle [CardFace.
/// glyphs] — så en mutation i valget ikke kan overleve med grøn suite.
enum CardGlyphType { splitX1, seq, multi, swap, jump, dirBoth }

class CardGlyph {
  const CardGlyph(this.type, {this.a = 0, this.b = 0});

  final CardGlyphType type;

  /// Tal-parametre: seq = (frem, tilbage); multi = (skridt, brikker).
  final int a;
  final int b;

  /// Fuld tekst til tooltip/legend — samme ordlyd som valg-arket og admin,
  /// så spilleren møder det samme sprog alle steder.
  String get label => switch (type) {
        CardGlyphType.splitX1 => 'del over dine brikker',
        // a == 0: rent "eller N tilbage"-alternativ (intet frem-led).
        CardGlyphType.seq =>
          a > 0 ? '$a frem → $b tilbage' : 'eller $b tilbage',
        // Antal brikker FØRST ("2× 1 frem") — brugerens læsning: man vælger
        // to brikker og rykker hver 1 frem, ikke omvendt.
        CardGlyphType.multi => '$b× $a frem',
        CardGlyphType.swap => 'byt to brikker',
        CardGlyphType.jump => 'hopper over blokade',
        CardGlyphType.dirBoth => 'frem eller tilbage',
      };

  // MUTATION B (test-manager, må ikke merges): heroWord fjernet — testen
  // 'hero-glyffet bærer sit ord: "byt" under det store ⇄' (test/
  // card_face_test.dart) skal blive RØD, fordi find.text('byt') ikke
  // længere finder noget.
  String? get heroWord => null;

  /// Kompakt hjørne-token til thumbnails (<40 px) — dér hvor tekst er
  /// kategorisk umulig, og hvor "hvorfor rykkede hans brik baglæns?" opstår.
  String get cornerToken => switch (type) {
        CardGlyphType.splitX1 => '×1',
        CardGlyphType.seq => '±',
        CardGlyphType.multi => '×$b',
        CardGlyphType.swap => '⇄',
        CardGlyphType.jump => '↷',
        CardGlyphType.dirBoth => '±',
      };
}

/// Hvad et kort viser — udledt fra de aktuelle OPLØSTE regler (ikke
/// hardkodet, så admin-ændringer og varianter slår igennem). Ingen kulør,
/// ingen A/K/Q/J: kun hvad kortet gør. "Ud af start" markeres med et hjerte.
class CardFace {
  const CardFace({
    required this.eyebrow,
    required this.accent,
    this.bigNumber,
    this.icon,
    this.unit,
    this.startChip = false,
    this.glyphs = const <CardGlyph>[],
    this.canForward = false,
    this.canBackward = false,
  });

  final String eyebrow;
  final Color accent;
  final String? bigNumber; // fx "4", "1 / 11", "13", "7"
  final String? icon; // '♥' for UD/rent startkort
  final String? unit; // "frem"/"tilbage" — ét ord, læseligt ned til 9 px
  final bool startChip; // vis "♥ Ud af start"

  /// Mekanik-tokens i prioriteret rækkefølge (én kilde — se [CardGlyph]).
  final List<CardGlyph> glyphs;

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
      unit: 'Sæt en brik ud',
    );
  }
  final CardRuleConfig c = rules.forRank(card.rank!);
  // Mekanik-tokens — HOP skal kunne ses på kortet, ellers ligner et
  // Hopsakort et almindeligt talkort, og modstanderen forstår ikke hvorfor
  // blokaden blev passeret. Hop gælder KUN fremad-skridt i motoren
  // (rules.dart), så tokenen vises kun når kortet faktisk HAR fremad-skridt
  // — ellers ville kortet love en evne, der ingen effekt har.
  final List<CardGlyph> glyphs = <CardGlyph>[
    if (c.hasFwdThenBack)
      CardGlyph(CardGlyphType.seq, a: c.seqForward!, b: c.seqBackward!),
    if (c.swap) const CardGlyph(CardGlyphType.swap),
    if (c.hasMultiForward)
      CardGlyph(CardGlyphType.multi, a: c.multiSteps!, b: c.multiPieces!),
    if (c.jumpsBlockade && c.forwardSteps.isNotEmpty)
      const CardGlyph(CardGlyphType.jump),
  ];
  final bool hasForward = c.forwardSteps.isNotEmpty;
  final bool hasBackward = c.backwardSteps != null;
  final String forwardText = c.forwardSteps.join(' / ');
  final bool sameFwdBack = hasForward &&
      hasBackward &&
      c.forwardSteps.length == 1 &&
      c.forwardSteps.first == c.backwardSteps;

  // Split (klassisk 7'er, 25 år-4×1): tallet + ×1-tokenen er ÉT udtryk
  // ("N enkelttræk") — de fysiske korts egen notation. Uden ×1 ville fx
  // 25 år-firen være tvetydig mod et klassisk 4-kort.
  if (c.splitTotal != null) {
    return CardFace(
      eyebrow: 'Special',
      accent: _cSpecial,
      bigNumber: '${c.splitTotal}',
      startChip: c.exitStart,
      glyphs: <CardGlyph>[
        const CardGlyph(CardGlyphType.splitX1),
        ...glyphs,
      ],
      canForward: true,
    );
  }

  // Kort med bevægelse (frem og/eller tilbage). Følger den AKTUELLE
  // konfiguration — ikke hardkodet.
  if (hasForward || hasBackward) {
    final String bigNumber = hasForward ? forwardText : '${c.backwardSteps}';
    String? unit;
    final List<CardGlyph> dirGlyphs = <CardGlyph>[];
    if (sameFwdBack) {
      // Fx klassisk 4: samme antal frem eller tilbage — dobbeltpil-token i
      // stedet for 8 px-sætningen "frem eller tilbage".
      dirGlyphs.add(const CardGlyph(CardGlyphType.dirBoth));
    } else if (hasForward && hasBackward) {
      unit = 'frem';
      // Forskellige tal frem/tilbage: tilbage-tallet som rødt −token.
      dirGlyphs.add(CardGlyph(CardGlyphType.seq, a: 0, b: c.backwardSteps!));
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
      startChip: c.exitStart,
      glyphs: <CardGlyph>[...dirGlyphs, ...glyphs],
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
      unit: 'Ud af start',
      glyphs: glyphs,
    );
  }

  // Ren byt (fx en Knægt sat til byt) — ⇄-glyffet ER indholdet.
  if (c.swap) {
    return CardFace(
      eyebrow: 'Special',
      accent: _cSpecial,
      glyphs: glyphs,
    );
  }

  return const CardFace(eyebrow: '—', accent: _cMove, unit: 'ingen effekt');
}

/// Kortets fulde funktion i ORD — bruges af tooltip (hold nede/hover) og af
/// "Kortene i dette spil"-legenden. Bygget af SAMME glyf-liste som maleren
/// ([CardFace.glyphs]), så tekst og grafik ikke kan drive fra hinanden.
String cardFunctionSummary(PlayingCard card, CardRules rules) {
  final CardFace f = describeCardFace(card, rules);
  final StringBuffer b = StringBuffer(f.eyebrow);
  if (f.bigNumber != null) b.write(' ${f.bigNumber}');
  // Efter et tal er unit en fortsættelse ("Flyt 6 frem"); uden tal er den
  // en beskrivelse og får skilletegn ("Ud-kort — Sæt en brik ud").
  if (f.unit != null) {
    b.write(f.bigNumber != null ? ' ${f.unit}' : ' — ${f.unit}');
  }
  if (f.startChip) b.write(' · ♥ Ud af start');
  for (final CardGlyph g in f.glyphs) {
    b.write(' · ${g.label}');
  }
  return b.toString();
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

  String _functionSummary() => cardFunctionSummary(card, rules);

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
    // kortets fulde funktion i ORD — opslagsvejen for token-sproget (plus
    // "Kortene"-arket i spil-topbaren).
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
    // Meget små kort (fx "sidst spillede"-thumbnail i spiller-panelet,
    // ~32 px): bånd + tal + mekanik-token i hjørnet. Tokenen er den største
    // grafik-gevinst pr. pixel — det er her man spørger "hvorfor rykkede
    // hans brik baglæns/forbi blokaden?".
    if (width < 40) {
      final String glyph = f.bigNumber ?? f.icon ?? '·';
      final String? corner =
          f.glyphs.isNotEmpty ? f.glyphs.first.cornerToken : null;
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
              child: Stack(
                children: <Widget>[
                  Center(
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
                                  : _cInkFwd,
                            ),
                          ),
                  ),
                  if (corner != null)
                    Positioned(
                      right: 2,
                      bottom: 1,
                      child: Text(
                        corner,
                        style: TextStyle(
                          fontSize: (width * 0.30).clamp(8.0, 12.0),
                          fontWeight: FontWeight.w800,
                          color: _cSpecial,
                          height: 1.0,
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
    // Eyebrow ("SPECIAL"/"FLYT") skæres på smalle kort: ved 48 px er den
    // clamped til 7 px — under den grænse brugeren kaldte ulæselig — og
    // båndfarven siger allerede typen. Pladsen går til token-rækken.
    final bool showEyebrow = width >= 56;
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
                  horizontal: width * 0.07, vertical: width * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  if (showEyebrow)
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
    // Split-tokenen (×1) står INLINE efter tallet — "4×1" er ét udtryk.
    final bool inlineX1 =
        f.glyphs.isNotEmpty && f.glyphs.first.type == CardGlyphType.splitX1;
    final List<CardGlyph> allRow = <CardGlyph>[
      for (final CardGlyph g in f.glyphs)
        if (g.type != CardGlyphType.splitX1) g,
    ];
    // Læsbarheds-loft (QC-fund): admin kan kombinere mekanikker frit, og
    // FittedBox garanterer kun "intet overlap" — ikke læsbarhed. Med tal +
    // 2 tokens + ♥-chip på 48 px ender tokens ~9 px: præcis den grød
    // redesignet fjerner. Derfor vises højst 2 tokens (1 når ♥-chippen også
    // skal være der); rækkefølgen i glyphs ER prioriteringen, og tooltippen
    // bærer altid den fulde liste. De indbyggede sæt rammer aldrig loftet.
    final int maxTokens = f.startChip ? 1 : 2;
    final List<CardGlyph> rowGlyphs = allRow.take(maxTokens).toList();
    // Glyf-ONLY-kort (fx ren byt): første glyf renderes som HOVEDELEMENT i
    // tal-størrelse — i token-rækkens størrelse druknede det (brugerens fund
    // på legenden). Resten (om nogen) bliver i rækken. INVARIANT (i dag
    // implicit i describeCardFace): startChip sættes kun i grene der også
    // sætter bigNumber, så hero + ♥-chip (maxTokens=1) kan ikke mødes og
    // tabe glyf nr. 2 — sætter en fremtidig gren startChip uden tal, skal
    // dette gentænkes.
    final bool heroGlyph =
        f.icon == null && f.bigNumber == null && rowGlyphs.isNotEmpty;
    final List<CardGlyph> tailGlyphs =
        heroGlyph ? rowGlyphs.skip(1).toList() : rowGlyphs;
    // FittedBox(scaleDown) sikrer at tal + tokens ALTID skaleres ned til den
    // plads Expanded giver — så en hjerte-chip nedenunder aldrig overlappes.
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
            if (heroGlyph) ...<Widget>[
              _glyphWidget(rowGlyphs.first, heroSize: true),
              if (rowGlyphs.first.heroWord != null)
                Padding(
                  padding: EdgeInsets.only(top: width * 0.04),
                  child: Text(
                    rowGlyphs.first.heroWord!,
                    style: TextStyle(
                      fontSize: (width * 0.17).clamp(9.0, 18.0),
                      fontWeight: FontWeight.w700,
                      color: _cInkFwd,
                    ),
                  ),
                ),
            ] else if (f.bigNumber != null)
              inlineX1
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        _bigNumber(f, dual),
                        Text(
                          '×1',
                          style: TextStyle(
                            fontSize: width * 0.26,
                            fontWeight: FontWeight.w800,
                            color: _cSpecial,
                            height: 1.0,
                          ),
                        ),
                      ],
                    )
                  : _bigNumber(f, dual),
            // "frem" er default-retningen (sort tal) og skrives IKKE på
            // kortet (brugerens fund: støj på hvert eneste kort) — men
            // bevares i tooltip/legend-teksten. "tilbage" og beskrivelser
            // ("Ud af start", "Sæt en brik ud") vises fortsat.
            if (f.unit != null && f.unit != 'frem')
              Text(
                f.unit!,
                style: TextStyle(
                  fontSize: (width * 0.17).clamp(9.0, 18.0),
                  fontWeight: FontWeight.w700,
                  // "tilbage" er nu kortets ENESTE retningsord — det skal
                  // følge tallets farve (rødt på rene tilbage-kort), ikke
                  // modsige den (QC-fund).
                  color: f.canBackward && !f.canForward ? _cInkBack : _cInkFwd,
                ),
              ),
            if (tailGlyphs.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: width * 0.04),
                // Tokens på ÉN række (aldrig stakket): de er smalle, så de
                // kan være STORE i stedet for mange. Ved 2+ bærer tooltippen
                // den fulde forklaring.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < tailGlyphs.length; i++) ...<Widget>[
                      if (i > 0) SizedBox(width: width * 0.08),
                      _glyphWidget(tailGlyphs[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Én mekanik-token. Tal-bærende tokens er komprimeret TYPOGRAFI
  /// (`+2−5`, `1→ ×2`) — fem tegn kan stå ved 12-13 px hvor en sætning ikke
  /// kan. Kun de tal-frie (byt, hop) er tegnede vektor-glyffer.
  /// [heroSize]: glyffet er kortets hovedindhold (glyf-only-kort) og får
  /// tal-størrelse (0,42×bredden) i stedet for token-rækkens 0,24.
  Widget _glyphWidget(CardGlyph g, {bool heroSize = false}) {
    final double h =
        heroSize ? width * 0.42 : (width * 0.24).clamp(11.0, 22.0);
    switch (g.type) {
      case CardGlyphType.seq:
        // "+2−5": rækkefølgen (frem SÅ tilbage, samme brik) — aldrig to
        // fritstående pile, der ville læses som et VALG. a==0 (rent
        // "eller N tilbage"-kort) viser kun −b.
        return Text.rich(
          TextSpan(children: <InlineSpan>[
            if (g.a > 0)
              TextSpan(
                  text: '+${g.a}',
                  style: const TextStyle(color: _cInkFwd)),
            TextSpan(
                text: '−${g.b}',
                style: const TextStyle(color: _cInkBack)),
          ]),
          style: TextStyle(
            fontSize: h,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        );
      case CardGlyphType.multi:
        // "2× 1→" — antal brikker FØRST (guld), så skridtet med pil (samme
        // ordstilling som label-teksten "2× 1 frem").
        return Text.rich(
          TextSpan(children: <InlineSpan>[
            TextSpan(
                text: '${g.b}× ',
                style: const TextStyle(color: _cSpecial)),
            TextSpan(
                text: '${g.a}→', style: const TextStyle(color: _cInkFwd)),
          ]),
          style: TextStyle(
            fontSize: h,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        );
      case CardGlyphType.swap:
        return CustomPaint(
          size: Size(h * 1.9, h),
          painter: SwapGlyphPainter(),
        );
      case CardGlyphType.jump:
        return CustomPaint(
          size: Size(h * 1.7, h),
          painter: JumpGlyphPainter(),
        );
      case CardGlyphType.dirBoth:
        return CustomPaint(
          size: Size(h * 1.9, h * 0.7),
          painter: DirBothGlyphPainter(),
        );
      case CardGlyphType.splitX1:
        // Renderes inline efter tallet (se _center) — her som fallback.
        return Text('×1',
            style: TextStyle(
                fontSize: h,
                fontWeight: FontWeight.w800,
                color: _cSpecial,
                height: 1.0));
    }
  }

  /// Det store tal, farvet efter retning:
  ///  - kun frem → sort
  ///  - kun tilbage → rødt
  ///  - begge → delt sort (venstre) / rødt (højre)
  Widget _bigNumber(CardFace f, bool dual) {
    final TextStyle style = TextStyle(
      fontSize: dual ? width * 0.34 : width * 0.52,
      fontWeight: FontWeight.w800,
      height: 0.95,
      letterSpacing: -0.5,
      color: Colors.white, // males af ShaderMask nedenfor
    );
    final Text text =
        Text(f.bigNumber!, textAlign: TextAlign.center, style: style);

    if (f.canBackward && f.canForward) {
      // Delt sort/rødt: hård overgang ved midten.
      return ShaderMask(
        shaderCallback: (Rect r) => const LinearGradient(
          colors: <Color>[_cInkFwd, _cInkFwd, _cInkBack, _cInkBack],
          stops: <double>[0.0, 0.5, 0.5, 1.0],
        ).createShader(r),
        child: text,
      );
    }
    final Color solid = f.canBackward ? _cInkBack : _cInkFwd;
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
}

/// Byt-glyffet: to brikker med dobbeltpil imellem. Regel: KUN byt tegner et
/// PAR brikker (repræsenterer byttet mellem to spillere) — split/multi er
/// ren typografi, så de ikke kan forveksles med byt. Hop-glyffets ENE
/// cirkel er den statiske blokade, ikke et par. Fyldt = din brik, kontur =
/// en andens — semantisk sandt: byttet sker mellem forskellige spillere.
class SwapGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.height * 0.30;
    final double cy = size.height / 2;
    final Paint fill = Paint()..color = _cInkFwd;
    final Paint stroke = Paint()
      ..color = _cInkFwd
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.12;
    // Venstre brik (fyldt = din), højre brik (kontur = en andens).
    canvas.drawCircle(Offset(r + stroke.strokeWidth, cy), r, fill);
    canvas.drawCircle(
        Offset(size.width - r - stroke.strokeWidth, cy), r, stroke);
    // Dobbeltpil imellem: to korte linjer med pilehoveder.
    final double x0 = r * 2 + stroke.strokeWidth * 2;
    final double x1 = size.width - r * 2 - stroke.strokeWidth * 2;
    if (x1 <= x0) return;
    final double dy = size.height * 0.16;
    _arrow(canvas, Offset(x0, cy - dy), Offset(x1, cy - dy), stroke,
        headAtEnd: true);
    _arrow(canvas, Offset(x1, cy + dy), Offset(x0, cy + dy), stroke,
        headAtEnd: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hop-glyffet: bue-pil hen over ÉN kontur-brik. Bevidst kun én brik: en
/// blokade er én brik på sit eget UD-felt — to stablede brikker ville lære
/// spillerne en spærre-regel, der ikke findes.
class JumpGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.height * 0.26;
    final Paint stroke = Paint()
      ..color = _cInkFwd
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.12;
    // Brikken der hoppes over (kontur = en andens), midt for.
    final Offset c = Offset(size.width / 2, size.height - r - stroke.strokeWidth);
    canvas.drawCircle(c, r, stroke);
    // Buen: fra venstre bund, over brikken, ned mod højre — med pilehoved.
    final Path arc = Path()
      ..moveTo(stroke.strokeWidth, size.height * 0.85)
      ..quadraticBezierTo(size.width / 2, -size.height * 0.25,
          size.width - stroke.strokeWidth, size.height * 0.85);
    canvas.drawPath(arc, stroke);
    // Pilehovedet følger kurvens FAKTISKE tangent i endepunktet (endepunkt
    // minus kontrolpunkt for en kvadratisk bezier), normaliseret — et
    // håndsat (0.5,1)-gæt gav et ~12 % aflangt hoved, der ikke fulgte buen.
    final Offset end =
        Offset(size.width - stroke.strokeWidth, size.height * 0.85);
    final Offset control = Offset(size.width / 2, -size.height * 0.25);
    final Offset tangent = end - control;
    _arrowHead(canvas, end, tangent / tangent.distance, size.height * 0.30,
        Paint()..color = _cInkFwd);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Frem eller tilbage"-glyffet (klassisk 4): dobbeltpil ←→, venstre halvdel
/// rød (tilbage), højre sort (frem) — retningen bæres af PILENE, farven
/// forstærker kun (matcher det delte tal ovenover).
class DirBothGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    final double mid = size.width / 2;
    final Paint back = Paint()
      ..color = _cInkBack
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.18;
    final Paint fwd = Paint()
      ..color = _cInkFwd
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.18;
    _arrow(canvas, Offset(mid, cy), Offset(0, cy), back, headAtEnd: true);
    _arrow(canvas, Offset(mid, cy), Offset(size.width, cy), fwd,
        headAtEnd: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _arrow(Canvas canvas, Offset from, Offset to, Paint stroke,
    {required bool headAtEnd}) {
  canvas.drawLine(from, to, stroke);
  if (headAtEnd) {
    final Offset dir = (to - from);
    final double len = dir.distance;
    if (len == 0) return;
    final Offset unit = dir / len;
    _arrowHead(canvas, to, unit, stroke.strokeWidth * 2.2,
        Paint()..color = stroke.color);
  }
}

void _arrowHead(
    Canvas canvas, Offset tip, Offset unit, double size, Paint fill) {
  final Offset back = tip - unit * size;
  final Offset normal = Offset(-unit.dy, unit.dx) * (size * 0.6);
  final Path head = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
    ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
    ..close();
  canvas.drawPath(head, fill);
}
