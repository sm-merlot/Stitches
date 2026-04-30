import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'page_config.dart';
import '../pattern.dart';
import '../../services/stitch_compositor.dart';

/// Precomputed page layout derived from a [PageConfig] and the pattern's stitch
/// data. Not persisted — recomputed whenever page config changes.
///
/// Boundaries are computed via a four-phase object-aware algorithm:
///   1. Object detection   — 8-directional flood-fill on same-colour cells
///   2. Adjacent grouping  — objects within 1-cell gap form super-groups
///   3. Boundary decision  — keep-whole vs split per super-group
///   4. Smooth-edge DP     — globally smooth per-row offsets (±2 max step)
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
  /// that removes any island groups disconnected from the page interior.
  bool cellOnPage(int col, int row, int pageCol, int pageRow) {
    if (!_boundaryCheck(col, row, pageCol, pageRow)) return false;
    final excluded = _excludedCells[pageRow * pagesAcross + pageCol];
    return excluded == null || !excluded.contains(_encodeCell(col, row));
  }

  /// Like [cellOnPage] but skips the corner-connectivity exclusion pass.
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

  // ── Phase 1: Object detection ──────────────────────────────────────────────

  /// 8-directional flood-fill: returns objectId → Set of (col, row) cells.
  /// Each object is a contiguous group of same-colour stitched cells.
  /// [snapColor] is keyed by encoded cell (col<<16|row) → colour index (null = empty).
  static Map<int, Set<(int, int)>> _detectObjects(
    Map<int, int?> snapColor,
    int width,
    int height,
  ) {
    final visited = <int>{};
    final objects = <int, Set<(int, int)>>{};
    int nextId = 0;

    for (int col = 0; col < width; col++) {
      for (int row = 0; row < height; row++) {
        final key = (col << 16) | row;
        if (visited.contains(key)) continue;
        visited.add(key);
        final color = snapColor[key];
        if (color == null) continue;

        // BFS 8-directional flood fill
        final cells = <(int, int)>{};
        final queue = [key];
        int qi = 0;
        while (qi < queue.length) {
          final k = queue[qi++];
          final c = k >> 16;
          final r = k & 0xFFFF;
          cells.add((c, r));
          for (final (dc, dr) in const [
            (-1, -1), (-1, 0), (-1, 1),
            (0, -1),           (0, 1),
            (1, -1),  (1, 0),  (1, 1),
          ]) {
            final nc = c + dc;
            final nr = r + dr;
            if (nc < 0 || nc >= width || nr < 0 || nr >= height) continue;
            final nk = (nc << 16) | nr;
            if (visited.contains(nk)) continue;
            if (snapColor[nk] != color) continue;
            visited.add(nk);
            queue.add(nk);
          }
        }
        objects[nextId++] = cells;
      }
    }
    return objects;
  }

  // ── Phase 2: Adjacent grouping (union-find) ────────────────────────────────

  /// Merges objects within 1-cell gap (Chebyshev distance ≤ 2) into
  /// super-groups via union-find. Returns superGroupId → Set of (col, row).
  static Map<int, Set<(int, int)>> _buildSuperGroups(
    Map<int, Set<(int, int)>> objects,
    int width,
    int height,
  ) {
    if (objects.isEmpty) return {};

    // Build cell → objectId for fast lookup
    final cellToObj = <int, int>{};
    for (final entry in objects.entries) {
      for (final (c, r) in entry.value) {
        cellToObj[(c << 16) | r] = entry.key;
      }
    }

    // Union-Find with path compression
    final parent = <int, int>{};
    for (final id in objects.keys) {
      parent[id] = id;
    }

    int find(int id) {
      var root = id;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      var cur = id;
      while (cur != root) {
        final next = parent[cur]!;
        parent[cur] = root;
        cur = next;
      }
      return root;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    // Two objects merge if their cells are within Chebyshev distance 2
    // (equivalent to "expand each object by 1, check set overlap").
    for (final entry in objects.entries) {
      final objId = entry.key;
      for (final (c, r) in entry.value) {
        for (int dc = -2; dc <= 2; dc++) {
          for (int dr = -2; dr <= 2; dr++) {
            if (dc == 0 && dr == 0) continue;
            final nc = c + dc;
            final nr = r + dr;
            if (nc < 0 || nc >= width || nr < 0 || nr >= height) continue;
            final neighborObj = cellToObj[(nc << 16) | nr];
            if (neighborObj != null && neighborObj != objId) {
              union(objId, neighborObj);
            }
          }
        }
      }
    }

    // Collect into super-groups
    final superGroups = <int, Set<(int, int)>>{};
    for (final entry in objects.entries) {
      final root = find(entry.key);
      superGroups.putIfAbsent(root, () => {}).addAll(entry.value);
    }
    return superGroups;
  }

  // ── Phase 3+4: Smooth-edge DP ─────────────────────────────────────────────

  // Window size for the qualifying-cut check (fixed scan range).
  static const int _snapRange = 4;

  /// Compute all boundary offsets for one boundary (vertical or horizontal)
  /// using the object-aware smooth-edge DP.
  ///
  /// [colorAt] semantics: `colorAt(primary, crossIndex)`.
  ///   Vertical boundary: primary = col, crossIndex = row.
  ///   Horizontal boundary: primary = row, crossIndex = col (caller transposes).
  ///
  /// [superGroups] must be in (primary, cross) space (caller transposes for
  /// horizontal boundaries).
  ///
  /// Returns: Map from crossIndex → offset delta (clamped to ±[tolerance]).
  static Map<int, int> _computeBoundaryOffsets({
    required int nominalBoundary,
    required int tolerance,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
    required Map<int, Set<(int, int)>> superGroups,
  }) {
    if (tolerance == 0) {
      return {for (int i = 0; i < maxCross; i++) i: 0};
    }

    // ── Phase 3: Classify super-groups ────────────────────────────────────────
    // Groups with bleedCells <= tolerance on the minority side → keep whole.
    // Represented as: cross → sorted list of primary positions for penalty calc.

    // keepWholeLeft: groups to keep entirely LEFT of boundary (primary < actual)
    //   Penalty: cells at primary >= actual boundary → on wrong side
    // keepWholeRight: groups to keep entirely RIGHT of boundary (primary >= actual)
    //   Penalty: cells at primary < actual boundary → on wrong side
    final keepWholeLeft = <Map<int, List<int>>>[];
    final keepWholeRight = <Map<int, List<int>>>[];

    for (final groupCells in superGroups.values) {
      // Collect distinct primary positions on each side.
      // 'tolerance' is measured in primary-axis units (columns for vertical
      // boundaries, rows for horizontal), NOT in total cell count. This ensures
      // a 1-row × 50-column bleed has depth=1, not depth=50.
      final leftPrimaries = <int>{};
      final rightPrimaries = <int>{};
      int countLeft = 0, countRight = 0;
      for (final (p, _) in groupCells) {
        if (p < nominalBoundary) {
          leftPrimaries.add(p);
          countLeft++;
        } else {
          rightPrimaries.add(p);
          countRight++;
        }
      }

      if (leftPrimaries.isEmpty || rightPrimaries.isEmpty) continue;

      // Bleed depth = how many primary-axis steps does the minority cross?
      //   Majority left  → minority right: depth = max(right) − nominal + 1
      //   Majority right → minority left:  depth = nominal − min(left)
      final keepOnLeft = countLeft >= countRight;
      final bleedDepth = keepOnLeft
          ? rightPrimaries.reduce(math.max) - nominalBoundary + 1
          : nominalBoundary - leftPrimaries.reduce(math.min);

      if (bleedDepth <= tolerance) {
        // Small bleed — keep entire object whole on majority side.
        final Map<int, List<int>> byCross = {};
        for (final (p, c) in groupCells) {
          byCross.putIfAbsent(c, () => []).add(p);
        }
        if (keepOnLeft) {
          keepWholeLeft.add(byCross);
        } else {
          keepWholeRight.add(byCross);
        }
        continue;
      }

      // Object too large to keep whole (e.g. black outlines spanning the
      // pattern). Split the minority-side cells into connected sub-groups
      // and evaluate each independently — small tendrils crossing the
      // boundary get keep-whole treatment even though the parent is huge.
      final minorityCells = <(int, int)>{};
      for (final (p, c) in groupCells) {
        if (keepOnLeft ? p >= nominalBoundary : p < nominalBoundary) {
          minorityCells.add((p, c));
        }
      }

      final visitedMinority = <(int, int)>{};
      for (final seed in minorityCells) {
        if (visitedMinority.contains(seed)) continue;
        // BFS flood-fill within minority cells to find connected sub-group.
        final component = <(int, int)>{};
        final queue = [seed];
        visitedMinority.add(seed);
        int qi = 0;
        while (qi < queue.length) {
          final (p, c) = queue[qi++];
          component.add((p, c));
          for (final (dp, dc) in const [
            (-1, -1), (-1, 0), (-1, 1),
            (0, -1),           (0, 1),
            (1, -1),  (1, 0),  (1, 1),
          ]) {
            final neighbor = (p + dp, c + dc);
            if (minorityCells.contains(neighbor) &&
                !visitedMinority.contains(neighbor)) {
              visitedMinority.add(neighbor);
              queue.add(neighbor);
            }
          }
        }

        // Compute bleed depth of this sub-group.
        final subBleedDepth = keepOnLeft
            ? component.map((e) => e.$1).reduce(math.max) -
                nominalBoundary +
                1
            : nominalBoundary -
                component.map((e) => e.$1).reduce(math.min);

        if (subBleedDepth > tolerance) continue; // sub-group too deep

        // Pull this sub-group to the majority side.
        final Map<int, List<int>> byCross = {};
        for (final (p, c) in component) {
          byCross.putIfAbsent(c, () => []).add(p);
        }
        if (keepOnLeft) {
          keepWholeLeft.add(byCross);
        } else {
          keepWholeRight.add(byCross);
        }
      }
    }

    // ── Phase 4: Smooth-edge DP ───────────────────────────────────────────────
    // dp[offsetIdx] = min cost at current cross-index with this offset.
    // offsetIdx → delta: offsetIdx - tolerance.
    // Smoothness constraint: |delta[ci] - delta[ci-1]| <= 2.

    final T = tolerance;
    final numOffsets = 2 * T + 1;
    const infinity = 1 << 30;

    // Precompute cost at each (crossIdx, offsetIdx).
    // Stored in a matrix for backtracking; fills on demand.
    int computeCost(int crossIdx, int offsetIdx) {
      final delta = offsetIdx - T;
      final actual = nominalBoundary + delta;

      // Keep-whole penalty: 1000 per cell on the wrong side (dominant)
      int cost = 0;
      for (final byCross in keepWholeLeft) {
        final primaries = byCross[crossIdx];
        if (primaries == null) continue;
        for (final p in primaries) {
          if (p >= actual) cost += 1000;
        }
      }
      for (final byCross in keepWholeRight) {
        final primaries = byCross[crossIdx];
        if (primaries == null) continue;
        for (final p in primaries) {
          if (p < actual) cost += 1000;
        }
      }

      // Distance: pull toward nominal; keeps fuzz close without a strong signal.
      cost += delta.abs() * 2;

      // Colour-change split: strong bonus for cutting at a clean colour
      // transition — second priority after keep-whole objects.
      final posA = actual - 1;
      final posB = actual;
      if (posA >= 0 && posB < maxBoundary) {
        if (_isQualifyingCut(posA, posB, crossIdx, maxBoundary, colorAt)) {
          cost -= 20;
        }
        // Gentle fuzz: small vertical-coherence bonus; creates slight bumps
        // when no colour change or object signal is present. Capped low so
        // it never overrides colour-change decisions.
        final cA = colorAt(posA, crossIdx);
        if (cA != null) {
          cost -= math.min(_verticalRun(posA, crossIdx, cA, maxCross, colorAt), 3);
        }
      }

      return cost;
    }

    // Rolling DP arrays (reuse to avoid allocations)
    var prev = List<int>.filled(numOffsets, 0);
    var curr = List<int>.filled(numOffsets, 0);

    // Backtrack table: backtrack[crossIdx][offsetIdx] = best prevOffsetIdx
    final backtrack =
        List.generate(maxCross, (_) => List<int>.filled(numOffsets, 0));

    // Initialise first cross-index (no transition cost)
    for (int oi = 0; oi < numOffsets; oi++) {
      prev[oi] = computeCost(0, oi);
      backtrack[0][oi] = oi; // sentinel; unused during final backtrack
    }

    // Fill DP
    for (int ci = 1; ci < maxCross; ci++) {
      for (int oi = 0; oi < numOffsets; oi++) {
        final delta = oi - T;
        int best = infinity;
        int bestPrev = oi;

        for (int poi = 0; poi < numOffsets; poi++) {
          final step = (delta - (poi - T)).abs();
          if (step > 2) continue; // smoothness constraint
          // Inertia: penalise offset changes so the boundary follows
          // colour-change lines straight instead of jittering.
          final candidate = prev[poi] + step * 12;
          if (candidate < best) {
            best = candidate;
            bestPrev = poi;
          }
        }

        curr[oi] = (best < infinity ? best : infinity) + computeCost(ci, oi);
        backtrack[ci][oi] = bestPrev;
      }
      // Swap rolling buffers
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    // Find best final offset (prev now holds costs for ci = maxCross-1)
    int bestFinalOi = 0;
    for (int oi = 1; oi < numOffsets; oi++) {
      if (prev[oi] < prev[bestFinalOi]) bestFinalOi = oi;
    }

    // Backtrack to recover per-cross-index offsets
    final result = <int, int>{};
    int oi = bestFinalOi;
    for (int ci = maxCross - 1; ci >= 0; ci--) {
      result[ci] = oi - T;
      oi = backtrack[ci][oi];
    }

    return result;
  }

  // ── Qualifying-cut helpers ─────────────────────────────────────────────────

  /// Returns true if cutting between [posA] and [posB] at [crossIndex] is a
  /// clean colour transition that does not create colour islands.
  static bool _isQualifyingCut(
    int posA,
    int posB,
    int crossIndex,
    int maxBoundary,
    int? Function(int primary, int cross) colorAt,
  ) {
    final cA = colorAt(posA, crossIndex);
    final cB = colorAt(posB, crossIndex);
    if (cA == null || cB == null || cA == cB) return false;

    // Left-run check: cA must have ≥ 2 stitches ending at posA.
    if (posA > 0 && colorAt(posA - 1, crossIndex) != cA) return false;

    // Fast-path ping-pong: single-stitch sandwich → reject.
    if (posA > 0 && colorAt(posA - 1, crossIndex) == cB) return false;
    if (posB + 1 < maxBoundary && colorAt(posB + 1, crossIndex) == cA) {
      return false;
    }

    // Window-based colour-island check.
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
      if (l == 0 || r == 0) continue;
      final minority = l <= r ? l : r;
      final majority = l <= r ? r : l;
      if (minority > 2 || majority < minority * 2) continue;
      if (l <= r) {
        final beyond = posA - window;
        if (beyond >= 0 && colorAt(beyond, crossIndex) == c) continue;
      } else {
        final beyond = posB + window;
        if (beyond < maxBoundary && colorAt(beyond, crossIndex) == c) continue;
      }
      return false;
    }

    // Extended-scan colour-split check.
    for (final c in leftCounts.keys) {
      if (rightCounts.containsKey(c)) continue;
      if ((leftCounts[c] ?? 0) > 2) continue;
      bool repeatsLeft = false;
      for (int p = posA - window; p >= math.max(0, posA - 3 * window); p--) {
        if (colorAt(p, crossIndex) == c) {
          repeatsLeft = true;
          break;
        }
      }
      if (repeatsLeft) continue;
      final extEnd = math.min(maxBoundary, posB + 2 * window);
      for (int p = posB + window; p < extEnd; p++) {
        if (colorAt(p, crossIndex) == c) return false;
      }
    }
    for (final c in rightCounts.keys) {
      if (leftCounts.containsKey(c)) continue;
      if ((rightCounts[c] ?? 0) > 2) continue;
      bool repeatsRight = false;
      for (int p = posB + window;
          p < math.min(maxBoundary, posB + 3 * window);
          p++) {
        if (colorAt(p, crossIndex) == c) {
          repeatsRight = true;
          break;
        }
      }
      if (repeatsRight) continue;
      final extStart = math.max(0, posA - 2 * window + 1);
      for (int p = posA - window; p >= extStart; p--) {
        if (colorAt(p, crossIndex) == c) return false;
      }
    }

    return true;
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

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Build a [PageLayout] from [config] and the pattern's current stitch data.
  ///
  /// Boundary offsets are computed once and cached in the returned [PageLayout].
  static PageLayout compute(PageConfig config, CrossStitchPattern pattern) {
    final pagesAcross =
        (pattern.width / config.pageWidth).ceil().clamp(1, pattern.width);
    final pagesDown =
        (pattern.height / config.pageHeight).ceil().clamp(1, pattern.height);

    // Build snap-colour map from the canonical composite view.
    final composite = StitchCompositor.computeComposite(pattern);
    final threadIndex = <String, int>{
      for (final (i, dmcCode) in pattern.threads.keys.indexed) dmcCode: i,
    };

    final Map<int, int?> snapColor = {
      for (final entry in composite.fullStitches.entries)
        (entry.key.x << 16) | entry.key.y:
            threadIndex[entry.value.resolvedThread.dmcCode],
    };

    int? colorAt(int col, int row) => snapColor[(col << 16) | row];

    // Phase 1: Detect individual objects (contiguous same-colour regions).
    // These are used directly for keep-whole classification. Super-groups
    // (Phase 2) are intentionally NOT used here because union-find chaining
    // merges objects transitively into mega-groups that always exceed the
    // tolerance threshold, effectively disabling keep-whole.
    final objects = _detectObjects(snapColor, pattern.width, pattern.height);

    // Transposed objects for horizontal boundaries:
    // (primary=row, cross=col) instead of (primary=col, cross=row).
    final objectsT = <int, Set<(int, int)>>{
      for (final e in objects.entries)
        e.key: e.value.map<(int, int)>((cr) => (cr.$2, cr.$1)).toSet(),
    };

    // Vertical boundary offsets (column boundaries).
    final Map<int, Map<int, int>> verticalOffsets = {};
    for (int p = 1; p < pagesAcross; p++) {
      final boundaryCol = p * config.pageWidth;
      verticalOffsets[boundaryCol] = _computeBoundaryOffsets(
        nominalBoundary: boundaryCol,
        tolerance: config.tolerance,
        maxBoundary: pattern.width,
        maxCross: pattern.height,
        colorAt: (primary, cross) => colorAt(primary, cross),
        superGroups: objects,
      );
    }

    // Horizontal boundary offsets (row boundaries).
    final Map<int, Map<int, int>> horizontalOffsets = {};
    for (int p = 1; p < pagesDown; p++) {
      final boundaryRow = p * config.pageHeight;
      horizontalOffsets[boundaryRow] = _computeBoundaryOffsets(
        nominalBoundary: boundaryRow,
        tolerance: config.tolerance,
        maxBoundary: pattern.height,
        maxCross: pattern.width,
        colorAt: (primary, cross) => colorAt(cross, primary),
        superGroups: objectsT,
      );
    }

    // ── Corner connectivity post-pass ────────────────────────────────────────
    // Vertical and horizontal offsets are computed independently; at corners
    // they can create isolated cell groups disconnected from the page interior.
    // Flood-fill from interior-connected cells and exclude any unreachable ones.

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

    if (config.tolerance > 0) {
      final fa = config.tolerance;

      for (int py = 0; py < pagesDown; py++) {
        for (int px = 0; px < pagesAcross; px++) {
          final pageIdx = py * pagesAcross + px;

          for (int cx = px; cx <= px + 1; cx++) {
            if (cx == 0 || cx >= pagesAcross) continue;
            for (int cy = py; cy <= py + 1; cy++) {
              if (cy == 0 || cy >= pagesDown) continue;

              final bv = cx * config.pageWidth;
              final bh = cy * config.pageHeight;

              final cMinC = (bv - fa).clamp(0, pattern.width - 1);
              final cMaxC = (bv + fa - 1).clamp(0, pattern.width - 1);
              final cMinR = (bh - fa).clamp(0, pattern.height - 1);
              final cMaxR = (bh + fa - 1).clamp(0, pattern.height - 1);

              final Set<int> regionOnPage = {};
              for (int c = cMinC; c <= cMaxC; c++) {
                for (int r = cMinR; r <= cMaxR; r++) {
                  if (rawOnPage(c, r, px, py)) {
                    regionOnPage.add(_encodeCell(c, r));
                  }
                }
              }
              if (regionOnPage.isEmpty) continue;

              final Set<int> connected = {};
              final List<int> queue = [];

              for (final key in regionOnPage) {
                final c = key >> 16;
                final r = key & 0xFFFF;
                bool isConnected = false;
                for (final d in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
                  final nc = c + d.$1;
                  final nr = r + d.$2;
                  if (nc < cMinC || nc > cMaxC || nr < cMinR || nr > cMaxR) {
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

  // ── Test-visible helpers ──────────────────────────────────────────────────

  @visibleForTesting
  static Map<int, Set<(int, int)>> detectObjects(
    Map<int, int?> snapColor,
    int width,
    int height,
  ) =>
      _detectObjects(snapColor, width, height);

  @visibleForTesting
  static Map<int, Set<(int, int)>> buildSuperGroups(
    Map<int, Set<(int, int)>> objects,
    int width,
    int height,
  ) =>
      _buildSuperGroups(objects, width, height);

  @visibleForTesting
  static Map<int, int> computeBoundaryOffsets({
    required int nominalBoundary,
    required int tolerance,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
    required Map<int, Set<(int, int)>> superGroups,
  }) =>
      _computeBoundaryOffsets(
        nominalBoundary: nominalBoundary,
        tolerance: tolerance,
        maxBoundary: maxBoundary,
        maxCross: maxCross,
        colorAt: colorAt,
        superGroups: superGroups,
      );

  @visibleForTesting
  static bool isQualifyingCut(
    int posA,
    int posB,
    int crossIndex,
    int maxBoundary,
    int? Function(int primary, int cross) colorAt,
  ) =>
      _isQualifyingCut(posA, posB, crossIndex, maxBoundary, colorAt);
}
