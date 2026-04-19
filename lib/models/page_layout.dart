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

  /// page index → set of encoded cell keys excluded by the corner connectivity
  /// post-pass (cells that pass raw boundary checks but are disconnected from
  /// the page interior due to fuzzy corner interaction).
  final Map<int, Set<int>> _excludedCells;

  PageLayout._({
    required this.config,
    required this.patternWidth,
    required this.patternHeight,
    required this.pagesAcross,
    required this.pagesDown,
    required this.verticalOffsets,
    required this.horizontalOffsets,
    required Map<int, Set<int>> excludedCells,
  }) : _excludedCells = excludedCells;

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
  /// Cells near page corners are checked against a precomputed exclusion set
  /// that removes any island groups disconnected from the page interior (a
  /// consequence of vertical and horizontal fuzzy offsets being computed
  /// independently and converging at corners).
  bool cellOnPage(int col, int row, int pageCol, int pageRow) {
    if (!_boundaryCheck(col, row, pageCol, pageRow)) return false;
    final excluded = _excludedCells[pageRow * pagesAcross + pageCol];
    return excluded == null || !excluded.contains(_encodeCell(col, row));
  }

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

  static int _encodeCell(int col, int row) => (col << 16) | row;

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

    // ── Corner connectivity post-pass ────────────────────────────────────────
    // Independent vertical and horizontal fuzzy offsets can create isolated
    // groups of cells at page corners. For each internal corner (where a
    // vertical and a horizontal boundary cross), flood-fill from cells
    // connected to the page interior and exclude any that aren't reachable.
    //
    // "Interior-connected" means: the cell has at least one orthogonal
    // neighbour that is on the page but OUTSIDE the corner region.
    //
    // Only cells within the corner region (cols within fa of the vertical
    // boundary AND rows within fa of the horizontal boundary) can be affected.

    // Local raw-boundary check closure (mirrors instance _boundaryCheck).
    bool rawOnPage(int col, int row, int px, int py) {
      if (col < 0 || col >= pattern.width || row < 0 || row >= pattern.height) {
        return false;
      }
      final leftNom = px * config.pageWidth;
      final left = px == 0
          ? 0
          : (leftNom + (verticalOffsets[leftNom]?[row] ?? 0))
              .clamp(0, pattern.width);
      final rightNom = (px + 1) * config.pageWidth;
      final right = px >= pagesAcross - 1
          ? pattern.width
          : (rightNom + (verticalOffsets[rightNom]?[row] ?? 0))
              .clamp(0, pattern.width);
      final topNom = py * config.pageHeight;
      final top = py == 0
          ? 0
          : (topNom + (horizontalOffsets[topNom]?[col] ?? 0))
              .clamp(0, pattern.height);
      final bottomNom = (py + 1) * config.pageHeight;
      final bottom = py >= pagesDown - 1
          ? pattern.height
          : (bottomNom + (horizontalOffsets[bottomNom]?[col] ?? 0))
              .clamp(0, pattern.height);
      return col >= left && col < right && row >= top && row < bottom;
    }

    final Map<int, Set<int>> excludedCells = {};

    if (config.fuzzyAmount > 0) {
      final fa = config.fuzzyAmount;

      for (int py = 0; py < pagesDown; py++) {
        for (int px = 0; px < pagesAcross; px++) {
          final pageIdx = py * pagesAcross + px;

          // The internal corners of this page: where a vertical boundary
          // (cx ∈ [1, pagesAcross-1]) and horizontal boundary
          // (cy ∈ [1, pagesDown-1]) both exist.
          for (int cx = px; cx <= px + 1; cx++) {
            if (cx == 0 || cx >= pagesAcross) continue;
            for (int cy = py; cy <= py + 1; cy++) {
              if (cy == 0 || cy >= pagesDown) continue;

              final bv = cx * config.pageWidth;
              final bh = cy * config.pageHeight;

              // Corner region: cells within fa of both boundaries.
              final cMinC = (bv - fa).clamp(0, pattern.width - 1);
              final cMaxC = (bv + fa - 1).clamp(0, pattern.width - 1);
              final cMinR = (bh - fa).clamp(0, pattern.height - 1);
              final cMaxR = (bh + fa - 1).clamp(0, pattern.height - 1);

              // Collect all cells in the corner region that pass raw boundary.
              final Set<int> regionOnPage = {};
              for (int c = cMinC; c <= cMaxC; c++) {
                for (int r = cMinR; r <= cMaxR; r++) {
                  if (rawOnPage(c, r, px, py)) {
                    regionOnPage.add(_encodeCell(c, r));
                  }
                }
              }
              if (regionOnPage.isEmpty) continue;

              // BFS: seed with region cells that have a non-region neighbour
              // also on the page (i.e., connected to the interior).
              final Set<int> connected = {};
              final List<int> queue = [];

              for (final key in regionOnPage) {
                final c = key >> 16;
                final r = key & 0xFFFF;
                bool isConnected = false;
                for (final d in [
                  (-1, 0), (1, 0), (0, -1), (0, 1)
                ]) {
                  final nc = c + d.$1;
                  final nr = r + d.$2;
                  if (nc < cMinC || nc > cMaxC || nr < cMinR || nr > cMaxR) {
                    // Outside corner region — if it's on the page, this cell
                    // is connected to the interior.
                    if (rawOnPage(nc, nr, px, py)) {
                      isConnected = true;
                      break;
                    }
                  }
                }
                if (isConnected) {
                  connected.add(key);
                  queue.add(key);
                }
              }

              // Flood-fill within the region.
              int qi = 0;
              while (qi < queue.length) {
                final key = queue[qi++];
                final c = key >> 16;
                final r = key & 0xFFFF;
                for (final d in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
                  final nc = c + d.$1;
                  final nr = r + d.$2;
                  final nkey = _encodeCell(nc, nr);
                  if (regionOnPage.contains(nkey) &&
                      !connected.contains(nkey)) {
                    connected.add(nkey);
                    queue.add(nkey);
                  }
                }
              }

              // Any cell on-page in the region but not reached → excluded.
              for (final key in regionOnPage) {
                if (!connected.contains(key)) {
                  excludedCells.putIfAbsent(pageIdx, () => {}).add(key);
                }
              }
            }
          }
        }
      }
    }

    return PageLayout._(
      config: config,
      patternWidth: pattern.width,
      patternHeight: pattern.height,
      pagesAcross: pagesAcross,
      pagesDown: pagesDown,
      verticalOffsets: verticalOffsets,
      horizontalOffsets: horizontalOffsets,
      excludedCells: excludedCells,
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
  /// Strategy:
  ///   1. Scan outward from the nominal boundary for the nearest colour change
  ///      where BOTH sides have a solid run of at least [_minRun] stitches of
  ///      their own colour.  This avoids snapping to stray singleton stitches
  ///      and leaving tiny colour islands at the page edge.
  ///   2. If no qualifying cut is found (the boundary bisects a solid block of
  ///      one colour), fall back to a seeded pseudo-random offset so the edge
  ///      appears organic rather than straight.
  static const int _minRun = 2;

  static int _computeOffset({
    required int nominalBoundary,
    required int crossIndex,
    required int fuzzyAmount,
    required int maxBoundary,
    required String? Function(int primary, int crossIndex) colorAt,
    required int seed,
  }) {
    if (fuzzyAmount == 0) return 0;

    // Returns the length of the run of [color] starting at [start] going in
    // direction [dir] (+1 or -1), capped at [cap].
    int runLength(String color, int start, int dir, int cap) {
      int count = 0;
      int pos = start;
      while (count < cap && pos >= 0 && pos < maxBoundary) {
        if (colorAt(pos, crossIndex) != color) break;
        count++;
        pos += dir;
      }
      return count;
    }

    // Check whether a cut between posA and posB (posB = posA+1) is a
    // "solid-block" transition: both sides have at least _minRun stitches of
    // their own colour.
    bool isQualifyingCut(int posA, int posB) {
      final cA = colorAt(posA, crossIndex);
      final cB = colorAt(posB, crossIndex);
      if (cA == null || cB == null || cA == cB) return false;
      // Verify both sides have a solid run.
      final runA = runLength(cA, posA, -1, _minRun);
      final runB = runLength(cB, posB, 1, _minRun);
      return runA >= _minRun && runB >= _minRun;
    }

    // Scan outward from the nominal boundary, preferring the closest qualifying
    // cut.  Offset d places the boundary between (nominalBoundary+d-1) and
    // (nominalBoundary+d).
    for (int d = 0; d <= fuzzyAmount; d++) {
      // Positive offset (right/below nominal).
      {
        final posA = nominalBoundary + d - 1;
        final posB = nominalBoundary + d;
        if (posA >= 0 && posB < maxBoundary && isQualifyingCut(posA, posB)) {
          return d;
        }
      }
      // Negative offset (left/above nominal); skip d=0 (already covered).
      if (d > 0) {
        final posA = nominalBoundary - d - 1;
        final posB = nominalBoundary - d;
        if (posA >= 0 && posB < maxBoundary && isQualifyingCut(posA, posB)) {
          return -d;
        }
      }
    }

    // No qualifying colour-change cut found — the boundary bisects a solid
    // block.  Apply a seeded random offset so the edge looks organic.
    return math.Random(seed).nextInt(2 * fuzzyAmount + 1) - fuzzyAmount;
  }
}
