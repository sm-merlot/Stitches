import 'stitch.dart';

/// Pure geometry helpers for [Stitch] objects.
///
/// Anything that needs to read a stitch's cell coordinates, screen-space
/// rect, symbol centre, etc. belongs here so the logic is shared between
/// the canvas painter, pattern progress tracking, and any future renderer.
///
/// Coordinate system: cell coords (x, y), screen-Y-down.  PDF rendering
/// uses an inverted Y-axis and has its own helpers in `services/pdf_service.dart`.

/// Returns the (x, y) cell coordinates of [stitch], or null for [BackStitch]
/// (which has no single cell — use `(x1, y1, x2, y2)` directly).
(int, int)? stitchXY(Stitch stitch) => switch (stitch) {
      FullStitch(:final x, :final y) => (x, y),
      HalfStitch(:final x, :final y) => (x, y),
      HalfCrossStitch(:final x, :final y) => (x, y),
      QuarterStitch(:final x, :final y) => (x, y),
      QuarterCrossStitch(:final x, :final y) => (x, y),
      BackStitch() => null,
    };
