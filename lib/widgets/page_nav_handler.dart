import 'package:flutter/widgets.dart' show Offset, Size;

/// Stateless helper that determines whether a pointer position falls inside
/// a page-navigation button hit zone.
///
/// Extracted from [PatternCanvas] so the geometry is named, documented, and
/// unit-testable without a widget tree.
class PageNavHandler {
  /// Width of the left/right arrow hit zones in screen pixels.
  static const double edgeGuard = 56.0;

  /// Height of the bottom hit zone in screen pixels (covers down-arrow + page indicator).
  static const double bottomGuard = 100.0;

  const PageNavHandler();

  /// Returns `true` when [screenPos] is inside a nav-button hit area.
  ///
  /// Always returns `false` when stitch mode is inactive, page mode is
  /// disabled, or there is no page layout — avoids accidental suppression of
  /// stitch operations when page chrome is not visible.
  bool isNavZone(
    Offset screenPos,
    Size canvasSize, {
    required bool stitchMode,
    required bool pageEnabled,
    required bool hasPageLayout,
  }) {
    if (!stitchMode || !pageEnabled || !hasPageLayout) return false;
    return screenPos.dx < edgeGuard ||
        screenPos.dx > canvasSize.width - edgeGuard ||
        screenPos.dy < edgeGuard ||
        screenPos.dy > canvasSize.height - bottomGuard;
  }
}
