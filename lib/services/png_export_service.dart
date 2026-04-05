import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import 'stitch_compositor.dart';

/// Renders a pattern as a PNG image and returns the raw bytes.
///
/// The output mirrors the PDF "realistic" title-page render: Aida background,
/// diagonal line-art stitches, backstitch segments, and a black border.
/// No grid, no symbols.
class PngExportService {
  /// Export [pattern] as PNG bytes.
  ///
  /// [cellSize] controls px-per-stitch (default 20 px → a 100×80 pattern
  /// produces a 2000×1600 px image).
  static Future<Uint8List> export(
    CrossStitchPattern pattern, {
    double cellSize = 20.0,
  }) async {
    final composite = StitchCompositor.compute(pattern);
    final nonBack = composite.dedupedNonBack;
    final backstitches = composite.backstitches;
    final threadMap = {for (final t in pattern.threads) t.dmcCode: t};
    final blendedColors = composite.blendedColors;

    final pw = pattern.width * cellSize;
    final ph = pattern.height * cellSize;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, pw, ph));

    // ── Aida background ───────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pw, ph),
      Paint()..color = pattern.aidaColor,
    );

    // ── Cross-type stitches ───────────────────────────────────────────────
    final strokeWidth = math.max(0.5, cellSize * 0.12);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    for (final s in nonBack) {
      final cx = _stitchX(s);
      final cy = _stitchY(s);
      final thread = threadMap[s.threadId];
      if (thread == null) continue;
      final effectiveColor = blendedColors['$cx,$cy'] ?? thread.color;
      strokePaint.color = effectiveColor;
      final gx = cx * cellSize;
      final gy = cy * cellSize;
      _drawStitch(canvas, s, gx, gy, cellSize, strokePaint);
    }

    // ── Backstitches ──────────────────────────────────────────────────────
    final bsPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.75, cellSize * 0.18);

    for (final bs in backstitches) {
      final thread = threadMap[bs.threadId];
      if (thread == null) continue;
      bsPaint.color = thread.color;
      canvas.drawLine(
        Offset(bs.x1 * cellSize, bs.y1 * cellSize),
        Offset(bs.x2 * cellSize, bs.y2 * cellSize),
        bsPaint,
      );
    }

    // ── Border ────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pw, ph),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black
        ..strokeWidth = math.max(1.0, cellSize * 0.05),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(pw.round(), ph.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ── Coordinate helpers ────────────────────────────────────────────────────

  static int _stitchX(Stitch s) => switch (s) {
        FullStitch(x: final x) => x,
        HalfStitch(x: final x) => x,
        QuarterStitch(x: final x) => x,
        HalfCrossStitch(x: final x) => x,
        QuarterCrossStitch(x: final x) => x,
        BackStitch() => 0,
      };

  static int _stitchY(Stitch s) => switch (s) {
        FullStitch(y: final y) => y,
        HalfStitch(y: final y) => y,
        QuarterStitch(y: final y) => y,
        HalfCrossStitch(y: final y) => y,
        QuarterCrossStitch(y: final y) => y,
        BackStitch() => 0,
      };

  // ── Stitch rendering ──────────────────────────────────────────────────────

  static void _drawStitch(
    Canvas canvas,
    Stitch s,
    double gx,
    double gy,
    double cs,
    Paint paint,
  ) {
    switch (s) {
      case FullStitch():
        canvas.drawLine(Offset(gx, gy), Offset(gx + cs, gy + cs), paint);
        canvas.drawLine(Offset(gx, gy + cs), Offset(gx + cs, gy), paint);

      case HalfStitch(isForward: true): // "/"
        canvas.drawLine(Offset(gx, gy + cs), Offset(gx + cs, gy), paint);

      case HalfStitch(isForward: false): // "\"
        canvas.drawLine(Offset(gx, gy), Offset(gx + cs, gy + cs), paint);

      case QuarterStitch(quadrant: QuadrantPosition.topLeft):
        canvas.drawLine(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy), paint);
      case QuarterStitch(quadrant: QuadrantPosition.topRight):
        canvas.drawLine(Offset(gx + cs / 2, gy), Offset(gx + cs, gy + cs / 2), paint);
      case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.drawLine(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy + cs), paint);
      case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.drawLine(Offset(gx + cs / 2, gy + cs), Offset(gx + cs, gy + cs / 2), paint);

      case HalfCrossStitch(half: HalfOrientation.left):
        canvas.drawLine(Offset(gx, gy), Offset(gx + cs / 2, gy + cs), paint);
        canvas.drawLine(Offset(gx, gy + cs), Offset(gx + cs / 2, gy), paint);
      case HalfCrossStitch(half: HalfOrientation.right):
        canvas.drawLine(Offset(gx + cs / 2, gy), Offset(gx + cs, gy + cs), paint);
        canvas.drawLine(Offset(gx + cs / 2, gy + cs), Offset(gx + cs, gy), paint);
      case HalfCrossStitch(half: HalfOrientation.top):
        canvas.drawLine(Offset(gx, gy + cs / 2), Offset(gx + cs, gy), paint);
        canvas.drawLine(Offset(gx, gy), Offset(gx + cs, gy + cs / 2), paint);
      case HalfCrossStitch(half: HalfOrientation.bottom):
        canvas.drawLine(Offset(gx, gy + cs), Offset(gx + cs, gy + cs / 2), paint);
        canvas.drawLine(Offset(gx, gy + cs / 2), Offset(gx + cs, gy + cs), paint);

      case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
        canvas.drawLine(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
        canvas.drawLine(Offset(gx + cs / 2, gy), Offset(gx + cs, gy + cs / 2), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.drawLine(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy + cs), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.drawLine(Offset(gx + cs / 2, gy + cs), Offset(gx + cs, gy + cs / 2), paint);

      case BackStitch():
        break;
    }
  }
}
