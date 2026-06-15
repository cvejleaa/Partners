import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/piece.dart';
import '../../models/player.dart';

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.state,
    this.highlightedPieceIds = const <String>{},
    this.onPieceTap,
  });

  final GameState state;
  final Set<String> highlightedPieceIds;
  final ValueChanged<String>? onPieceTap;

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
              highlighted: highlightedPieceIds,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset pos, double size) {
    if (onPieceTap == null) return;
    final List<_PiecePoint> points =
        _BoardPainter.computePiecePoints(state, size);
    _PiecePoint? best;
    double bestDist = double.infinity;
    for (final _PiecePoint pp in points) {
      final double d = (pp.center - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = pp;
      }
    }
    if (best != null && bestDist <= 28) {
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

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.state, required this.highlighted});

  final GameState state;
  final Set<String> highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final double dim = size.shortestSide;
    final Offset center = Offset(dim / 2, dim / 2);
    final double trackRadius = dim * 0.40;
    final double cellRadius = dim * 0.022;
    final int trackLen = state.geometry.trackLength;
    final int quarter = trackLen ~/ 4;

    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFF5EAD2));

    // Spor-felter + numre (1..14 mellem ud-felterne, "UD" på ud-felterne).
    for (int i = 0; i < trackLen; i++) {
      final Offset p = _trackPoint(center, trackRadius, i, trackLen);
      final bool isEntry = i % quarter == 0;
      canvas.drawCircle(p, cellRadius, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        cellRadius,
        Paint()
          ..color = Colors.black45
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      if (!isEntry) {
        _drawText(canvas, '${i % quarter}', p, cellRadius * 0.95,
            Colors.black54);
      }
    }

    // Udgangsfelter med farvet ring + "UD".
    for (final Player pl in state.players) {
      final int idx = state.geometry.startTrackIndexFor(pl.index);
      final Offset p = _trackPoint(center, trackRadius, idx, trackLen);
      canvas.drawCircle(
        p,
        cellRadius + 3,
        Paint()
          ..color = pl.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      _drawText(canvas, 'UD', p, cellRadius * 0.8, pl.color);
    }

    // Hjemstræk.
    for (final Player pl in state.players) {
      for (int slot = 0; slot < state.geometry.homeStretchLength; slot++) {
        final Offset p =
            _homeStretchPoint(center, trackRadius, pl.index, slot, trackLen);
        canvas.drawCircle(
            p, cellRadius, Paint()..color = pl.color.withOpacity(0.18));
        canvas.drawCircle(
          p,
          cellRadius,
          Paint()
            ..color = pl.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Start-bås.
    for (final Player pl in state.players) {
      for (int slot = 0; slot < 4; slot++) {
        final Offset p =
            _startSlotPoint(center, trackRadius, pl.index, slot, trackLen);
        canvas.drawCircle(
            p, cellRadius, Paint()..color = pl.color.withOpacity(0.10));
        canvas.drawCircle(
          p,
          cellRadius,
          Paint()
            ..color = pl.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // Brikker (stakkede brikker spredes en smule).
    for (final _PiecePoint pp in computePiecePoints(state, dim)) {
      final bool hl = highlighted.contains(pp.pieceId);
      canvas.drawCircle(pp.center, cellRadius * 1.1, Paint()..color = pp.color);
      canvas.drawCircle(
        pp.center,
        cellRadius * 1.1,
        Paint()
          ..color = hl ? Colors.amber : Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = hl ? 3.5 : 1.5,
      );
    }

    // Antal-badge på beskyttede dobbelt-felter (2+ brikker på samme spor-felt).
    _drawStackBadges(canvas, dim, cellRadius);
  }

  void _drawStackBadges(Canvas canvas, double dim, double cellRadius) {
    final Offset center = Offset(dim / 2, dim / 2);
    final double trackRadius = dim * 0.40;
    final int trackLen = state.geometry.trackLength;
    final Map<int, List<Piece>> byTrack = <int, List<Piece>>{};
    for (final Piece pc in state.allPieces) {
      final p = pc.position;
      if (p is TrackPosition) {
        byTrack.putIfAbsent(p.index, () => <Piece>[]).add(pc);
      }
    }
    byTrack.forEach((int index, List<Piece> pieces) {
      if (pieces.length < 2) return;
      final Offset p = _trackPoint(center, trackRadius, index, trackLen);
      final Offset badge = p + Offset(cellRadius, -cellRadius);
      canvas.drawCircle(badge, cellRadius * 0.7, Paint()..color = Colors.black);
      _drawText(canvas, '${pieces.length}', badge, cellRadius * 0.8,
          Colors.white);
    });
  }

  static void _drawText(
      Canvas canvas, String s, Offset center, double fontSize, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            fontSize: fontSize, color: color, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static List<_PiecePoint> computePiecePoints(GameState state, double dim) {
    final Offset center = Offset(dim / 2, dim / 2);
    final double trackRadius = dim * 0.40;
    final int trackLen = state.geometry.trackLength;
    final double spread = dim * 0.016;

    // Saml base-punkter + grupper efter felt (kun spor-felter stakker).
    final List<_PiecePoint> bases = <_PiecePoint>[];
    final List<String> keys = <String>[];
    for (final Player pl in state.players) {
      for (final Piece piece in pl.pieces) {
        final PiecePosition pos = piece.position;
        final Offset p;
        final String key;
        if (pos is StartPosition) {
          p = _startSlotPoint(
              center, trackRadius, pos.ownerIndex, pos.slot, trackLen);
          key = 'S${pos.ownerIndex}.${pos.slot}';
        } else if (pos is TrackPosition) {
          p = _trackPoint(center, trackRadius, pos.index, trackLen);
          key = 'T${pos.index}';
        } else if (pos is HomeStretchPosition) {
          p = _homeStretchPoint(
              center, trackRadius, pos.ownerIndex, pos.slot, trackLen);
          key = 'H${pos.ownerIndex}.${pos.slot}';
        } else {
          continue;
        }
        bases.add(_PiecePoint(piece.id, p, pl.color));
        keys.add(key);
      }
    }

    // Tæl pr. felt og tildel offset til stakkede brikker.
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
      out.add(_PiecePoint(bases[i].pieceId, bases[i].center + offset,
          bases[i].color));
    }
    return out;
  }

  static Offset _trackPoint(
      Offset center, double radius, int index, int trackLen) {
    final double angle = -pi / 2 + 2 * pi * index / trackLen;
    return Offset(
        center.dx + radius * cos(angle), center.dy + radius * sin(angle));
  }

  static Offset _homeStretchPoint(
    Offset center,
    double radius,
    int playerIndex,
    int slot,
    int trackLen,
  ) {
    final int entry = playerIndex * (trackLen ~/ 4);
    final double angle = -pi / 2 + 2 * pi * entry / trackLen;
    final double r = radius - (slot + 1) * radius * 0.18;
    return Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
  }

  static Offset _startSlotPoint(
    Offset center,
    double radius,
    int playerIndex,
    int slot,
    int trackLen,
  ) {
    final int entry = playerIndex * (trackLen ~/ 4);
    final double angleEntry = -pi / 2 + 2 * pi * entry / trackLen;
    final double rOuter = radius + radius * 0.22;
    final double angle = angleEntry + (slot - 1.5) * 0.10;
    return Offset(
      center.dx + rOuter * cos(angle),
      center.dy + rOuter * sin(angle),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.state != state || old.highlighted != highlighted;
}
