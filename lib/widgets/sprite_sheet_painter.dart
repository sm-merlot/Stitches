import 'package:flutter/material.dart';

class SpriteSheetPainter extends CustomPainter {
  final Size imageSize;
  final double zoom;
  final Offset pan;
  final Rect? cropRect;
  final List<Rect> paletteStrips;
  final Rect? stripDraftRect;
  final bool isDrawingStrip;

  const SpriteSheetPainter({
    required this.imageSize,
    required this.zoom,
    required this.pan,
    this.cropRect,
    this.paletteStrips = const [],
    this.stripDraftRect,
    this.isDrawingStrip = false,
  });

  /// Converts image-space rect to canvas-space rect.
  Rect _toCanvas(Rect r) => Rect.fromLTRB(
        r.left * zoom + pan.dx,
        r.top * zoom + pan.dy,
        r.right * zoom + pan.dx,
        r.bottom * zoom + pan.dy,
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (cropRect != null) {
      _paintCropOverlay(canvas, size, _toCanvas(cropRect!));
    }
    _paintPaletteStrips(canvas, size);
    if (stripDraftRect != null) {
      _paintDraftStrip(canvas, _toCanvas(stripDraftRect!));
    }
  }

  void _paintCropOverlay(Canvas canvas, Size size, Rect canvasCrop) {
    final alpha = isDrawingStrip ? 0.65 : 0.45;
    final maskPaint = Paint()..color = Colors.black.withOpacity(alpha);

    // Draw dark mask around crop
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, canvasCrop.top), maskPaint);
    canvas.drawRect(Rect.fromLTWH(0, canvasCrop.bottom, size.width, size.height - canvasCrop.bottom), maskPaint);
    canvas.drawRect(Rect.fromLTWH(0, canvasCrop.top, canvasCrop.left, canvasCrop.height), maskPaint);
    canvas.drawRect(Rect.fromLTWH(canvasCrop.right, canvasCrop.top, size.width - canvasCrop.right, canvasCrop.height), maskPaint);

    // Crop border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(canvasCrop, borderPaint);

    _drawCornerHandles(canvas, canvasCrop, Colors.white);
  }

  void _paintPaletteStrips(Canvas canvas, Size size) {
    final stripColors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
    ];

    for (int i = 0; i < paletteStrips.length; i++) {
      final canvasStrip = _toCanvas(paletteStrips[i]);
      final color = stripColors[i % stripColors.length];

      // Fill
      canvas.drawRect(canvasStrip, Paint()..color = color.withOpacity(0.15));

      // Border
      canvas.drawRect(
        canvasStrip,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: 'P${i + 1}',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, canvasStrip.topLeft + const Offset(4, 2));

      _drawCornerHandles(canvas, canvasStrip, color);
    }
  }

  void _paintDraftStrip(Canvas canvas, Rect canvasStrip) {
    canvas.drawRect(canvasStrip, Paint()..color = Colors.amber.withOpacity(0.15));
    _drawDashedRect(canvas, canvasStrip, Colors.amber.shade700);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dashLen = 6.0;
    const gapLen = 4.0;

    void drawDashedLine(Offset a, Offset b) {
      final dir = (b - a);
      final total = dir.distance;
      final unit = dir / total;
      double d = 0;
      while (d < total) {
        final start = a + unit * d;
        final end = a + unit * (d + dashLen).clamp(0, total);
        canvas.drawLine(start, end, paint);
        d += dashLen + gapLen;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  void _drawCornerHandles(Canvas canvas, Rect rect, Color color) {
    const hs = 6.0;
    final handlePaint = Paint()..color = color;
    for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: hs, height: hs),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(SpriteSheetPainter old) =>
      old.imageSize != imageSize ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.cropRect != cropRect ||
      old.paletteStrips != paletteStrips ||
      old.stripDraftRect != stripDraftRect ||
      old.isDrawingStrip != isDrawingStrip;
}
