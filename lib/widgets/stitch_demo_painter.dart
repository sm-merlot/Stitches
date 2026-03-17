import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/gif_renderer.dart' show kDemoSubFrames;
import '../services/stitch_renderer.dart';

const _needleColor = Color(0xFFE8C020); // golden needle dot

/// Maps [StitchType] to the same Flutter [Color]s used by the CLI GIF renderer.
final _typeColors = stitchTypeArgb.map(
  (type, argb) => MapEntry(type, Color(argb)),
);

/// [CustomPainter] that draws the step-by-step stitching demonstration.
///
/// Colors match the educational palette used by the CLI GIF renderer:
/// purple = front1, green = front2, gold/red/blue = back layers.
///
/// [currentSubStep] runs from 0 (empty canvas) to
/// `segments.length * kDemoSubFrames` (all complete). Within each group of
/// [kDemoSubFrames] steps the active segment is drawn incrementally so the
/// line appears to be pulled across the fabric in real time.
class StitchDemoPainter extends CustomPainter {
  final PlannedAida aida;
  final int currentSubStep;
  final Color aidaColor;

  const StitchDemoPainter({
    required this.aida,
    required this.currentSubStep,
    this.aidaColor = const Color(0xFFFAF6F0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = computeGridBounds(aida, 1.0);
    if (bounds.width == 0 || bounds.height == 0) return;

    const paddingFraction = 0.04;
    final padPx = size.shortestSide * paddingFraction;
    final availW = size.width - padPx * 2;
    final availH = size.height - padPx * 2;
    final cellSize = (availW / bounds.width) < (availH / bounds.height)
        ? availW / bounds.width
        : availH / bounds.height;

    final originX =
        (size.width - bounds.width * cellSize) / 2 - bounds.left * cellSize;
    final originY =
        (size.height - bounds.height * cellSize) / 2 - bounds.top * cellSize;

    final segments = resolveSegments(
      aida,
      cellSize: cellSize,
      originX: originX,
      originY: originY,
    );

    // Derive complete / in-progress state from the sub-step counter.
    final completeCount = currentSubStep ~/ kDemoSubFrames;
    final subProgress =
        (currentSubStep % kDemoSubFrames) / kDemoSubFrames; // 0.0–<1.0

    // ── Background ───────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = aidaColor,
    );

    // ── Grid ─────────────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFFB4B4B4)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (final sqId in aida.activeSquareIds) {
      final sq = aida.squares[sqId];
      final l = originX + (sq.x - 0.5) * cellSize;
      final t = originY + (sq.y - 0.5) * cellSize;
      final r = originX + (sq.x + 0.5) * cellSize;
      final b = originY + (sq.y + 0.5) * cellSize;
      canvas.drawRect(Rect.fromLTRB(l, t, r, b), gridPaint);
    }

    // ── Completed stitches ───────────────────────────────────────────────────
    final strokeW = (cellSize * 0.06).clamp(1.0, 3.0);
    final basePaint = Paint()
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < completeCount && i < segments.length; i++) {
      final seg = segments[i];
      final color = _typeColors[seg.type] ?? const Color(0xFF888888);
      _drawSegment(canvas, seg.x1, seg.y1, seg.x2, seg.y2, seg.type, color,
          basePaint..color = color..strokeWidth = strokeW);
    }

    // ── In-progress stitch ───────────────────────────────────────────────────
    if (subProgress > 0 && completeCount < segments.length) {
      final seg = segments[completeCount];
      final tipX = seg.x1 + (seg.x2 - seg.x1) * subProgress;
      final tipY = seg.y1 + (seg.y2 - seg.y1) * subProgress;

      final activeColor = _typeColors[seg.type] ?? const Color(0xFF888888);
      final activeStrokeW = (strokeW * 1.6).clamp(1.5, 4.0);
      final activePaint = Paint()
        ..color = activeColor
        ..strokeWidth = activeStrokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawSegment(canvas, seg.x1, seg.y1, tipX, tipY, seg.type, activeColor,
          activePaint..strokeWidth = activeStrokeW);

      // Needle dot at the tip.
      final needleRadius = (cellSize * 0.08).clamp(3.0, 7.0);
      canvas.drawCircle(
        Offset(tipX, tipY),
        needleRadius,
        Paint()..color = _needleColor,
      );
      // Small dark outline so the dot is visible on any background.
      canvas.drawCircle(
        Offset(tipX, tipY),
        needleRadius,
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  /// Draws one segment, using dashes for back2/back3 to match the GIF renderer:
  /// back2 = long dashes (8 on / 5 off), back3 = short dashes (3 on / 5 off).
  void _drawSegment(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    StitchType type,
    Color color,
    Paint paint,
  ) {
    if (type == StitchType.backTwo) {
      _drawDashedLine(canvas, x1, y1, x2, y2, paint,
          dashLen: 8.0, gapLen: 5.0);
    } else if (type == StitchType.backThree) {
      _drawDashedLine(canvas, x1, y1, x2, y2, paint,
          dashLen: 3.0, gapLen: 5.0);
    } else {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  /// Draws a dashed line using Flutter [Canvas] path operations.
  void _drawDashedLine(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final dist = Offset(dx, dy).distance;
    if (dist < 1e-9) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var d = 0.0;
    var drawing = true;
    while (d < dist) {
      final segLen =
          drawing ? dashLen.clamp(0.0, dist - d) : gapLen.clamp(0.0, dist - d);
      if (drawing && segLen > 0) {
        canvas.drawLine(
          Offset(x1 + ux * d, y1 + uy * d),
          Offset(x1 + ux * (d + segLen), y1 + uy * (d + segLen)),
          paint,
        );
      }
      d += segLen;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(StitchDemoPainter old) =>
      old.currentSubStep != currentSubStep ||
      old.aida != aida ||
      old.aidaColor != aidaColor;
}
