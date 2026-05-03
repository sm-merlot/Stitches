import 'dart:math' as math;
import '../cell.dart';
import 'stitch.dart';

/// Pure geometry helpers for [Stitch] objects.
///
/// Anything that needs to read a stitch's cell coordinates, screen-space
/// rect, symbol centre, etc. belongs here so the logic is shared between
/// the canvas painter, pattern progress tracking, and any future renderer.
///
/// Coordinate system: cell coords (x, y), screen-Y-down.  PDF rendering
/// uses an inverted Y-axis and has its own helpers in `services/pdf_service.dart`.

/// Returns the [Cell] grid coordinate of [stitch], or null for [BackStitch]
/// (which has no single cell — use `(x1, y1, x2, y2)` directly).
///
/// Prefer [Stitch.cellCoords] extension getter over this free function.
Cell? stitchXY(Stitch stitch) => stitch.cellCoords;

extension StitchGeometry on Stitch {
  /// Cell grid position. Null for [BackStitch] (which spans grid intersections).
  Cell? get cellCoords => switch (this) {
        FullStitch(:final x, :final y) => Cell(x, y),
        HalfStitch(:final x, :final y) => Cell(x, y),
        HalfCrossStitch(:final x, :final y) => Cell(x, y),
        QuarterStitch(:final x, :final y) => Cell(x, y),
        ThreeQuarterStitch(:final x, :final y) => Cell(x, y),
        BackStitch() => null,
      };

  /// Bounding box in cell-unit space.
  /// Non-backstitch types: always (minX: x, maxX: x+1, minY: y, maxY: y+1).
  /// [BackStitch]: min/max of the two endpoints.
  ({double minX, double maxX, double minY, double maxY}) get bounds => switch (this) {
        BackStitch(:final x1, :final y1, :final x2, :final y2) => (
            minX: math.min(x1, x2),
            maxX: math.max(x1, x2),
            minY: math.min(y1, y2),
            maxY: math.max(y1, y2),
          ),
        FullStitch(:final x, :final y) ||
        HalfStitch(:final x, :final y) ||
        QuarterStitch(:final x, :final y) ||
        HalfCrossStitch(:final x, :final y) ||
        ThreeQuarterStitch(:final x, :final y) =>
          (
            minX: x.toDouble(),
            maxX: x + 1.0,
            minY: y.toDouble(),
            maxY: y + 1.0,
          ),
      };

  /// Block-mode rect in cell-unit space: `(left, top, width, height)`.
  /// Multiply each component by `cellSize` to convert to canvas pixels.
  ///
  /// Each fractional-stitch type fills its logical region of the cell so
  /// that four quadrant stitches tile a cell cleanly:
  /// - [FullStitch] → full cell (1×1)
  /// - [HalfStitch] forward `/` → right half; backward `\` → left half
  /// - [HalfCrossStitch] → corresponding left/right/top/bottom half
  /// - [QuarterStitch] → corresponding quarter
  /// - [ThreeQuarterStitch] → 3/4 cell rect anchored at quadrant corner
  /// - [BackStitch] → null (no block representation)
  (double left, double top, double width, double height)? get blockCells =>
      switch (this) {
        FullStitch(:final x, :final y) => (x.toDouble(), y.toDouble(), 1.0, 1.0),

        HalfStitch(:final x, :final y, isForward: true) =>
          (x + 0.5, y.toDouble(), 0.5, 1.0),
        HalfStitch(:final x, :final y, isForward: false) =>
          (x.toDouble(), y.toDouble(), 0.5, 1.0),

        HalfCrossStitch(:final x, :final y, half: HalfOrientation.left) =>
          (x.toDouble(), y.toDouble(), 0.5, 1.0),
        HalfCrossStitch(:final x, :final y, half: HalfOrientation.right) =>
          (x + 0.5, y.toDouble(), 0.5, 1.0),
        HalfCrossStitch(:final x, :final y, half: HalfOrientation.top) =>
          (x.toDouble(), y.toDouble(), 1.0, 0.5),
        HalfCrossStitch(:final x, :final y, half: HalfOrientation.bottom) =>
          (x.toDouble(), y + 0.5, 1.0, 0.5),

        QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.topLeft) =>
          (x.toDouble(), y.toDouble(), 0.5, 0.5),
        QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.topRight) =>
          (x + 0.5, y.toDouble(), 0.5, 0.5),
        QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.bottomLeft) =>
          (x.toDouble(), y + 0.5, 0.5, 0.5),
        QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.bottomRight) =>
          (x + 0.5, y + 0.5, 0.5, 0.5),

        // ThreeQuarterStitch: half-cell triangle — bounding rect is the full cell.
        ThreeQuarterStitch(:final x, :final y) =>
          (x.toDouble(), y.toDouble(), 1.0, 1.0),

        BackStitch() => null,
      };

  /// Returns true when this stitch intersects the visible cell range
  /// `[minX, maxX) × [minY, maxY)`.
  ///
  /// For non-backstitch types the cell `(x, y)` must fall inside the range.
  /// For [BackStitch] the segment bounding box must overlap the range.
  bool isInViewport(int minX, int minY, int maxX, int maxY) => switch (this) {
        FullStitch(:final x, :final y) ||
        HalfStitch(:final x, :final y) ||
        QuarterStitch(:final x, :final y) ||
        HalfCrossStitch(:final x, :final y) ||
        ThreeQuarterStitch(:final x, :final y) =>
          x >= minX && x < maxX && y >= minY && y < maxY,
        BackStitch(:final x1, :final y1, :final x2, :final y2) =>
          math.max(x1, x2) > minX &&
              math.min(x1, x2) < maxX &&
              math.max(y1, y2) > minY &&
              math.min(y1, y2) < maxY,
      };

  /// The sub-cell region(s) this stitch occupies, for overlap detection.
  ///
  /// Each stitch claims one or more [CellRegion] values. Two stitches in the
  /// same cell overlap if they share any region.
  Set<CellRegion> get claimedRegions => switch (this) {
    FullStitch() => CellRegion.values.toSet(),
    HalfStitch(isForward: true) =>
      {CellRegion.topRight, CellRegion.bottomLeft},
    HalfStitch(isForward: false) =>
      {CellRegion.topLeft, CellRegion.bottomRight},
    QuarterStitch(:final quadrant) =>
      {CellRegion.fromQuadrant(quadrant)},
    HalfCrossStitch(half: HalfOrientation.left) =>
      {CellRegion.topLeft, CellRegion.bottomLeft},
    HalfCrossStitch(half: HalfOrientation.right) =>
      {CellRegion.topRight, CellRegion.bottomRight},
    HalfCrossStitch(half: HalfOrientation.top) =>
      {CellRegion.topLeft, CellRegion.topRight},
    HalfCrossStitch(half: HalfOrientation.bottom) =>
      {CellRegion.bottomLeft, CellRegion.bottomRight},
    ThreeQuarterStitch(:final quadrant) => switch (quadrant) {
      QuadrantPosition.topLeft =>
        {CellRegion.topLeft, CellRegion.topRight, CellRegion.bottomLeft},
      QuadrantPosition.topRight =>
        {CellRegion.topLeft, CellRegion.topRight, CellRegion.bottomRight},
      QuadrantPosition.bottomLeft =>
        {CellRegion.topLeft, CellRegion.bottomLeft, CellRegion.bottomRight},
      QuadrantPosition.bottomRight =>
        {CellRegion.topRight, CellRegion.bottomLeft, CellRegion.bottomRight},
    },
    BackStitch() => const {},
  };
}

/// Sub-cell quadrant regions for overlap detection.
enum CellRegion {
  topLeft, topRight, bottomLeft, bottomRight;

  static CellRegion fromQuadrant(QuadrantPosition q) => switch (q) {
    QuadrantPosition.topLeft     => CellRegion.topLeft,
    QuadrantPosition.topRight    => CellRegion.topRight,
    QuadrantPosition.bottomLeft  => CellRegion.bottomLeft,
    QuadrantPosition.bottomRight => CellRegion.bottomRight,
  };
}

/// Returns true if [a] and [b] (in the same cell) would overlap.
bool stitchesOverlap(Stitch a, Stitch b) {
  final ra = a.claimedRegions;
  final rb = b.claimedRegions;
  return ra.any(rb.contains);
}
