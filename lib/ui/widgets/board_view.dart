import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/piece.dart';
import '../../models/player.dart';

/// Beskriver brikker der animeres fra ét felt til et andet.
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

  double get _rotation =>
      pi - viewerIndex * (pi / 2) - (quarterTurn ? pi / 4 : 0);

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
  // Kun lyse farver mørknes; jo lysere, jo mere. Gul (lum≈0.72) → ~0.30 så
  // den bliver et tydeligt guld der kontrasterer banen.
  final double amount = ((lum - 0.4).clamp(0.0, 1.0)) * 0.95;
  return Color.lerp(c, const Color(0xFF000000), amount) ?? c;
}

// ---------------------------------------------------------------------------
// Geometri (statiske, rotation-bevidste hjælpere)
// ---------------------------------------------------------------------------

// Ringen er en 60-felts ring: 4 UD-felter (ved indeks 0, 15, 30, 45) +
// 14 nummererede felter pr. spiller. Hvert ringindeks er en TrackPosition.

Offset _trackPoint(Offset c, double radius, int index, int trackLen, double rot) {
  final double a = -pi / 2 + 2 * pi * index / trackLen + rot;
  return Offset(c.dx + radius * cos(a), c.dy + radius * sin(a));
}

Offset _homePoint(
    Offset c, double radius, int playerIndex, int slot, int trackLen, double rot) {
  // Hjemstrækket peger fra UD-feltets retning radielt ind mod centrum.
  final int entry = playerIndex * (trackLen ~/ 4);
  final double a = -pi / 2 + 2 * pi * entry / trackLen + rot;
  final double r = radius - (slot + 1) * radius * 0.17;
  return Offset(c.dx + r * cos(a), c.dy + r * sin(a));
}

Offset _startPoint(
    Offset c, double radius, int playerIndex, int slot, int trackLen, double rot) {
  // Start-båsen ligger uden for ringen ud for UD-feltet.
  final int entry = playerIndex * (trackLen ~/ 4);
  final double aEntry = -pi / 2 + 2 * pi * entry / trackLen + rot;
  final double rOuter = radius + radius * 0.22;
  final double a = aEntry + (slot - 1.5) * 0.10;
  return Offset(c.dx + rOuter * cos(a), c.dy + rOuter * sin(a));
}

Offset _posPoint(
    PiecePosition pos, Offset c, double radius, int trackLen, double rot) {
  if (pos is StartPosition) {
    return _startPoint(c, radius, pos.ownerIndex, pos.slot, trackLen, rot);
  } else if (pos is TrackPosition) {
    return _trackPoint(c, radius, pos.index, trackLen, rot);
  } else if (pos is HomeStretchPosition) {
    return _homePoint(c, radius, pos.ownerIndex, pos.slot, trackLen, rot);
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
    // 60 celler rundt: hold cellerne små nok til ikke at overlappe hinanden
    // (omkreds/60 ≈ 0.042·dim pr. celle; diameter 2·cr ≈ 0.038·dim < det).
    final double cr = dim * 0.0188 * scale;
    final int trackLen = state.geometry.trackLength;
    final int quarter = trackLen ~/ 4;

    // Skiven skaleres med brættet, men klippes til boksen så en forstørret
    // (drejet) skive ikke løber over kanten.
    final double discR = min(dim * 0.46 * scale, dim * 0.492);
    final double shadowR = min(discR * 1.022, dim * 0.499);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF14331F));
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

    // Hjemstræk. Kontur tegnes i en MØRKERE variant af spillerfarven, så lyse
    // farver (især gul) ikke drukner i den cremefarvede bane.
    for (final Player pl in state.players) {
      final Color plColor = _seatColor(pl.index);
      final Color outline = _boardOutline(plColor);
      for (int slot = 0; slot < state.geometry.homeStretchLength; slot++) {
        final Offset p = _homePoint(center, tr, pl.index, slot, trackLen, rotation);
        canvas.drawCircle(p, cr, Paint()..color = plColor.withValues(alpha: 0.38));
        canvas.drawCircle(
          p,
          cr,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
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

    // Spor-felter. Ringen er på [trackLen] felter (60 = 4 UD + 4×14
    // nummererede). For hvert ringindeks: UD-felter (i % quarter == 0) tegnes
    // i ejer-spillerens farve, øvrige som hvide cirkler med felt-nummer 1..14.
    for (int i = 0; i < trackLen; i++) {
      final Offset p = _trackPoint(center, tr, i, trackLen, rotation);
      final bool isExit = i % quarter == 0;
      final int owner = i ~/ quarter;
      if (isExit) {
        final Color ownerColor = _seatColor(owner);
        final Color outline = _boardOutline(ownerColor);
        canvas.drawCircle(
            p, cr, Paint()..color = ownerColor.withValues(alpha: 0.42));
        canvas.drawCircle(
          p,
          cr,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        _text(canvas, 'UD', p, cr * 0.85, outline);
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

    // Start-bås.
    for (final Player pl in state.players) {
      final Color plColor = _seatColor(pl.index);
      final Color outline = _boardOutline(plColor);
      for (int slot = 0; slot < 4; slot++) {
        final Offset p = _startPoint(center, tr, pl.index, slot, trackLen, rotation);
        canvas.drawCircle(p, cr, Paint()..color = plColor.withValues(alpha: 0.22));
        canvas.drawCircle(
          p,
          cr,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
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
    _text(canvas, 'Partners', center, dim * 0.035 * scale, const Color(0xFFEAD9B5));

    // Brikker (animeret hvis aktiv).
    for (final _PiecePoint pp in computePiecePoints(state, dim, rotation,
        colorOffset: colorOffset, scale: scale)) {
      Offset c = pp.center;
      final BoardAnimation? anim = animation;
      if (anim != null && anim.moves.containsKey(pp.pieceId)) {
        final m = anim.moves[pp.pieceId]!;
        final Offset from = _posPoint(m.from, center, tr, trackLen, rotation);
        final Offset to = _posPoint(m.to, center, tr, trackLen, rotation);
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
      final Offset p = _trackPoint(center, tr, index, trackLen, rotation);
      final Offset badge = p + Offset(cr, -cr);
      canvas.drawCircle(badge, cr * 0.7, Paint()..color = Colors.black);
      _text(canvas, '$count', badge, cr * 0.8, Colors.white);
    });
  }

  void _drawPiece(Canvas canvas, Offset c, double r, Color color, bool hl) {
    final double pr = r * 1.15;
    // Lyse farver (især gul) mørknes så brikken læses som en solid token på
    // den cremefarvede bane — ellers smelter den sammen med felterne.
    final Color base = _pieceFill(color);
    // Mindre hvid-highlight på lyse farver, så toppen ikke bliver næsten hvid.
    final double lum = color.computeLuminance();
    final double hi = lum > 0.5 ? 0.25 : 0.45;
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
    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..color = hl ? Colors.amber : Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = hl ? 3.5 : 1.8,
    );
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
    final int trackLen = state.geometry.trackLength;
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
        bases.add(_PiecePoint(
            piece.id, _posPoint(pos, center, tr, trackLen, rotation), plColor));
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

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.state != state ||
      old.highlighted != highlighted ||
      old.animation != animation ||
      old.rotation != rotation ||
      old.colorOffset != colorOffset ||
      old.scale != scale;
}
