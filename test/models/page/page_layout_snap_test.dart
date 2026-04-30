// Unit tests for the new object-aware page boundary algorithm in PageLayout.
//
// Tests cover:
//   - Phase 1: detectObjects (8-directional flood-fill)
//   - Phase 2: buildSuperGroups (union-find with 1-cell-gap adjacency)
//   - Phase 3+4: computeBoundaryOffsets (keep-whole + smooth-edge DP)
//   - isQualifyingCut (unchanged per-row colour-transition check)
//   - PageConfig.fromYaml YAML migration (fuzzyAmount → tolerance)

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page/page_config.dart';
import 'package:stitches/models/page/page_layout.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const int A = 1;
const int B = 2;
const int C = 3;
const int D = 4;

/// Build a colorAt closure from a flat 1D list (index = primary col/row).
/// Null entries represent empty (unstitched) cells.
// ignore: unintended_html_in_doc_comment
int? Function(int, int) colorMap1D(List<int?> cells) =>
    (int primary, int crossIndex) =>
        (primary >= 0 && primary < cells.length) ? cells[primary] : null;

/// Build a 2D colorAt from rows (crossIndex=row index, primary=col).
int? Function(int, int) colorMap2D(List<List<int?>> rows) =>
    (int primary, int crossIndex) =>
        (crossIndex >= 0 &&
                crossIndex < rows.length &&
                primary >= 0 &&
                primary < rows[crossIndex].length)
            ? rows[crossIndex][primary]
            : null;

/// Build a snapColor map from a 2D grid (row-major).
// ignore: unintended_html_in_doc_comment
/// Returns Map encoded-cell to color index. Null values are omitted.
Map<int, int?> snapColorFrom2D(List<List<int?>> grid) {
  final result = <int, int?>{};
  for (int row = 0; row < grid.length; row++) {
    for (int col = 0; col < grid[row].length; col++) {
      final color = grid[row][col];
      if (color != null) result[(col << 16) | row] = color;
    }
  }
  return result;
}

/// Call computeBoundaryOffsets with a 1D colorMap (single-row pattern).
Map<int, int> offsets1D(
  List<int?> cells,
  int nominalBoundary, {
  int tolerance = 3,
  Map<int, Set<(int, int)>> superGroups = const {},
}) =>
    PageLayout.computeBoundaryOffsets(
      nominalBoundary: nominalBoundary,
      tolerance: tolerance,
      maxBoundary: cells.length,
      maxCross: 1,
      colorAt: colorMap1D(cells),
      superGroups: superGroups,
    );

/// Convenience: single-row offset at crossIndex=0.
int snap1D(
  List<int?> cells,
  int nominalBoundary, {
  int tolerance = 3,
  Map<int, Set<(int, int)>> superGroups = const {},
}) =>
    offsets1D(cells, nominalBoundary,
        tolerance: tolerance, superGroups: superGroups)[0]!;

// ── Phase 1: detectObjects ────────────────────────────────────────────────────

void main() {
  group('Phase 1 — detectObjects', () {
    test('empty map → no objects', () {
      final objs = PageLayout.detectObjects({}, 5, 5);
      expect(objs, isEmpty);
    });

    test('single cell → one object', () {
      final sc = {(0 << 16) | 0: A};
      final objs = PageLayout.detectObjects(sc, 5, 5);
      expect(objs.length, equals(1));
      expect(objs.values.single, contains((0, 0)));
    });

    test('two isolated cells same colour → separate objects', () {
      final sc = {
        (0 << 16) | 0: A,
        (4 << 16) | 4: A, // far away, not 8-connected
      };
      final objs = PageLayout.detectObjects(sc, 5, 5);
      expect(objs.length, equals(2));
    });

    test('two adjacent cells same colour (orthogonal) → one object', () {
      final sc = {
        (0 << 16) | 0: A,
        (1 << 16) | 0: A,
      };
      final objs = PageLayout.detectObjects(sc, 5, 5);
      expect(objs.length, equals(1));
      expect(objs.values.single.length, equals(2));
    });

    test('two diagonal cells same colour → one object (8-directional)', () {
      final sc = {
        (0 << 16) | 0: A,
        (1 << 16) | 1: A,
      };
      final objs = PageLayout.detectObjects(sc, 5, 5);
      expect(objs.length, equals(1));
    });

    test('two adjacent cells different colour → two objects', () {
      final sc = {
        (0 << 16) | 0: A,
        (1 << 16) | 0: B,
      };
      final objs = PageLayout.detectObjects(sc, 5, 5);
      expect(objs.length, equals(2));
    });

    test('L-shaped connected region → one object', () {
      // A . .
      // A . .
      // A A A
      final sc = {
        (0 << 16) | 0: A, (0 << 16) | 1: A, (0 << 16) | 2: A,
        (1 << 16) | 2: A,
        (2 << 16) | 2: A,
      };
      final objs = PageLayout.detectObjects(sc, 3, 3);
      expect(objs.length, equals(1));
      expect(objs.values.single.length, equals(5));
    });

    test('two objects of same colour separated by gap → two objects', () {
      // A . A (col 0, 2 — not connected via 8-directions)
      final sc = {
        (0 << 16) | 0: A,
        (2 << 16) | 0: A,
      };
      final objs = PageLayout.detectObjects(sc, 3, 1);
      expect(objs.length, equals(2));
    });
  });

  // ── Phase 2: buildSuperGroups ───────────────────────────────────────────────

  group('Phase 2 — buildSuperGroups', () {
    test('empty objects → empty super-groups', () {
      expect(PageLayout.buildSuperGroups({}, 5, 5), isEmpty);
    });

    test('single object → single super-group', () {
      final objs = {0: {(0, 0), (1, 0)}};
      final sg = PageLayout.buildSuperGroups(objs, 5, 5);
      expect(sg.length, equals(1));
    });

    test('two objects directly touching → merged into one super-group', () {
      // Objects at col 0 and col 1 (directly adjacent, 0 gap)
      final objs = {
        0: {(0, 0)},
        1: {(1, 0)},
      };
      final sg = PageLayout.buildSuperGroups(objs, 5, 5);
      expect(sg.length, equals(1));
      expect(sg.values.single, containsAll([(0, 0), (1, 0)]));
    });

    test('two objects 1 cell apart → merged into one super-group', () {
      // Object A at col 0, Object B at col 2; 1-cell gap at col 1
      final objs = {
        0: {(0, 0)},
        1: {(2, 0)},
      };
      final sg = PageLayout.buildSuperGroups(objs, 5, 5);
      expect(sg.length, equals(1), reason: '1-cell gap → merged');
    });

    test('two objects 2 cells apart → remain separate', () {
      // Object A at col 0, Object B at col 3; 2-cell gap (cols 1,2 empty)
      final objs = {
        0: {(0, 0)},
        1: {(3, 0)},
      };
      final sg = PageLayout.buildSuperGroups(objs, 5, 5);
      expect(sg.length, equals(2), reason: '2-cell gap → separate');
    });

    test('three objects in a chain merge transitively', () {
      // A at 0, B at 2, C at 4: each 1-cell gap apart → all merge
      final objs = {
        0: {(0, 0)},
        1: {(2, 0)},
        2: {(4, 0)},
      };
      final sg = PageLayout.buildSuperGroups(objs, 6, 1);
      expect(sg.length, equals(1), reason: 'chain merges transitively');
    });

    test('diagonal 1-cell gap → merged (8-directional expansion)', () {
      // Object A at (0,0), Object B at (2,2): diagonal 1-cell gap
      // Chebyshev distance = 2 → merged
      final objs = {
        0: {(0, 0)},
        1: {(2, 2)},
      };
      final sg = PageLayout.buildSuperGroups(objs, 5, 5);
      expect(sg.length, equals(1));
    });
  });

  // ── tolerance=0: always straight edge ────────────────────────────────────

  group('tolerance=0 always returns 0', () {
    test('solid block', () {
      expect(snap1D([A, A, A, A, A, A], 3, tolerance: 0), 0);
    });
    test('colour change at boundary', () {
      expect(snap1D([A, A, A, B, B, B], 3, tolerance: 0), 0);
    });
    test('all offsets are 0 in multi-row case', () {
      final result = PageLayout.computeBoundaryOffsets(
        nominalBoundary: 3,
        tolerance: 0,
        maxBoundary: 6,
        maxCross: 5,
        colorAt: colorMap2D([
          [A, A, A, B, B, B],
          [A, A, A, B, B, B],
          [A, A, A, B, B, B],
          [A, A, A, B, B, B],
          [A, A, A, B, B, B],
        ]),
        superGroups: {},
      );
      for (final v in result.values) {
        expect(v, equals(0));
      }
    });
  });

  // ── DP — basic offset behaviour ────────────────────────────────────────────

  group('computeBoundaryOffsets — basic offset selection', () {
    test('exact colour boundary at nominal → offset 0', () {
      // Clean A|B at posA=2, posB=3 → qualifying cut → δ=0 preferred
      final result = snap1D([A, A, A, B, B, B], 3);
      expect(result, equals(0));
    });

    test('colour boundary one right → offset +1', () {
      // Clean A|B at col 3|4, nominal=3 → δ=+1
      final result = snap1D([A, A, A, A, B, B, B], 3);
      expect(result, equals(1));
    });

    test('colour boundary one left → offset -1', () {
      // Clean A|B at col 1|2, nominal=3 → δ=-1 (closer than δ=+2)
      final result = snap1D([A, A, B, B, B, B, B], 3);
      expect(result, equals(-1));
    });

    test('solid block → offset 0 (no qualifying cut, minimum distance wins)', () {
      // No colour transitions → DP prefers δ=0 (distance cost minimised)
      final result = snap1D(List.filled(20, A), 10);
      expect(result, equals(0));
    });

    test('offset clamped to ±tolerance', () {
      final result = snap1D([A, A, B, B, B, B, B, B, B, B], 5, tolerance: 2);
      expect(result, inInclusiveRange(-2, 2));
    });
  });

  // ── DP — smoothness across rows ────────────────────────────────────────────

  group('computeBoundaryOffsets — smoothness constraint', () {
    test('consecutive offsets never differ by more than 2', () {
      // 5 rows, all with A|B at different positions — DP must smooth.
      final rows = [
        [A, A, A, A, A, B, B, B, B, B], // clear cut at col 5, nominal=5 → δ=0
        [A, A, A, B, B, B, B, B, B, B], // cut at 3, nominal=5 → δ=-2
        [A, A, A, B, B, B, B, B, B, B], // same
        [A, A, A, A, A, B, B, B, B, B], // cut at 5 → δ=0
        [A, A, A, A, A, B, B, B, B, B], // same
      ];
      final result = PageLayout.computeBoundaryOffsets(
        nominalBoundary: 5,
        tolerance: 4,
        maxBoundary: 10,
        maxCross: 5,
        colorAt: colorMap2D(rows),
        superGroups: {},
      );
      for (int ci = 1; ci < 5; ci++) {
        expect(
          (result[ci]! - result[ci - 1]!).abs(),
          lessThanOrEqualTo(2),
          reason: 'rows ${ ci - 1}→$ci: Δδ too large',
        );
      }
    });

    test('all offsets in map cover every cross-index', () {
      final result = PageLayout.computeBoundaryOffsets(
        nominalBoundary: 5,
        tolerance: 2,
        maxBoundary: 10,
        maxCross: 8,
        colorAt: colorMap1D([A, A, A, A, A, B, B, B, B, B]),
        superGroups: {},
      );
      expect(result.length, equals(8));
      for (int i = 0; i < 8; i++) {
        expect(result.containsKey(i), isTrue, reason: 'crossIndex $i missing');
      }
    });
  });

  // ── DP — keep-whole object constraint ─────────────────────────────────────

  group('computeBoundaryOffsets — keep-whole constraint', () {
    test('group with 1 minority cell kept whole on majority side', () {
      // Super-group: 3 cells at col 3-5 (right of boundary at col 4), 1 cell at col 3.
      // bleedCells=1 ≤ tolerance=2 → keep-whole on right.
      // The DP should prefer δ that keeps all cells to the right of the boundary.
      // With group cells (3,0),(4,0),(5,0),(6,0): countLeft=1 (col 3), countRight=3 (cols 4-6).
      // keep-whole-on-right: need actual ≤ 3 → δ ≤ 3-4=-1.
      // So DP should choose δ=-1 (or more negative).
      final superGroups = {
        0: {(3, 0), (4, 0), (5, 0), (6, 0)},
      };
      final result = PageLayout.computeBoundaryOffsets(
        nominalBoundary: 4,
        tolerance: 2,
        maxBoundary: 10,
        maxCross: 1,
        colorAt: (p, c) => null, // no color transitions
        superGroups: superGroups,
      );
      // δ=-1 means actual=3; all group cells (3,4,5,6) are at col ≥ 3 → kept right.
      expect(result[0], lessThanOrEqualTo(-1),
          reason: 'keep-whole-on-right should force δ ≤ -1');
    });

    test('group entirely on one side — no constraint (bleedCells=0)', () {
      // Group entirely left of boundary — should not constrain boundary.
      final superGroups = {
        0: {(0, 0), (1, 0), (2, 0)}, // all at col 0-2, boundary at col 5
      };
      final result = PageLayout.computeBoundaryOffsets(
        nominalBoundary: 5,
        tolerance: 2,
        maxBoundary: 10,
        maxCross: 1,
        colorAt: colorMap1D([A, A, A, A, A, B, B, B, B, B]),
        superGroups: superGroups,
      );
      // Should still snap to A|B at col 5 → δ=0
      expect(result[0], equals(0));
    });

    test('group with bleedCells > tolerance — treated as split, no keep-whole', () {
      // Group with 3 cells on each side (bleedCells=3), tolerance=2 → split.
      // DP chooses based on color quality / distance, not keep-whole.
      final superGroups = {
        0: {(2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)},
      };
      final result = PageLayout.computeBoundaryOffsets(
        nominalBoundary: 5,
        tolerance: 2,
        maxBoundary: 10,
        maxCross: 1,
        colorAt: colorMap1D([A, A, A, A, A, B, B, B, B, B]),
        superGroups: superGroups,
      );
      // With clean A|B at col 5 → δ=0 regardless of the split group
      expect(result[0], equals(0));
    });
  });

  // ── isQualifyingCut ────────────────────────────────────────────────────────

  group('isQualifyingCut', () {
    bool cut(List<int?> cells, int posA, int posB) =>
        PageLayout.isQualifyingCut(posA, posB, 0, cells.length, colorMap1D(cells));

    test('clean A|B boundary → qualifying', () {
      expect(cut([A, A, A, B, B, B], 2, 3), isTrue);
    });

    test('same colour both sides → not qualifying', () {
      expect(cut([A, A, A, A, A, A], 2, 3), isFalse);
    });

    test('null on left → not qualifying', () {
      expect(cut([null, A, B, B, B, B], 1, 2), isFalse);
    });

    test('ping-pong left: [B, A | B, B] → not qualifying', () {
      // posA=1(A), posB=2(B), left(posA-1=0)=B==cB → ping-pong
      expect(cut([B, A, B, B, B, B, B], 1, 2), isFalse);
    });

    test('ping-pong right: [A, A | B, A, B] → not qualifying', () {
      // posA=1(A), posB=2(B), right(posB+1=3)=A==cA → ping-pong
      expect(cut([A, A, B, A, B, B, B], 1, 2), isFalse);
    });

    test('left-run check: single A stitch at posA → not qualifying', () {
      // [B, A, B, B, B] posA=1(A), posA-1=0=B ≠ cA → left run too short
      expect(cut([B, A, B, B, B], 1, 2), isFalse);
    });

    test('colour island: B appears 1× left and 4× right → not qualifying', () {
      // [A, A, B, A | B, B, B, B] — B straddles the cut
      expect(cut([A, A, B, A, B, B, B, B, B, B], 3, 4), isFalse);
    });
  });

  // ── PageConfig YAML migration ──────────────────────────────────────────────

  group('PageConfig.fromYaml — fuzzyAmount migration', () {
    test('new tolerance key is read correctly', () {
      final cfg = PageConfig.fromYaml({'enabled': true, 'pageWidth': 50, 'pageHeight': 50, 'tolerance': 6});
      expect(cfg.tolerance, equals(6));
    });

    test('legacy fuzzyAmount key maps to tolerance', () {
      final cfg = PageConfig.fromYaml({'enabled': true, 'pageWidth': 50, 'pageHeight': 50, 'fuzzyAmount': 2});
      expect(cfg.tolerance, equals(2),
          reason: 'fuzzyAmount=2 must map to tolerance=2');
    });

    test('tolerance takes precedence over fuzzyAmount when both present', () {
      final cfg = PageConfig.fromYaml({
        'enabled': true,
        'pageWidth': 50,
        'pageHeight': 50,
        'tolerance': 5,
        'fuzzyAmount': 1,
      });
      expect(cfg.tolerance, equals(5));
    });

    test('missing both keys → default tolerance=4', () {
      final cfg = PageConfig.fromYaml({'enabled': true, 'pageWidth': 50, 'pageHeight': 50});
      expect(cfg.tolerance, equals(4));
    });

    test('toYaml writes tolerance, not fuzzyAmount', () {
      const cfg = PageConfig(enabled: true, pageWidth: 50, pageHeight: 50, tolerance: 3);
      final yaml = cfg.toYaml();
      expect(yaml.containsKey('tolerance'), isTrue);
      expect(yaml.containsKey('fuzzyAmount'), isFalse);
      expect(yaml['tolerance'], equals(3));
    });

    test('round-trip: toYaml + fromYaml preserves tolerance', () {
      const cfg = PageConfig(enabled: true, pageWidth: 40, pageHeight: 30, tolerance: 6);
      final cfg2 = PageConfig.fromYaml(cfg.toYaml());
      expect(cfg2, equals(cfg));
    });
  });
}
