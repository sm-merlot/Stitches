import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/stitch_renderer.dart';

/// [CustomPainter] that draws the step-by-step stitching demonstration.
///
/// The painter computes layout (cellSize, origin) from the available [Size] so
/// the pattern fills the canvas while maintaining aspect ratio.
class StitchDemoPainter extends CustomPainter {
  final PlannedAida aida;
  final int currentStep;
  final Color threadColor;
  final Color aidaColor;

  const StitchDemoPainter({
    required this.aida,
    required this.currentStep,
    required this.threadColor,
    this.aidaColor = const Color(0xFFFAF6F0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Compute layout in grid-unit space (cellSize=1) then scale to fit.
    final bounds = computeGridBounds(aida, 1.0);
    if (bounds.width == 0 || bounds.height == 0) return;

    const paddingFraction = 0.04;
    final padPx = size.shortestSide * paddingFraction;
    final availW = size.width - padPx * 2;
    final availH = size.height - padPx * 2;
    final cellSize = (availW / bounds.width) < (availH / bounds.height)
        ? availW / bounds.width
        : availH / bounds.height;

    // Origin: position the pattern centred in the canvas.
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

    for (var i = 0; i < currentStep && i < segments.length; i++) {
      final seg = segments[i];
      canvas.drawLine(
        Offset(seg.x1, seg.y1),
        Offset(seg.x2, seg.y2),
        _isFront(seg.type) ? frontPaint : backPaint,
      );
    }

    // ── Current stitch (highlighted) ─────────────────────────────────────────
    if (currentStep > 0 && currentStep <= segments.length) {
      final seg = segments[currentStep - 1];
      final highlightPaint = Paint()
        ..color = _isFront(seg.type) ? threadColor : const Color(0xFF555555)
        ..strokeWidth = (strokeW * 1.8).clamp(2.0, 5.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(seg.x1, seg.y1),
        Offset(seg.x2, seg.y2),
        highlightPaint,
      );
    }
  }

  bool _isFront(StitchType type) =>
      type == StitchType.frontOne ||
      type == StitchType.frontTwo ||
      type == StitchType.automatic;

  @override
  bool shouldRepaint(StitchDemoPainter old) =>
      old.currentStep != currentStep ||
      old.aida != aida ||
      old.threadColor != threadColor ||
      old.aidaColor != aidaColor;
}
