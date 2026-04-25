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
    bool realistic = true,
  }) async {
    final composite = StitchCompositor.computeLayer(pattern);
    final nonBack = [
      ...composite.fullStitches.values.map((cs) => cs.stitch),
      ...composite.otherStitches.map((cs) => cs.stitch),
    ];
    final backstitches = composite.backstitches;
    final threadMap = {for (final t in pattern.threads) t.dmcCode: t};
    final blendedColors = {
      for (final e in composite.fullStitches.entries)
        if (e.value.isBlended) e.key: e.value.blendedColor,
    };

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
    if (realistic) {
      final fillPaint = Paint()..style = PaintingStyle.fill;
      final endW = math.max(0.8, cellSize * 0.14);
      final midW = math.max(1.6, cellSize * 0.32);

      for (final s in nonBack) {
        final cx = _stitchX(s);
        final cy = _stitchY(s);
        final thread = threadMap[s.threadId];
        if (thread == null) continue;
        final effectiveColor = blendedColors['$cx,$cy'] ?? thread.color;
        fillPaint.color = effectiveColor;
        final gx = cx * cellSize;
        final gy = cy * cellSize;
        _drawRealisticStitch(canvas, s, gx, gy, cellSize, fillPaint, endW, midW);
      }
    } else {
      final fillPaint = Paint();
      for (final s in nonBack) {
        final cx = _stitchX(s);
        final cy = _stitchY(s);
        final thread = threadMap[s.threadId];
        if (thread == null) continue;
        final effectiveColor = blendedColors['$cx,$cy'] ?? thread.color;
        fillPaint.color = effectiveColor;
        final gx = cx * cellSize;
        final gy = cy * cellSize;
        _fillBlock(canvas, s, gx, gy, cellSize, fillPaint);
      }
    }

    // ── Backstitches (single thread — thinner than cross-stitches) ────────
    final bsPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.6, cellSize * 0.08);

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

  /// Draws a single thread line as a lens shape — thin at endpoints, thicker
  /// in the middle — mimicking how real thread bulges where it crosses.
  static void _drawThreadLens(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
    double endWidth,
    double midWidth,
  ) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;
    // Perpendicular unit vector.
    final px = -dy / len;
    final py = dx / len;

    final eOff = endWidth / 2;
    final mOff = midWidth / 2;
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);

    final path = Path()
      ..moveTo(from.dx + px * eOff, from.dy + py * eOff)
      ..quadraticBezierTo(
          mid.dx + px * mOff, mid.dy + py * mOff, to.dx + px * eOff, to.dy + py * eOff)
      ..quadraticBezierTo(
          mid.dx - px * mOff, mid.dy - py * mOff, from.dx - px * eOff, from.dy - py * eOff)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Realistic stitch rendering using lens-shaped thread lines.
  static void _drawRealisticStitch(
    Canvas canvas,
    Stitch s,
    double gx,
    double gy,
    double cs,
    Paint paint,
    double endW,
    double midW,
  ) {
    void lens(Offset a, Offset b) => _drawThreadLens(canvas, a, b, paint, endW, midW);

    switch (s) {
      case FullStitch():
        lens(Offset(gx, gy), Offset(gx + cs, gy + cs));
        lens(Offset(gx, gy + cs), Offset(gx + cs, gy));
      case HalfStitch(isForward: true):
        lens(Offset(gx, gy + cs), Offset(gx + cs, gy));
      case HalfStitch(isForward: false):
        lens(Offset(gx, gy), Offset(gx + cs, gy + cs));
      case QuarterStitch(quadrant: QuadrantPosition.topLeft):
        lens(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy));
      case QuarterStitch(quadrant: QuadrantPosition.topRight):
        lens(Offset(gx + cs / 2, gy), Offset(gx + cs, gy + cs / 2));
      case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
        lens(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy + cs));
      case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
        lens(Offset(gx + cs / 2, gy + cs), Offset(gx + cs, gy + cs / 2));
      case HalfCrossStitch(half: HalfOrientation.left):
        lens(Offset(gx, gy), Offset(gx + cs / 2, gy + cs));
        lens(Offset(gx, gy + cs), Offset(gx + cs / 2, gy));
      case HalfCrossStitch(half: HalfOrientation.right):
        lens(Offset(gx + cs / 2, gy), Offset(gx + cs, gy + cs));
        lens(Offset(gx + cs / 2, gy + cs), Offset(gx + cs, gy));
      case HalfCrossStitch(half: HalfOrientation.top):
        lens(Offset(gx, gy + cs / 2), Offset(gx + cs, gy));
        lens(Offset(gx, gy), Offset(gx + cs, gy + cs / 2));
      case HalfCrossStitch(half: HalfOrientation.bottom):
        lens(Offset(gx, gy + cs), Offset(gx + cs, gy + cs / 2));
        lens(Offset(gx, gy + cs / 2), Offset(gx + cs, gy + cs));
      case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
        lens(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy));
      case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
        lens(Offset(gx + cs / 2, gy), Offset(gx + cs, gy + cs / 2));
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
        lens(Offset(gx, gy + cs / 2), Offset(gx + cs / 2, gy + cs));
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
        lens(Offset(gx + cs / 2, gy + cs), Offset(gx + cs, gy + cs / 2));
      case BackStitch():
        break;
    }
  }

  /// Block rendering: fills the stitch's sub-region as a solid rect.
  static void _fillBlock(
    Canvas canvas,
    Stitch s,
    double gx,
    double gy,
    double cs,
    Paint paint,
  ) {
    final half = cs / 2;
    switch (s) {
      case FullStitch():
        canvas.drawRect(Rect.fromLTWH(gx, gy, cs, cs), paint);
      case HalfStitch(isForward: true):
        canvas.drawRect(Rect.fromLTWH(gx, gy, cs, cs), paint);
      case HalfStitch(isForward: false):
        canvas.drawRect(Rect.fromLTWH(gx, gy, cs, cs), paint);
      case QuarterStitch(quadrant: QuadrantPosition.topLeft):
        canvas.drawRect(Rect.fromLTWH(gx, gy, half, half), paint);
      case QuarterStitch(quadrant: QuadrantPosition.topRight):
        canvas.drawRect(Rect.fromLTWH(gx + half, gy, half, half), paint);
      case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.drawRect(Rect.fromLTWH(gx, gy + half, half, half), paint);
      case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.drawRect(Rect.fromLTWH(gx + half, gy + half, half, half), paint);
      case HalfCrossStitch(half: HalfOrientation.left):
        canvas.drawRect(Rect.fromLTWH(gx, gy, half, cs), paint);
      case HalfCrossStitch(half: HalfOrientation.right):
        canvas.drawRect(Rect.fromLTWH(gx + half, gy, half, cs), paint);
      case HalfCrossStitch(half: HalfOrientation.top):
        canvas.drawRect(Rect.fromLTWH(gx, gy, cs, half), paint);
      case HalfCrossStitch(half: HalfOrientation.bottom):
        canvas.drawRect(Rect.fromLTWH(gx, gy + half, cs, half), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
        canvas.drawRect(Rect.fromLTWH(gx, gy, half, half), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
        canvas.drawRect(Rect.fromLTWH(gx + half, gy, half, half), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.drawRect(Rect.fromLTWH(gx, gy + half, half, half), paint);
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.drawRect(Rect.fromLTWH(gx + half, gy + half, half, half), paint);
      case BackStitch():
        break;
    }
  }
}
