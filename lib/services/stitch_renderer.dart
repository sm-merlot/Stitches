import '../models/stitch/stitch_plan.dart';

/// A resolved stitch line ready for rendering, in pixel coordinates.
class StitchSegment {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final StitchType type;

  const StitchSegment({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.type,
  });
}

/// Grid bounds in pixel space for a [PlannedAida].
class GridBounds {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const GridBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
}

/// ARGB color (0xAARRGGBB) for each stitch type.
///
/// Uses the educational/demonstration palette from the original Python
/// animation: purple=front1, green=front2, gold=back1, red=back2, blue=back3.
const stitchTypeArgb = <StitchType, int>{
  StitchType.frontOne: 0xFF9B30D0, // purple
  StitchType.frontTwo: 0xFF27AE60, // green
  StitchType.backOne: 0xFFE6B800, // gold
  StitchType.backTwo: 0xFFE63030, // red
  StitchType.backThree: 0xFF0074D9, // blue
  StitchType.automatic: 0xFF888888, // grey
};

/// Compute the pixel bounding box that tightly encloses all active squares,
/// given [cellSize] pixels per grid cell.
GridBounds computeGridBounds(PlannedAida aida, double cellSize) {
  if (aida.activeSquareIds.isEmpty) {
    return GridBounds(left: 0, top: 0, right: cellSize, bottom: cellSize);
  }
  double minX = double.infinity,
      minY = double.infinity,
      maxX = double.negativeInfinity,
      maxY = double.negativeInfinity;
  for (final sqId in aida.activeSquareIds) {
    final sq = aida.squares[sqId];
    final l = (sq.x - 0.5) * cellSize;
    final t = (sq.y - 0.5) * cellSize;
    final r = (sq.x + 0.5) * cellSize;
    final b = (sq.y + 0.5) * cellSize;
    if (l < minX) minX = l;
    if (t < minY) minY = t;
    if (r > maxX) maxX = r;
    if (b > maxY) maxY = b;
  }
  return GridBounds(left: minX, top: minY, right: maxX, bottom: maxY);
}

/// Convert all stitches in [aida] to [StitchSegment]s with pixel coordinates.
///
/// [cellSize] is pixels per grid cell.
/// [originX]/[originY] is the pixel offset applied to all coordinates (use
/// padding values so the image has a margin around the pattern).
List<StitchSegment> resolveSegments(
  PlannedAida aida, {
  required double cellSize,
  double originX = 0,
  double originY = 0,
}) {
  (double, double) toPixel((double, double) coord) =>
      (originX + coord.$1 * cellSize, originY + coord.$2 * cellSize);

  final result = <StitchSegment>[];
  for (final stitch in aida.stitches) {
    final (double, double) c1, c2;
    if (stitch is PlanSimpleStitch) {
      c1 = aida.squares[stitch.squareId].cornerCoord(stitch.fro);
      c2 = aida.squares[stitch.squareId].cornerCoord(stitch.to);
    } else {
      final cs = stitch as PlanCrossStitch;
      c1 = aida.squares[cs.fro.squareId].cornerCoord(cs.fro.corner);
      c2 = aida.squares[cs.to.squareId].cornerCoord(cs.to.corner);
    }
    final (px1, py1) = toPixel(c1);
    final (px2, py2) = toPixel(c2);
    result.add(StitchSegment(x1: px1, y1: py1, x2: px2, y2: py2, type: stitch.type));
  }
  return result;
}
