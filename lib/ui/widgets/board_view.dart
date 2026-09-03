import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/piece.dart';
import '../../models/player.dart';

/// Beskriver brikker der animeres fra ét felt til et andet.
/// Den lokale farve-rotation for [BoardView.colorOffset].
///
/// Spilleren kan vælge sin egen ønske-farve; brættet roterer så farverne uden
/// at ændre noget i spillets data. ÉN vagt: både spille-brættet og
/// "mens du var væk"-brættet skal regne den ens — ellers ville replayen vise
/// Carin som gul, mens brættet lige under viser hende som blå.
int colorOffsetFor(List<int> seatColorValues, int mySeat, int? preferred) {
  if (preferred == null) return 0;
  final int n = seatColorValues.length;
  if (n == 0) return 0;
  for (int k = 0; k < n; k++) {
    if (seatColorValues[(mySeat + k) % n] == preferred) return k;
  }
  return 0;
}

class BoardAnimation {
  const BoardAnimation(this.moves, this.progress);

  /// pieceId -> (fra, til)
  final Map<String, ({PiecePosition from, PiecePosition to})> moves;
  final double progress;
}

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.state,
    this.viewerIndex = 0,
    this.highlightedPieceIds = const <String>{},
    this.animation,
    this.onPieceTap,
    this.colorOffset = 0,
    this.quarterTurn = false,
  });

  final GameState state;
  final int viewerIndex;
  final Set<String> highlightedPieceIds;
  final BoardAnimation? animation;
  final ValueChanged<String>? onPieceTap;

  /// Lokal farve-rotation (0..3). Plads `s` vises i farven fra plads
  /// `(s + colorOffset) % antalSpillere` — rent visuelt, ændrer intet i
  /// spillets data. Bruges så en spiller kan vælge sin egen ønske-farve.
  final int colorOffset;

  /// Drej hele opsætningen en kvart-diagonal (45°) med uret, så start-/UD-
  /// områderne peger mod hjørnerne i stedet for kanterne. Derved kan selve
  /// skiven fylde mere af en smal (telefon-)skærm. Spillerens eget hjem havner
  /// nederst til højre. Rent visuelt — ændrer intet i spillets data.
  final bool quarterTurn;

  // Ét segment fylder 2π/segments. Rotationen bringer viewerens eget sæde ned,
  // og quarterTurn drejer en HALV segment-bredde (π/segments) så UD-områderne
  // peger mod hjørnerne. Klassisk (4 segmenter): 2π/4 = π/2 og π/4 — uændret.
  double get _rotation {
    final int segments = state.geometry.segments;
    return pi -
        viewerIndex * (2 * pi / segments) -
        (quarterTurn ? pi / segments : 0);
  }

  /// Når brættet er drejet 45° peger start-båsene mod hjørnerne, så der er plads
  /// til at forstørre skiven en anelse inden for samme (kvadratiske) boks.
  double get _scale => quarterTurn ? 1.07 : 1.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double size = c.biggest.shortestSide;
        return GestureDetector(
          // onTapUp (ikke onTapDown): et rent tap vælger en brik, mens et
          // træk (panorering i InteractiveViewer når man er zoomet ind) taber
          // tap-arenaen og derfor IKKE fejlagtigt vælger en brik.
          onTapUp: (TapUpDetails d) => _handleTap(d.localPosition, size),
          child: CustomPaint(
            size: Size.square(size),
            painter: _BoardPainter(
              state: state,
              rotation: _rotation,
              highlighted: highlightedPieceIds,
              animation: animation,
              colorOffset: colorOffset,
              scale: _scale,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset pos, double size) {
    if (onPieceTap == null) return;
    final List<_PiecePoint> points =
        _BoardPainter.computePiecePoints(state, size, _rotation, scale: _scale);
    _PiecePoint? best;
    double bestDist = double.infinity;
    for (final _PiecePoint pp in points) {
      final double d = (pp.center - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = pp;
      }
    }
    if (best != null && bestDist <= 30) {
      onPieceTap!(best.pieceId);
    }
  }

  /// Brik-id → skærm-center, som brættet faktisk tegner dem. Kun til test af
  /// rendering-geometrien for N spillere (den private painter kan ellers ikke
  /// nås udefra). Samme kilde som både tegning og tap-detektion.
  @visibleForTesting
  /// KUN TIL TEST: painterens visuelle signatur for [state]. Eksponeret så
  /// testen kan låse at variant.id indgår (klassisk/p25 er identiske på
  /// geometri/brikker/farver, så to ens sig'er ville betyde at et variant-
  /// skift ikke udløser repaint). Samme mønster som [debugPieceCenters] —
  /// dansk privathed er library-scoped, så en test kan ikke nå
  /// _BoardPainter._computeVisualSig direkte.
  @visibleForTesting
  static String debugVisualSig(GameState state) =>
      _BoardPainter._computeVisualSig(state);

  static Map<String, Offset> debugPieceCenters(
      GameState state, double dim, double rotation,
      {double scale = 1.0}) {
    return <String, Offset>{
      for (final _PiecePoint p
          in _BoardPainter.computePiecePoints(state, dim, rotation, scale: scale))
        p.pieceId: p.center,
    };
  }
}

class _PiecePoint {
  _PiecePoint(this.pieceId, this.center, this.color);
  final String pieceId;
  final Offset center;
  final Color color;
}

/// Kontur-farve til felt-markører på den cremefarvede bane. Lyse farver (fx
/// gul) mørknes MERE, så de får synlig definition; mørke farver mørknes let.
Color _boardOutline(Color c) {
  // Perceptuel lyshed (0..1). Gul ligger højt → mørknes kraftigt.
  final double lum = c.computeLuminance();
  final double amount = 0.30 + lum * 0.45; // 0.30 (mørk) .. 0.75 (meget lys)
  return Color.lerp(c, const Color(0xFF000000), amount) ?? c;
}

/// Brik-fyldfarve: KUN lyse farver (gul o.l.) mørknes til en rigere nuance, så
/// brikken kontrasterer den cremefarvede bane. Mørke farver (rød/blå/grøn)
/// røres stort set ikke, så deres identitet bevares.
Color _pieceFill(Color c) {
  final double lum = c.computeLuminance();
  // Kun lyse farver mørknes. Vi mørkner mod en VARM mørk tone (ikke ren sort),
  // så gul bliver et rigt, mættet guld — ikke en mudret oliven — der stadig
  // læses som gul, men kontrasterer den varme bane.
  final double amount = ((lum - 0.45).clamp(0.0, 1.0)) * 0.72;
  return Color.lerp(c, const Color(0xFF4A3300), amount) ?? c;
}

/// Den klassiske ringlængde (4 segmenter × 15 felter). Celle-radius blev tunet
/// mod denne; længere ringe krymper cellerne proportionalt (se [_BoardPainter]).
const double _kClassicRingLength = 60.0;

// ---------------------------------------------------------------------------
// Geometri (statiske, rotation-bevidste hjælpere)
// ---------------------------------------------------------------------------

// Ringen er delt i [geo.segments] lige store segmenter: ét UD-felt pr. segment
// (ved indeks 0, trackLen/segments, 2·…, …) + de nummererede felter. Klassisk =
// 60 felter / 4 segmenter (UD ved 0, 15, 30, 45). Al "hvor ligger sæde k's
// indgang"-matematik delegeres til [BoardGeometry.startTrackIndexFor], så reglen
// findes ét sted og er dækket af geometri-testen.

Offset _trackPoint(Offset c, double radius, int index, BoardGeometry geo, double rot) {
  final double a = -pi / 2 + 2 * pi * index / geo.trackLength + rot;
  return Offset(c.dx + radius * cos(a), c.dy + radius * sin(a));
}

Offset _homePoint(
    Offset c, double radius, int playerIndex, int slot, BoardGeometry geo, double rot) {
  // Hjemstrækket peger fra UD-feltets retning radielt ind mod centrum.
  final int entry = geo.startTrackIndexFor(playerIndex);
  final double a = -pi / 2 + 2 * pi * entry / geo.trackLength + rot;
  final double r = radius - (slot + 1) * radius * 0.17;
  return Offset(c.dx + r * cos(a), c.dy + r * sin(a));
}

Offset _startPoint(Offset c, double radius, int playerIndex, int slot,
    int piecesPerPlayer, BoardGeometry geo, double rot) {
  // Start-båsen ligger uden for ringen ud for UD-feltet. Båsene fordeles
  // symmetrisk om indgangsvinklen: centreringen er (P-1)/2, ikke hardkodet 1.5,
  // så P≠4 brikker ikke giver en skæv vifte. Klassisk P=4 → (4-1)/2 = 1.5.
  final int entry = geo.startTrackIndexFor(playerIndex);
  final double aEntry = -pi / 2 + 2 * pi * entry / geo.trackLength + rot;
  final double rOuter = radius + radius * 0.22;
  final double a = aEntry + (slot - (piecesPerPlayer - 1) / 2) * 0.10;
  return Offset(c.dx + rOuter * cos(a), c.dy + rOuter * sin(a));
}

Offset _posPoint(PiecePosition pos, Offset c, double radius, int piecesPerPlayer,
    BoardGeometry geo, double rot) {
  if (pos is StartPosition) {
    return _startPoint(
        c, radius, pos.ownerIndex, pos.slot, piecesPerPlayer, geo, rot);
  } else if (pos is TrackPosition) {
    return _trackPoint(c, radius, pos.index, geo, rot);
  } else if (pos is HomeStretchPosition) {
    return _homePoint(c, radius, pos.ownerIndex, pos.slot, geo, rot);
  }
  return c;
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.state,
    required this.rotation,
    required this.highlighted,
    this.animation,
    this.colorOffset = 0,
    this.scale = 1.0,
  });

  final GameState state;
  final double rotation;
  final Set<String> highlighted;
  final BoardAnimation? animation;
  final int colorOffset;
  final double scale;

  /// Kompakt signatur af ALT det brættet faktisk tegner: brik-position pr. id,
  /// farve pr. sæde og geometri. Bruges i [shouldRepaint] i stedet for at
  /// sammenligne hele [GameState] — som ikke har værdi-lighed og desuden
  /// gen-oprettes ved hvert snapshot. Så et rebuild med UÆNDRET bræt (fx udløst
  /// af en presence-heartbeat, forbrugs-fund #4/#5) genmaler ikke canvas'et.
  /// rotation/colorOffset/highlight/animation sammenlignes separat nedenfor.
  late final String _visualSig = _computeVisualSig(state);

  // colorOffset indgår IKKE her — den sammenlignes separat i shouldRepaint, og
  // signaturen bruger farve pr. sæde i state.players-rækkefølge.
  static String _computeVisualSig(GameState state) {
    // Geometri: trackLength/homeStretch + segments og piecesPerPlayer, da de
    // to sidste ændrer indgangs-positioner og start-båsenes antal/centrering.
    final StringBuffer sb = StringBuffer()
      ..write(state.geometry.trackLength)
      ..write('/')
      ..write(state.geometry.homeStretchLength)
      ..write('/')
      ..write(state.geometry.segments)
      ..write('/')
      ..write(state.variant.piecesPerPlayer)
      // Variant-id: klassisk/p25 har IDENTISK geometri, så uden denne ville et
      // variant-skift ikke udløse repaint af bord-farven (feltColor).
      ..write('/')
      ..write(state.variant.id);
    for (final Player p in state.players) {
      sb
        ..write(';')
        ..write(p.color.toARGB32());
    }
    final List<Piece> pieces = state.allPieces.toList()
      ..sort((Piece a, Piece b) => a.id.compareTo(b.id));
    for (final Piece pc in pieces) {
      final PiecePosition pos = pc.position;
      sb
        ..write('|')
        ..write(pc.id)
        ..write('@');
      if (pos is StartPosition) {
        sb
          ..write('S')
          ..write(pos.ownerIndex)
          ..write('.')
          ..write(pos.slot);
      } else if (pos is TrackPosition) {
        sb
          ..write('T')
          ..write(pos.index);
      } else if (pos is HomeStretchPosition) {
        sb
          ..write('H')
          ..write(pos.ownerIndex)
          ..write('.')
          ..write(pos.slot);
      } else {
        sb.write('?');
      }
    }
    return sb.toString();
  }

  /// Vis-farve for en plads efter lokal rotation.
  Color _seatColor(int seat) {
    final int n = state.players.length;
    return state.players[(seat + colorOffset) % n].color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double dim = size.shortestSide;
    final Offset center = Offset(dim / 2, dim / 2);
    final double tr = dim * 0.405 * scale;
    final BoardGeometry geo = state.geometry;
    final int trackLen = geo.trackLength;
    final int segments = geo.segments;
    final int piecesPerPlayer = state.variant.piecesPerPlayer;
    // Celle-radius tunet til den klassiske 60-felts ring (omkreds/60 ≈ 0.042·dim
    // pr. celle; diameter 2·cr ≈ 0.038·dim < det). For en LÆNGERE ring krymper
    // cellerne proportionalt (referencelængde/trackLen) så de ikke overlapper.
    // Klassisk: 60/60 = 1 → nøjagtig 0.0188 som før.
    final double cr =
        dim * 0.0188 * (_kClassicRingLength / trackLen) * scale;
    final int quarter = trackLen ~/ segments;

    // Skiven skaleres med brættet, men klippes til boksen så en forstørret
    // (drejet) skive ikke løber over kanten.
    final double discR = min(dim * 0.46 * scale, dim * 0.492);
    final double shadowR = min(discR * 1.022, dim * 0.499);
    // Bord-farven kommer fra varianten (klassisk grøn / 25 år marineblå) —
    // selve spillefladen ovenpå er creme uanset variant, så brikkernes
    // læsbarhed er uændret.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = state.variant.feltColor);
    final Rect boardRect = Rect.fromCircle(center: center, radius: shadowR);
    canvas.drawCircle(
      center,
      shadowR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      center,
      discR,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFFF7ECD2), Color(0xFFE7D2A6)],
        ).createShader(boardRect),
    );
    canvas.drawCircle(
      center,
      discR,
      Paint()
        ..color = const Color(0xFF8B5E3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = dim * 0.012,
    );

    // Hjemstræk. Felterne tegnes som NEUTRALE brønde med en tynd farvet
    // ejer-ring — så en brik i samme farve som feltet ikke drukner.
    for (final Player pl in state.players) {
      final Color plColor = _seatColor(pl.index);
      for (int slot = 0; slot < state.geometry.homeStretchLength; slot++) {
        final Offset p = _homePoint(center, tr, pl.index, slot, geo, rotation);
        _drawWell(canvas, p, cr, plColor);
      }
    }

    // Mørkere ring-bånd UNDER felterne: en dybere tan-cirkel langs sporet, så
    // de hvide felter og tallene får mere kontrast — især vigtigt når brættet
    // vises småt på et lille vindue.
    canvas.drawCircle(
      center,
      tr,
      Paint()
        ..color = const Color(0xFFB08A50).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cr * 2.6,
    );

    // Spor-felter. Ringen er på [trackLen] felter (klassisk 60 = 4 UD + 4×14
    // nummererede; generelt segments UD + segments×fieldsPerSegment). For hvert
    // ringindeks: UD-felter (i % quarter == 0) tegnes i ejer-spillerens farve,
    // øvrige som hvide cirkler med felt-nummer 1..(quarter-1).
    for (int i = 0; i < trackLen; i++) {
      final Offset p = _trackPoint(center, tr, i, geo, rotation);
      final bool isExit = i % quarter == 0;
      final int owner = i ~/ quarter;
      if (isExit) {
        final Color ownerColor = _seatColor(owner);
        // UD-felt: neutral brønd + farvet ejer-ring, "UD" i mørk ejer-farve.
        _drawWell(canvas, p, cr, ownerColor, ringWidth: 0.17);
        _text(canvas, 'UD', p, cr * 0.85, _boardOutline(ownerColor));
      } else {
        canvas.drawCircle(p, cr, Paint()..color = Colors.white);
        canvas.drawCircle(
          p,
          cr,
          Paint()
            ..color = Colors.black54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        // Font ≈ 1.32 × celle-radius, ekstra fed og helt sort: tallet fylder
        // cirklen ud og er læsbart selv når brættet vises småt.
        _text(canvas, '${i % quarter}', p, cr * 1.32, Colors.black,
            weight: FontWeight.w800);
      }
    }

    // Start-bås — samme neutrale brønd med farvet ejer-ring. Én brønd pr. brik.
    for (final Player pl in state.players) {
      final Color plColor = _seatColor(pl.index);
      for (int slot = 0; slot < piecesPerPlayer; slot++) {
        final Offset p = _startPoint(
            center, tr, pl.index, slot, piecesPerPlayer, geo, rotation);
        _drawWell(canvas, p, cr, plColor, ringWidth: 0.13);
      }
    }

    // Center-emblem.
    final double emblemR = dim * 0.11 * scale;
    canvas.drawCircle(center, emblemR, Paint()..color = const Color(0xFF8B5E3C));
    canvas.drawCircle(
        center,
        emblemR,
        Paint()
          ..color = const Color(0xFFEAD9B5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // To linjer: "Partners" + variantens korte navn ("Klassisk"/"25 år") —
    // versionen står dermed midt på selve spillepladen, for BEGGE varianter
    // (samme positiv-tilstedeværelses-princip som badgen: et par læres, en
    // enkelt markering gør ikke).
    _text(canvas, 'Partners', center - Offset(0, dim * 0.018 * scale),
        dim * 0.035 * scale, const Color(0xFFEAD9B5));
    _text(canvas, state.variant.shortLabel,
        center + Offset(0, dim * 0.022 * scale), dim * 0.026 * scale,
        const Color(0xFFEAD9B5),
        weight: FontWeight.w500);

    // Brikker (animeret hvis aktiv).
    for (final _PiecePoint pp in computePiecePoints(state, dim, rotation,
        colorOffset: colorOffset, scale: scale)) {
      Offset c = pp.center;
      final BoardAnimation? anim = animation;
      if (anim != null && anim.moves.containsKey(pp.pieceId)) {
        final m = anim.moves[pp.pieceId]!;
        final Offset from =
            _posPoint(m.from, center, tr, piecesPerPlayer, geo, rotation);
        final Offset to =
            _posPoint(m.to, center, tr, piecesPerPlayer, geo, rotation);
        c = Offset.lerp(from, to, Curves.easeInOut.transform(anim.progress))!;
      }
      _drawPiece(canvas, c, cr, pp.color, highlighted.contains(pp.pieceId));
    }

    // Antal-badge på dobbelt-felter.
    final Map<int, int> byTrack = <int, int>{};
    for (final Piece pc in state.allPieces) {
      final pos = pc.position;
      if (pos is TrackPosition) {
        byTrack[pos.index] = (byTrack[pos.index] ?? 0) + 1;
      }
    }
    byTrack.forEach((int index, int count) {
      if (count < 2) return;
      final Offset p = _trackPoint(center, tr, index, geo, rotation);
      final Offset badge = p + Offset(cr, -cr);
      canvas.drawCircle(badge, cr * 0.7, Paint()..color = Colors.black);
      _text(canvas, '$count', badge, cr * 0.8, Colors.white);
    });
  }

  /// Neutral "brønd" med en tynd farvet ejer-ring: en lys fordybning med en
  /// mørk kant-rim og en ring i ejerens farve. Erstatter de tidligere
  /// farve-fyldte felter, så en brik i SAMME farve som feltet ikke drukner.
  void _drawWell(Canvas canvas, Offset p, double cr, Color ringColor,
      {double ringWidth = 0.16}) {
    // Mørk fordybnings-rim under en lys neutral brønd (giver dybde + kontrast).
    canvas.drawCircle(
        p, cr, Paint()..color = Colors.black.withValues(alpha: 0.14));
    canvas.drawCircle(
        p, cr * 0.92, Paint()..color = const Color(0xFFF2E7CC));
    // Ejer-ring.
    canvas.drawCircle(
      p,
      cr,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = cr * ringWidth,
    );
  }

  void _drawPiece(Canvas canvas, Offset c, double r, Color color, bool hl) {
    final double pr = r * 1.15;
    // Lyse farver (især gul) mørknes så brikken læses som en solid token på
    // den cremefarvede bane — ellers smelter den sammen med felterne.
    final Color base = _pieceFill(color);
    // Lyse farver (gul) får MINDRE top-glans, så toppen ikke vaskes ud mod den
    // lyse bane, og en KRAFTIGERE mørk kant, så brikken står skarpt.
    final double lum = color.computeLuminance();
    final bool light = lum > 0.5;
    final double hi = light ? 0.12 : 0.45;
    final double darkEdge = light ? 2.4 : 1.5;
    canvas.drawCircle(c + const Offset(0, 1.5), pr,
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: <Color>[Color.lerp(base, Colors.white, hi)!, base],
        ).createShader(Rect.fromCircle(center: c, radius: pr)),
    );
    // Kontrast-kant: en hvid ring med en tynd mørk/amber streg ovenpå. Den
    // hvide ring "løfter" brikken fra baggrunden — også fra et felt i SAMME
    // farve (fx en gul brik i det gule hus) — så det altid er tydeligt at der
    // står en brik. Gælder alle farver.
    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = hl ? 4.0 : 3.0,
    );
    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..color = hl ? const Color(0xFFFF8F00) : Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = hl ? 3.0 : darkEdge,
    );
    // Lille glans-prik → brikken læses som en blank, rund token.
    canvas.drawCircle(c + Offset(-pr * 0.32, -pr * 0.34), pr * 0.18,
        Paint()..color = Colors.white.withValues(alpha: 0.55));
  }

  static void _text(
      Canvas canvas, String s, Offset center, double fontSize, Color color,
      {FontWeight weight = FontWeight.w700}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            fontSize: fontSize, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static List<_PiecePoint> computePiecePoints(
      GameState state, double dim, double rotation,
      {int colorOffset = 0, double scale = 1.0}) {
    final Offset center = Offset(dim / 2, dim / 2);
    final double tr = dim * 0.405 * scale;
    final BoardGeometry geo = state.geometry;
    final int piecesPerPlayer = state.variant.piecesPerPlayer;
    final double spread = dim * 0.014 * scale;
    final int n = state.players.length;

    final List<_PiecePoint> bases = <_PiecePoint>[];
    final List<String> keys = <String>[];
    for (final Player pl in state.players) {
      final Color plColor = state.players[(pl.index + colorOffset) % n].color;
      for (final Piece piece in pl.pieces) {
        final PiecePosition pos = piece.position;
        final String key;
        if (pos is StartPosition) {
          key = 'S${pos.ownerIndex}.${pos.slot}';
        } else if (pos is TrackPosition) {
          key = 'T${pos.index}';
        } else if (pos is HomeStretchPosition) {
          key = 'H${pos.ownerIndex}.${pos.slot}';
        } else {
          continue;
        }
        bases.add(_PiecePoint(piece.id,
            _posPoint(pos, center, tr, piecesPerPlayer, geo, rotation), plColor));
        keys.add(key);
      }
    }

    final Map<String, int> counts = <String, int>{};
    for (final String k in keys) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final Map<String, int> seen = <String, int>{};
    final List<_PiecePoint> out = <_PiecePoint>[];
    for (int i = 0; i < bases.length; i++) {
      final String k = keys[i];
      final int n = counts[k] ?? 1;
      final int idx = seen[k] ?? 0;
      seen[k] = idx + 1;
      Offset offset = Offset.zero;
      if (n > 1) {
        final double angle = 2 * pi * idx / n;
        offset = Offset(cos(angle), sin(angle)) * spread;
      }
      out.add(_PiecePoint(
          bases[i].pieceId, bases[i].center + offset, bases[i].color));
    }
    return out;
  }

  /// Indholds-lighed for to Set<String> (undgår afhængighed af setEquals'
  /// import-sti). highlighted er et NYT Set pr. build (_highlightSet), så vi må
  /// sammenligne indhold — ellers ville brættet genmale ved hvert rebuild
  /// uanset signaturen.
  static bool _sameSet(Set<String> a, Set<String> b) =>
      identical(a, b) || (a.length == b.length && a.containsAll(b));

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old._visualSig != _visualSig ||
      !_sameSet(old.highlighted, highlighted) ||
      old.animation != animation ||
      old.rotation != rotation ||
      old.colorOffset != colorOffset ||
      old.scale != scale;
}
