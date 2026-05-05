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
          onTapDown: (TapDownDetails d) =>
              _handleTap(d.localPosition, size),
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

    // Baggrund
    final Paint bg = Paint()..color = const Color(0xFFF5EAD2);
    canvas.drawRect(Offset.zero & size, bg);

    // Tegn ydre spor (track)
    final int trackLen = state.geometry.trackLength;
    for (int i = 0; i < trackLen; i++) {
      final Offset p =
          _trackPoint(center, trackRadius, i, trackLen);
      final Paint paint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, cellRadius, paint);
      canvas.drawCircle(
        p,
        cellRadius,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Marker udgangsfelt for hver spiller med farvet ring
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
    }

    // Hjemstrækket (4 felter pr. spiller, ind mod centrum)
    for (final Player pl in state.players) {
      for (int slot = 0; slot < state.geometry.homeStretchLength; slot++) {
        final Offset p = _homeStretchPoint(
            center, trackRadius, pl.index, slot, trackLen);
        canvas.drawCircle(
          p,
          cellRadius,
          Paint()..color = pl.color.withOpacity(0.18),
        );
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

    // Start-bås (4 brikker pr. spiller, udenfor banen)
    for (final Player pl in state.players) {
      for (int slot = 0; slot < 4; slot++) {
        final Offset p =
            _startSlotPoint(center, trackRadius, pl.index, slot, trackLen);
        canvas.drawCircle(
          p,
          cellRadius,
          Paint()..color = pl.color.withOpacity(0.10),
        );
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

    // Brikker
    for (final _PiecePoint pp in computePiecePoints(state, dim)) {
      final bool hl = highlighted.contains(pp.pieceId);
      canvas.drawCircle(
        pp.center,
        cellRadius * 1.1,
        Paint()..color = pp.color,
      );
      canvas.drawCircle(
        pp.center,
        cellRadius * 1.1,
        Paint()
          ..color = hl ? Colors.amber : Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = hl ? 3.5 : 1.5,
      );
    }
  }

  static List<_PiecePoint> computePiecePoints(GameState state, double dim) {
    final Offset center = Offset(dim / 2, dim / 2);
    final double trackRadius = dim * 0.40;
    final int trackLen = state.geometry.trackLength;
    final List<_PiecePoint> out = <_PiecePoint>[];
    for (final Player pl in state.players) {
      for (final Piece piece in pl.pieces) {
        final PiecePosition pos = piece.position;
        final Offset p;
        if (pos is StartPosition) {
          p = _startSlotPoint(
              center, trackRadius, pos.ownerIndex, pos.slot, trackLen);
        } else if (pos is TrackPosition) {
          p = _trackPoint(center, trackRadius, pos.index, trackLen);
        } else if (pos is HomeStretchPosition) {
          p = _homeStretchPoint(
              center, trackRadius, pos.ownerIndex, pos.slot, trackLen);
        } else {
          continue;
        }
        out.add(_PiecePoint(piece.id, p, pl.color));
      }
    }
    return out;
  }

  static Offset _trackPoint(
      Offset center, double radius, int index, int trackLen) {
    final double angle =
        -pi / 2 + 2 * pi * index / trackLen;
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
    return Offset(
        center.dx + r * cos(angle), center.dy + r * sin(angle));
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
    // Placér start-bås i en bue udenfor banen, omkring spillerens udgangsfelt.
    final double rOuter = radius + radius * 0.22;
    final double angleOffset = (slot - 1.5) * 0.10;
    final double angle = angleEntry + angleOffset;
    return Offset(
      center.dx + rOuter * cos(angle),
      center.dy + rOuter * sin(angle),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.state != state || old.highlighted != highlighted;
}
