import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/gif_renderer.dart' show kDemoSubFrames;
import '../services/stitch_renderer.dart';

const _needleColor = Color(0xFFE8C020); // golden needle dot

/// [CustomPainter] that draws the step-by-step stitching demonstration.
///
/// [currentSubStep] runs from 0 (empty canvas) to
/// `segments.length * kDemoSubFrames` (all complete). Within each group of
/// [kDemoSubFrames] steps the active segment is drawn incrementally so the
/// line appears to be pulled across the fabric in real time.
class StitchDemoPainter extends CustomPainter {
  final PlannedAida aida;
  final int currentSubStep;
  final Color threadColor;
  final Color aidaColor;

  const StitchDemoPainter({
    required this.aida,
    required this.currentSubStep,
    required this.threadColor,
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
    final frontPaint = Paint()
      ..color = threadColor
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final backPaint = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < completeCount && i < segments.length; i++) {
      final seg = segments[i];
      canvas.drawLine(
        Offset(seg.x1, seg.y1),
        Offset(seg.x2, seg.y2),
        _isFront(seg.type) ? frontPaint : backPaint,
      );
    }

    // ── In-progress stitch ───────────────────────────────────────────────────
    if (subProgress > 0 && completeCount < segments.length) {
      final seg = segments[completeCount];
      final tipX = seg.x1 + (seg.x2 - seg.x1) * subProgress;
      final tipY = seg.y1 + (seg.y2 - seg.y1) * subProgress;

      final activeColor =
          _isFront(seg.type) ? threadColor : const Color(0xFF555555);
      final activePaint = Paint()
        ..color = activeColor
        ..strokeWidth = (strokeW * 1.6).clamp(1.5, 4.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(seg.x1, seg.y1), Offset(tipX, tipY), activePaint);

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

  bool _isFront(StitchType type) =>
      type == StitchType.frontOne ||
      type == StitchType.frontTwo ||
      type == StitchType.automatic;

  @override
  bool shouldRepaint(StitchDemoPainter old) =>
      old.currentSubStep != currentSubStep ||
      old.aida != aida ||
      old.threadColor != threadColor ||
      old.aidaColor != aidaColor;
}
