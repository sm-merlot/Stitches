import 'dart:math' as math;

/// Pure-Dart dashed-line segment iterator.
///
/// No Flutter or `dart:ui` imports — safe to use from the CLI / `image`
/// package code as well as from Flutter Canvas painters.
///
/// Walks the line from `(x1, y1)` to `(x2, y2)`, alternating "on" segments of
/// length [dashLen] with "off" segments of length [gapLen]. For each "on"
/// segment, calls [onSegment] with its endpoints.  Final segments are clamped
/// so the dash never extends past the end of the line.

void forEachDashSegment(
  double x1,
  double y1,
  double x2,
  double y2, {
  required double dashLen,
  required double gapLen,
  required void Function(double sx, double sy, double ex, double ey) onSegment,
}) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (dist < 1e-9) return;

  final ux = dx / dist;
  final uy = dy / dist;
  var d = 0.0;
  var drawing = true;
  while (d < dist) {
    final segLen =
        drawing ? math.min(dashLen, dist - d) : math.min(gapLen, dist - d);
    if (drawing && segLen > 0) {
      onSegment(
        x1 + ux * d,
        y1 + uy * d,
        x1 + ux * (d + segLen),
        y1 + uy * (d + segLen),
      );
    }
    d += segLen;
    drawing = !drawing;
  }
}
