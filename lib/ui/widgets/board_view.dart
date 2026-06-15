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
  });

  final GameState state;
  final int viewerIndex;
  final Set<String> highlightedPieceIds;
  final BoardAnimation? animation;
  final ValueChanged<String>? onPieceTap;

  double get _rotation => pi - viewerIndex * (pi / 2);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double size = c.biggest.shortestSide;
        return GestureDetector(
          onTapDown: (TapDownDetails d) => _handleTap(d.localPosition, size),
          child: CustomPaint(
            size: Size.square(size),
            painter: _BoardPainter(
              state: state,
              rotation: _rotation,
              highlighted: highlightedPieceIds,
              animation: animation,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset pos, double size) {
    if (onPieceTap == null) return;
    final List<_PiecePoint> points =
        _BoardPainter.computePiecePoints(state, size, _rotation);
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

// ---------------------------------------------------------------------------
// Geometri (statiske, rotation-bevidste hjælpere)
// ---------------------------------------------------------------------------

Offset _trackPoint(Offset c, double radius, int index, int trackLen, double rot) {
  final double a = -pi / 2 + 2 * pi * index / trackLen + rot;
  return Offset(c.dx + radius * cos(a), c.dy + radius * sin(a));
}

Offset _homePoint(
    Offset c, double radius, int playerIndex, int slot, int trackLen, double rot) {
  final int entry = playerIndex * (trackLen ~/ 4);
  final double a = -pi / 2 + 2 * pi * entry / trackLen + rot;
  final double r = radius - (slot + 1) * radius * 0.17;
  return Offset(c.dx + r * cos(a), c.dy + r * sin(a));
}

Offset _startPoint(
    Offset c, double radius, int playerIndex, int slot, int trackLen, double rot) {
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
  });

  final GameState state;
  final double rotation;
  final Set<String> highlighted;
  final BoardAnimation? animation;

  @override
  void paint(Canvas canvas, Size size) {
    final double dim = size.shortestSide;
    final Offset center = Offset(dim / 2, dim / 2);
    final double tr = dim * 0.40;
    final double cr = dim * 0.023;
    final int trackLen = state.geometry.trackLength;
    final int quarter = trackLen ~/ 4;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF14331F));
    final Rect boardRect = Rect.fromCircle(center: center, radius: dim * 0.47);
    canvas.drawCircle(
      center,
      dim * 0.47,
      Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      center,
      dim * 0.46,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFFF7ECD2), Color(0xFFE7D2A6)],
        ).createShader(boardRect),
    );
    canvas.drawCircle(
      center,
      dim * 0.46,
      Paint()
        ..color = const Color(0xFF8B5E3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = dim * 0.012,
    );

    // Hjemstræk.
    for (final Player pl in state.players) {
      for (int slot = 0; slot < state.geometry.homeStretchLength; slot++) {
        final Offset p = _homePoint(center, tr, pl.index, slot, trackLen, rotation);
        canvas.drawCircle(p, cr, Paint()..color = pl.color.withOpacity(0.22));
        canvas.drawCircle(
          p,
          cr,
          Paint()
            ..color = pl.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Spor-felter + numre.
    for (int i = 0; i < trackLen; i++) {
      final Offset p = _trackPoint(center, tr, i, trackLen, rotation);
      canvas.drawCircle(p, cr, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        cr,
        Paint()
          ..color = Colors.black38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      if (i % quarter != 0) {
        _text(canvas, '${i % quarter}', p, cr * 0.95, Colors.black54);
      }
    }

    // Ud-felter.
    for (final Player pl in state.players) {
      final int idx = state.geometry.startTrackIndexFor(pl.index);
      final Offset p = _trackPoint(center, tr, idx, trackLen, rotation);
      canvas.drawCircle(p, cr + 1.5, Paint()..color = pl.color.withOpacity(0.25));
      canvas.drawCircle(
        p,
        cr + 3,
        Paint()
          ..color = pl.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      _text(canvas, 'UD', p, cr * 0.8, pl.color);
    }

    // Start-bås.
    for (final Player pl in state.players) {
      for (int slot = 0; slot < 4; slot++) {
        final Offset p = _startPoint(center, tr, pl.index, slot, trackLen, rotation);
        canvas.drawCircle(p, cr, Paint()..color = pl.color.withOpacity(0.12));
        canvas.drawCircle(
          p,
          cr,
          Paint()
            ..color = pl.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // Center-emblem.
    canvas.drawCircle(center, dim * 0.11, Paint()..color = const Color(0xFF8B5E3C));
    canvas.drawCircle(
        center,
        dim * 0.11,
        Paint()
          ..color = const Color(0xFFEAD9B5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    _text(canvas, 'Partners', center, dim * 0.035, const Color(0xFFEAD9B5));

    // Brikker (animeret hvis aktiv).
    for (final _PiecePoint pp in computePiecePoints(state, dim, rotation)) {
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
    canvas.drawCircle(
        c + const Offset(0, 1.5), pr, Paint()..color = Colors.black.withOpacity(0.3));
    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: <Color>[Color.lerp(color, Colors.white, 0.45)!, color],
        ).createShader(Rect.fromCircle(center: c, radius: pr)),
    );
    canvas.drawCircle(
      c,
      pr,
      Paint()
        ..color = hl ? Colors.amber : Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = hl ? 3.5 : 1.4,
    );
  }

  static void _text(
      Canvas canvas, String s, Offset center, double fontSize, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            fontSize: fontSize, color: color, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static List<_PiecePoint> computePiecePoints(
      GameState state, double dim, double rotation) {
    final Offset center = Offset(dim / 2, dim / 2);
    final double tr = dim * 0.40;
    final int trackLen = state.geometry.trackLength;
    final double spread = dim * 0.016;

    final List<_PiecePoint> bases = <_PiecePoint>[];
    final List<String> keys = <String>[];
    for (final Player pl in state.players) {
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
            piece.id, _posPoint(pos, center, tr, trackLen, rotation), pl.color));
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
      old.rotation != rotation;
}
