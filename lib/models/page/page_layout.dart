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

  /// page index → set of encoded cell keys that belong to this page despite
  /// failing the primary boundary check. Used when two objects at the same
  /// cross-index need opposite boundary adjustments — both objects' cells are
  /// kept whole by including the conflicting cells on the appropriate page.
  final Map<int, Set<int>> _includedCells;

  PageLayout._({
    required this.config,
    required this.patternWidth,
    required this.patternHeight,
    required this.pagesAcross,
    required this.pagesDown,
    required this.verticalOffsets,
    required this.horizontalOffsets,
    required Map<int, Set<int>> excludedCells,
    required Map<int, Set<int>> includedCells,
  })  : _excludedCells = excludedCells,
        _includedCells = includedCells;

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
    final pageIdx = pageRow * pagesAcross + pageCol;
    final key = _encodeCell(col, row);

    // Explicit inclusion overrides boundary check (multi-crossing support).
    final included = _includedCells[pageIdx];
    if (included != null && included.contains(key)) return true;

    if (!_boundaryCheck(col, row, pageCol, pageRow)) return false;
    final excluded = _excludedCells[pageIdx];
    return excluded == null || !excluded.contains(key);
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

  // ── Band-local analysis (v2) ──────────────────────────────────────────────

  /// Minimum object size (cells) for a colour transition to qualify as an
  /// anchor point. Exposed as a named constant for easy tuning.
  static const int kMinAnchorSize = 8;

  /// Extract band cells: all stitched cells within
  /// [nominal−tolerance, nominal+tolerance) along the primary axis.
  ///
  /// Returns encoded cell → colour index (null-colour cells omitted).
  static Map<int, int> _extractBand({
    required int nominalBoundary,
    required int tolerance,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
  }) {
    final bandMin = (nominalBoundary - tolerance).clamp(0, maxBoundary);
    final bandMax = (nominalBoundary + tolerance).clamp(0, maxBoundary);
    final band = <int, int>{};
    for (int p = bandMin; p < bandMax; p++) {
      for (int c = 0; c < maxCross; c++) {
        final color = colorAt(p, c);
        if (color != null) {
          band[(p << 16) | c] = color;
        }
      }
    }
    return band;
  }

  /// Band min/max primary coordinate for a given boundary.
  static (int, int) _bandBounds(int nominal, int tolerance, int maxBoundary) => (
        (nominal - tolerance).clamp(0, maxBoundary),
        (nominal + tolerance).clamp(0, maxBoundary),
      );

  /// 8-directional flood-fill within a set of band cells.
  /// Returns objectId → Set of (primary, cross) cells.
  ///
  /// Unlike [_detectObjects], this iterates only over the provided cells rather
  /// than a full grid — objects that extend outside the band are naturally
  /// clipped at band edges.
  static Map<int, Set<(int, int)>> _detectLocalObjects(
    Map<int, int> bandColors,
  ) {
    final visited = <int>{};
    final objects = <int, Set<(int, int)>>{};
    int nextId = 0;

    for (final entry in bandColors.entries) {
      final key = entry.key;
      if (visited.contains(key)) continue;
      visited.add(key);
      final color = entry.value;

      final cells = <(int, int)>{};
      final queue = [key];
      int qi = 0;
      while (qi < queue.length) {
        final k = queue[qi++];
        final p = k >> 16;
        final c = k & 0xFFFF;
        cells.add((p, c));
        for (final (dp, dc) in const [
          (-1, -1), (-1, 0), (-1, 1),
          (0, -1),           (0, 1),
          (1, -1),  (1, 0),  (1, 1),
        ]) {
          final nk = ((p + dp) << 16) | (c + dc);
          if (visited.contains(nk)) continue;
          if (bandColors[nk] != color) continue;
          visited.add(nk);
          queue.add(nk);
        }
      }
      objects[nextId++] = cells;
    }
    return objects;
  }

  /// Same-colour proximity grouping within band. Objects of the same colour
  /// within Chebyshev distance ≤ 2 (1-cell gap) are merged into clusters.
  ///
  /// Different-colour objects remain separate — their boundary is a potential
  /// anchor point for cut placement, not a merge point.
  static Map<int, Set<(int, int)>> _buildLocalClusters(
    Map<int, Set<(int, int)>> localObjects,
    Map<int, int> bandColors,
  ) {
    if (localObjects.isEmpty) return {};

    // Build cell → objectId lookup
    final cellToObj = <int, int>{};
    for (final entry in localObjects.entries) {
      for (final (p, c) in entry.value) {
        cellToObj[(p << 16) | c] = entry.key;
      }
    }

    // Determine colour of each object (all cells same colour by construction)
    final objColor = <int, int>{};
    for (final entry in localObjects.entries) {
      final (p, c) = entry.value.first;
      objColor[entry.key] = bandColors[(p << 16) | c]!;
    }

    // Union-Find with path compression
    final parent = <int, int>{for (final id in localObjects.keys) id: id};

    int find(int id) {
      var root = id;
      while (parent[root] != root) root = parent[root]!;
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

    // Merge same-colour objects within Chebyshev distance ≤ 2
    for (final entry in localObjects.entries) {
      final objId = entry.key;
      final color = objColor[objId];
      for (final (p, c) in entry.value) {
        for (int dp = -2; dp <= 2; dp++) {
          for (int dc = -2; dc <= 2; dc++) {
            if (dp == 0 && dc == 0) continue;
            final nk = ((p + dp) << 16) | (c + dc);
            final neighborObj = cellToObj[nk];
            if (neighborObj != null &&
                neighborObj != objId &&
                objColor[neighborObj] == color) {
              union(objId, neighborObj);
            }
          }
        }
      }
    }

    // Collect into clusters
    final clusters = <int, Set<(int, int)>>{};
    for (final entry in localObjects.entries) {
      final root = find(entry.key);
      clusters.putIfAbsent(root, () => {}).addAll(entry.value);
    }
    return clusters;
  }

  /// Classification result for a cluster relative to a page boundary.
  ///
  /// - [noOp]: entirely on one side of nominal — no action needed.
  /// - [keepWhole]: spans boundary but fits within band — keep intact.
  /// - [keepLeft]: extends beyond band on left/top only — keep on left side.
  /// - [keepRight]: extends beyond band on right/bottom only — keep on right.
  /// - [tooBig]: extends beyond band on both sides — must split.
  static const int _clNoOp = 0;
  static const int _clKeepWhole = 1;
  static const int _clTooBig = 2;

  /// Max steps keep-whole can shift from the interpolated offset at any cross.
  /// Beyond this cap, cells are added to override sets instead.
  static const int _kMaxKeepWholeStep = 2;
  static const int _clKeepLeft = 3;
  static const int _clKeepRight = 4;

  /// Classify a cluster: does it need keep-whole protection or is it too big?
  ///
  /// A cluster is "clipped" if it touches a band edge AND the same colour
  /// continues just outside the band (peeking one cell via [colorAt]).
  /// If clipped on only one side, the real object edge is on the other side
  /// and can be protected via keep-whole (keepLeft/keepRight).
  static int _classifyCluster(
    Set<(int, int)> cluster,
    int nominalBoundary,
    int bandMin,
    int bandMax,
    int? Function(int primary, int cross) colorAt,
    Map<int, int> bandColors,
  ) {
    bool hasLeft = false, hasRight = false;
    bool touchesBandMin = false, touchesBandMax = false;

    for (final (p, _) in cluster) {
      if (p < nominalBoundary) hasLeft = true;
      if (p >= nominalBoundary) hasRight = true;
      if (p == bandMin) touchesBandMin = true;
      if (p == bandMax - 1) touchesBandMax = true;
    }

    // Check if clipped at band edges (object continues beyond band)
    bool extendsLeft = false, extendsRight = false;
    if (touchesBandMin || touchesBandMax) {
      final (fp, fc) = cluster.first;
      final color = bandColors[(fp << 16) | fc];

      if (touchesBandMin && bandMin > 0) {
        for (final (p, c) in cluster) {
          if (p == bandMin && colorAt(bandMin - 1, c) == color) {
            extendsLeft = true;
            break;
          }
        }
      }
      if (touchesBandMax) {
        for (final (p, c) in cluster) {
          if (p == bandMax - 1 && colorAt(bandMax, c) == color) {
            extendsRight = true;
            break;
          }
        }
      }
    }

    // Doesn't span boundary → no-op
    if (!hasLeft || !hasRight) return _clNoOp;

    if (extendsLeft && extendsRight) return _clTooBig;
    if (extendsLeft) return _clKeepLeft;
    if (extendsRight) return _clKeepRight;
    return _clKeepWhole;
  }

  // ── Anchor detection ──────────────────────────────────────────────────────

  /// Detect anchor points: high-confidence cut positions at colour transitions
  /// weighted by adjacent cluster size.
  ///
  /// Returns: crossIndex → offset delta from nominal boundary.
  /// Only rows with a qualifying transition whose largest adjacent cluster
  /// has ≥ [kMinAnchorSize] cells are included.
  ///
  /// At each row, if multiple qualifying transitions exist, the one with the
  /// highest weight wins (tiebreak: closest to nominal).
  static Map<int, int> _detectAnchors({
    required int nominalBoundary,
    required int tolerance,
    required int bandMin,
    required int bandMax,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
    required Map<int, Set<(int, int)>> localClusters,
  }) {
    // Build cell → clusterId for size lookups
    final cellToCluster = <int, int>{};
    for (final entry in localClusters.entries) {
      for (final (p, c) in entry.value) {
        cellToCluster[(p << 16) | c] = entry.key;
      }
    }

    final anchors = <int, int>{};
    int prevDelta = 0; // Track previous anchor for continuity tie-break

    for (int cross = 0; cross < maxCross; cross++) {
      int bestDelta = 0;
      int bestWeight = 0;
      int bestDist = tolerance + 1;
      int bestContinuity = tolerance + 1;

      for (int p = bandMin; p < bandMax - 1; p++) {
        final cA = colorAt(p, cross);
        final cB = colorAt(p + 1, cross);
        if (cA == null || cB == null || cA == cB) continue;

        // Weight = max of the two adjacent cluster sizes
        final leftId = cellToCluster[(p << 16) | cross];
        final rightId = cellToCluster[((p + 1) << 16) | cross];
        final leftSize = leftId != null ? localClusters[leftId]!.length : 0;
        final rightSize = rightId != null ? localClusters[rightId]!.length : 0;
        final weight = leftSize > rightSize ? leftSize : rightSize;

        if (weight < kMinAnchorSize) continue;

        final delta = (p + 1) - nominalBoundary;
        final dist = delta.abs();
        final continuity = (delta - prevDelta).abs();

        if (weight > bestWeight ||
            (weight == bestWeight && dist < bestDist) ||
            (weight == bestWeight && dist == bestDist &&
                continuity < bestContinuity)) {
          bestDelta = delta;
          bestWeight = weight;
          bestDist = dist;
          bestContinuity = continuity;
        }
      }

      if (bestWeight >= kMinAnchorSize) {
        anchors[cross] = bestDelta;
        prevDelta = bestDelta;
      }
    }

    return anchors;
  }

  // ── Interpolation ─────────────────────────────────────────────────────────

  /// Produce per-cross-index offset deltas for an entire boundary by
  /// connecting anchor points and filling anchor-free gaps.
  ///
  /// - Between two anchors: linear interpolation (step-clamped to ±2).
  /// - Before first / after last anchor: deterministic fuzz from the
  ///   nearest anchor.
  /// - No anchors at all: deterministic fuzz from nominal (δ=0).
  ///
  /// All values are clamped to ±[tolerance]. Adjacent values differ by ≤ 2.
  static Map<int, int> _interpolateAnchors({
    required Map<int, int> anchors,
    required int maxCross,
    required int tolerance,
    required int nominalBoundary,
  }) {
    if (tolerance == 0) {
      return {for (int i = 0; i < maxCross; i++) i: 0};
    }

    final result = <int, int>{};

    if (anchors.isEmpty) {
      _fuzzFill(result, 0, maxCross - 1, 0, tolerance, nominalBoundary);
      return result;
    }

    final sorted = anchors.keys.toList()..sort();

    // Set anchor points first
    for (final key in sorted) {
      result[key] = anchors[key]!.clamp(-tolerance, tolerance);
    }

    // Before first anchor: fuzz backward from anchor
    if (sorted.first > 0) {
      _fuzzFillReverse(
          result, 0, sorted.first - 1, result[sorted.first]!, tolerance,
          nominalBoundary);
    }

    // Between consecutive anchors: linear interpolation
    for (int i = 0; i < sorted.length - 1; i++) {
      final fromCross = sorted[i];
      final toCross = sorted[i + 1];
      if (toCross - fromCross <= 1) continue;
      _linearFill(result, fromCross, toCross, result[fromCross]!,
          result[toCross]!, tolerance);
    }

    // After last anchor: fuzz forward from anchor
    if (sorted.last < maxCross - 1) {
      _fuzzFill(result, sorted.last + 1, maxCross - 1, result[sorted.last]!,
          tolerance, nominalBoundary);
    }

    return result;
  }

  /// Fill [startCross..endCross] walking forward with deterministic fuzz.
  /// Each step is ±{0,1,2}, clamped to ±tolerance.
  static void _fuzzFill(Map<int, int> result, int startCross, int endCross,
      int startDelta, int tolerance, int seed) {
    int prev = startDelta;
    for (int i = startCross; i <= endCross; i++) {
      final step = _fuzzStep(seed, i);
      prev = (prev + step).clamp(-tolerance, tolerance);
      result[i] = prev;
    }
  }

  /// Fill [startCross..endCross] walking backward from endDelta.
  /// Ensures the value at endCross connects to the anchor at endCross+1.
  static void _fuzzFillReverse(Map<int, int> result, int startCross,
      int endCross, int endDelta, int tolerance, int seed) {
    int prev = endDelta;
    for (int i = endCross; i >= startCross; i--) {
      final step = _fuzzStep(seed, i);
      prev = (prev + step).clamp(-tolerance, tolerance);
      result[i] = prev;
    }
  }

  /// Linear interpolation between anchors at [from] and [to].
  /// Fills (from+1) to (to-1), clamping each step to ±2.
  static void _linearFill(Map<int, int> result, int from, int to,
      int deltaFrom, int deltaTo, int tolerance) {
    int prev = deltaFrom;
    final span = to - from;
    for (int i = from + 1; i < to; i++) {
      final t = (i - from) / span;
      final target = (deltaFrom + (deltaTo - deltaFrom) * t).round();
      final step = (target - prev).clamp(-2, 2);
      prev = (prev + step).clamp(-tolerance, tolerance);
      result[i] = prev;
    }
  }

  /// Deterministic pseudo-random step in [-2, +2] for a given seed and index.
  /// Uses Knuth multiplicative hash for reproducibility.
  static int _fuzzStep(int seed, int index) {
    final h = ((seed + index) * 2654435761) & 0xFFFFFFFF;
    return (h >> 16) % 5 - 2;
  }

  // ── v2 boundary result ─────────────────────────────────────────────────────

  // ── v2 boundary computation (band-local pipeline) ──────────────────────────
  //
  // The v2 pipeline returns both per-cross offsets AND override cell sets.
  // When two objects conflict at the same cross-index (one needs keepLeft,
  // the other keepRight), the first locks the cross offset. The second's
  // cells are added to override sets instead — these become _includedCells
  // in compute(), allowing cells to appear on a page despite failing the
  // primary boundary check.

  /// Compute boundary offsets using the v2 band-local algorithm.
  ///
  /// Pipeline: extract band → local flood fill → same-colour clustering →
  /// classify clusters → detect anchors → interpolate → keep-whole → reclaim.
  ///
  /// Returns `(offsets, includeLeftCells, includeRightCells)`:
  ///   - offsets: crossIndex → offset delta from nominal boundary
  ///   - includeLeftCells: (primary, cross) cells to include on the LEFT page
  ///   - includeRightCells: (primary, cross) cells to include on the RIGHT page
  ///
  /// Override cells arise when two objects at the same cross need opposite
  /// boundary adjustments — both can't be satisfied by a single offset.
  static (Map<int, int>, Set<(int, int)>, Set<(int, int)>) _computeBoundaryOffsetsV2({
    required int nominalBoundary,
    required int tolerance,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
  }) {
    final emptyLeft = <(int, int)>{};
    final emptyRight = <(int, int)>{};
    if (tolerance == 0) {
      return ({for (int i = 0; i < maxCross; i++) i: 0}, emptyLeft, emptyRight);
    }

    // ── Phase 1: Band extraction ──────────────────────────────────────────
    final bandColors = _extractBand(
      nominalBoundary: nominalBoundary,
      tolerance: tolerance,
      maxBoundary: maxBoundary,
      maxCross: maxCross,
      colorAt: colorAt,
    );

    final (bandMin, bandMax) = _bandBounds(nominalBoundary, tolerance, maxBoundary);

    // ── Phase 2: Local object detection ───────────────────────────────────
    final localObjects = _detectLocalObjects(bandColors);

    // ── Phase 2b: Filter spanning objects for keep-whole clustering ───────
    // noOp (entirely one side) and tooBig (extends beyond band both sides)
    // are excluded so they don't skew the cluster's side decision.
    final spanningObjects = <int, Set<(int, int)>>{};
    final tooBigObjectIds = <int>{};
    for (final entry in localObjects.entries) {
      final cl = _classifyCluster(
          entry.value, nominalBoundary, bandMin, bandMax, colorAt, bandColors);
      if (cl == _clTooBig) {
        tooBigObjectIds.add(entry.key);
      } else if (cl != _clNoOp) {
        spanningObjects[entry.key] = entry.value;
      }
    }

    // ── Phase 2c: Same-colour clustering (for classification only) ───────
    // Clustering merges nearby same-colour spanning objects so that
    // classification (keepWhole vs keepLeft/Right vs tooBig) considers the
    // group as a whole. But the SIDE DECISION is per local object — each
    // 8-connected object is atomic and all its cells go to the same side.
    final keepWholeClusters =
        _buildLocalClusters(spanningObjects, bandColors);

    // Build cell → objectId lookup for spanning objects.
    final cellToSpanningObj = <(int, int), int>{};
    for (final entry in spanningObjects.entries) {
      for (final cell in entry.value) {
        cellToSpanningObj[cell] = entry.key;
      }
    }

    // Build set of object IDs that belong to keep-whole-eligible clusters
    // (clusters that aren't noOp or tooBig after clustering).
    final keepWholeObjectIds = <int>{};
    for (final cluster in keepWholeClusters.values) {
      final cl = _classifyCluster(
          cluster, nominalBoundary, bandMin, bandMax, colorAt, bandColors);
      if (cl == _clNoOp || cl == _clTooBig) continue;
      for (final cell in cluster) {
        final objId = cellToSpanningObj[cell];
        if (objId != null) keepWholeObjectIds.add(objId);
      }
    }

    // ── Phase 3: Side decision + hard constraints ─────────────────────────
    // Each LOCAL OBJECT (8-connected) picks a side independently based on
    // where its cells are. Objects are atomic — never split. The required
    // offset at each cross becomes a HARD CONSTRAINT for interpolation.
    // Conflicts at the same cross (opposite sides) → _includedCells.
    final hardConstraints = <int, int>{}; // cross → required offset
    final constraintDirection = <int, bool>{}; // cross → true=keepLeft
    final includeLeftCells = <(int, int)>{};
    final includeRightCells = <(int, int)>{};

    for (final objId in keepWholeObjectIds) {
      final obj = spanningObjects[objId]!;
      final cl = _classifyCluster(
          obj, nominalBoundary, bandMin, bandMax, colorAt, bandColors);
      if (cl == _clNoOp || cl == _clTooBig) continue;

      // Side decision: per-object, based on this object's own cells.
      final bool keepLeft;
      if (cl == _clKeepLeft) {
        keepLeft = true;
      } else if (cl == _clKeepRight) {
        keepLeft = false;
      } else {
        // keepWhole: majority side, tie-break by min displacement.
        int leftCount = 0, rightCount = 0;
        for (final (p, _) in obj) {
          if (p < nominalBoundary) leftCount++;
          else rightCount++;
        }
        if (leftCount != rightCount) {
          keepLeft = leftCount > rightCount;
        } else {
          int maxP = obj.first.$1, minP = obj.first.$1;
          for (final (p, _) in obj) {
            if (p > maxP) maxP = p;
            if (p < minP) minP = p;
          }
          keepLeft = ((maxP + 1) - nominalBoundary).abs() <=
              (nominalBoundary - minP).abs();
        }
      }

      // Compute required offset at each cross to keep the object whole.
      final byCross = <int, List<int>>{};
      for (final (p, c) in obj) {
        byCross.putIfAbsent(c, () => []).add(p);
      }

      for (final entry in byCross.entries) {
        final cross = entry.key;
        final primaries = entry.value;

        // Check for conflicting constraint at this cross.
        final existingDir = constraintDirection[cross];
        if (existingDir != null && existingDir != keepLeft) {
          // Opposite direction conflict — can't satisfy both with one offset.
          // This object's cells on the wrong side → overrides.
          final currentConstraint = hardConstraints[cross]!;
          final actual = nominalBoundary + currentConstraint;
          for (final p in primaries) {
            if (keepLeft && p >= actual) {
              includeLeftCells.add((p, cross));
            } else if (!keepLeft && p < actual) {
              includeRightCells.add((p, cross));
            }
          }
          continue;
        }

        if (keepLeft) {
          final maxP = primaries.reduce(math.max);
          // Only constrain if cells are on the wrong side (right of nominal).
          if (maxP < nominalBoundary) continue;
          final ideal = ((maxP + 1) - nominalBoundary).clamp(-tolerance, tolerance);
          final capped = ideal.clamp(-_kMaxKeepWholeStep, _kMaxKeepWholeStep);
          final existing = hardConstraints[cross];
          if (existing == null || capped > existing) {
            hardConstraints[cross] = capped;
            constraintDirection[cross] = true;
          }
          // Cells beyond the cap → overrides.
          final actual = nominalBoundary + (hardConstraints[cross] ?? 0);
          for (final p in primaries) {
            if (p >= actual) includeLeftCells.add((p, cross));
          }
        } else {
          final minP = primaries.reduce(math.min);
          // Only constrain if cells are on the wrong side (left of nominal).
          if (minP >= nominalBoundary) continue;
          final ideal = (minP - nominalBoundary).clamp(-tolerance, tolerance);
          final capped = ideal.clamp(-_kMaxKeepWholeStep, _kMaxKeepWholeStep);
          final existing = hardConstraints[cross];
          if (existing == null || capped < existing) {
            hardConstraints[cross] = capped;
            constraintDirection[cross] = false;
          }
          // Cells beyond the cap → overrides.
          final actual = nominalBoundary + (hardConstraints[cross] ?? 0);
          for (final p in primaries) {
            if (p < actual) includeRightCells.add((p, cross));
          }
        }
      }
    }

    // ── Phase 4a: Anchor detection (tooBig regions only) ──────────────────
    // Use ALL objects for anchor weight calculation — large objects provide
    // strong edges for cut placement.
    final allClusters = _buildLocalClusters(localObjects, bandColors);
    final anchors = _detectAnchors(
      nominalBoundary: nominalBoundary,
      tolerance: tolerance,
      bandMin: bandMin,
      bandMax: bandMax,
      maxBoundary: maxBoundary,
      maxCross: maxCross,
      colorAt: colorAt,
      localClusters: allClusters,
    );

    // ── Phase 4b: Merge constraints + anchors, then interpolate ───────────
    // Hard constraints from keep-whole take priority. Anchors fill in crosses
    // without constraints. Interpolation connects them smoothly.
    final fixedPoints = <int, int>{};

    // Hard constraints first (always win).
    fixedPoints.addAll(hardConstraints);

    // Anchors for unconstrained crosses.
    for (final entry in anchors.entries) {
      if (!fixedPoints.containsKey(entry.key)) {
        fixedPoints[entry.key] = entry.value;
      }
    }

    // Interpolate between all fixed points (constraints + anchors).
    final offsets = _interpolateAnchors(
      anchors: fixedPoints,
      maxCross: maxCross,
      tolerance: tolerance,
      nominalBoundary: nominalBoundary,
    );

    // Restore hard constraints (interpolation might have smoothed them).
    for (final entry in hardConstraints.entries) {
      offsets[entry.key] = entry.value;
    }

    // ── Phase 5: Fragment reclamation ─────────────────────────────────────
    // After the cut is placed, small object fragments may be stranded on the
    // wrong side. Shift offsets or add overrides. Hard-constrained crosses
    // use overrides only.
    _reclaimFragments(
      offsets: offsets,
      hardConstraints: hardConstraints,
      nominalBoundary: nominalBoundary,
      tolerance: tolerance,
      bandMin: bandMin,
      bandMax: bandMax,
      maxCross: maxCross,
      colorAt: colorAt,
      bandColors: bandColors,
      localObjects: localObjects,
      includeLeftCells: includeLeftCells,
      includeRightCells: includeRightCells,
    );

    // ── Phase 6: Split-object protection ────────────────────────────────
    _protectSplitObjects(
      offsets: offsets,
      nominalBoundary: nominalBoundary,
      tolerance: tolerance,
      localObjects: localObjects,
      excludeObjectIds: tooBigObjectIds,
      includeLeftCells: includeLeftCells,
      includeRightCells: includeRightCells,
    );

    return (offsets, includeLeftCells, includeRightCells);
  }

  /// Scan all local objects against the actual boundary. Any object with
  /// cells on both sides gets override cells for its minority-side cells
  /// so it appears whole on the majority side.
  static void _protectSplitObjects({
    required Map<int, int> offsets,
    required int nominalBoundary,
    required int tolerance,
    required Map<int, Set<(int, int)>> localObjects,
    required Set<int> excludeObjectIds,
    required Set<(int, int)> includeLeftCells,
    required Set<(int, int)> includeRightCells,
  }) {
    for (final entry in localObjects.entries) {
      if (excludeObjectIds.contains(entry.key)) continue;
      final obj = entry.value;

      // Skip large objects — they span too many cross-indices to keep whole
      // without creating massive overrides. The band width (2× tolerance)
      // is a natural size threshold: objects larger than the band area are
      // effectively tooBig for split protection.
      if (obj.length > tolerance * 4) continue;

      int leftCount = 0, rightCount = 0;
      for (final (p, c) in obj) {
        final actual = nominalBoundary + (offsets[c] ?? 0);
        if (p < actual) leftCount++;
        else rightCount++;
      }

      // Object is entirely on one side → no split, skip.
      if (leftCount == 0 || rightCount == 0) continue;

      // Object is split — add minority-side cells as overrides.
      if (leftCount >= rightCount) {
        // Majority left — add right-side cells to includeLeftCells.
        for (final (p, c) in obj) {
          final actual = nominalBoundary + (offsets[c] ?? 0);
          if (p >= actual) includeLeftCells.add((p, c));
        }
      } else {
        // Majority right — add left-side cells to includeRightCells.
        for (final (p, c) in obj) {
          final actual = nominalBoundary + (offsets[c] ?? 0);
          if (p < actual) includeRightCells.add((p, c));
        }
      }
    }
  }

  /// Reclaim small object fragments stranded by the cut.
  ///
  /// For each cross-index, examines the cell immediately left and right of
  /// the cut position. If that cell belongs to a local object that fits
  /// entirely within [bandMin, bandMax), the boundary is shifted to keep
  /// the object whole. Hard-constrained crosses (from keep-whole) are not
  /// shifted — stranded cells there become overrides instead.
  static void _reclaimFragments({
    required Map<int, int> offsets,
    required Map<int, int> hardConstraints,
    required int nominalBoundary,
    required int tolerance,
    required int bandMin,
    required int bandMax,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
    required Map<int, int> bandColors,
    required Map<int, Set<(int, int)>> localObjects,
    required Set<(int, int)> includeLeftCells,
    required Set<(int, int)> includeRightCells,
  }) {
    // Build cell → objectId lookup
    final cellToObj = <int, int>{};
    for (final entry in localObjects.entries) {
      for (final (p, c) in entry.value) {
        cellToObj[(p << 16) | c] = entry.key;
      }
    }

    // Cache which objects fit in band (don't extend beyond band edges).
    final objFitsInBand = <int, bool>{};
    bool fitsInBand(int objId) {
      return objFitsInBand.putIfAbsent(objId, () {
        final cells = localObjects[objId]!;
        final (fp, fc) = cells.first;
        final color = bandColors[(fp << 16) | fc];

        for (final (p, c) in cells) {
          if (p == bandMin && bandMin > 0 && colorAt(bandMin - 1, c) == color) {
            return false;
          }
          if (p == bandMax - 1 && colorAt(bandMax, c) == color) {
            return false;
          }
        }
        return true;
      });
    }

    // Cache object primary-axis extent per cross-index.
    final objByCross = <int, Map<int, List<int>>>{};
    Map<int, List<int>> getObjByCross(int objId) {
      return objByCross.putIfAbsent(objId, () {
        final byCross = <int, List<int>>{};
        for (final (p, c) in localObjects[objId]!) {
          byCross.putIfAbsent(c, () => []).add(p);
        }
        return byCross;
      });
    }

    // Track which objects have already been reclaimed to avoid double-processing.
    final reclaimed = <int>{};

    for (int cross = 0; cross < maxCross; cross++) {
      final delta = offsets[cross] ?? 0;
      final actual = nominalBoundary + delta;

      // Check cell immediately left of cut (stranded on page 1)
      if (actual > bandMin) {
        final leftKey = ((actual - 1) << 16) | cross;
        final leftObjId = cellToObj[leftKey];
        if (leftObjId != null &&
            !reclaimed.contains(leftObjId) &&
            fitsInBand(leftObjId)) {
          final byCross = getObjByCross(leftObjId);
          int objLeft = 0, objRight = 0;
          for (final entry in byCross.entries) {
            final crossDelta = offsets[entry.key] ?? 0;
            final crossActual = nominalBoundary + crossDelta;
            for (final p in entry.value) {
              if (p < crossActual) objLeft++;
              else objRight++;
            }
          }
          // If majority is on page 2, reclaim stranded cells
          if (objRight > objLeft) {
            reclaimed.add(leftObjId);
            for (final crossEntry in byCross.entries) {
              final c = crossEntry.key;
              final primaries = crossEntry.value;
              final minP = primaries.reduce(math.min);
              final currentDelta = offsets[c] ?? 0;
              final crossActual = nominalBoundary + currentDelta;
              if (minP < crossActual) {
                if (hardConstraints.containsKey(c)) {
                  // Hard-constrained — can't shift, add overrides.
                  for (final p in primaries) {
                    if (p < crossActual) includeRightCells.add((p, c));
                  }
                } else {
                  final needed =
                      (minP - nominalBoundary).clamp(-tolerance, tolerance);
                  offsets[c] = needed;
                  // Override any cells still stranded.
                  final newActual = nominalBoundary + needed;
                  for (final p in primaries) {
                    if (p < newActual) includeRightCells.add((p, c));
                  }
                }
              }
            }
          }
        }
      }

      // Check cell immediately right of cut (stranded on page 2)
      if (actual < bandMax) {
        final rightKey = (actual << 16) | cross;
        final rightObjId = cellToObj[rightKey];
        if (rightObjId != null &&
            !reclaimed.contains(rightObjId) &&
            fitsInBand(rightObjId)) {
          final byCross = getObjByCross(rightObjId);
          int objLeft = 0, objRight = 0;
          for (final entry in byCross.entries) {
            final crossDelta = offsets[entry.key] ?? 0;
            final crossActual = nominalBoundary + crossDelta;
            for (final p in entry.value) {
              if (p < crossActual) objLeft++;
              else objRight++;
            }
          }
          // If majority is on page 1, reclaim stranded cells
          if (objLeft > objRight) {
            reclaimed.add(rightObjId);
            for (final crossEntry in byCross.entries) {
              final c = crossEntry.key;
              final primaries = crossEntry.value;
              final maxP = primaries.reduce(math.max);
              final currentDelta = offsets[c] ?? 0;
              final crossActual = nominalBoundary + currentDelta;
              if (maxP >= crossActual) {
                if (hardConstraints.containsKey(c)) {
                  // Hard-constrained — can't shift, add overrides.
                  for (final p in primaries) {
                    if (p >= crossActual) includeLeftCells.add((p, c));
                  }
                } else {
                  final needed =
                      ((maxP + 1) - nominalBoundary).clamp(-tolerance, tolerance);
                  offsets[c] = needed;
                  final newActual = nominalBoundary + needed;
                  for (final p in primaries) {
                    if (p >= newActual) includeLeftCells.add((p, c));
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// Smooth offsets so adjacent values differ by ≤ 2.
  /// Two passes: forward then backward, averaging when both constrain.
  static void _smoothOffsets(Map<int, int> offsets, int maxCross, int tolerance) {
    // Forward pass
    for (int i = 1; i < maxCross; i++) {
      final prev = offsets[i - 1] ?? 0;
      final curr = offsets[i] ?? 0;
      if ((curr - prev).abs() > 2) {
        offsets[i] = (prev + (curr - prev).clamp(-2, 2)).clamp(-tolerance, tolerance);
      }
    }
    // Backward pass
    for (int i = maxCross - 2; i >= 0; i--) {
      final next = offsets[i + 1] ?? 0;
      final curr = offsets[i] ?? 0;
      if ((curr - next).abs() > 2) {
        offsets[i] = (next + (curr - next).clamp(-2, 2)).clamp(-tolerance, tolerance);
      }
    }
  }

  // ── Phase 1: Object detection (v1, to be replaced) ────────────────────────

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
        // Small object — keep entire thing whole on majority side.
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

      // ── Large object (e.g. outlines spanning the pattern). ──────────────
      // Collect cells within tolerance of boundary on BOTH sides, flood-fill
      // into local sub-groups, and let each sub-group independently decide
      // which page it belongs to based on its own left/right balance.
      final localCells = <(int, int)>{};
      for (final (p, c) in groupCells) {
        if (p >= nominalBoundary - tolerance &&
            p < nominalBoundary + tolerance) {
          localCells.add((p, c));
        }
      }

      final visitedLocal = <(int, int)>{};
      for (final seed in localCells) {
        if (visitedLocal.contains(seed)) continue;

        // BFS within local window.
        final component = <(int, int)>{};
        final queue = [seed];
        visitedLocal.add(seed);
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
            if (localCells.contains(neighbor) &&
                !visitedLocal.contains(neighbor)) {
              visitedLocal.add(neighbor);
              queue.add(neighbor);
            }
          }
        }

        // Count cells on each side of boundary.
        int subLeft = 0, subRight = 0;
        final subLeftPrimaries = <int>{};
        final subRightPrimaries = <int>{};
        for (final (p, _) in component) {
          if (p < nominalBoundary) {
            subLeft++;
            subLeftPrimaries.add(p);
          } else {
            subRight++;
            subRightPrimaries.add(p);
          }
        }

        // Skip if entirely on one side (no bleed to resolve).
        if (subLeftPrimaries.isEmpty || subRightPrimaries.isEmpty) continue;

        // Decide which side this sub-group belongs to.
        bool subKeepLeft;
        if (subLeft != subRight) {
          subKeepLeft = subLeft > subRight;
        } else {
          // Tiebreaker: count connections to the full object outside
          // the tolerance window — whichever side has more continuity wins.
          int connectsLeft = 0, connectsRight = 0;
          for (final (p, c) in component) {
            for (final (dp, dc) in const [
              (-1, -1), (-1, 0), (-1, 1),
              (0, -1),           (0, 1),
              (1, -1),  (1, 0),  (1, 1),
            ]) {
              final np = p + dp;
              final nc = c + dc;
              if (!localCells.contains((np, nc)) &&
                  groupCells.contains((np, nc))) {
                if (np < nominalBoundary) {
                  connectsLeft++;
                } else {
                  connectsRight++;
                }
              }
            }
          }
          subKeepLeft = (subLeft + connectsLeft) >= (subRight + connectsRight);
        }

        // Compute bleed depth for this sub-group.
        final subBleedDepth = subKeepLeft
            ? subRightPrimaries.reduce(math.max) - nominalBoundary + 1
            : nominalBoundary - subLeftPrimaries.reduce(math.min);
        if (subBleedDepth > tolerance) continue;

        // Add keep-whole constraint for this sub-group.
        final Map<int, List<int>> byCross = {};
        for (final (p, c) in component) {
          byCross.putIfAbsent(c, () => []).add(p);
        }
        if (subKeepLeft) {
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

    // Vertical boundary offsets (column boundaries) — v2 band-local pipeline.
    final Map<int, Map<int, int>> verticalOffsets = {};
    // Collect override cells per vertical boundary: boundary page index → cells.
    // Key: pageCol of the LEFT page (= p-1). "includeLeft" → left page,
    // "includeRight" → right page (= p).
    final Map<int, Set<(int, int)>> vIncludeLeft = {};
    final Map<int, Set<(int, int)>> vIncludeRight = {};
    for (int p = 1; p < pagesAcross; p++) {
      final boundaryCol = p * config.pageWidth;
      final (offsets, leftCells, rightCells) = _computeBoundaryOffsetsV2(
        nominalBoundary: boundaryCol,
        tolerance: config.tolerance,
        maxBoundary: pattern.width,
        maxCross: pattern.height,
        colorAt: (primary, cross) => colorAt(primary, cross),
      );
      verticalOffsets[boundaryCol] = offsets;
      if (leftCells.isNotEmpty) vIncludeLeft[p - 1] = leftCells;
      if (rightCells.isNotEmpty) vIncludeRight[p] = rightCells;
    }

    // Horizontal boundary offsets (row boundaries) — v2 band-local pipeline.
    final Map<int, Map<int, int>> horizontalOffsets = {};
    final Map<int, Set<(int, int)>> hIncludeTop = {};
    final Map<int, Set<(int, int)>> hIncludeBottom = {};
    for (int p = 1; p < pagesDown; p++) {
      final boundaryRow = p * config.pageHeight;
      final (offsets, topCells, bottomCells) = _computeBoundaryOffsetsV2(
        nominalBoundary: boundaryRow,
        tolerance: config.tolerance,
        maxBoundary: pattern.height,
        maxCross: pattern.width,
        colorAt: (primary, cross) => colorAt(cross, primary),
      );
      horizontalOffsets[boundaryRow] = offsets;
      if (topCells.isNotEmpty) hIncludeTop[p - 1] = topCells;
      if (bottomCells.isNotEmpty) hIncludeBottom[p] = bottomCells;
    }

    // ── Build _includedCells from override sets ─────────────────────────────
    // Translate boundary-relative (primary, cross) overrides to absolute
    // page indices. Vertical: primary=col, cross=row. Horizontal: primary=row,
    // cross=col (transposed by caller).
    final Map<int, Set<int>> includedCells = {};
    final Map<int, Set<int>> excludedCells = {};

    void addIncluded(int pageIdx, int col, int row) {
      includedCells.putIfAbsent(pageIdx, () => {}).add(_encodeCell(col, row));
    }

    void addExcluded(int pageIdx, int col, int row) {
      excludedCells.putIfAbsent(pageIdx, () => {}).add(_encodeCell(col, row));
    }

    // Helper: find pageRow for a cell via horizontal boundaries.
    int findPageRow(int col, int row) {
      for (int py = 0; py < pagesDown; py++) {
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
        if (row >= top && row < bottom) return py;
      }
      // Fallback: nominal page row.
      return (row ~/ config.pageHeight).clamp(0, pagesDown - 1);
    }

    // Helper: find pageCol for a cell via vertical boundaries.
    int findPageCol(int col, int row) {
      for (int px = 0; px < pagesAcross; px++) {
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
        if (col >= left && col < right) return px;
      }
      return (col ~/ config.pageWidth).clamp(0, pagesAcross - 1);
    }

    // Track override target axes per cell for corner fixup.
    // Key: encoded cell. Value: target page col from V override.
    final vOverrideCol = <int, int>{};
    // Key: encoded cell. Value: target page row from H override.
    final hOverrideRow = <int, int>{};

    // Vertical overrides: (primary=col, cross=row)
    // vIncludeLeft[p-1]: cell was on page col p (right), move to p-1 (left)
    for (final entry in vIncludeLeft.entries) {
      final targetPageCol = entry.key; // p - 1
      for (final (col, row) in entry.value) {
        final key = _encodeCell(col, row);
        vOverrideCol[key] = targetPageCol;
        final py = findPageRow(col, row);
        addIncluded(py * pagesAcross + targetPageCol, col, row);
        addExcluded(py * pagesAcross + (targetPageCol + 1), col, row);
      }
    }
    // vIncludeRight[p]: cell was on page col p-1 (left), move to p (right)
    for (final entry in vIncludeRight.entries) {
      final targetPageCol = entry.key; // p
      for (final (col, row) in entry.value) {
        final key = _encodeCell(col, row);
        vOverrideCol[key] = targetPageCol;
        final py = findPageRow(col, row);
        addIncluded(py * pagesAcross + targetPageCol, col, row);
        addExcluded(py * pagesAcross + (targetPageCol - 1), col, row);
      }
    }

    // Horizontal overrides: (primary=row, cross=col) — transposed
    // hIncludeTop[p-1]: cell was on page row p (bottom), move to p-1 (top)
    for (final entry in hIncludeTop.entries) {
      final targetPageRow = entry.key; // p - 1
      for (final (row, col) in entry.value) {
        final key = _encodeCell(col, row);
        hOverrideRow[key] = targetPageRow;
        final px = findPageCol(col, row);
        addIncluded(targetPageRow * pagesAcross + px, col, row);
        addExcluded((targetPageRow + 1) * pagesAcross + px, col, row);
      }
    }
    // hIncludeBottom[p]: cell was on page row p-1 (top), move to p (bottom)
    for (final entry in hIncludeBottom.entries) {
      final targetPageRow = entry.key; // p
      for (final (row, col) in entry.value) {
        final key = _encodeCell(col, row);
        hOverrideRow[key] = targetPageRow;
        final px = findPageCol(col, row);
        addIncluded(targetPageRow * pagesAcross + px, col, row);
        addExcluded((targetPageRow - 1) * pagesAcross + px, col, row);
      }
    }

    // ── Corner override fixup ────────────────────────────────────────────────
    // Cells overridden by BOTH a vertical and horizontal boundary got placed
    // using findPageRow/findPageCol for the other axis, which doesn't account
    // for the other override. Fix: move them to the page that combines both
    // override axes.
    for (final key in vOverrideCol.keys) {
      final hRow = hOverrideRow[key];
      if (hRow == null) continue; // only V override — already correct

      final col = key >> 16;
      final row = key & 0xFFFF;
      final vCol = vOverrideCol[key]!;
      final correctIdx = hRow * pagesAcross + vCol;

      // Remove from wherever V and H independently placed it.
      // V override placed it at (findPageRow, vCol).
      // H override placed it at (hRow, findPageCol).
      final vPlacedRow = findPageRow(col, row);
      final vPlacedIdx = vPlacedRow * pagesAcross + vCol;
      final hPlacedCol = findPageCol(col, row);
      final hPlacedIdx = hRow * pagesAcross + hPlacedCol;

      final encoded = _encodeCell(col, row);

      // Remove incorrect placements.
      if (vPlacedIdx != correctIdx) {
        includedCells[vPlacedIdx]?.remove(encoded);
      }
      if (hPlacedIdx != correctIdx && hPlacedIdx != vPlacedIdx) {
        includedCells[hPlacedIdx]?.remove(encoded);
      }

      // Add to correct page.
      addIncluded(correctIdx, col, row);

      // Exclude from all 4 corner pages except the correct one.
      for (final py in [vPlacedRow, hRow]) {
        for (final px in [vCol, hPlacedCol]) {
          final idx = py * pagesAcross + px;
          if (idx != correctIdx) {
            addExcluded(idx, col, row);
          }
        }
      }
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

    // ── Corner object reconciliation ──────────────────────────────────────
    // V and H boundaries are independent → at 4-page corners, objects can
    // be fragmented across 3-4 pages. Fix: detect objects in corner regions,
    // assign each object to the page with the most of its cells. Minimises
    // the number of pages an object spans.
    if (config.tolerance > 0) {
      final fa = config.tolerance;

      // Resolve which page a cell is currently on.
      int? pageOf(int col, int row) {
        final key = _encodeCell(col, row);
        for (final entry in includedCells.entries) {
          if (entry.value.contains(key)) return entry.key;
        }
        for (int py = 0; py < pagesDown; py++) {
          for (int px = 0; px < pagesAcross; px++) {
            if (rawOnPage(col, row, px, py)) {
              final idx = py * pagesAcross + px;
              final ex = excludedCells[idx];
              if (ex == null || !ex.contains(key)) return idx;
            }
          }
        }
        return null;
      }

      // Move a cell from one page to another.
      void moveCell(int col, int row, int fromPage, int toPage) {
        final key = _encodeCell(col, row);
        includedCells[fromPage]?.remove(key);
        addExcluded(fromPage, col, row);
        addIncluded(toPage, col, row);
        excludedCells[toPage]?.remove(key);
      }

      // Process each corner (intersection of a V and H boundary).
      for (int cx = 1; cx < pagesAcross; cx++) {
        for (int cy = 1; cy < pagesDown; cy++) {
          final bv = cx * config.pageWidth;
          final bh = cy * config.pageHeight;
          final cMinC = (bv - fa).clamp(0, pattern.width);
          final cMaxC = (bv + fa).clamp(0, pattern.width);
          final cMinR = (bh - fa).clamp(0, pattern.height);
          final cMaxR = (bh + fa).clamp(0, pattern.height);

          // Build colour map for corner region (non-null only).
          final cornerColors = <int, int>{};
          for (int c = cMinC; c < cMaxC; c++) {
            for (int r = cMinR; r < cMaxR; r++) {
              final ci = colorAt(c, r);
              if (ci != null) cornerColors[(c << 16) | r] = ci;
            }
          }

          // Detect 8-connected same-colour objects within the corner.
          final cornerObjects = _detectLocalObjects(cornerColors);

          // For each object, find the page with the most cells.
          for (final obj in cornerObjects.values) {
            if (obj.length <= 1) continue;

            // Count cells per page.
            final pageCounts = <int, int>{};
            final cellPages = <(int, int), int>{};
            for (final (c, r) in obj) {
              final page = pageOf(c, r);
              if (page != null) {
                pageCounts[page] = (pageCounts[page] ?? 0) + 1;
                cellPages[(c, r)] = page;
              }
            }

            // Already all on one page → skip.
            if (pageCounts.length <= 1) continue;

            // Find majority page.
            int bestPage = pageCounts.entries.first.key;
            int bestCount = 0;
            for (final entry in pageCounts.entries) {
              if (entry.value > bestCount) {
                bestCount = entry.value;
                bestPage = entry.key;
              }
            }

            // Move minority cells to majority page.
            for (final entry in cellPages.entries) {
              if (entry.value != bestPage) {
                final (c, r) = entry.key;
                moveCell(c, r, entry.value, bestPage);
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
      includedCells: includedCells,
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

  // ── Band-local test-visible helpers ────────────────────────────────────────

  @visibleForTesting
  static Map<int, int> extractBand({
    required int nominalBoundary,
    required int tolerance,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
  }) =>
      _extractBand(
        nominalBoundary: nominalBoundary,
        tolerance: tolerance,
        maxBoundary: maxBoundary,
        maxCross: maxCross,
        colorAt: colorAt,
      );

  @visibleForTesting
  static (int, int) bandBounds(int nominal, int tolerance, int maxBoundary) =>
      _bandBounds(nominal, tolerance, maxBoundary);

  @visibleForTesting
  static Map<int, Set<(int, int)>> detectLocalObjects(
    Map<int, int> bandColors,
  ) =>
      _detectLocalObjects(bandColors);

  @visibleForTesting
  static Map<int, Set<(int, int)>> buildLocalClusters(
    Map<int, Set<(int, int)>> localObjects,
    Map<int, int> bandColors,
  ) =>
      _buildLocalClusters(localObjects, bandColors);

  @visibleForTesting
  static int classifyCluster(
    Set<(int, int)> cluster,
    int nominalBoundary,
    int bandMin,
    int bandMax,
    int? Function(int primary, int cross) colorAt,
    Map<int, int> bandColors,
  ) =>
      _classifyCluster(
          cluster, nominalBoundary, bandMin, bandMax, colorAt, bandColors);

  @visibleForTesting
  static Map<int, int> detectAnchors({
    required int nominalBoundary,
    required int tolerance,
    required int bandMin,
    required int bandMax,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
    required Map<int, Set<(int, int)>> localClusters,
  }) =>
      _detectAnchors(
        nominalBoundary: nominalBoundary,
        tolerance: tolerance,
        bandMin: bandMin,
        bandMax: bandMax,
        maxBoundary: maxBoundary,
        maxCross: maxCross,
        colorAt: colorAt,
        localClusters: localClusters,
      );

  @visibleForTesting
  static Map<int, int> interpolateAnchors({
    required Map<int, int> anchors,
    required int maxCross,
    required int tolerance,
    required int nominalBoundary,
  }) =>
      _interpolateAnchors(
        anchors: anchors,
        maxCross: maxCross,
        tolerance: tolerance,
        nominalBoundary: nominalBoundary,
      );

  @visibleForTesting
  static int fuzzStep(int seed, int index) => _fuzzStep(seed, index);

  @visibleForTesting
  static (Map<int, int>, Set<(int, int)>, Set<(int, int)>) computeBoundaryOffsetsV2({
    required int nominalBoundary,
    required int tolerance,
    required int maxBoundary,
    required int maxCross,
    required int? Function(int primary, int cross) colorAt,
  }) =>
      _computeBoundaryOffsetsV2(
        nominalBoundary: nominalBoundary,
        tolerance: tolerance,
        maxBoundary: maxBoundary,
        maxCross: maxCross,
        colorAt: colorAt,
      );

  /// Test-visible classification constants.
  static const int clNoOp = _clNoOp;
  static const int clKeepWhole = _clKeepWhole;
  static const int clTooBig = _clTooBig;
  static const int clKeepLeft = _clKeepLeft;
  static const int clKeepRight = _clKeepRight;
}
