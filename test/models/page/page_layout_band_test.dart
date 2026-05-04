// Unit tests for band-local analysis (v2 page boundary algorithm).
//
// Tests cover:
//   - extractBand: band cell extraction within tolerance of boundary
//   - detectLocalObjects: 8-directional flood-fill within band cells
//   - buildLocalClusters: same-colour proximity grouping
//   - classifyCluster: keep-whole vs too-big classification

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page/page_layout.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const int A = 1;
const int B = 2;
const int C = 3;

/// Encode a (primary, cross) cell as a single int key.
int enc(int p, int c) => (p << 16) | c;

/// Build a colorAt closure from a 2D grid (cross=row index, primary=col).
int? Function(int, int) colorMap2D(List<List<int?>> rows) =>
    (int primary, int crossIndex) =>
        (crossIndex >= 0 &&
                crossIndex < rows.length &&
                primary >= 0 &&
                primary < rows[crossIndex].length)
            ? rows[crossIndex][primary]
            : null;

/// Build a band color map from a 2D grid, extracting only cells in
/// [pMin, pMax) along the primary axis.
Map<int, int> bandFrom2D(List<List<int?>> rows, int pMin, int pMax) {
  final band = <int, int>{};
  for (int c = 0; c < rows.length; c++) {
    for (int p = pMin; p < pMax; p++) {
      if (p < rows[c].length) {
        final color = rows[c][p];
        if (color != null) band[enc(p, c)] = color;
      }
    }
  }
  return band;
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── bandBounds ──────────────────────────────────────────────────────────────

  group('bandBounds', () {
    test('nominal in middle → symmetric band', () {
      final (min, max) = PageLayout.bandBounds(50, 6, 100);
      expect(min, equals(44));
      expect(max, equals(56));
    });

    test('nominal near start → clamped at 0', () {
      final (min, max) = PageLayout.bandBounds(3, 6, 100);
      expect(min, equals(0));
      expect(max, equals(9));
    });

    test('nominal near end → clamped at maxBoundary', () {
      final (min, max) = PageLayout.bandBounds(97, 6, 100);
      expect(min, equals(91));
      expect(max, equals(100));
    });

    test('tolerance 0 → empty band', () {
      final (min, max) = PageLayout.bandBounds(50, 0, 100);
      expect(min, equals(max));
    });
  });

  // ── extractBand ─────────────────────────────────────────────────────────────

  group('extractBand', () {
    test('extracts only cells within tolerance band', () {
      // 10-wide pattern, boundary at col 5, tolerance 2 → band [3, 7)
      final band = PageLayout.extractBand(
        nominalBoundary: 5,
        tolerance: 2,
        maxBoundary: 10,
        maxCross: 1,
        colorAt: (p, c) => p < 10 ? A : null,
      );
      final primaries = band.keys.map((k) => k >> 16).toSet();
      expect(primaries, equals({3, 4, 5, 6}));
    });

    test('skips empty (null) cells', () {
      final band = PageLayout.extractBand(
        nominalBoundary: 5,
        tolerance: 2,
        maxBoundary: 10,
        maxCross: 1,
        colorAt: (p, c) => p == 4 ? null : A,
      );
      expect(band.containsKey(enc(4, 0)), isFalse);
      expect(band.containsKey(enc(3, 0)), isTrue);
    });

    test('includes all cross indices', () {
      final band = PageLayout.extractBand(
        nominalBoundary: 5,
        tolerance: 1,
        maxBoundary: 10,
        maxCross: 3,
        colorAt: (p, c) => A,
      );
      // Band [4, 6) × 3 rows = 6 cells
      expect(band.length, equals(6));
    });
  });

  // ── detectLocalObjects ──────────────────────────────────────────────────────

  group('detectLocalObjects', () {
    test('empty band → no objects', () {
      expect(PageLayout.detectLocalObjects({}), isEmpty);
    });

    test('single cell → one object', () {
      final objs = PageLayout.detectLocalObjects({enc(5, 0): A});
      expect(objs.length, equals(1));
      expect(objs.values.single, contains((5, 0)));
    });

    test('two adjacent same-colour cells → one object', () {
      final band = {enc(5, 0): A, enc(6, 0): A};
      final objs = PageLayout.detectLocalObjects(band);
      expect(objs.length, equals(1));
      expect(objs.values.single.length, equals(2));
    });

    test('diagonal same-colour cells → one object (8-directional)', () {
      final band = {enc(5, 0): A, enc(6, 1): A};
      final objs = PageLayout.detectLocalObjects(band);
      expect(objs.length, equals(1));
    });

    test('two same-colour cells with gap → two objects', () {
      // Cells at primary 5 and 7, gap at 6
      final band = {enc(5, 0): A, enc(7, 0): A};
      final objs = PageLayout.detectLocalObjects(band);
      expect(objs.length, equals(2));
    });

    test('adjacent different-colour cells → two objects', () {
      final band = {enc(5, 0): A, enc(6, 0): B};
      final objs = PageLayout.detectLocalObjects(band);
      expect(objs.length, equals(2));
    });

    test('band clipping: objects limited to band cells only', () {
      // Simulate a band [3, 7) — only include cells in that range.
      // A large same-colour region would be clipped at band edges.
      final band = <int, int>{};
      for (int p = 3; p < 7; p++) {
        band[enc(p, 0)] = A;
      }
      final objs = PageLayout.detectLocalObjects(band);
      expect(objs.length, equals(1));
      expect(objs.values.single.length, equals(4));
      // Verify no cells outside band
      for (final (p, _) in objs.values.single) {
        expect(p, inInclusiveRange(3, 6));
      }
    });

    test('L-shaped region within band → one object', () {
      final band = {
        enc(3, 0): A, enc(4, 0): A, enc(5, 0): A,
        enc(3, 1): A,
        enc(3, 2): A,
      };
      final objs = PageLayout.detectLocalObjects(band);
      expect(objs.length, equals(1));
      expect(objs.values.single.length, equals(5));
    });
  });

  // ── buildLocalClusters ──────────────────────────────────────────────────────

  group('buildLocalClusters', () {
    test('empty → empty', () {
      expect(PageLayout.buildLocalClusters({}, {}), isEmpty);
    });

    test('single object → single cluster', () {
      final objs = {0: {(5, 0), (6, 0)}};
      final band = {enc(5, 0): A, enc(6, 0): A};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      expect(clusters.length, equals(1));
    });

    test('two same-colour objects 1 cell apart → merged', () {
      // Object 0 at (3,0), Object 1 at (5,0) — gap at (4,0)
      final objs = {
        0: {(3, 0)},
        1: {(5, 0)},
      };
      final band = {enc(3, 0): A, enc(5, 0): A};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      expect(clusters.length, equals(1),
          reason: 'same colour, 1-cell gap → merged');
    });

    test('two different-colour objects 1 cell apart → NOT merged', () {
      final objs = {
        0: {(3, 0)},
        1: {(5, 0)},
      };
      final band = {enc(3, 0): A, enc(5, 0): B};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      expect(clusters.length, equals(2),
          reason: 'different colour → remain separate');
    });

    test('three same-colour objects in chain → all merge', () {
      final objs = {
        0: {(3, 0)},
        1: {(5, 0)},
        2: {(7, 0)},
      };
      final band = {enc(3, 0): A, enc(5, 0): A, enc(7, 0): A};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      expect(clusters.length, equals(1),
          reason: 'transitive chaining within band');
    });

    test('same-colour objects 3 cells apart → NOT merged', () {
      // Object 0 at (3,0), Object 1 at (6,0) — Chebyshev distance 3 > 2
      final objs = {
        0: {(3, 0)},
        1: {(6, 0)},
      };
      final band = {enc(3, 0): A, enc(6, 0): A};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      expect(clusters.length, equals(2),
          reason: '3-cell gap exceeds Chebyshev distance 2');
    });

    test('diagonal same-colour objects within Chebyshev 2 → merged', () {
      final objs = {
        0: {(3, 0)},
        1: {(5, 2)},
      };
      final band = {enc(3, 0): A, enc(5, 2): A};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      expect(clusters.length, equals(1));
    });

    test('mixed colours: only same-colour objects merge', () {
      // A at (3,0), B at (4,0), A at (5,0)
      // A objects should merge (gap bridged by B), B stays separate
      // Wait — Chebyshev between (3,0) and (5,0) is 2 → they merge (same colour)
      final objs = {
        0: {(3, 0)}, // A
        1: {(4, 0)}, // B
        2: {(5, 0)}, // A
      };
      final band = {enc(3, 0): A, enc(4, 0): B, enc(5, 0): A};
      final clusters = PageLayout.buildLocalClusters(objs, band);
      // A objects merge (Chebyshev 2), B stays separate
      expect(clusters.length, equals(2));
      // Find the A cluster
      final aCluster =
          clusters.values.firstWhere((cells) => cells.contains((3, 0)));
      expect(aCluster, contains((5, 0)),
          reason: 'same-colour A objects should merge');
      // B cluster is separate
      final bCluster =
          clusters.values.firstWhere((cells) => cells.contains((4, 0)));
      expect(bCluster.length, equals(1));
    });
  });

  // ── classifyCluster ─────────────────────────────────────────────────────────

  group('classifyCluster', () {
    test('cluster entirely left of nominal → noOp', () {
      final cluster = {(3, 0), (4, 0)};
      final band = {enc(3, 0): A, enc(4, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clNoOp));
    });

    test('cluster entirely right of nominal → noOp', () {
      final cluster = {(5, 0), (6, 0)};
      final band = {enc(5, 0): A, enc(6, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clNoOp));
    });

    test('cluster spans boundary, fits in band → keepWhole', () {
      final cluster = {(4, 0), (5, 0)};
      final band = {enc(4, 0): A, enc(5, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => null, band,
      );
      expect(result, equals(PageLayout.clKeepWhole));
    });

    test('cluster touches left band edge, colour continues outside → keepLeft',
        () {
      // Cluster at (3,0)-(5,0), band [3,7), colour A continues at col 2.
      // Extends beyond band on left only → keepLeft.
      final cluster = {(3, 0), (4, 0), (5, 0)};
      final band = {enc(3, 0): A, enc(4, 0): A, enc(5, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, // colour A everywhere including outside
        band,
      );
      expect(result, equals(PageLayout.clKeepLeft));
    });

    test('cluster touches band edge, colour changes outside → keepWhole', () {
      // Cluster at (3,0)-(5,0), band [3,7), colour B at col 2 (different)
      final cluster = {(3, 0), (4, 0), (5, 0)};
      final band = {enc(3, 0): A, enc(4, 0): A, enc(5, 0): A};
      final result = PageLayout.classifyCluster(
        cluster,
        5,
        3,
        7,
        (p, c) => p < 3 ? B : A, // different colour outside band
        band,
      );
      expect(result, equals(PageLayout.clKeepWhole));
    });

    test('cluster touches right band edge, colour continues → keepRight', () {
      // Cluster at (4,0)-(6,0), band [3,7). Touches bandMax-1=6,
      // colour continues at 7. Doesn't touch bandMin. → keepRight.
      final cluster = {(4, 0), (5, 0), (6, 0)};
      final band = {enc(4, 0): A, enc(5, 0): A, enc(6, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clKeepRight));
    });

    test('cluster touches band edge, empty outside → keepWhole', () {
      final cluster = {(3, 0), (4, 0), (5, 0)};
      final band = {enc(3, 0): A, enc(4, 0): A, enc(5, 0): A};
      final result = PageLayout.classifyCluster(
        cluster,
        5,
        3,
        7,
        (p, c) => (p >= 3 && p < 7) ? A : null, // empty outside band
        band,
      );
      expect(result, equals(PageLayout.clKeepWhole));
    });

    test('cluster at band edge 0 (pattern start) → keepWhole', () {
      // bandMin=0, can't peek left, so not clipped
      final cluster = {(0, 0), (1, 0)};
      final band = {enc(0, 0): A, enc(1, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 1, 0, 4, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clKeepWhole));
    });

    test('multi-row cluster: one row clipped on left → keepLeft', () {
      // Cluster spans (3,0)-(5,0) and (3,1)-(5,1)
      // Touches bandMin=3, colour continues at col 2. Doesn't touch bandMax.
      final cluster = {(3, 0), (4, 0), (5, 0), (3, 1), (4, 1), (5, 1)};
      final band = <int, int>{};
      for (final (p, c) in cluster) {
        band[enc(p, c)] = A;
      }
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clKeepLeft));
    });

    test('cluster extends both sides → tooBig', () {
      // Cluster spans full band [3,7), colour continues at both col 2 and 7.
      final cluster = {(3, 0), (4, 0), (5, 0), (6, 0)};
      final band = <int, int>{};
      for (final (p, c) in cluster) {
        band[enc(p, c)] = A;
      }
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clTooBig));
    });
  });

  // ── detectAnchors ───────────────────────────────────────────────────────────

  group('detectAnchors', () {
    /// Helper: build clusters from a 2D grid within band [bandMin, bandMax).
    /// Returns clusters via detectLocalObjects + buildLocalClusters.
    Map<int, Set<(int, int)>> clustersFrom2D(
        List<List<int?>> rows, int bandMin, int bandMax) {
      final band = bandFrom2D(rows, bandMin, bandMax);
      final objs = PageLayout.detectLocalObjects(band);
      return PageLayout.buildLocalClusters(objs, band);
    }

    test('clean A|B at nominal → anchor at δ=0', () {
      // 20 cols × 3 rows, boundary at 10, tolerance 5, band [5,15)
      // A on left, B on right → A cluster=15 cells, B cluster=15 cells
      final rows = List.generate(3, (_) => List.generate(20, (i) => i < 10 ? A : B));
      final clusters = clustersFrom2D(rows, 5, 15);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 10,
        tolerance: 5,
        bandMin: 5,
        bandMax: 15,
        maxBoundary: 20,
        maxCross: 3,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors[0], equals(0), reason: 'transition at nominal → δ=0');
    });

    test('A|B one right of nominal → anchor at δ=+1', () {
      // Transition at col 10|11, nominal=10, 3 rows
      final rows = List.generate(3, (_) => List.generate(20, (i) => i <= 10 ? A : B));
      final clusters = clustersFrom2D(rows, 5, 15);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 10,
        tolerance: 5,
        bandMin: 5,
        bandMax: 15,
        maxBoundary: 20,
        maxCross: 3,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors[0], equals(1));
    });

    test('no colour transition → no anchor', () {
      final rows = [List.filled(20, A)];
      final clusters = clustersFrom2D(rows, 6, 14);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 10,
        tolerance: 4,
        bandMin: 6,
        bandMax: 14,
        maxBoundary: 20,
        maxCross: 1,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors.containsKey(0), isFalse);
    });

    test('small objects below kMinAnchorSize → no anchor', () {
      // Two tiny objects: 3 cells A, 3 cells B
      // Band [4, 10), transition at 6|7
      final row = [null, null, null, null, A, A, A, B, B, B, null, null];
      final rows = [row];
      final clusters = clustersFrom2D(rows, 4, 10);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 7,
        tolerance: 3,
        bandMin: 4,
        bandMax: 10,
        maxBoundary: 12,
        maxCross: 1,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors.containsKey(0), isFalse,
          reason: 'both objects < kMinAnchorSize');
    });

    test('large object meets small object → anchor (max weight)', () {
      // 15 A cells + 3 B cells, transition at 14|15
      // Band [10, 18), nominal=14
      final row = List.generate(20, (i) => i < 15 ? A : (i < 18 ? B : null));
      final rows = [row];
      final clusters = clustersFrom2D(rows, 10, 18);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 14,
        tolerance: 4,
        bandMin: 10,
        bandMax: 18,
        maxBoundary: 20,
        maxCross: 1,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      // A cluster within band has 5 cells (cols 10-14), B has 3 cells (15-17)
      // max(5, 3) = 5 < kMinAnchorSize(8) → no anchor actually!
      // Need bigger objects. Let me think...
      // The A object outside the band (cols 0-9) isn't in localClusters.
      // Only band-local cells count. So we need ≥ 8 cells within the band.
      expect(anchors.containsKey(0), isFalse,
          reason: 'band-local sizes: A=5, B=3 — both below threshold');
    });

    test('large band-local objects → anchor found', () {
      // 20 A cells + 20 B cells, band [10, 30), nominal=20
      // A cluster: cols 10-19 = 10 cells, B cluster: cols 20-29 = 10 cells
      final row = List.generate(40, (i) => i < 20 ? A : B);
      final rows = [row];
      final clusters = clustersFrom2D(rows, 10, 30);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 20,
        tolerance: 10,
        bandMin: 10,
        bandMax: 30,
        maxBoundary: 40,
        maxCross: 1,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors[0], equals(0),
          reason: 'A|B transition at nominal, both ≥ kMinAnchorSize');
    });

    test('multiple transitions → highest weight wins', () {
      // Pattern: 10×A, 3×C, 10×B within band
      // Band [0, 23), nominal=12
      // Transitions: A|C at 9|10, C|B at 12|13
      // A cluster=10, C cluster=3, B cluster=10
      // A|C: max(10,3)=10, C|B: max(3,10)=10 → tie → closest to nominal wins
      // A|C delta = 10-12 = -2, C|B delta = 13-12 = +1 → C|B closer
      final row = [
        ...List.filled(10, A), // cols 0-9
        ...List.filled(3, C),  // cols 10-12
        ...List.filled(10, B), // cols 13-22
      ];
      final rows = [row];
      final clusters = clustersFrom2D(rows, 0, 23);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 12,
        tolerance: 12,
        bandMin: 0,
        bandMax: 23,
        maxBoundary: 23,
        maxCross: 1,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors[0], equals(1),
          reason: 'C|B transition at +1 is closer to nominal than A|C at -2');
    });

    test('multi-row: anchors at different positions per row', () {
      // Row 0: A|B at col 10 (nominal), Row 1: A|B at col 12 (+2)
      final rows = [
        List.generate(20, (i) => i < 10 ? A : B),
        List.generate(20, (i) => i < 12 ? A : B),
      ];
      final clusters = clustersFrom2D(rows, 6, 14);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 10,
        tolerance: 4,
        bandMin: 6,
        bandMax: 14,
        maxBoundary: 20,
        maxCross: 2,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      expect(anchors[0], equals(0), reason: 'row 0: transition at nominal');
      expect(anchors[1], equals(2), reason: 'row 1: transition at +2');
    });

    test('ping-pong pattern still produces anchor (keep-whole handles integrity)', () {
      // [B, A, B, B, ...] — previously rejected by isQualifyingCut, but
      // with v2 keep-whole + fragment reclamation, island prevention is
      // handled post-hoc. Anchor detection accepts all colour transitions.
      final row = [B, A, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B];
      final rows = [row];
      final clusters = clustersFrom2D(rows, 0, 20);
      final anchors = PageLayout.detectAnchors(
        nominalBoundary: 2,
        tolerance: 10,
        bandMin: 0,
        bandMax: 20,
        maxBoundary: 20,
        maxCross: 1,
        colorAt: colorMap2D(rows),
        localClusters: clusters,
      );
      // A|B transition at 1|2 — closest to nominal, large B cluster → anchor
      expect(anchors.containsKey(0), isTrue);
    });
  });

  // ── interpolateAnchors ──────────────────────────────────────────────────────

  group('interpolateAnchors', () {
    test('tolerance 0 → all zeros', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {3: 2},
        maxCross: 10,
        tolerance: 0,
        nominalBoundary: 50,
      );
      expect(result.length, equals(10));
      for (final v in result.values) {
        expect(v, equals(0));
      }
    });

    test('no anchors → all indices filled with fuzz', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      expect(result.length, equals(20));
      for (int i = 0; i < 20; i++) {
        expect(result.containsKey(i), isTrue, reason: 'index $i missing');
        expect(result[i], inInclusiveRange(-4, 4));
      }
    });

    test('no anchors → fuzz is not a straight line', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {},
        maxCross: 50,
        tolerance: 4,
        nominalBoundary: 50,
      );
      // With 50 rows and ±2 steps, should have some variation
      final distinct = result.values.toSet();
      expect(distinct.length, greaterThan(1),
          reason: 'fuzz should produce variation, not a flat line');
    });

    test('no anchors → fuzz is deterministic', () {
      final r1 = PageLayout.interpolateAnchors(
        anchors: {},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      final r2 = PageLayout.interpolateAnchors(
        anchors: {},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      expect(r1, equals(r2));
    });

    test('no anchors → different seeds produce different patterns', () {
      final r1 = PageLayout.interpolateAnchors(
        anchors: {},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      final r2 = PageLayout.interpolateAnchors(
        anchors: {},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 100,
      );
      // Not guaranteed to differ at every index, but should differ overall
      expect(r1, isNot(equals(r2)));
    });

    test('single anchor → anchor value preserved, rest fuzzed', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {10: 3},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      expect(result[10], equals(3), reason: 'anchor value preserved');
      expect(result.length, equals(20));
      for (final v in result.values) {
        expect(v, inInclusiveRange(-4, 4));
      }
    });

    test('two anchors → linear interpolation between them', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {0: -4, 20: 4},
        maxCross: 21,
        tolerance: 4,
        nominalBoundary: 50,
      );
      expect(result[0], equals(-4));
      expect(result[20], equals(4));
      // Middle should be near 0
      expect(result[10], inInclusiveRange(-2, 2));
      // Should be monotonically increasing (or near it)
      for (int i = 1; i <= 20; i++) {
        expect(result[i]! - result[i - 1]!, inInclusiveRange(-2, 2),
            reason: 'step $i violates ±2');
      }
    });

    test('adjacent values always satisfy ±2 step constraint', () {
      // Mix of anchors and gaps to stress the constraint
      final result = PageLayout.interpolateAnchors(
        anchors: {5: -3, 15: 3, 25: -2},
        maxCross: 30,
        tolerance: 4,
        nominalBoundary: 50,
      );
      for (int i = 1; i < 30; i++) {
        final step = (result[i]! - result[i - 1]!).abs();
        expect(step, lessThanOrEqualTo(2),
            reason: 'step at $i: ${result[i-1]} → ${result[i]}');
      }
    });

    test('all values within ±tolerance', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {10: 3, 20: -3},
        maxCross: 30,
        tolerance: 4,
        nominalBoundary: 50,
      );
      for (int i = 0; i < 30; i++) {
        expect(result[i]!.abs(), lessThanOrEqualTo(4),
            reason: 'index $i out of tolerance bounds');
      }
    });

    test('anchor value clamped to ±tolerance', () {
      // Anchor delta exceeds tolerance — should be clamped
      final result = PageLayout.interpolateAnchors(
        anchors: {5: 10},
        maxCross: 10,
        tolerance: 4,
        nominalBoundary: 50,
      );
      expect(result[5], equals(4), reason: 'anchor clamped to tolerance');
    });

    test('fuzz before first anchor connects smoothly', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {10: 2},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      // Step from index 9 to anchor at 10 should be ≤ 2
      expect((result[10]! - result[9]!).abs(), lessThanOrEqualTo(2));
    });

    test('fuzz after last anchor connects smoothly', () {
      final result = PageLayout.interpolateAnchors(
        anchors: {10: 2},
        maxCross: 20,
        tolerance: 4,
        nominalBoundary: 50,
      );
      // Step from anchor at 10 to index 11 should be ≤ 2
      expect((result[11]! - result[10]!).abs(), lessThanOrEqualTo(2));
    });

    test('fuzzStep produces values in [-2, +2]', () {
      for (int seed = 0; seed < 100; seed++) {
        for (int i = 0; i < 100; i++) {
          final step = PageLayout.fuzzStep(seed, i);
          expect(step, inInclusiveRange(-2, 2),
              reason: 'fuzzStep($seed, $i) = $step');
        }
      }
    });
  });

  // ── computeBoundaryOffsetsV2 (end-to-end) ─────────────────────────────────

  group('computeBoundaryOffsetsV2 — end-to-end', () {
    test('clean A|B boundary → snaps to colour transition', () {
      // 30 cols × 5 rows: A on left, B on right, transition at col 15
      final rows = List.generate(
          5, (_) => List.generate(30, (i) => i < 15 ? A : B));
      final result = PageLayout.computeBoundaryOffsetsV2(
        nominalBoundary: 15,
        tolerance: 4,
        maxBoundary: 30,
        maxCross: 5,
        colorAt: colorMap2D(rows),
      );
      // All rows should snap to the colour transition at col 15 → δ=0
      for (int i = 0; i < 5; i++) {
        expect(result[i], equals(0),
            reason: 'row $i should be at nominal (colour transition)');
      }
    });

    test('shifted A|B boundary → anchors follow transition', () {
      // Transition at col 17, nominal at 15 → should anchor at δ=+2
      final rows = List.generate(
          5, (_) => List.generate(30, (i) => i < 17 ? A : B));
      final result = PageLayout.computeBoundaryOffsetsV2(
        nominalBoundary: 15,
        tolerance: 4,
        maxBoundary: 30,
        maxCross: 5,
        colorAt: colorMap2D(rows),
      );
      for (int i = 0; i < 5; i++) {
        expect(result[i], equals(2),
            reason: 'row $i should follow A|B transition at col 17');
      }
    });

    test('uniform colour → fuzz (non-straight)', () {
      final rows = List.generate(50, (_) => List.filled(30, A));
      final result = PageLayout.computeBoundaryOffsetsV2(
        nominalBoundary: 15,
        tolerance: 4,
        maxBoundary: 30,
        maxCross: 50,
        colorAt: colorMap2D(rows),
      );
      expect(result.length, equals(50));
      final distinct = result.values.toSet();
      expect(distinct.length, greaterThan(1),
          reason: 'uniform colour should produce fuzz, not straight line');
    });

    test('all invariants hold: ±tolerance, ±2 step, full coverage', () {
      // Complex pattern: A left, B right, transition wobbles
      final rows = List.generate(20, (r) {
        final transition = 15 + (r % 3) - 1; // wobbles 14-16
        return List.generate(30, (c) => c < transition ? A : B);
      });
      final result = PageLayout.computeBoundaryOffsetsV2(
        nominalBoundary: 15,
        tolerance: 4,
        maxBoundary: 30,
        maxCross: 20,
        colorAt: colorMap2D(rows),
      );
      expect(result.length, equals(20));
      for (int i = 0; i < 20; i++) {
        expect(result[i]!.abs(), lessThanOrEqualTo(4),
            reason: 'row $i exceeds ±tolerance');
      }
      for (int i = 1; i < 20; i++) {
        expect((result[i]! - result[i - 1]!).abs(), lessThanOrEqualTo(2),
            reason: 'step $i violates ±2 smoothness');
      }
    });

    test('tolerance 0 → all zeros', () {
      final rows = List.generate(
          5, (_) => List.generate(30, (i) => i < 15 ? A : B));
      final result = PageLayout.computeBoundaryOffsetsV2(
        nominalBoundary: 15,
        tolerance: 0,
        maxBoundary: 30,
        maxCross: 5,
        colorAt: colorMap2D(rows),
      );
      for (final v in result.values) {
        expect(v, equals(0));
      }
    });

    test('keep-whole: small object spanning boundary stays intact', () {
      // Uniform A background with a small B object spanning the boundary
      // B at cols 14-16, rows 2-3 (6 cells, spans nominal at 15)
      final rows = List.generate(10, (r) {
        return List.generate(30, (c) {
          if (r >= 2 && r <= 3 && c >= 14 && c <= 16) return B;
          return A;
        });
      });
      final result = PageLayout.computeBoundaryOffsetsV2(
        nominalBoundary: 15,
        tolerance: 4,
        maxBoundary: 30,
        maxCross: 10,
        colorAt: colorMap2D(rows),
      );
      // At rows 2-3, the boundary should not cut through the B object.
      // B spans cols 14-16, so boundary should be at ≤14 or ≥17.
      for (final r in [2, 3]) {
        final actual = 15 + result[r]!;
        final cutsB = actual > 14 && actual <= 16;
        expect(cutsB, isFalse,
            reason: 'row $r: boundary at $actual cuts through B object (14-16)');
      }
    });
  });
}
