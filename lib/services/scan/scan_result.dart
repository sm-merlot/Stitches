// Data types for pattern scanning results and intermediate text extraction.
//
// These types are framework-independent (no pdfrx dependency) so they can be
// constructed in unit tests without native PDF libraries.

/// A positioned text fragment extracted from a PDF page.
///
/// Mirrors the subset of PdfPageTextFragment that the parser needs, without
/// depending on the pdfrx native library.
class TextFragment {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const TextFragment({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
}

/// Extracted text data for a single PDF page.
class PageTextData {
  final String fullText;
  final List<TextFragment> fragments;

  const PageTextData({required this.fullText, required this.fragments});
}

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
