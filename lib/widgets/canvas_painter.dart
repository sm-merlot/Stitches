import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

class CanvasPainter extends CustomPainter {
  final CrossStitchPattern pattern;
  final double cellSize;
  final Offset panOffset;
  final double scale;
  final Offset? backstitchStartPoint;
  final Offset? backstitchCurrentPoint;
  final bool isErasing;
  final bool isDrawCursor;
  final bool isColorPickerCursor;
  final Offset? cursorScreenPos;
  final Color aidaColor;
  final Rect? selectionRect;
  final List<Stitch>? ghostStitches;
  /// Extra threads used by [ghostStitches] that may not be in [pattern] yet.
  final List<Thread>? ghostThreads;

  const CanvasPainter({
    required this.pattern,
    required this.cellSize,
    required this.panOffset,
    required this.scale,
    this.backstitchStartPoint,
    this.backstitchCurrentPoint,
    this.isErasing = false,
    this.isDrawCursor = false,
    this.isColorPickerCursor = false,
    this.cursorScreenPos,
    this.aidaColor = const Color(0xFFFFFFFF),
    this.selectionRect,
    this.ghostStitches,
    this.ghostThreads,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    final w = pattern.width * cellSize;
    final h = pattern.height * cellSize;

    // Build thread lookup map once
    final threadMap = <String, Thread>{
      for (final t in pattern.threads) t.dmcCode: t,
    };

    // ── Background ───────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = aidaColor,
    );

    // ── Stitches ─────────────────────────────────────────────────────────────
    // Render order: full → half → quarter → halfcross → quartercross → back
    for (final stitch in pattern.stitches) {
      final thread = threadMap[stitch.threadId];
      if (thread == null) continue;

      switch (stitch) {
        case FullStitch(:final x, :final y):
          _drawFullStitch(canvas, x, y, thread.color);
        case HalfStitch(:final x, :final y, :final isForward):
          _drawHalfStitch(canvas, x, y, isForward, thread.color);
        case QuarterStitch(:final x, :final y, :final quadrant):
          _drawQuarterStitch(canvas, x, y, quadrant, thread.color);
        case HalfCrossStitch(:final x, :final y, :final half):
          _drawHalfCrossStitch(canvas, x, y, half, thread.color);
        case QuarterCrossStitch(:final x, :final y, :final quadrant):
          _drawQuarterCrossStitch(canvas, x, y, quadrant, thread.color);
        case BackStitch():
          break; // drawn after grid
      }
    }

    // ── Grid ─────────────────────────────────────────────────────────────────
    _drawGrid(canvas, w, h);

    // ── Backstitches (drawn on top of grid) ──────────────────────────────────
    for (final stitch in pattern.stitches) {
      if (stitch is! BackStitch) continue;
      final thread = threadMap[stitch.threadId];
      if (thread == null) continue;
      _drawBackstitch(
          canvas, stitch.x1, stitch.y1, stitch.x2, stitch.y2, thread.color);
    }

    // ── Stitch symbols (drawn after grid so they sit on top of grid lines) ──
    if (cellSize * scale >= 8) {
      for (final stitch in pattern.stitches) {
        if (stitch is BackStitch) continue;
        final thread = threadMap[stitch.threadId];
        if (thread == null || thread.symbol.isEmpty) continue;
        _drawStitchSymbol(canvas, stitch, thread.symbol, thread.color);
      }
    }

    // ── Backstitch in-progress preview ───────────────────────────────────────
    if (backstitchStartPoint != null) {
      _drawGridPointIndicator(canvas, backstitchStartPoint!);

      if (backstitchCurrentPoint != null &&
          backstitchCurrentPoint != backstitchStartPoint) {
        _drawBackstitchPreview(
            canvas, backstitchStartPoint!, backstitchCurrentPoint!);
      }
    }

    // ── Ghost stitches (paste preview / move preview) ─────────────────────
    if (ghostStitches != null && ghostStitches!.isNotEmpty) {
      _drawGhostStitches(canvas, ghostStitches!, threadMap);
    }

    // ── Selection rect ───────────────────────────────────────────────────────
    if (selectionRect != null) _drawSelectionRect(canvas, selectionRect!);

    // ── Pattern border ───────────────────────────────────────────────────────
    final borderBase = aidaColor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = borderBase.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale,
    );

    canvas.restore();

    // ── Grid labels (screen-space, sticky at viewport edges) ─────────────────
    _drawGridLabels(canvas, size);

    // ── Custom cursors (drawn in screen space, after restore) ────────────────
    if (cursorScreenPos != null) {
      if (isErasing) _drawEraserCursor(canvas, cursorScreenPos!);
      if (isDrawCursor) _drawPencilCursor(canvas, cursorScreenPos!);
      if (isColorPickerCursor) _drawEyedropperCursor(canvas, cursorScreenPos!);
    }
  }

  // ─── Full stitch (X) ──────────────────────────────────────────────────────

  void _drawFullStitch(Canvas canvas, int x, int y, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;

    _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color);
    _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color);
  }

  // ─── Half stitch (diagonal /) ─────────────────────────────────────────────

  void _drawHalfStitch(
      Canvas canvas, int x, int y, bool isForward, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;

    if (isForward) {
      _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color);
    } else {
      _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color);
    }
  }

  // ─── Quarter stitch (diagonal to center) ─────────────────────────────────

  void _drawQuarterStitch(
      Canvas canvas, int x, int y, QuadrantPosition quadrant, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final cx = left + cellSize / 2;
    final cy = top + cellSize / 2;

    final (from, to) = switch (quadrant) {
      QuadrantPosition.topLeft => (Offset(left, top), Offset(cx, cy)),
      QuadrantPosition.topRight => (Offset(right, top), Offset(cx, cy)),
      QuadrantPosition.bottomLeft => (Offset(left, bottom), Offset(cx, cy)),
      QuadrantPosition.bottomRight => (Offset(right, bottom), Offset(cx, cy)),
    };

    _drawThreadLine(canvas, from, to, color);
  }

  // ─── Half-cross stitch (full X in half a cell) ───────────────────────────

  void _drawHalfCrossStitch(
      Canvas canvas, int x, int y, HalfOrientation half, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final midX = left + cellSize / 2;
    final midY = top + cellSize / 2;

    final (tl, tr, bl, br) = switch (half) {
      HalfOrientation.left => (
          Offset(left, top),
          Offset(midX, top),
          Offset(left, bottom),
          Offset(midX, bottom),
        ),
      HalfOrientation.right => (
          Offset(midX, top),
          Offset(right, top),
          Offset(midX, bottom),
          Offset(right, bottom),
        ),
      HalfOrientation.top => (
          Offset(left, top),
          Offset(right, top),
          Offset(left, midY),
          Offset(right, midY),
        ),
      HalfOrientation.bottom => (
          Offset(left, midY),
          Offset(right, midY),
          Offset(left, bottom),
          Offset(right, bottom),
        ),
    };

    _drawThreadLine(canvas, tl, br, color);
    _drawThreadLine(canvas, tr, bl, color);
  }

  // ─── Quarter-cross stitch (full X in quarter of a cell / petit point) ─────

  void _drawQuarterCrossStitch(
      Canvas canvas, int x, int y, QuadrantPosition quadrant, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final midX = left + cellSize / 2;
    final midY = top + cellSize / 2;

    final (tl, tr, bl, br) = switch (quadrant) {
      QuadrantPosition.topLeft => (
          Offset(left, top),
          Offset(midX, top),
          Offset(left, midY),
          Offset(midX, midY),
        ),
      QuadrantPosition.topRight => (
          Offset(midX, top),
          Offset(right, top),
          Offset(midX, midY),
          Offset(right, midY),
        ),
      QuadrantPosition.bottomLeft => (
          Offset(left, midY),
          Offset(midX, midY),
          Offset(left, bottom),
          Offset(midX, bottom),
        ),
      QuadrantPosition.bottomRight => (
          Offset(midX, midY),
          Offset(right, midY),
          Offset(midX, bottom),
          Offset(right, bottom),
        ),
    };

    _drawThreadLine(canvas, tl, br, color);
    _drawThreadLine(canvas, tr, bl, color);
  }

  // ─── Backstitch ───────────────────────────────────────────────────────────

  void _drawBackstitch(
      Canvas canvas, double x1, double y1, double x2, double y2, Color color) {
    final from = Offset(x1 * cellSize, y1 * cellSize);
    final to = Offset(x2 * cellSize, y2 * cellSize);
    _drawThreadLine(canvas, from, to, color,
        widthFactor: 0.15, minWidth: 1.5);
  }

  void _drawBackstitchPreview(Canvas canvas, Offset start, Offset end) {
    final p = Paint()
      ..color = Colors.black54
      ..strokeWidth = math.max(1.0, cellSize * 0.1)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Dashed line via path
    final path = Path();
    final startPx = Offset(start.dx * cellSize, start.dy * cellSize);
    final endPx = Offset(end.dx * cellSize, end.dy * cellSize);
    final dx = endPx.dx - startPx.dx;
    final dy = endPx.dy - startPx.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return;
    const dashLen = 6.0;
    const gapLen = 4.0;
    final ux = dx / dist;
    final uy = dy / dist;
    var d = 0.0;
    var drawing = true;
    while (d < dist) {
      final segLen =
          drawing ? math.min(dashLen, dist - d) : math.min(gapLen, dist - d);
      if (drawing) {
        path.moveTo(startPx.dx + ux * d, startPx.dy + uy * d);
        path.lineTo(
            startPx.dx + ux * (d + segLen), startPx.dy + uy * (d + segLen));
      }
      d += segLen;
      drawing = !drawing;
    }
    canvas.drawPath(path, p);
  }

  // ─── Stitch symbols ───────────────────────────────────────────────────────

  void _drawStitchSymbol(
      Canvas canvas, Stitch stitch, String symbol, Color threadColor) {
    final center = _symbolCenter(stitch);
    final fontSize = math.max(4.0, cellSize * 0.46);

    // Text contrasts with the thread colour badge background
    final textColor = threadColor.computeLuminance() > 0.35
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFFFFFFF);

    final tp = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          fontSize: fontSize,
          color: textColor,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Solid thread-colour badge behind text — covers stitch marks so the
    // symbol is always readable, and keeps the colour identity clear.
    final bgRect = Rect.fromCenter(
      center: center,
      width: tp.width + 4,
      height: tp.height + 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
      Paint()..color = threadColor,
    );
    // Subtle border so the badge has a clean edge against the aida/grid
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
      Paint()
        ..color = textColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 / scale,
    );

    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  Offset _symbolCenter(Stitch stitch) {
    return switch (stitch) {
      FullStitch(:final x, :final y) =>
        Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize),
      HalfStitch(:final x, :final y) =>
        Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize),
      QuarterStitch(:final x, :final y, :final quadrant) =>
        _quadrantCenter(x, y, quadrant),
      HalfCrossStitch(:final x, :final y, :final half) =>
        _halfOrientCenter(x, y, half),
      QuarterCrossStitch(:final x, :final y, :final quadrant) =>
        _quadrantCenter(x, y, quadrant),
      BackStitch() => Offset.zero,
    };
  }

  Offset _quadrantCenter(int x, int y, QuadrantPosition q) {
    final l = x * cellSize;
    final t = y * cellSize;
    final q4 = cellSize / 4;
    return switch (q) {
      QuadrantPosition.topLeft     => Offset(l + q4,         t + q4),
      QuadrantPosition.topRight    => Offset(l + 3 * q4,     t + q4),
      QuadrantPosition.bottomLeft  => Offset(l + q4,         t + 3 * q4),
      QuadrantPosition.bottomRight => Offset(l + 3 * q4,     t + 3 * q4),
    };
  }

  Offset _halfOrientCenter(int x, int y, HalfOrientation h) {
    final l = x * cellSize;
    final t = y * cellSize;
    final q4 = cellSize / 4;
    final half = cellSize / 2;
    return switch (h) {
      HalfOrientation.left   => Offset(l + q4,    t + half),
      HalfOrientation.right  => Offset(l + 3 * q4, t + half),
      HalfOrientation.top    => Offset(l + half,   t + q4),
      HalfOrientation.bottom => Offset(l + half,   t + 3 * q4),
    };
  }

  void _drawGridPointIndicator(Canvas canvas, Offset gridPoint) {
    final px = gridPoint.dx * cellSize;
    final py = gridPoint.dy * cellSize;
    canvas.drawCircle(
      Offset(px, py),
      math.max(3.0, cellSize * 0.15),
      Paint()..color = Colors.blue.shade700,
    );
  }

  // ─── Contrast helper ──────────────────────────────────────────────────────

  /// WCAG contrast ratio between two colours (1–21).
  double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  // ─── Thread line with highlight effect ────────────────────────────────────

  /// Draws a line with a subtle perpendicular highlight to simulate thread roundness.
  void _drawThreadLine(Canvas canvas, Offset from, Offset to, Color color,
      {double widthFactor = 0.12, double minWidth = 1.2}) {
    final width = math.max(minWidth, cellSize * widthFactor);

    // Contrast outline — drawn first (behind thread) so low-contrast stitches
    // stay visible against the aida colour. Fades out as contrast improves.
    final contrast = _contrastRatio(color, aidaColor);
    if (contrast < 3.5) {
      final outlineBase =
          aidaColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      final alpha = ((3.5 - contrast.clamp(1.0, 3.5)) / 2.5) * 0.7;
      canvas.drawLine(
          from,
          to,
          Paint()
            ..color = outlineBase.withValues(alpha: alpha)
            ..strokeWidth = width * 1.8
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke);
    }

    // Base stroke
    canvas.drawLine(
        from,
        to,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);

    // Perpendicular highlight — simulates rounded thread catching light
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return;

    // Perpendicular unit vector (rotate 90°)
    final px = -dy / dist;
    final py = dx / dist;
    final offset = Offset(px, py) * (width * 0.22);

    canvas.drawLine(
        from + offset,
        to + offset,
        Paint()
          ..color = Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: 0.65)
          ..strokeWidth = width * 0.38
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
  }

  // ─── Single stitch dispatcher ─────────────────────────────────────────────

  void _drawSingleStitch(Canvas canvas, Stitch stitch, Color color) {
    switch (stitch) {
      case FullStitch(:final x, :final y):
        _drawFullStitch(canvas, x, y, color);
      case HalfStitch(:final x, :final y, :final isForward):
        _drawHalfStitch(canvas, x, y, isForward, color);
      case QuarterStitch(:final x, :final y, :final quadrant):
        _drawQuarterStitch(canvas, x, y, quadrant, color);
      case HalfCrossStitch(:final x, :final y, :final half):
        _drawHalfCrossStitch(canvas, x, y, half, color);
      case QuarterCrossStitch(:final x, :final y, :final quadrant):
        _drawQuarterCrossStitch(canvas, x, y, quadrant, color);
      case BackStitch(:final x1, :final y1, :final x2, :final y2):
        _drawBackstitch(canvas, x1, y1, x2, y2, color);
    }
  }

  // ─── Selection rect ───────────────────────────────────────────────────────

  void _drawSelectionRect(Canvas canvas, Rect rect) {
    final px = Rect.fromLTRB(
      rect.left * cellSize,
      rect.top * cellSize,
      rect.right * cellSize,
      rect.bottom * cellSize,
    );

    // Semi-transparent fill
    canvas.drawRect(px, Paint()..color = const Color(0x264D90FE));

    // Solid border
    canvas.drawRect(
      px,
      Paint()
        ..color = const Color(0xFF4D90FE)
        ..strokeWidth = 1.5 / scale
        ..style = PaintingStyle.stroke,
    );

    // Corner handles
    final h = math.max(4.0, 8.0 / scale);
    final hp = Paint()
      ..color = const Color(0xFF4D90FE)
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    for (final corner in [px.topLeft, px.topRight, px.bottomLeft, px.bottomRight]) {
      final dx = corner.dx == px.left ? h : -h;
      final dy = corner.dy == px.top ? h : -h;
      canvas.drawLine(corner, Offset(corner.dx + dx, corner.dy), hp);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy), hp);
    }
  }

  // ─── Ghost stitches (paste/move preview) ─────────────────────────────────

  void _drawGhostStitches(
      Canvas canvas, List<Stitch> stitches, Map<String, Thread> threadMap) {
    // Merge in any extra threads from the clipboard (cross-pattern paste)
    final Map<String, Thread> map = (ghostThreads != null && ghostThreads!.isNotEmpty)
        ? {...threadMap, for (final t in ghostThreads!) t.dmcCode: t}
        : threadMap;
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, pattern.width * cellSize, pattern.height * cellSize),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    for (final stitch in stitches) {
      final thread = map[stitch.threadId];
      if (thread == null) continue;
      _drawSingleStitch(canvas, stitch, thread.color);
    }
    canvas.restore();
  }

  // ─── Grid ─────────────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, double w, double h) {
    // Choose black or white grid lines depending on aida luminance.
    final base = aidaColor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    final minorPaint = Paint()
      ..color = base.withValues(alpha: 0.18)
      ..strokeWidth = 0.5;

    final majorPaint = Paint()
      ..color = base.withValues(alpha: 0.38)
      ..strokeWidth = 1.0;

    for (int x = 0; x <= pattern.width; x++) {
      final px = x * cellSize;
      final paint = (x % 10 == 0) ? majorPaint : minorPaint;
      canvas.drawLine(Offset(px, 0), Offset(px, h), paint);
    }

    for (int y = 0; y <= pattern.height; y++) {
      final py = y * cellSize;
      final paint = (y % 10 == 0) ? majorPaint : minorPaint;
      canvas.drawLine(Offset(0, py), Offset(w, py), paint);
    }
  }

  // ─── Eraser cursor (screen-space) ─────────────────────────────────────────

  void _drawEraserCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    // Same 45° angle as pencil/eyedropper: active face at origin (upper-left),
    // body extends toward lower-right.
    canvas.rotate(-math.pi / 4);

    const w = 11.0;
    const h = 18.0;

    // Eraser body — active face (erasing edge) at origin, body goes down (+y)
    final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-w / 2, 0, w, h), const Radius.circular(2));
    canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFFF4A0B0));

    // White stripe at active face
    canvas.save();
    canvas.clipRRect(bodyRect);
    canvas.drawRect(Rect.fromLTWH(-w / 2, 0, w, h * 0.25),
        Paint()..color = Colors.white.withValues(alpha: 0.55));
    canvas.restore();

    // Border
    canvas.drawRRect(
        bodyRect,
        Paint()
          ..color = const Color(0xFF444444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    canvas.restore();
  }

  // ─── Pencil cursor (screen-space) ─────────────────────────────────────────

  void _drawPencilCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    // Tip at origin (upper-left hotspot); body extends toward lower-right.
    canvas.rotate(-math.pi / 4);

    const halfW = 2.5;

    final outlinePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Graphite tip — at origin, body goes down (+y → lower-right on screen)
    final graphitePath = Path()
      ..moveTo(0, 0)
      ..lineTo(-1.0, 2.5)
      ..lineTo(1.0, 2.5)
      ..close();
    canvas.drawPath(graphitePath, Paint()..color = const Color(0xFF555555));
    canvas.drawPath(graphitePath, outlinePaint);

    // Wood (sharpening cone)
    final woodPath = Path()
      ..moveTo(-1.0, 2.5)
      ..lineTo(1.0, 2.5)
      ..lineTo(halfW, 7.0)
      ..lineTo(-halfW, 7.0)
      ..close();
    canvas.drawPath(woodPath, Paint()..color = const Color(0xFFD4A04A));
    canvas.drawPath(woodPath, outlinePaint);

    // Body
    canvas.drawRect(Rect.fromLTWH(-halfW, 7.0, halfW * 2, 12.0),
        Paint()..color = const Color(0xFFFFD700));
    canvas.drawRect(Rect.fromLTWH(-halfW, 7.0, halfW * 2, 12.0), outlinePaint);

    // Metal ferrule
    canvas.drawRect(Rect.fromLTWH(-halfW, 19.0, halfW * 2, 2.0),
        Paint()..color = const Color(0xFFAAAAAA));
    canvas.drawRect(
        Rect.fromLTWH(-halfW, 19.0, halfW * 2, 2.0), outlinePaint);

    // Eraser
    canvas.drawRect(Rect.fromLTWH(-halfW, 21.0, halfW * 2, 3.5),
        Paint()..color = const Color(0xFFF4A0B0));
    canvas.drawRect(
        Rect.fromLTWH(-halfW, 21.0, halfW * 2, 3.5), outlinePaint);

    // Divider line between wood and body
    canvas.drawLine(Offset(-halfW, 7.0), Offset(halfW, 7.0), outlinePaint);

    canvas.restore();
  }

  // ─── Eyedropper cursor (screen-space) ─────────────────────────────────────

  void _drawEyedropperCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    // Tip at origin (upper-left hotspot); body extends toward lower-right.
    canvas.rotate(-math.pi / 4);

    final outlinePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Tip dot
    canvas.drawCircle(Offset.zero, 1.5, Paint()..color = const Color(0xFF333333));

    // Narrow metal rod — goes down (+y → lower-right on screen)
    final rodPath = Path()
      ..moveTo(-1.0, 1.5)
      ..lineTo(1.0, 1.5)
      ..lineTo(1.5, 6.0)
      ..lineTo(-1.5, 6.0)
      ..close();
    canvas.drawPath(rodPath, Paint()..color = const Color(0xFF888888));
    canvas.drawPath(rodPath, outlinePaint);

    // Collar
    canvas.drawRect(Rect.fromLTWH(-2.0, 6.0, 4.0, 1.5),
        Paint()..color = const Color(0xFF666666));
    canvas.drawRect(Rect.fromLTWH(-2.0, 6.0, 4.0, 1.5), outlinePaint);

    // Barrel/body
    canvas.drawRect(Rect.fromLTWH(-2.5, 7.5, 5.0, 9.5),
        Paint()..color = const Color(0xFFDDDDDD));
    canvas.drawRect(Rect.fromLTWH(-2.5, 7.5, 5.0, 9.5), outlinePaint);

    // Rubber bulb
    canvas.drawCircle(const Offset(0, 22.0), 5.0,
        Paint()..color = const Color(0xFF888888));
    canvas.drawCircle(const Offset(0, 22.0), 5.0, outlinePaint);

    // Highlight on bulb
    canvas.drawCircle(const Offset(-1.5, 20.5), 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.45));

    canvas.restore();
  }

  // ─── Grid labels (screen-space, sticky) ───────────────────────────────────

  /// Minimum step size so labels are at least ~35 px apart.
  int _labelStep(double effectiveCellPx) {
    const minSpacing = 35.0;
    for (final s in [5, 10, 20, 50, 100]) {
      if (s * effectiveCellPx >= minSpacing) return s;
    }
    return 100;
  }

  void _drawGridLabels(Canvas canvas, Size size) {
    final effectiveCellPx = cellSize * scale;
    final step = _labelStep(effectiveCellPx);

    const fontSize = 10.0;
    const textColor = Color(0xFF666666);
    final bgColor = Colors.white.withValues(alpha: 0.82);

    // Label pill is ~(fontSize + 4) px tall and ~24 px wide at most.
    const halfH = (fontSize + 4) / 2; // ≈ 7
    const halfW = 14.0; // conservative half-width for 2–3 digit numbers

    // Column label Y: sit just ABOVE the grid top edge when it's on screen.
    // When the grid top scrolls off the top, clamp to stay visible.
    final colLabelY =
        (panOffset.dy - halfH - 3).clamp(halfH + 2, size.height - halfH - 2);

    // Row label X: sit just LEFT of the grid left edge when it's on screen.
    // When the grid left scrolls off the left, clamp to stay visible.
    final rowLabelX =
        (panOffset.dx - halfW - 4).clamp(halfW + 2, size.width - halfW - 2);

    // Column numbers (top of grid, sticky at top of viewport)
    for (int x = step; x <= pattern.width; x += step) {
      final screenX = x * effectiveCellPx + panOffset.dx;
      if (screenX < 0 || screenX > size.width) continue;
      _drawNumberLabel(
          canvas, '$x', Offset(screenX, colLabelY), fontSize, textColor, bgColor);
    }

    // Row numbers (left of grid, sticky at left of viewport)
    for (int y = step; y <= pattern.height; y += step) {
      final screenY = y * effectiveCellPx + panOffset.dy;
      if (screenY < 0 || screenY > size.height) continue;
      _drawNumberLabel(
          canvas, '$y', Offset(rowLabelX, screenY), fontSize, textColor, bgColor);
    }
  }

  void _drawNumberLabel(Canvas canvas, String text, Offset center,
      double fontSize, Color textColor, Color bgColor) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: textColor,
          fontWeight: FontWeight.w500,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: center,
      width: tp.width + 6,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = bgColor,
    );
    tp.paint(canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    return oldDelegate.pattern != pattern ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.scale != scale ||
        oldDelegate.backstitchStartPoint != backstitchStartPoint ||
        oldDelegate.backstitchCurrentPoint != backstitchCurrentPoint ||
        oldDelegate.isErasing != isErasing ||
        oldDelegate.isDrawCursor != isDrawCursor ||
        oldDelegate.isColorPickerCursor != isColorPickerCursor ||
        oldDelegate.cursorScreenPos != cursorScreenPos ||
        oldDelegate.aidaColor != aidaColor ||
        oldDelegate.selectionRect != selectionRect ||
        oldDelegate.ghostStitches != ghostStitches ||
        oldDelegate.ghostThreads != ghostThreads;
  }
}
