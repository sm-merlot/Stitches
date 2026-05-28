part of 'canvas_painter.dart';

// ─── Shared drawing primitives ────────────────────────────────────────────────
// Both CanvasStaticPainter and CanvasOverlayPainter mix this in.

mixin _DrawingMethods {
  double get cellSize;
  Color get aidaColor;
  double get scale;

  // ─── Contrast helpers ───────────────────────────────────────────────────────

  double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// CIE Lab ΔE between two colours.  More perceptually accurate than
  /// luminance contrast ratio — correctly separates achromatic greys from
  /// chromatic colours (red, blue, etc.) at the same luminance.
  double _labDeltaE(Color a, Color b) {
    LabColor toLab(Color c) =>
        rgbToLab((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());
    return labDistance(toLab(a), toLab(b));
  }

  // ─── Thread line with highlight ─────────────────────────────────────────────

  // Reusable Paint instances for _drawThreadLine — mutated in place per call.
  // Safe because canvas.drawLine() records the paint state immediately and does
  // not retain a reference to the Paint object after the call returns.
  // All three share the same immutable base properties (stroke, round cap).
  static final _tlOutlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final _tlMainPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final _tlHighlightPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _drawThreadLine(Canvas canvas, Offset from, Offset to, Color color,
      {double widthFactor = 0.12, double minWidth = 1.2}) {
    final width = math.max(minWidth, cellSize * widthFactor);

    final contrast = _contrastRatio(color, aidaColor);
    if (contrast < 3.5) {
      final outlineBase =
          aidaColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      final alpha = ((3.5 - contrast.clamp(1.0, 3.5)) / 2.5) * 0.7;
      _tlOutlinePaint
        ..color = outlineBase.withValues(alpha: alpha)
        ..strokeWidth = width * 1.8;
      canvas.drawLine(from, to, _tlOutlinePaint);
    }

    _tlMainPaint
      ..color = color
      ..strokeWidth = width;
    canvas.drawLine(from, to, _tlMainPaint);

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return;

    final px = -dy / dist;
    final py = dx / dist;
    final offset = Offset(px, py) * (width * 0.22);

    _tlHighlightPaint
      ..color = Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: 0.65)
      ..strokeWidth = width * 0.38;
    canvas.drawLine(from + offset, to + offset, _tlHighlightPaint);
  }

  // ─── Stitch draw methods ────────────────────────────────────────────────────

  void _drawFullStitch(Canvas canvas, int x, int y, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color);
    _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color);
  }

  void _drawHalfStitch(Canvas canvas, int x, int y, bool isForward, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    if (isForward) {
      _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color,
          widthFactor: 0.18);
    } else {
      _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color,
          widthFactor: 0.18);
    }
  }

  /// Petit point — full X in a quarter of the cell.
  void _drawQuarterStitch(
      Canvas canvas, int x, int y, QuadrantPosition quadrant, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final midX = left + cellSize / 2;
    final midY = top + cellSize / 2;
    final (tl, tr, bl, br) = switch (quadrant) {
      QuadrantPosition.topLeft => (
          Offset(left, top), Offset(midX, top), Offset(left, midY), Offset(midX, midY)),
      QuadrantPosition.topRight => (
          Offset(midX, top), Offset(right, top), Offset(midX, midY), Offset(right, midY)),
      QuadrantPosition.bottomLeft => (
          Offset(left, midY), Offset(midX, midY), Offset(left, bottom), Offset(midX, bottom)),
      QuadrantPosition.bottomRight => (
          Offset(midX, midY), Offset(right, midY), Offset(midX, bottom), Offset(right, bottom)),
    };
    _drawThreadLine(canvas, tl, br, color);
    _drawThreadLine(canvas, tr, bl, color);
  }

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
          Offset(left, top), Offset(midX, top), Offset(left, bottom), Offset(midX, bottom)),
      HalfOrientation.right => (
          Offset(midX, top), Offset(right, top), Offset(midX, bottom), Offset(right, bottom)),
      HalfOrientation.top => (
          Offset(left, top), Offset(right, top), Offset(left, midY), Offset(right, midY)),
      HalfOrientation.bottom => (
          Offset(left, midY), Offset(right, midY), Offset(left, bottom), Offset(right, bottom)),
    };
    _drawThreadLine(canvas, tl, br, color);
    _drawThreadLine(canvas, tr, bl, color);
  }

  void _drawThreeQuarterStitch(
      Canvas canvas, int x, int y, QuadrantPosition quadrant, bool isForward, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final cx = left + cellSize / 2;
    final cy = top + cellSize / 2;
    // Full diagonal
    if (isForward) {
      _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color);
    } else {
      _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color);
    }
    // Quarter diagonal from quadrant corner to centre
    final corner = switch (quadrant) {
      QuadrantPosition.topLeft     => Offset(left, top),
      QuadrantPosition.topRight    => Offset(right, top),
      QuadrantPosition.bottomLeft  => Offset(left, bottom),
      QuadrantPosition.bottomRight => Offset(right, bottom),
    };
    _drawThreadLine(canvas, corner, Offset(cx, cy), color);
  }

  void _drawBackstitch(
      Canvas canvas, double x1, double y1, double x2, double y2, Color color) {
    _drawThreadLine(
        canvas,
        Offset(x1 * cellSize, y1 * cellSize),
        Offset(x2 * cellSize, y2 * cellSize),
        color,
        widthFactor: 0.15,
        minWidth: 1.5);
  }

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
      case ThreeQuarterStitch(:final x, :final y, :final quadrant, :final isForward):
        _drawThreeQuarterStitch(canvas, x, y, quadrant, isForward, color);
      case BackStitch(:final x1, :final y1, :final x2, :final y2):
        _drawBackstitch(canvas, x1, y1, x2, y2, color);
    }
  }

  // ─── Backstitch preview & start indicator ───────────────────────────────────

  void _drawGridPointIndicator(Canvas canvas, Offset gridPoint) {
    canvas.drawCircle(
      Offset(gridPoint.dx * cellSize, gridPoint.dy * cellSize),
      math.max(3.0, cellSize * 0.15),
      Paint()..color = Colors.blue.shade700,
    );
  }

  void _drawBackstitchPreview(Canvas canvas, Offset start, Offset end) {
    final p = Paint()
      ..color = Colors.black54
      ..strokeWidth = math.max(1.0, cellSize * 0.1)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

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
    final path = Path();
    while (d < dist) {
      final segLen =
          drawing ? math.min(dashLen, dist - d) : math.min(gapLen, dist - d);
      if (drawing) {
        path.moveTo(startPx.dx + ux * d, startPx.dy + uy * d);
        path.lineTo(startPx.dx + ux * (d + segLen), startPx.dy + uy * (d + segLen));
      }
      d += segLen;
      drawing = !drawing;
    }
    canvas.drawPath(path, p);
  }

  // ─── Ghost stitches (paste / move preview) ──────────────────────────────────

  void _drawGhostStitches(
      Canvas canvas, List<Stitch> stitches, Map<String, Thread> threadMap,
      {double opacity = 1.0}) {
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: opacity));
    for (final stitch in stitches) {
      final thread = threadMap[stitch.threadId];
      if (thread == null) continue;
      final shape = RenderCache.buildBlockShape(stitch, cellSize);
      if (shape != null) {
        shape.draw(canvas, Paint()..color = thread.color);
      } else {
        // BackStitch — no block shape, fall back to line rendering.
        _drawSingleStitch(canvas, stitch, thread.color);
      }
    }
    canvas.restore();
  }

  // ─── Selection rect ─────────────────────────────────────────────────────────

  void _drawSelectionRect(Canvas canvas, Rect rect) {
    final px = Rect.fromLTRB(
      rect.left * cellSize,
      rect.top * cellSize,
      rect.right * cellSize,
      rect.bottom * cellSize,
    );
    canvas.drawRect(px, Paint()..color = const Color(0x264D90FE));
    canvas.drawRect(
      px,
      Paint()
        ..color = const Color(0xFF4D90FE)
        ..strokeWidth = 1.5 / scale
        ..style = PaintingStyle.stroke,
    );
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

  // ─── Custom cursors (screen-space) ──────────────────────────────────────────

  void _drawEraserCursor(Canvas canvas, Offset pos, {bool fillErase = false}) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-math.pi / 4);
    const w = 11.0;
    const h = 18.0;
    final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-w / 2, 0, w, h), const Radius.circular(2));
    // Fill erase: orange body; regular erase: pink body
    final bodyColor = fillErase ? const Color(0xFFFFB74D) : const Color(0xFFF4A0B0);
    canvas.drawRRect(bodyRect, Paint()..color = bodyColor);
    canvas.save();
    canvas.clipRRect(bodyRect);
    canvas.drawRect(Rect.fromLTWH(-w / 2, 0, w, h * 0.25),
        Paint()..color = Colors.white.withValues(alpha: 0.55));
    canvas.restore();
    canvas.drawRRect(
        bodyRect,
        Paint()
          ..color = const Color(0xFF444444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
    canvas.restore();
  }

  void _drawPencilCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-math.pi / 4);
    const halfW = 2.5;
    final outlinePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final graphitePath = Path()
      ..moveTo(0, 0)
      ..lineTo(-1.0, 2.5)
      ..lineTo(1.0, 2.5)
      ..close();
    canvas.drawPath(graphitePath, Paint()..color = const Color(0xFF555555));
    canvas.drawPath(graphitePath, outlinePaint);
    final woodPath = Path()
      ..moveTo(-1.0, 2.5)
      ..lineTo(1.0, 2.5)
      ..lineTo(halfW, 7.0)
      ..lineTo(-halfW, 7.0)
      ..close();
    canvas.drawPath(woodPath, Paint()..color = const Color(0xFFD4A04A));
    canvas.drawPath(woodPath, outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-halfW, 7.0, halfW * 2, 12.0),
        Paint()..color = const Color(0xFFFFD700));
    canvas.drawRect(Rect.fromLTWH(-halfW, 7.0, halfW * 2, 12.0), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-halfW, 19.0, halfW * 2, 2.0),
        Paint()..color = const Color(0xFFAAAAAA));
    canvas.drawRect(Rect.fromLTWH(-halfW, 19.0, halfW * 2, 2.0), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-halfW, 21.0, halfW * 2, 3.5),
        Paint()..color = const Color(0xFFF4A0B0));
    canvas.drawRect(Rect.fromLTWH(-halfW, 21.0, halfW * 2, 3.5), outlinePaint);
    canvas.drawLine(Offset(-halfW, 7.0), Offset(halfW, 7.0), outlinePaint);
    canvas.restore();
  }

  void _drawEyedropperCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-math.pi / 4);
    final outlinePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset.zero, 1.5, Paint()..color = const Color(0xFF333333));
    final rodPath = Path()
      ..moveTo(-1.0, 1.5)
      ..lineTo(1.0, 1.5)
      ..lineTo(1.5, 6.0)
      ..lineTo(-1.5, 6.0)
      ..close();
    canvas.drawPath(rodPath, Paint()..color = const Color(0xFF888888));
    canvas.drawPath(rodPath, outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-2.0, 6.0, 4.0, 1.5),
        Paint()..color = const Color(0xFF666666));
    canvas.drawRect(Rect.fromLTWH(-2.0, 6.0, 4.0, 1.5), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-2.5, 7.5, 5.0, 9.5),
        Paint()..color = const Color(0xFFDDDDDD));
    canvas.drawRect(Rect.fromLTWH(-2.5, 7.5, 5.0, 9.5), outlinePaint);
    canvas.drawCircle(
        const Offset(0, 22.0), 5.0, Paint()..color = const Color(0xFF888888));
    canvas.drawCircle(const Offset(0, 22.0), 5.0, outlinePaint);
    canvas.drawCircle(const Offset(-1.5, 20.5), 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.45));
    canvas.restore();
  }
}
