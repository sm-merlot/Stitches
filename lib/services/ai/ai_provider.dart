/// A single thread colour identified during pattern scanning.
class ScannedThread {
  final String dmcCode;
  final String name;
  final String colorHex; // '#RRGGBB'

  const ScannedThread({
    required this.dmcCode,
    required this.name,
    required this.colorHex,
  });
}

/// A single stitch identified during pattern scanning.
///
/// For backstitch: [x]/[y] are the start intersection, [x2]/[y2] the end.
/// All coordinates are integers; backstitch coordinates are grid intersections
/// (0 = top-left corner of the grid, up to width/height).
class ScannedStitch {
  final int x;
  final int y;
  final String type; // 'full' | 'half_forward' | 'half_backward' | 'backstitch'
  final String dmcCode;
  final int? x2; // backstitch end only
  final int? y2;

  const ScannedStitch({
    required this.x,
    required this.y,
    required this.type,
    required this.dmcCode,
    this.x2,
    this.y2,
  });
}

/// The complete result of a pattern scan.
class PatternScanResult {
  final int width;
  final int height;
  final List<ScannedThread> threads;
  final List<ScannedStitch> stitches;
  final String? warning;

  /// Stated design dimensions in stitches (e.g. from PDF text "80 x 60 stitches").
  /// Null when not available.
  final int? patternW;
  final int? patternH;

  const PatternScanResult({
    required this.width,
    required this.height,
    required this.threads,
    required this.stitches,
    this.warning,
    this.patternW,
    this.patternH,
  });
}
