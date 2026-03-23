import 'dart:math';

import 'package:flutter/material.dart';

enum SpriteMode { tile, crop }

/// Paints the tile grid overlay (tile mode) or rubber-band crop selection
/// (crop mode) on top of the sprite sheet image.
///
/// The transform from image-space to screen-space is:
///   screen = image * zoom + pan
///
/// All selection coordinates ([cropRect]) are in image-space pixels.
class SpriteSheetPainter extends CustomPainter {
  final Size imageSize;
  final double zoom;
  final Offset pan;
  final SpriteMode mode;
  final int tileSize;

  /// Selected tile column / row (tile mode).
  final int? selTileX;
  final int? selTileY;

  /// Selected crop region in image coordinates (crop mode).
  final Rect? cropRect;

  const SpriteSheetPainter({
    required this.imageSize,
    required this.zoom,
    required this.pan,
    required this.mode,
    required this.tileSize,
    this.selTileX,
    this.selTileY,
    this.cropRect,
  });

  // ── Coordinate helpers ───────────────────────────────────────────────────────

  Offset _toScreen(Offset imgPos) =>
      Offset(imgPos.dx * zoom + pan.dx, imgPos.dy * zoom + pan.dy);

  Rect _rectToScreen(Rect r) =>
      Rect.fromPoints(_toScreen(r.topLeft), _toScreen(r.bottomRight));

  // ── Paint ────────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == SpriteMode.tile) {
      _paintTileGrid(canvas, size);
    } else {
      _paintCropOverlay(canvas, size);
    }
  }

  void _paintTileGrid(Canvas canvas, Size size) {
    // Only draw grid lines when zoom is high enough to be useful.
    if (zoom * tileSize < 4) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = max(0.5, zoom * 0.02)
      ..style = PaintingStyle.stroke;

    final cols = (imageSize.width / tileSize).ceil();
    final rows = (imageSize.height / tileSize).ceil();

    for (var col = 0; col <= cols; col++) {
      final imgX = (col * tileSize).toDouble();
      canvas.drawLine(
        _toScreen(Offset(imgX, 0)),
        _toScreen(Offset(imgX, imageSize.height)),
        gridPaint,
      );
    }

    for (var row = 0; row <= rows; row++) {
      final imgY = (row * tileSize).toDouble();
      canvas.drawLine(
        _toScreen(Offset(0, imgY)),
        _toScreen(Offset(imageSize.width, imgY)),
        gridPaint,
      );
    }

    // Highlight selected tile.
    if (selTileX != null && selTileY != null) {
      final tileRect = _rectToScreen(Rect.fromLTWH(
        (selTileX! * tileSize).toDouble(),
        (selTileY! * tileSize).toDouble(),
        tileSize.toDouble(),
        tileSize.toDouble(),
      ));
      canvas.drawRect(
        tileRect,
        Paint()
          ..color = Colors.amber.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        tileRect,
        Paint()
          ..color = Colors.amber
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintCropOverlay(Canvas canvas, Size size) {
    if (cropRect == null || cropRect!.isEmpty) return;

    final dispRect = _rectToScreen(cropRect!);

    // Dark mask outside selection.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRect(dispRect),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.fill,
    );

    // Selection border.
    canvas.drawRect(
      dispRect,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Corner handles.
    const handleSize = 6.0;
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final corner in [
      dispRect.topLeft,
      dispRect.topRight,
      dispRect.bottomLeft,
      dispRect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handleSize, height: handleSize),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(SpriteSheetPainter old) =>
      old.mode != mode ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.tileSize != tileSize ||
      old.selTileX != selTileX ||
      old.selTileY != selTileY ||
      old.cropRect != cropRect ||
      old.imageSize != imageSize;
}
