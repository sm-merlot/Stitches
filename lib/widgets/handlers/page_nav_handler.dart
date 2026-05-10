import 'package:flutter/widgets.dart' show Offset, Size;

/// Stateless helper that determines whether a pointer position falls inside
/// a page-navigation button hit zone.
///
/// Extracted from [AidaWidget] so the geometry is named, documented, and
/// unit-testable without a widget tree.
class PageNavHandler {
  /// Hit margin (screen pixels) used for left/right arrows and the horizontal
  /// extent of the up/down arrows. Matches the button width (36px) plus
  /// its 4px margin on each side = 44px total.
  static const double edgeGuard = 44.0;

  /// Height of the bottom guard in screen pixels (covers down-arrow + page
  /// indicator pill).
  static const double bottomGuard = 100.0;

  /// Half-width of the up/down arrow buttons (64px wide → 32px half + 4px buffer).
  static const double _upDownHalfWidth = 36.0;

  /// Height of the up-arrow button including its vertical margin (36px + 4px×2).
  static const double _upButtonHeight = 44.0;

  /// The down-arrow button sits at `bottom: 52` with 44px height, so its top
  /// edge is at `canvasHeight - 52 - 44 = canvasHeight - 96`.
  static const double _downButtonTopFromBottom = 96.0;

  const PageNavHandler();

  /// Returns `true` when [screenPos] is inside a nav-button hit area.
  ///
  /// Always returns `false` when stitch mode is inactive, page mode is
  /// disabled, or there is no page layout — avoids accidental suppression of
  /// stitch operations when page chrome is not visible.
  ///
  /// Pass [hasLeft], [hasRight], [hasUp], [hasDown] to match which arrows are
  /// actually rendered. Guards are only applied for directions that have a
  /// visible button, preventing false positives on border rows/columns.
  ///
  /// The up/down guards only cover the centred button strip (not the full
  /// canvas width), so cells to the sides of those buttons remain tappable.
  bool isNavZone(
    Offset screenPos,
    Size canvasSize, {
    required bool stitchMode,
    required bool pageEnabled,
    required bool hasPageLayout,
    bool hasLeft = true,
    bool hasRight = true,
    bool hasUp = false,
    bool hasDown = false,
  }) {
    if (!stitchMode || !pageEnabled || !hasPageLayout) return false;

    final dx = screenPos.dx;
    final dy = screenPos.dy;
    final w = canvasSize.width;
    final h = canvasSize.height;

    // Left/right arrows: full-height centred, edgeGuard px wide.
    if (hasLeft && dx < edgeGuard) return true;
    if (hasRight && dx > w - edgeGuard) return true;

    // Up arrow: edgeGuard px tall, centred horizontally (only the button strip).
    if (hasUp && dy < _upButtonHeight && (dx - w / 2).abs() < _upDownHalfWidth) {
      return true;
    }

    // Down arrow: positioned at bottom: 52 in the overlay; _downButtonTopFromBottom
    // px from the canvas bottom. Only the centred strip.
    if (hasDown &&
        dy > h - _downButtonTopFromBottom &&
        dy < h - 48 &&
        (dx - w / 2).abs() < _upDownHalfWidth) {
      return true;
    }

    // Page indicator pill: always shown at bottom: 16 (~50px tall).
    // bottomGuard covers both the pill and the down-arrow when hasDown is true.
    if (dy > h - bottomGuard) return true;

    return false;
  }
}
