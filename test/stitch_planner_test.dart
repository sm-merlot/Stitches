import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stitchx/models/stitch_plan.dart';
import 'package:stitchx/services/stitch_planner.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<StitchType> stitchTypes(PlannedAida grid) => grid.stitches.map((s) => s.type).toList();

int? frontIndex(PlannedAida grid, int sqId, StitchType kind) {
  for (var i = 0; i < grid.stitches.length; i++) {
    final s = grid.stitches[i];
    if (s is PlanSimpleStitch && s.squareId == sqId && s.type == kind) return i;
  }
  return null;
}

List<(double, double, double, double)> backStitchCoords(PlannedAida grid) {
  final result = <(double, double, double, double)>[];
  const backTypes = {StitchType.backOne, StitchType.backTwo, StitchType.backThree};
  for (final s in grid.stitches) {
    if (!backTypes.contains(s.type)) continue;
    final double fx, fy, tx, ty;
    if (s is PlanSimpleStitch) {
      final sq = grid.squares[s.squareId];
      (fx, fy) = sq.cornerCoord(s.fro);
      (tx, ty) = sq.cornerCoord(s.to);
    } else if (s is PlanCrossStitch) {
      (fx, fy) = grid.squares[s.fro.squareId].cornerCoord(s.fro.corner);
      (tx, ty) = grid.squares[s.to.squareId].cornerCoord(s.to.corner);
    } else {
      continue;
    }
    result.add((fx, fy, tx, ty));
  }
  return result;
}

double maxJump(PlannedAida grid) {
  var worst = 0.0;
  for (final (fx, fy, tx, ty) in backStitchCoords(grid)) {
    worst = max(worst, sqrt((fx - tx) * (fx - tx) + (fy - ty) * (fy - ty)));
  }
  return worst;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('alternation', () {
    void check(PlannedAida grid, String label) {
      final types = stitchTypes(grid);
      expect(types, isNotEmpty, reason: '$label: no stitches generated');
      for (var i = 0; i < types.length; i++) {
        final expected = i % 2 == 0 ? 'Front' : 'Back';
        expect(types[i].name, contains(expected.toLowerCase()),
            reason: '$label: position $i expected $expected, got ${types[i]}');
      }
    }

    test('single cell', () => check(planStitching(title: '1x1', cols: 1, rows: 1, cells: [(0, 0)]), '1x1'));

    test('horizontal row', () => check(
        planStitching(title: '3x1', cols: 3, rows: 1, cells: [for (var x = 0; x < 3; x++) (x, 0)]), '3x1'));

    test('vertical column', () => check(
        planStitching(title: '1x3', cols: 1, rows: 3, cells: [for (var y = 0; y < 3; y++) (0, y)]), '1x3'));

    test('rectangle', () => check(
        planStitching(
            title: '3x3',
            cols: 3,
            rows: 3,
            cells: [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)]),
        '3x3'));

    test('l shape', () => check(
        planStitching(
            title: 'L',
            cols: 4,
            rows: 2,
            cells: [...[for (var x = 0; x < 4; x++) (x, 0)], (0, 1), (1, 1)]),
        'L'));

    test('gapped row', () => check(
        planStitching(title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]),
        'gapped'));

    test('staircase', () => check(
        planStitching(
            title: 'staircase',
            cols: 5,
            rows: 3,
            cells: [
              ...[for (var x = 0; x < 3; x++) (x, 0)],
              ...[for (var x = 1; x < 4; x++) (x, 1)],
              ...[for (var x = 2; x < 5; x++) (x, 2)],
            ]),
        'staircase'));
  });

  // -------------------------------------------------------------------------
  group('front_one_before_front_two', () {
    void check(PlannedAida grid, String label) {
      for (final sqId in grid.activeSquareIds) {
        final f1 = frontIndex(grid, sqId, StitchType.frontOne);
        final f2 = frontIndex(grid, sqId, StitchType.frontTwo);
        if (f1 != null && f2 != null) {
          expect(f1, lessThan(f2),
              reason: '$label: cell $sqId FrontOne at $f1, FrontTwo at $f2');
        }
      }
    }

    test('single cell', () => check(planStitching(title: '1x1', cols: 1, rows: 1, cells: [(0, 0)]), '1x1'));

    test('horizontal row', () => check(
        planStitching(title: '3x1', cols: 3, rows: 1, cells: [for (var x = 0; x < 3; x++) (x, 0)]), '3x1'));

    test('vertical column', () => check(
        planStitching(title: '1x3', cols: 1, rows: 3, cells: [for (var y = 0; y < 3; y++) (0, y)]), '1x3'));

    test('rectangle', () => check(
        planStitching(
            title: '3x3',
            cols: 3,
            rows: 3,
            cells: [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)]),
        '3x3'));

    test('l shape', () => check(
        planStitching(
            title: 'L',
            cols: 4,
            rows: 2,
            cells: [...[for (var x = 0; x < 4; x++) (x, 0)], (0, 1), (1, 1)]),
        'L'));

    test('gapped row', () => check(
        planStitching(title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]),
        'gapped'));

    test('staircase', () => check(
        planStitching(
            title: 'staircase',
            cols: 5,
            rows: 3,
            cells: [
              ...[for (var x = 0; x < 3; x++) (x, 0)],
              ...[for (var x = 1; x < 4; x++) (x, 1)],
              ...[for (var x = 2; x < 5; x++) (x, 2)],
            ]),
        'staircase'));
  });

  // -------------------------------------------------------------------------
  group('no_zero_distance_back', () {
    void check(PlannedAida grid, String label) {
      for (final (fx, fy, tx, ty) in backStitchCoords(grid)) {
        final d = sqrt((fx - tx) * (fx - tx) + (fy - ty) * (fy - ty));
        expect(d, greaterThan(1e-9),
            reason: '$label: zero-length back stitch at ($fx,$fy)');
      }
    }

    test('single cell', () => check(planStitching(title: '1x1', cols: 1, rows: 1, cells: [(0, 0)]), '1x1'));

    test('rectangle', () => check(
        planStitching(
            title: '3x3',
            cols: 3,
            rows: 3,
            cells: [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)]),
        '3x3'));

    test('gapped row', () => check(
        planStitching(title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]),
        'gapped'));
  });

  // -------------------------------------------------------------------------
  group('no_diagonal_back', () {
    void check(PlannedAida grid, String label) {
      for (final (fx, fy, tx, ty) in backStitchCoords(grid)) {
        final isHV = (fx - tx).abs() < 1e-9 || (fy - ty).abs() < 1e-9;
        expect(isHV, isTrue,
            reason: '$label: diagonal back stitch ($fx,$fy)->($tx,$ty)');
      }
    }

    test('single cell', () => check(planStitching(title: '1x1', cols: 1, rows: 1, cells: [(0, 0)]), '1x1'));

    test('horizontal row', () => check(
        planStitching(title: '3x1', cols: 3, rows: 1, cells: [for (var x = 0; x < 3; x++) (x, 0)]), '3x1'));

    test('rectangle', () => check(
        planStitching(
            title: '3x3',
            cols: 3,
            rows: 3,
            cells: [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)]),
        '3x3'));

    test('l shape', () => check(
        planStitching(
            title: 'L',
            cols: 4,
            rows: 2,
            cells: [...[for (var x = 0; x < 4; x++) (x, 0)], (0, 1), (1, 1)]),
        'L'));

    test('gapped row', () => check(
        planStitching(title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]),
        'gapped'));

    test('staircase', () => check(
        planStitching(
            title: 'staircase',
            cols: 5,
            rows: 3,
            cells: [
              ...[for (var x = 0; x < 3; x++) (x, 0)],
              ...[for (var x = 1; x < 4; x++) (x, 1)],
              ...[for (var x = 2; x < 5; x++) (x, 2)],
            ]),
        'staircase'));
  });

  // -------------------------------------------------------------------------
  group('stitch_count', () {
    void check(PlannedAida grid, int nCells, String label) {
      final expected = 4 * nCells - 1;
      expect(grid.stitches.length, expected,
          reason: '$label: expected $expected stitches, got ${grid.stitches.length}');
    }

    test('single cell', () => check(planStitching(title: '1x1', cols: 1, rows: 1, cells: [(0, 0)]), 1, '1x1'));

    test('horizontal row', () => check(
        planStitching(title: '3x1', cols: 3, rows: 1, cells: [for (var x = 0; x < 3; x++) (x, 0)]), 3, '3x1'));

    test('vertical column', () => check(
        planStitching(title: '1x3', cols: 1, rows: 3, cells: [for (var y = 0; y < 3; y++) (0, y)]), 3, '1x3'));

    test('rectangle', () => check(
        planStitching(
            title: '3x3',
            cols: 3,
            rows: 3,
            cells: [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)]),
        9, '3x3'));
  });

  // -------------------------------------------------------------------------
  group('empty_grid', () {
    test('no cells returns empty', () {
      final grid = planStitching(title: 'empty', cols: 3, rows: 3, cells: []);
      expect(grid.stitches, isEmpty);
    });

    test('cells outside grid ignored', () {
      final grid = planStitching(title: 'out', cols: 2, rows: 2, cells: [(5, 5)]);
      expect(grid.stitches, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('starts_at_corner', () {
    (int, int) startCell(PlannedAida grid) {
      final s = grid.stitches.first as PlanSimpleStitch;
      final sq = grid.squares[s.squareId];
      return (sq.x, sq.y);
    }

    Set<(int, int)> boundingCorners(List<(int, int)> cells) {
      final xs = cells.map((c) => c.$1).toList();
      final ys = cells.map((c) => c.$2).toList();
      final minX = xs.reduce(min), maxX = xs.reduce(max);
      final minY = ys.reduce(min), maxY = ys.reduce(max);
      return {(minX, minY), (maxX, minY), (minX, maxY), (maxX, maxY)};
    }

    test('rectangle starts at corner', () {
      final cells = [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)];
      final grid = planStitching(title: '3x3', cols: 3, rows: 3, cells: cells);
      expect(boundingCorners(cells), contains(startCell(grid)));
    });

    test('wide rectangle starts at corner', () {
      final cells = [for (var x = 0; x < 4; x++) for (var y = 0; y < 3; y++) (x, y)];
      final grid = planStitching(title: '4x3', cols: 4, rows: 3, cells: cells);
      expect(boundingCorners(cells), contains(startCell(grid)));
    });

    test('l shape starts at corner', () {
      final cells = [...[for (var x = 0; x < 4; x++) (x, 0)], (0, 1), (1, 1)];
      final grid = planStitching(title: 'L', cols: 4, rows: 2, cells: cells);
      expect(boundingCorners(cells), contains(startCell(grid)));
    });

    // Screen coords: preferred corners are (minX, minY) = top-left and
    // (maxX, maxY) = bottom-right (the main diagonal of the bounding box).
    test('preferred corner is top-left or bottom-right', () {
      final cells = [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)];
      final grid = planStitching(title: '3x3', cols: 3, rows: 3, cells: cells);
      final start = startCell(grid);
      final allXs = cells.map((c) => c.$1).toList();
      final allYs = cells.map((c) => c.$2).toList();
      // top-left = (minX, minY), bottom-right = (maxX, maxY) in screen coords
      final preferred = {
        (allXs.reduce(min), allYs.reduce(min)),
        (allXs.reduce(max), allYs.reduce(max)),
      };
      expect(preferred, contains(start));
    });
  });

  // -------------------------------------------------------------------------
  group('gapped_row_jumps', () {
    test('max jump is two not four', () {
      final grid = planStitching(
          title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]);
      expect(maxJump(grid), lessThanOrEqualTo(2.0 + 1e-9),
          reason: 'expected max jump ≤ 2.0 for gapped row');
    });

    test('jump count', () {
      final grid = planStitching(
          title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]);
      final jumps = backStitchCoords(grid)
          .where((c) => sqrt((c.$1 - c.$3) * (c.$1 - c.$3) + (c.$2 - c.$4) * (c.$2 - c.$4)) > 1.0 + 1e-9)
          .toList();
      expect(jumps.length, 2, reason: 'expected exactly 2 jumps for gapped row');
    });
  });

  // -------------------------------------------------------------------------
  group('back_stitch_segment_styles', () {
    const backTypes = {StitchType.backOne, StitchType.backTwo, StitchType.backThree};

    List<(double, double, double, double, StitchType)> backEntries(PlannedAida grid) {
      final result = <(double, double, double, double, StitchType)>[];
      for (final s in grid.stitches) {
        if (!backTypes.contains(s.type)) continue;
        final double fx, fy, tx, ty;
        if (s is PlanSimpleStitch) {
          final sq = grid.squares[s.squareId];
          (fx, fy) = sq.cornerCoord(s.fro);
          (tx, ty) = sq.cornerCoord(s.to);
        } else if (s is PlanCrossStitch) {
          (fx, fy) = grid.squares[s.fro.squareId].cornerCoord(s.fro.corner);
          (tx, ty) = grid.squares[s.to.squareId].cornerCoord(s.to.corner);
        } else {
          continue;
        }
        result.add((fx, fy, tx, ty, s.type));
      }
      return result;
    }

    Set<String> segments(double fx, double fy, double tx, double ty) {
      final segs = <String>{};
      if ((fy - ty).abs() < 1e-9) {
        var x = min(fx, tx);
        final xHi = max(fx, tx);
        while (x < xHi - 1e-9) {
          segs.add('h:${(fy * 2).round()}:${(x * 2).round()}');
          x += 1.0;
        }
      } else {
        var y = min(fy, ty);
        final yHi = max(fy, ty);
        while (y < yHi - 1e-9) {
          segs.add('v:${(fx * 2).round()}:${(y * 2).round()}');
          y += 1.0;
        }
      }
      return segs;
    }

    void check(PlannedAida grid, String label) {
      final backs = backEntries(grid);
      for (var i = 0; i < backs.length; i++) {
        for (var j = i + 1; j < backs.length; j++) {
          final a = backs[i];
          final b = backs[j];
          if (a.$5 == b.$5) {
            final segsA = segments(a.$1, a.$2, a.$3, a.$4);
            final segsB = segments(b.$1, b.$2, b.$3, b.$4);
            final overlap = segsA.intersection(segsB);
            expect(overlap, isEmpty,
                reason: '$label: back stitches share segment(s) $overlap with same style ${a.$5}');
          }
        }
      }
    }

    test('rectangle', () => check(
        planStitching(
            title: '3x3',
            cols: 3,
            rows: 3,
            cells: [for (var x = 0; x < 3; x++) for (var y = 0; y < 3; y++) (x, y)]),
        '3x3'));

    test('horizontal row', () => check(
        planStitching(title: '5x1', cols: 5, rows: 1, cells: [for (var x = 0; x < 5; x++) (x, 0)]),
        '5x1'));

    test('gapped row', () => check(
        planStitching(title: 'gapped', cols: 5, rows: 1, cells: [(0, 0), (1, 0), (3, 0), (4, 0)]),
        'gapped'));

    test('staircase', () => check(
        planStitching(
            title: 'staircase',
            cols: 5,
            rows: 3,
            cells: [
              ...[for (var x = 0; x < 3; x++) (x, 0)],
              ...[for (var x = 1; x < 4; x++) (x, 1)],
              ...[for (var x = 2; x < 5; x++) (x, 2)],
            ]),
        'staircase'));
  });

  // -------------------------------------------------------------------------
  group('end_run_order', () {
    // Order-preserving deduplication (equivalent to Python's dict.fromkeys).
    List<T> uniqueOrdered<T>(List<T> items) {
      final seen = <T>{};
      return [for (final item in items) if (seen.add(item)) item];
    }

    bool listsEqual<T>(List<T> a, List<T> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    List<(int, int)> lastFrontCells(PlannedAida grid, int n) {
      final fronts = grid.stitches
          .where((s) => s.type == StitchType.frontOne || s.type == StitchType.frontTwo)
          .toList();
      final lastN = fronts.sublist(fronts.length - n);
      return lastN.map((s) {
        final sq = grid.squares[(s as PlanSimpleStitch).squareId];
        return (sq.x, sq.y);
      }).toList();
    }

    test('horizontal row 5 cells ends in run order', () {
      final cells = [for (var x = 0; x < 5; x++) (x, 0)];
      final grid = planStitching(title: '5x1', cols: 5, rows: 1, cells: cells);
      final last3Cells = lastFrontCells(grid, 6); // 6 front stitches = last 3 cells
      final unique = uniqueOrdered(last3Cells);
      final xs = unique.map((c) => c.$1).toList();
      expect(unique.length, 3, reason: 'last 3 cells should be 3 distinct cells');
      final sorted = [...xs]..sort();
      final sortedDesc = [...xs]..sort((a, b) => b.compareTo(a));
      expect(listsEqual(xs, sorted) || listsEqual(xs, sortedDesc), isTrue,
          reason: 'last 3 cells must be in run order, got $unique');
    });

    test('vertical column 4 cells ends in run cells', () {
      // In screen coords, BL(0,y) == TL(0,y+1) (shared corner), which can
      // cause d=0 for fwd direction and alter visit ordering within the end run.
      // We verify the reservation mechanism is correct: the last 3 unique cells
      // are all from the end of the run (not the start cell), in any order.
      final cells = [for (var y = 0; y < 4; y++) (0, y)];
      final grid = planStitching(title: '1x4', cols: 1, rows: 4, cells: cells);
      final last3Cells = lastFrontCells(grid, 6);
      final unique = uniqueOrdered(last3Cells);
      expect(unique.length, 3, reason: 'should have 3 distinct end cells, got $unique');
      // All 3 must be from the end of the run — not the start cell (0,0).
      const endRunCells = {(0, 1), (0, 2), (0, 3)};
      for (final cell in unique) {
        expect(endRunCells, contains(cell),
            reason: 'last 3 cells should be from end of run, got $unique');
      }
    });

    test('short run no reservation', () {
      final cells = [for (var x = 0; x < 3; x++) (x, 0)];
      final grid = planStitching(title: '3x1', cols: 3, rows: 1, cells: cells);
      final types = stitchTypes(grid);
      expect(types, isNotEmpty);
      for (var i = 0; i < types.length; i++) {
        final expected = i % 2 == 0 ? 'front' : 'back';
        expect(types[i].name, contains(expected),
            reason: 'position $i expected $expected, got ${types[i]}');
      }
    });
  });
}
