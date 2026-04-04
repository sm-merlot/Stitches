import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'page_config.dart';
import 'pattern.dart';
import 'stitch.dart';

/// Precomputed page layout derived from a [PageConfig] and the pattern's stitch
/// data. Not persisted — recomputed whenever page config changes.
class PageLayout {
  final PageConfig config;
  final int patternWidth;
  final int patternHeight;

  /// Number of pages across (columns of pages).
  final int pagesAcross;

  /// Number of pages down (rows of pages).
  final int pagesDown;

  /// verticalOffsets[boundaryCol][row] = offset delta from nominal boundary.
  /// Actual column boundary for (boundaryCol, row) =
  ///   boundaryCol + verticalOffsets[boundaryCol]![row]!
  final Map<int, Map<int, int>> verticalOffsets;

  /// horizontalOffsets[boundaryRow][col] = offset delta from nominal boundary.
  final Map<int, Map<int, int>> horizontalOffsets;

  PageLayout._({
    required this.config,
    required this.patternWidth,
    required this.patternHeight,
    required this.pagesAcross,
    required this.pagesDown,
    required this.verticalOffsets,
    required this.horizontalOffsets,
  });

  int get totalPages => pagesAcross * pagesDown;

  /// Page column and row for a given page index (0-based, row-major).
  (int, int) pageCoords(int pageIndex) =>
      (pageIndex % pagesAcross, pageIndex ~/ pagesAcross);

  /// Page index (0-based) for given page column and row.
  int pageIndex(int pageCol, int pageRow) => pageRow * pagesAcross + pageCol;

  /// Actual left column boundary for [pageCol] at [row].
  int leftBoundaryForRow(int pageCol, int row) {
    if (pageCol == 0) return 0;
    final nominal = pageCol * config.pageWidth;
    return (nominal + (verticalOffsets[nominal]?[row] ?? 0))
        .clamp(0, patternWidth);
  }

  /// Actual right column boundary (exclusive) for [pageCol] at [row].
  int rightBoundaryForRow(int pageCol, int row) {
    if (pageCol >= pagesAcross - 1) return patternWidth;
    final nominal = (pageCol + 1) * config.pageWidth;
    return (nominal + (verticalOffsets[nominal]?[row] ?? 0))
        .clamp(0, patternWidth);
  }

  /// Actual top row boundary for [pageRow] at [col].
  int topBoundaryForCol(int pageRow, int col) {
    if (pageRow == 0) return 0;
    final nominal = pageRow * config.pageHeight;
    return (nominal + (horizontalOffsets[nominal]?[col] ?? 0))
        .clamp(0, patternHeight);
  }

  /// Actual bottom row boundary (exclusive) for [pageRow] at [col].
  int bottomBoundaryForCol(int pageRow, int col) {
    if (pageRow >= pagesDown - 1) return patternHeight;
    final nominal = (pageRow + 1) * config.pageHeight;
    return (nominal + (horizontalOffsets[nominal]?[col] ?? 0))
        .clamp(0, patternHeight);
  }

  /// Whether the stitch at (x=col, y=row) belongs to page (pageCol, pageRow).
  ///
  /// A connectivity guard is applied: the cell must also have at least one
  /// orthogonal neighbour that passes the boundary check. This prevents
  /// floating corner cells that arise when independent vertical and horizontal
  /// fuzzy offsets converge at a page corner.
  bool cellOnPage(int col, int row, int pageCol, int pageRow) {
    if (!_boundaryCheck(col, row, pageCol, pageRow)) return false;
    return _boundaryCheck(col - 1, row, pageCol, pageRow) ||
        _boundaryCheck(col + 1, row, pageCol, pageRow) ||
        _boundaryCheck(col, row - 1, pageCol, pageRow) ||
        _boundaryCheck(col, row + 1, pageCol, pageRow);
  }

  /// Raw boundary check without connectivity guard. Used internally by
  /// [cellOnPage] to test neighbours without infinite recursion.
  bool _boundaryCheck(int col, int row, int pageCol, int pageRow) {
    if (col < 0 || col >= patternWidth || row < 0 || row >= patternHeight) {
      return false;
    }
    final left = leftBoundaryForRow(pageCol, row);
    final right = rightBoundaryForRow(pageCol, row);
    final top = topBoundaryForCol(pageRow, col);
    final bottom = bottomBoundaryForCol(pageRow, col);
    return col >= left && col < right && row >= top && row < bottom;
  }

  /// Nominal (non-fuzzy) cell-space bounding rect of a page. Used for
  /// auto-fit pan/zoom calculations.
  Rect nominalPageRect(int pageCol, int pageRow) {
    final left = (pageCol * config.pageWidth).toDouble();
    final top = (pageRow * config.pageHeight).toDouble();
    final right = (pageCol < pagesAcross - 1
            ? (pageCol + 1) * config.pageWidth
            : patternWidth)
        .toDouble();
    final bottom = (pageRow < pagesDown - 1
            ? (pageRow + 1) * config.pageHeight
            : patternHeight)
        .toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Build a [PageLayout] from [config] and the pattern's current stitch data.
  ///
  /// Fuzzy boundary offsets are computed once and cached in the returned
  /// [PageLayout] object. Deterministic for the same config+pattern content.
  static PageLayout compute(PageConfig config, CrossStitchPattern pattern) {
    final pagesAcross =
        (pattern.width / config.pageWidth).ceil().clamp(1, pattern.width);
    final pagesDown =
        (pattern.height / config.pageHeight).ceil().clamp(1, pattern.height);

    // Build top-most FullStitch colour map: encoded cell key → threadId.
    // Iterate layers top-to-bottom so earlier entries (higher layers) win.
    final Map<int, String?> cellColor = {};
    for (final layer in pattern.layers.reversed) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is FullStitch) {
          cellColor[(stitch.x << 16) | stitch.y] = stitch.threadId;
        }
      }
    }

    String? colorAt(int col, int row) => cellColor[(col << 16) | row];

    // Vertical boundary offsets (column boundaries).
    final Map<int, Map<int, int>> verticalOffsets = {};
    for (int p = 1; p < pagesAcross; p++) {
      final boundaryCol = p * config.pageWidth;
      final Map<int, int> rowOffsets = {};
      for (int row = 0; row < pattern.height; row++) {
        rowOffsets[row] = _computeOffset(
          nominalBoundary: boundaryCol,
          crossIndex: row,
          fuzzyAmount: config.fuzzyAmount,
          maxBoundary: pattern.width,
          colorAt: (primary, secondary) => colorAt(primary, secondary),
          seed: _makeSeed(
              pattern.width, pattern.height, config, boundaryCol * 100003 + row),
        );
      }
      verticalOffsets[boundaryCol] = rowOffsets;
    }

    // Horizontal boundary offsets (row boundaries).
    final Map<int, Map<int, int>> horizontalOffsets = {};
    for (int p = 1; p < pagesDown; p++) {
      final boundaryRow = p * config.pageHeight;
      final Map<int, int> colOffsets = {};
      for (int col = 0; col < pattern.width; col++) {
        colOffsets[col] = _computeOffset(
          nominalBoundary: boundaryRow,
          crossIndex: col,
          fuzzyAmount: config.fuzzyAmount,
          maxBoundary: pattern.height,
          colorAt: (primary, secondary) => colorAt(secondary, primary),
          seed: _makeSeed(
              pattern.width, pattern.height, config, boundaryRow * 100003 + col + 500000000),
        );
      }
      horizontalOffsets[boundaryRow] = colOffsets;
    }

    return PageLayout._(
      config: config,
      patternWidth: pattern.width,
      patternHeight: pattern.height,
      pagesAcross: pagesAcross,
      pagesDown: pagesDown,
      verticalOffsets: verticalOffsets,
      horizontalOffsets: horizontalOffsets,
    );
  }

  static int _makeSeed(int pw, int ph, PageConfig config, int extra) =>
      (pw * 73856093) ^
      (ph * 19349663) ^
      (config.pageWidth * 83492791) ^
      (config.pageHeight * 41) ^
      (config.fuzzyAmount * 7) ^
      extra;

  /// Compute the fuzzy offset for one row/column at a boundary.
  ///
  /// [colorAt] takes (primary, crossIndex): for vertical boundaries
  /// `primary = col, crossIndex = row`; for horizontal, `primary = row,
  /// crossIndex = col`.
  ///
  /// Priority: snap to nearest colour change within the fuzzy zone; fall back
  /// to seeded pseudo-random if no change exists.
  static int _computeOffset({
    required int nominalBoundary,
    required int crossIndex,
    required int fuzzyAmount,
    required int maxBoundary,
    required String? Function(int primary, int crossIndex) colorAt,
    required int seed,
  }) {
    if (fuzzyAmount == 0) return 0;

    // Scan outward from the nominal boundary for the nearest colour change.
    // Offset k places the boundary between positions (nominalBoundary+k-1)
    // and (nominalBoundary+k).
    for (int d = 0; d <= fuzzyAmount; d++) {
      // Positive offset (right/below nominal).
      {
        final posA = nominalBoundary + d - 1;
        final posB = nominalBoundary + d;
        if (posA >= 0 && posB < maxBoundary) {
          final cA = colorAt(posA, crossIndex);
          final cB = colorAt(posB, crossIndex);
          // Only snap to changes between two STITCHED cells of different colours
          // — ignore transitions to/from empty aida.
          if (cA != null && cB != null && cA != cB) return d;
        }
      }
      // Negative offset (left/above nominal); skip d=0 (already covered).
      if (d > 0) {
        final posA = nominalBoundary - d - 1;
        final posB = nominalBoundary - d;
        if (posA >= 0 && posB < maxBoundary) {
          final cA = colorAt(posA, crossIndex);
          final cB = colorAt(posB, crossIndex);
          if (cA != null && cB != null && cA != cB) return -d;
        }
      }
    }

    // No colour change in the fuzzy zone — use seeded pseudo-random offset.
    return math.Random(seed).nextInt(2 * fuzzyAmount + 1) - fuzzyAmount;
  }
}
