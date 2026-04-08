import 'package:flutter/widgets.dart';

/// Immutable view of the pan/zoom state used by [PatternCanvas] and
/// [CanvasStaticPainter].
///
/// Holds the cell size, pan offset, scale, and (during paint) the screen
/// size. Provides the screen↔canvas↔cell coordinate transforms and viewport
/// culling math that previously lived inline in both files.
@immutable
class CanvasViewport {
  /// Logical pixels per cell at scale 1.0.
  final double cellSize;

  /// Translation (in screen logical pixels) applied to the canvas before
  /// scaling.
  final Offset panOffset;

  /// Zoom factor.  `1.0` = native, `>1.0` = zoomed in.
  final double scale;

  const CanvasViewport({
    required this.cellSize,
    required this.panOffset,
    required this.scale,
  });

  /// On-screen size of one cell in logical pixels.
  double get effectivePx => cellSize * scale;

  /// Converts a screen-space point to canvas/pattern space.
  Offset screenToCanvas(Offset screen) => (screen - panOffset) / scale;

  /// Snaps a canvas-space point to the nearest half-cell grid intersection.
  /// Used for backstitch endpoint placement.
  Offset canvasToGridPoint(Offset canvas) {
    final gx = (canvas.dx / cellSize * 2).round() / 2.0;
    final gy = (canvas.dy / cellSize * 2).round() / 2.0;
    return Offset(gx, gy);
  }

  /// Returns the (col, row) cell containing the canvas-space point.
  (int, int) canvasToCell(Offset canvas) => (
        (canvas.dx / cellSize).floor(),
        (canvas.dy / cellSize).floor(),
      );

  /// Returns the sub-cell position (0..1, 0..1) of [canvas] within the cell at
  /// `(cellX, cellY)`. Used for quadrant / half-orientation detection.
  (double, double) subCellPos(Offset canvas, int cellX, int cellY) {
    final subX = (canvas.dx / cellSize) - cellX;
    final subY = (canvas.dy / cellSize) - cellY;
    return (subX.clamp(0.0, 1.0), subY.clamp(0.0, 1.0));
  }

  /// Returns the visible cell range for the given screen [size], expanded by
  /// a 1-cell buffer (to avoid seams) and clipped to `(0..maxCols, 0..maxRows)`.
  ///
  /// Used by [CanvasStaticPainter] for viewport culling.
  ({int minX, int minY, int maxX, int maxY}) visibleCellRange(
      Size size, int maxCols, int maxRows) {
    final visLeft = -panOffset.dx / scale;
    final visTop = -panOffset.dy / scale;
    final visRight = (size.width - panOffset.dx) / scale;
    final visBottom = (size.height - panOffset.dy) / scale;
    return (
      minX: ((visLeft / cellSize).floor() - 1).clamp(0, maxCols),
      minY: ((visTop / cellSize).floor() - 1).clamp(0, maxRows),
      maxX: ((visRight / cellSize).ceil() + 1).clamp(0, maxCols),
      maxY: ((visBottom / cellSize).ceil() + 1).clamp(0, maxRows),
    );
  }

  /// Returns a new viewport zoomed by [factor] around the screen-space
  /// [focalPoint], so the focal point stays under the cursor/finger.
  CanvasViewport zoomedAround(Offset focalPoint, double factor,
      {double minScale = 0.1, double maxScale = 20.0}) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final scaleFactor = newScale / scale;
    return CanvasViewport(
      cellSize: cellSize,
      panOffset: focalPoint - (focalPoint - panOffset) * scaleFactor,
      scale: newScale,
    );
  }

  /// Returns a new viewport translated by [delta] screen-space pixels.
  CanvasViewport pannedBy(Offset delta) => CanvasViewport(
        cellSize: cellSize,
        panOffset: panOffset + delta,
        scale: scale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasViewport &&
          cellSize == other.cellSize &&
          panOffset == other.panOffset &&
          scale == other.scale;

  @override
  int get hashCode => Object.hash(cellSize, panOffset, scale);
}
