import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/dashed_line.dart';
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
  final (int, int)? startCell;
  final bool pickingStart;

  const StitchDemoPainter({
    required this.aida,
    required this.currentSubStep,
    this.aidaColor = const Color(0xFFFAF6F0),
    this.startCell,
    this.pickingStart = false,
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

    final rawSegments = resolveSegments(
      aida,
      cellSize: cellSize,
      originX: originX,
      originY: originY,
    );

    // Stroke width is needed for offset scaling — compute before drawing.
    final strokeW = (cellSize * 0.06).clamp(1.0, 3.0);

    // Spread overlapping segments so every stitch on the same line is visible.
    final segments = _applyLineOffsets(rawSegments, strokeW);

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

    // ── Start-cell affordance (picking mode) / marker ────────────────────────
    if (pickingStart) {
      final hoverPaint = Paint()
        ..color = const Color(0x339B30D0)
        ..style = PaintingStyle.fill;
      for (final sqId in aida.activeSquareIds) {
        final sq = aida.squares[sqId];
        final l = originX + (sq.x - 0.5) * cellSize;
        final t = originY + (sq.y - 0.5) * cellSize;
        final r = originX + (sq.x + 0.5) * cellSize;
        final b = originY + (sq.y + 0.5) * cellSize;
        canvas.drawRect(Rect.fromLTRB(l, t, r, b), hoverPaint);
      }
    }

    if (startCell != null) {
      final (scx, scy) = startCell!;
      final cx = originX + scx * cellSize;
      final cy = originY + scy * cellSize;
      final r = (cellSize * 0.22).clamp(4.0, 10.0);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = const Color(0xFF9B30D0),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // ── Completed stitches ───────────────────────────────────────────────────
    // Back stitches are drawn first so front stitches paint on top of them,
    // matching the physical reality where the back thread sits under the fabric.
    final basePaint = Paint()
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Pass 1: back stitches (backOne / backTwo / backThree)
    for (var i = 0; i < completeCount && i < segments.length; i++) {
      final seg = segments[i];
      if (seg.type == StitchType.frontOne || seg.type == StitchType.frontTwo) {
        continue;
      }
      final color = _typeColors[seg.type] ?? const Color(0xFF888888);
      _drawSegment(canvas, seg.x1, seg.y1, seg.x2, seg.y2, seg.type, color,
          basePaint..color = color..strokeWidth = strokeW);
    }

    // Pass 2: front stitches (frontOne / frontTwo) — drawn on top
    for (var i = 0; i < completeCount && i < segments.length; i++) {
      final seg = segments[i];
      if (seg.type != StitchType.frontOne && seg.type != StitchType.frontTwo) {
        continue;
      }
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

  /// Returns a stable key for a segment's geometric line, direction-independent.
  /// Coordinates are multiplied by 2 and rounded to handle half-pixel values.
  static String _segKey(double x1, double y1, double x2, double y2) {
    if (x1 > x2 || (x1 == x2 && y1 > y2)) {
      return '${(x2 * 2).round()},${(y2 * 2).round()},${(x1 * 2).round()},${(y1 * 2).round()}';
    }
    return '${(x1 * 2).round()},${(y1 * 2).round()},${(x2 * 2).round()},${(y2 * 2).round()}';
  }

  /// Shifts co-linear segments by a small perpendicular offset each so that
  /// all threads on the same line remain individually visible.
  ///
  /// The step between adjacent parallel copies is [strokeW] × 1.6, just wide
  /// enough for a visible gap between strokes.
  static List<StitchSegment> _applyLineOffsets(
      List<StitchSegment> segs, double strokeW) {
    // Group segment indices by their geometric line.
    final groups = <String, List<int>>{};
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      groups.putIfAbsent(_segKey(s.x1, s.y1, s.x2, s.y2), () => []).add(i);
    }

    // Fast path: nothing overlaps.
    if (groups.values.every((g) => g.length <= 1)) return segs;

    final result = List<StitchSegment>.from(segs);
    final step = strokeW * 1.6;

    for (final indices in groups.values) {
      if (indices.length <= 1) continue;
      final n = indices.length;

      // Compute a consistent perpendicular unit vector from the first segment.
      final s0 = segs[indices[0]];
      final lineVec = Offset(s0.x2 - s0.x1, s0.y2 - s0.y1);
      if (lineVec.distance < 1e-6) continue;
      final perpUnit = Offset(-lineVec.dy, lineVec.dx) / lineVec.distance;

      for (var i = 0; i < n; i++) {
        // Centre the fan of offsets around 0 so the average stays on the line.
        final offset = (i - (n - 1) / 2.0) * step;
        final dx = perpUnit.dx * offset;
        final dy = perpUnit.dy * offset;
        final orig = segs[indices[i]];
        result[indices[i]] = StitchSegment(
          x1: orig.x1 + dx,
          y1: orig.y1 + dy,
          x2: orig.x2 + dx,
          y2: orig.y2 + dy,
          type: orig.type,
        );
      }
    }

    return result;
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
    if (type == StitchType.backOne ||
        type == StitchType.backTwo ||
        type == StitchType.backThree) {
      _drawDashedLine(canvas, x1, y1, x2, y2, paint,
          dashLen: 5.0, gapLen: 4.0);
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
    forEachDashSegment(
      x1, y1, x2, y2,
      dashLen: dashLen,
      gapLen: gapLen,
      onSegment: (sx, sy, ex, ey) =>
          canvas.drawLine(Offset(sx, sy), Offset(ex, ey), paint),
    );
  }

  @override
  bool shouldRepaint(StitchDemoPainter old) =>
      old.currentSubStep != currentSubStep ||
      old.aida != aida ||
      old.aidaColor != aidaColor ||
      old.startCell != startCell ||
      old.pickingStart != pickingStart;
}
