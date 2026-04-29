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
  final int eraserSize;
  final bool fillEraseActive;
  final bool isDrawCursor;
  final bool isColorPickerCursor;
  final Offset? cursorScreenPos;
  final Rect? selectionRect;
  final List<Stitch>? ghostStitches;
  final List<Thread>? ghostThreads;
  final double ghostOpacity;
  final Map<String, Thread> patternThreads;
  final (int, int)? stylusHoverCell;
  final Color? stylusHoverColor;
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
    this.eraserSize = 1,
    this.fillEraseActive = false,
    this.isDrawCursor = false,
    this.isColorPickerCursor = false,
    this.cursorScreenPos,
    this.selectionRect,
    this.ghostStitches,
    this.ghostThreads,
    this.ghostOpacity = 1.0,
    this.stylusHoverCell,
    this.stylusHoverColor,
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
        ...patternThreads,
        if (ghostThreads != null) for (final t in ghostThreads!) t.dmcCode: t,
      };
      _drawGhostStitches(canvas, ghostStitches!, threadMap, opacity: ghostOpacity);
    }

    // Selection rect
    if (selectionRect != null) _drawSelectionRect(canvas, selectionRect!);

    // Stylus hover preview
    if (stylusHoverCell != null) {
      final (hx, hy) = stylusHoverCell!;
      if (isErasing && !fillEraseActive) {
        // Box eraser preview — show the full footprint that will be erased
        const eraseColor = Color(0xFFE53935);
        final half = (eraserSize - 1) ~/ 2;
        final x0 = hx - half;
        final y0 = hy - half;
        final boxRect = Rect.fromLTWH(
            x0 * cellSize, y0 * cellSize, eraserSize * cellSize, eraserSize * cellSize);
        canvas.drawRect(boxRect, Paint()..color = eraseColor.withValues(alpha: 0.15));
        canvas.drawRect(
            boxRect,
            Paint()
              ..color = eraseColor.withValues(alpha: 0.75)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 / scale);
      } else {
        // Draw cursor / fill-erase / non-erase: single cell highlight
        final hColor = fillEraseActive && isErasing
            ? const Color(0xFFFF6D00) // orange = flood erase
            : (stylusHoverColor ?? const Color(0xFF9B30D0));
        final rect = Rect.fromLTWH(hx * cellSize, hy * cellSize, cellSize, cellSize);
        canvas.drawRect(rect, Paint()..color = hColor.withValues(alpha: 0.25));
        canvas.drawRect(
            rect,
            Paint()
              ..color = hColor.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 / scale);
      }
    }

    canvas.restore();

    // Custom cursors (screen-space, after restore)
    if (cursorScreenPos != null) {
      if (isErasing) _drawEraserCursor(canvas, cursorScreenPos!, fillErase: fillEraseActive);
      if (isDrawCursor) _drawPencilCursor(canvas, cursorScreenPos!);
      if (isColorPickerCursor) _drawEyedropperCursor(canvas, cursorScreenPos!);
    }

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
      old.eraserSize != eraserSize ||
      old.fillEraseActive != fillEraseActive ||
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
      old.stitchMode != stitchMode;
}
