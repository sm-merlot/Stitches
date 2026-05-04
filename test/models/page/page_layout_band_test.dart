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

    test('cluster touches band edge, colour continues outside → tooBig', () {
      // Cluster at (3,0)-(5,0), band [3,7), colour A continues at col 2
      final cluster = {(3, 0), (4, 0), (5, 0)};
      final band = {enc(3, 0): A, enc(4, 0): A, enc(5, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, // colour A everywhere including outside
        band,
      );
      expect(result, equals(PageLayout.clTooBig));
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

    test('cluster touches right band edge, colour continues → tooBig', () {
      final cluster = {(4, 0), (5, 0), (6, 0)};
      final band = {enc(4, 0): A, enc(5, 0): A, enc(6, 0): A};
      final result = PageLayout.classifyCluster(
        cluster, 5, 3, 7, (p, c) => A, band,
      );
      expect(result, equals(PageLayout.clTooBig));
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

    test('multi-row cluster: one row clipped → tooBig', () {
      // Cluster spans (3,0)-(5,0) and (3,1)-(5,1)
      // Row 0: col 3 at band edge, colour continues at col 2
      final cluster = {(3, 0), (4, 0), (5, 0), (3, 1), (4, 1), (5, 1)};
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
}
