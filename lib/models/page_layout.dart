import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'page_config.dart';
import 'pattern.dart';
import '../services/stitch_compositor.dart';

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

  /// Like [cellOnPage] but skips the corner-connectivity exclusion pass.
  ///
  /// Used for progress marking so that edge cells which pass the raw fuzzy
  /// boundary check (and appear on-page visually) can always be marked.
  bool rawCellOnPage(int col, int row, int pageCol, int pageRow) =>
      _boundaryCheck(col, row, pageCol, pageRow);

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

    // Build snap-colour map from the canonical composite view — same thread
    // per cell that the stitcher sees on the canvas (visible layers, blending
    // resolved, topmost layer wins for overlapping FullStitches).
    final composite = StitchCompositor.computeLayer(pattern);
    final threadIndex = <String, int>{
      for (final (i, dmcCode) in pattern.threads.keys.indexed) dmcCode: i,
    };

    // fullStitches is keyed Cell → CompositeStitch; resolvedThread is the winner.
    final Map<int, int?> snapColor = {
      for (final entry in composite.fullStitches.entries)
        (entry.key.x << 16) | entry.key.y: threadIndex[entry.value.resolvedThread.dmcCode],
    };

    int? colorAt(int col, int row) => snapColor[(col << 16) | row];

    // Vertical boundary offsets (column boundaries).
    final Map<int, Map<int, int>> verticalOffsets = {};
    for (int p = 1; p < pagesAcross; p++) {
      final boundaryCol = p * config.pageWidth;
      final Map<int, int> rowOffsets = {};
      for (int row = 0, patternHeight = pattern.height; row < patternHeight; row++) {
        rowOffsets[row] = _computeOffset(
          nominalBoundary: boundaryCol,
          crossIndex: row,
          fuzzyAmount: config.fuzzyAmount,
          maxBoundary: pattern.width,
          maxCross: pattern.height,
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
      for (int col = 0, patternWidth = pattern.width; col < patternWidth; col++) {
        colOffsets[col] = _computeOffset(
          nominalBoundary: boundaryRow,
          crossIndex: col,
          fuzzyAmount: config.fuzzyAmount,
          maxBoundary: pattern.height,
          maxCross: pattern.width,
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
      // Use the same effective range as _computeOffset so the corner region
      // covers all cells that could be shifted by a snap (up to _snapRange).
      final fa = math.max(config.fuzzyAmount, _snapRange);

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

  @visibleForTesting
  static int makeSeed(int pw, int ph, PageConfig config, int extra) =>
      _makeSeed(pw, ph, config, extra);

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
  ///   1. Scan outward up to [_snapRange] stitches for a colour transition
  ///      that does NOT create a colour island.  A cut between posA (colour
  ///      cA) and posB (colour cB) is rejected if:
  ///      • Fast-path ping-pong: color(posA-1)==cB or color(posB+1)==cA
  ///        (single stitch of one colour sandwiched between two runs of the
  ///        other colour).
  ///      • Window island check: within a window of [_snapRange] stitches on
  ///        each side of the proposed cut, any colour whose minority-side
  ///        count is ≤ 2 AND whose majority-side count is ≥ 2× the minority
  ///        is flagged as an island — UNLESS the colour demonstrably
  ///        continues beyond the window on the minority side (i.e. it is a
  ///        large region that merely clips the window, not a thin strip).
  ///      [_snapRange] is always at least [_snapRange] so natural borders a
  ///      few stitches from the nominal line are still reachable.
  ///   2. If no qualifying cut is found (solid block crosses the boundary)
  ///      fall back to a seeded pseudo-random offset within ±[fuzzyAmount].
  @visibleForTesting
  static const int snapRange = 4;
  static const int _snapRange = snapRange;

  /// Minimum vertical run length to accept a colour transition as a
  /// "structural column" candidate, bypassing the 1D qualifying checks.
  static const int _minVerticalRun = 7;

  @visibleForTesting
  static int computeOffset({
    required int nominalBoundary,
    required int crossIndex,
    required int fuzzyAmount,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int crossIndex) colorAt,
    required int seed,
  }) =>
      _computeOffset(
        nominalBoundary: nominalBoundary,
        crossIndex: crossIndex,
        fuzzyAmount: fuzzyAmount,
        maxBoundary: maxBoundary,
        maxCross: maxCross,
        colorAt: colorAt,
        seed: seed,
      );

  static int _computeOffset({
    required int nominalBoundary,
    required int crossIndex,
    required int fuzzyAmount,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int crossIndex) colorAt,
    required int seed,
  }) {
    if (fuzzyAmount == 0) return 0;

    // Returns true if cutting between posA (colour cA) and posB (colour cB)
    // is valid — i.e. it does not create a colour island on either page.
    bool isQualifyingCut(int posA, int posB) {
      final cA = colorAt(posA, crossIndex);
      final cB = colorAt(posB, crossIndex);
      if (cA == null || cB == null || cA == cB) return false;

      // ── Left-run check ─────────────────────────────────────────────────────
      // Require cA to have a run of at least 2 stitches ending at posA.
      // A single isolated stitch at the cut edge belongs with the colour block
      // on the right page — cutting right after it strands it on the left.
      if (posA > 0 && colorAt(posA - 1, crossIndex) != cA) return false;

      // ── Fast-path ping-pong check ───────────────────────────────────────
      // Reject [cB, cA | cB, ...] or [..., cA | cB, cA]: a single stitch of
      // one colour sandwiched between two runs of the other.
      if (posA > 0 && colorAt(posA - 1, crossIndex) == cB) return false;
      if (posB + 1 < maxBoundary && colorAt(posB + 1, crossIndex) == cA) {
        return false;
      }

      // ── Window-based colour-island check ───────────────────────────────
      // Build stitch-count maps for the [_snapRange]-wide window on each side
      // of the proposed cut.  A colour is flagged as an island on one side if:
      //   • its minority-side count is ≤ 2, AND
      //   • the majority-side count is ≥ 2× the minority count, AND
      //   • the colour does NOT continue beyond the window edge on the
      //     minority side (which would indicate a large region merely
      //     clipping the window, not a thin isolated strip).
      const window = _snapRange;
      final leftCounts = <int, int>{};
      final rightCounts = <int, int>{};
      for (int p = math.max(0, posA - window + 1); p <= posA; p++) {
        final c = colorAt(p, crossIndex);
        if (c != null) leftCounts[c] = (leftCounts[c] ?? 0) + 1;
      }
      for (int p = posB; p < math.min(maxBoundary, posB + window); p++) {
        final c = colorAt(p, crossIndex);
        if (c != null) rightCounts[c] = (rightCounts[c] ?? 0) + 1;
      }

      for (final c in {...leftCounts.keys, ...rightCounts.keys}) {
        final l = leftCounts[c] ?? 0;
        final r = rightCounts[c] ?? 0;
        if (l == 0 || r == 0) continue; // colour is only on one side, fine
        final minority = l <= r ? l : r;
        final majority = l <= r ? r : l;
        if (minority > 2 || majority < minority * 2) continue;
        // Potential island — check whether the minority region extends
        // beyond the window (large region clipping the window → not an island).
        if (l <= r) {
          // Minority is on the left: check just beyond the left window edge.
          final beyond = posA - window;
          if (beyond >= 0 && colorAt(beyond, crossIndex) == c) continue;
        } else {
          // Minority is on the right: check just beyond the right window edge.
          final beyond = posB + window;
          if (beyond < maxBoundary && colorAt(beyond, crossIndex) == c) {
            continue;
          }
        }
        return false; // colour island detected — reject this cut position
      }

      // ── Extended-scan colour-split check ─────────────────────────────────
      // If a colour has a small presence on one side of the cut but does NOT
      // appear in the immediate window on the other side, scan one extra
      // window-width further to see if it reappears.  If it does, the cut is
      // splitting a colour block whose "other half" lies just beyond the search
      // window, leaving a few stitches of that colour stranded on the wrong
      // page (e.g. 2 blue stitches on the left, then 4 white, then 3 more
      // blue to the right — cutting at the blue/white boundary is wrong).
      //
      // Guard: if the colour ALSO appears beyond the left window (further left),
      // it is a regularly-repeating structural element (outline, separator) and
      // should NOT be treated as a block split.
      for (final c in leftCounts.keys) {
        if (rightCounts.containsKey(c)) continue; // handled above
        if ((leftCounts[c] ?? 0) > 2) continue;   // large block, not an island
        // If this colour already appeared further left, it's a repeating element.
        // Scan 3× window to handle patterns whose period is up to 2× window wide.
        bool repeatsLeft = false;
        for (int p = posA - window; p >= math.max(0, posA - 3 * window); p--) {
          if (colorAt(p, crossIndex) == c) { repeatsLeft = true; break; }
        }
        if (repeatsLeft) continue;
        // Otherwise check if it reappears to the right beyond the window.
        final extEnd = math.min(maxBoundary, posB + 2 * window);
        for (int p = posB + window; p < extEnd; p++) {
          if (colorAt(p, crossIndex) == c) return false;
        }
      }
      for (final c in rightCounts.keys) {
        if (leftCounts.containsKey(c)) continue; // handled above
        if ((rightCounts[c] ?? 0) > 2) continue;
        // Symmetric: scan 3× window to handle wide repeating patterns.
        bool repeatsRight = false;
        for (int p = posB + window; p < math.min(maxBoundary, posB + 3 * window); p++) {
          if (colorAt(p, crossIndex) == c) { repeatsRight = true; break; }
        }
        if (repeatsRight) continue;
        // Check if it reappears to the left beyond the window.
        final extStart = math.max(0, posA - 2 * window + 1);
        for (int p = posA - window; p >= extStart; p--) {
          if (colorAt(p, crossIndex) == c) return false;
        }
      }

      return true;
    }

    // Scan outward, collecting qualifying cuts and vertical-column candidates,
    // scoring with 2D flood penalty, vertical coherence, and distance.
    //
    // Composite score (lower = better):
    //   penalty * 1000          — stranding dominates
    //   − min(vExt, 10) * 2    — vertical column bonus (each row of vExt offsets 2 distance units)
    //   + distance              — prefer closer to nominal
    final effectiveRange = math.max(fuzzyAmount, _snapRange);
    int? bestOffset;
    int bestScore = 0x7FFFFFFF;

    void considerCandidate(int offset, int posA, int posB, int dist) {
      final cA = colorAt(posA, crossIndex)!;
      final penalty = _floodPenalty(
          posA, posB, crossIndex, maxBoundary, maxCross, colorAt);
      final vExt = _verticalRun(posA, crossIndex, cA, maxCross, colorAt);
      final score = penalty * 1000 - math.min(vExt, 10) * 2 + dist;
      if (score < bestScore) {
        bestOffset = offset;
        bestScore = score;
      }
    }

    for (int d = 0; d <= effectiveRange; d++) {
      // Positive offset (right/below nominal).
      {
        final posA = nominalBoundary + d - 1;
        final posB = nominalBoundary + d;
        if (posA >= 0 && posB < maxBoundary) {
          final cA = colorAt(posA, crossIndex);
          final cB = colorAt(posB, crossIndex);
          if (cA != null && cB != null && cA != cB) {
            // Accept if 1D-qualifying OR cA has vertical column support.
            if (isQualifyingCut(posA, posB) ||
                _verticalRun(posA, crossIndex, cA, maxCross, colorAt) >=
                    _minVerticalRun) {
              considerCandidate(d, posA, posB, d);
            }
          }
        }
      }
      // Negative offset (left/above nominal); skip d=0 (already covered above).
      if (d > 0) {
        final posA = nominalBoundary - d - 1;
        final posB = nominalBoundary - d;
        if (posA >= 0 && posB < maxBoundary) {
          final cA = colorAt(posA, crossIndex);
          final cB = colorAt(posB, crossIndex);
          if (cA != null && cB != null && cA != cB) {
            if (isQualifyingCut(posA, posB) ||
                _verticalRun(posA, crossIndex, cA, maxCross, colorAt) >=
                    _minVerticalRun) {
              considerCandidate(-d, posA, posB, d);
            }
          }
        }
      }
    }

    final result = bestOffset;
    if (result != null) return result;

    // No qualifying cut found — boundary bisects a solid block.
    // Apply a seeded random offset within ±fuzzyAmount for an organic edge.
    return math.Random(seed).nextInt(2 * fuzzyAmount + 1) - fuzzyAmount;
  }

  /// Total stranding penalty for cutting between [posA] and [posB].
  /// Floods each colour in 2D and counts cells that would end up on the
  /// wrong side of the cut. Lower = better.
  static int _floodPenalty(
    int posA,
    int posB,
    int crossIndex,
    int maxBoundary,
    int maxCross,
    int? Function(int primary, int cross) colorAt,
  ) {
    final cA = colorAt(posA, crossIndex);
    final cB = colorAt(posB, crossIndex);
    if (cA == null || cB == null) return 0;

    // cA lives on the left page (primary < posB). Count cA cells at >= posB.
    final strandedA = _floodStrandedCount(
      posA, crossIndex, cA, posB, true, maxBoundary, maxCross, colorAt);
    // cB lives on the right page (primary >= posB). Count cB cells at < posB.
    final strandedB = _floodStrandedCount(
      posB, crossIndex, cB, posB, false, maxBoundary, maxCross, colorAt);

    return strandedA + strandedB;
  }

  /// BFS flood from ([startP], [startC]) following [targetColor].
  /// Returns the count of visited cells on the "wrong" side of [cutBoundary]:
  ///   [wrongSideIsRight] true  → count cells at primary >= cutBoundary
  ///   [wrongSideIsRight] false → count cells at primary <  cutBoundary
  ///
  /// Bounded to ±[_snapRange] in both axes from the start cell, max 40 cells.
  static int _floodStrandedCount(
    int startP,
    int startC,
    int targetColor,
    int cutBoundary,
    bool wrongSideIsRight,
    int maxBoundary,
    int maxCross,
    int? Function(int primary, int cross) colorAt,
  ) {
    const maxCells = 40;

    final visited = <int>{};
    final queue = <int>[];
    final startKey = (startP << 16) | startC;
    visited.add(startKey);
    queue.add(startKey);

    int count = 0;
    int qi = 0;

    while (qi < queue.length && visited.length <= maxCells) {
      final key = queue[qi++];
      final p = key >> 16;
      final c = key & 0xFFFF;

      if (wrongSideIsRight ? (p >= cutBoundary) : (p < cutBoundary)) {
        count++;
      }

      for (final (dp, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final np = p + dp;
        final nc = c + dc;
        if (np < 0 || np >= maxBoundary || nc < 0 || nc >= maxCross) continue;
        if ((np - startP).abs() > _snapRange) continue;
        if ((nc - startC).abs() > _snapRange) continue;
        final nkey = (np << 16) | nc;
        if (visited.contains(nkey)) continue;
        if (colorAt(np, nc) != targetColor) continue;
        visited.add(nkey);
        queue.add(nkey);
      }
    }

    return count;
  }

  /// Vertical run length of [color] at primary position [pos], centred on
  /// [crossIndex]. Returns 1 if only the cell itself matches. Capped at 10.
  static int _verticalRun(
    int pos,
    int crossIndex,
    int color,
    int maxCross,
    int? Function(int primary, int cross) colorAt,
  ) {
    int run = 1;
    for (int r = crossIndex - 1; r >= 0 && colorAt(pos, r) == color; r--) {
      if (++run >= 10) return run;
    }
    for (int r = crossIndex + 1;
        r < maxCross && colorAt(pos, r) == color;
        r++) {
      if (++run >= 10) return run;
    }
    return run;
  }
}
