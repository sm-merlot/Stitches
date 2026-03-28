part of 'canvas_painter.dart';

// ─── Overlay layer ─────────────────────────────────────────────────────────────
// Cursor, ghost stitches, selection rect, stylus hover, backstitch preview.
// Repaints independently of the static layer — never invalidates its cache.

class CanvasOverlayPainter extends CustomPainter with _DrawingMethods {
  @override final double cellSize;
  final Offset panOffset;
  @override final double scale;
  @override final Color aidaColor;
  final Offset? backstitchStartPoint;
  final Offset? backstitchCurrentPoint;
  final bool isErasing;
  final bool isDrawCursor;
  final bool isColorPickerCursor;
  final Offset? cursorScreenPos;
  final Rect? selectionRect;
  final List<Stitch>? ghostStitches;
  final List<Thread>? ghostThreads;
  final double ghostOpacity;
  final List<Thread> patternThreads;
  final (int, int)? stylusHoverCell;
  final Color? stylusHoverColor;
  final String? activeLayerName;
  final bool stitchMode;

  CanvasOverlayPainter({
    required this.cellSize,
    required this.panOffset,
    required this.scale,
    required this.aidaColor,
    required this.patternThreads,
    this.backstitchStartPoint,
    this.backstitchCurrentPoint,
    this.isErasing = false,
    this.isDrawCursor = false,
    this.isColorPickerCursor = false,
    this.cursorScreenPos,
    this.selectionRect,
    this.ghostStitches,
    this.ghostThreads,
    this.ghostOpacity = 1.0,
    this.stylusHoverCell,
    this.stylusHoverColor,
    this.activeLayerName,
    this.stitchMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Keep overlay drawing within widget bounds too.
    canvas.clipRect(Offset.zero & size);

    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    // Backstitch start indicator + preview
    if (backstitchStartPoint != null) {
      _drawGridPointIndicator(canvas, backstitchStartPoint!);
      if (backstitchCurrentPoint != null &&
          backstitchCurrentPoint != backstitchStartPoint) {
        _drawBackstitchPreview(canvas, backstitchStartPoint!, backstitchCurrentPoint!);
      }
    }

    // Ghost stitches (paste / move preview)
    if (ghostStitches != null && ghostStitches!.isNotEmpty) {
      final threadMap = <String, Thread>{
        for (final t in patternThreads) t.dmcCode: t,
        if (ghostThreads != null) for (final t in ghostThreads!) t.dmcCode: t,
      };
      _drawGhostStitches(canvas, ghostStitches!, threadMap, opacity: ghostOpacity);
    }

    // Selection rect
    if (selectionRect != null) _drawSelectionRect(canvas, selectionRect!);

    // Stylus hover preview
    if (stylusHoverCell != null) {
      final (hx, hy) = stylusHoverCell!;
      final hColor = stylusHoverColor ?? const Color(0xFF9B30D0);
      final rect = Rect.fromLTWH(hx * cellSize, hy * cellSize, cellSize, cellSize);
      canvas.drawRect(rect, Paint()..color = hColor.withValues(alpha: 0.25));
      canvas.drawRect(
          rect,
          Paint()
            ..color = hColor.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale);
    }

    canvas.restore();

    // Custom cursors (screen-space, after restore)
    if (cursorScreenPos != null) {
      if (isErasing) _drawEraserCursor(canvas, cursorScreenPos!);
      if (isDrawCursor) _drawPencilCursor(canvas, cursorScreenPos!);
      if (isColorPickerCursor) _drawEyedropperCursor(canvas, cursorScreenPos!);
    }

    // ── Active layer chip ───────────────────────────────────────────────────
    if (!stitchMode && activeLayerName != null) {
      _drawActiveLayerChip(canvas, size, activeLayerName!);
    }
  }

  void _drawActiveLayerChip(Canvas canvas, Size size, String layerName) {
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    const textStyle = TextStyle(
      fontSize: 11,
      color: Colors.white,
      fontWeight: FontWeight.w500,
    );
    final label = 'Drawing on: $layerName';
    final tp = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    const left = 8.0;
    const bottom = 8.0;
    final chipRect = Rect.fromLTWH(
      left,
      size.height - bottom - tp.height - padding.vertical,
      tp.width + padding.horizontal,
      tp.height + padding.vertical,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
      Paint()..color = const Color(0xCC1A1A2E),
    );
    tp.paint(canvas,
        Offset(chipRect.left + padding.left, chipRect.top + padding.top));
  }

  @override
  bool shouldRepaint(CanvasOverlayPainter old) =>
      old.cellSize != cellSize ||
      old.panOffset != panOffset ||
      old.scale != scale ||
      old.aidaColor != aidaColor ||
      old.backstitchStartPoint != backstitchStartPoint ||
      old.backstitchCurrentPoint != backstitchCurrentPoint ||
      old.isErasing != isErasing ||
      old.isDrawCursor != isDrawCursor ||
      old.isColorPickerCursor != isColorPickerCursor ||
      old.cursorScreenPos != cursorScreenPos ||
      old.selectionRect != selectionRect ||
      old.ghostStitches != ghostStitches ||
      old.ghostThreads != ghostThreads ||
      old.ghostOpacity != ghostOpacity ||
      old.patternThreads != patternThreads ||
      old.stylusHoverCell != stylusHoverCell ||
      old.stylusHoverColor != stylusHoverColor ||
      old.activeLayerName != activeLayerName ||
      old.stitchMode != stitchMode;
}
