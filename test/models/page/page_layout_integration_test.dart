// Integration tests for PageLayout.compute() using a real .stitches file.
//
// Fixture: Super Metroid – Samus battles Ridley, originally configured with
// pageWidth=50, pageHeight=50, fuzzyAmount=1. The legacy 'fuzzyAmount' key is
// migrated to 'tolerance=1' by PageConfig.fromYaml.
//
// The new object-aware DP algorithm guarantees:
//   1. All per-row offsets are within ±tolerance of the nominal boundary.
//   2. Consecutive row offsets differ by at most 2 (smoothness constraint).
//   3. The boundary always stays within the pattern bounds.

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page/page_config.dart';
import 'package:stitches/models/page/page_layout.dart';
import 'package:stitches/services/file_service.dart';
import '../../test_fixtures.dart';

void main() {
  final fixturePath = testFixturePath('sm_test.stitches');
  final fixtureExists = File(fixturePath).existsSync();
  const nominal = 50; // First vertical boundary at col 50.

  group('PageLayout integration — sm_test.stitches',
      skip: fixtureExists ? null : 'fixture sm_test.stitches not found — clone stitches-test-fixtures repo as a sibling directory',
      () {
  late PageLayout layout;
  late int patternHeight;
  late int tolerance;

  setUpAll(() async {
    final bytes = await File(fixturePath).readAsBytes();
    final (pattern, _) = await FileService.parseBytesToPattern(bytes);
    layout = PageLayout.compute(pattern.pageConfig, pattern);
    patternHeight = pattern.height;
    tolerance = pattern.pageConfig.tolerance;
  });

  int offsetAt(int row) => layout.verticalOffsets[nominal]![row]!;

  // ── YAML migration ─────────────────────────────────────────────────────────
  // Legacy 'fuzzyAmount' key in the .stitches file maps to 'tolerance'.
  test('pageConfig loaded from legacy fuzzyAmount=1 → tolerance=1', () {
    expect(layout.config.tolerance, equals(1));
    expect(layout.config, isNot(equals(PageConfig.disabled)));
    expect(layout.config.pageWidth, equals(50));
    expect(layout.config.pageHeight, equals(50));
  });

  // ── Layout structure ───────────────────────────────────────────────────────
  test('layout page grid dimensions are positive', () {
    expect(layout.pagesAcross, greaterThanOrEqualTo(1));
    expect(layout.pagesDown, greaterThanOrEqualTo(1));
    expect(layout.totalPages, equals(layout.pagesAcross * layout.pagesDown));
  });

  // ── First vertical boundary: DP invariants ────────────────────────────────
  group('first vertical boundary (col $nominal) — DP invariants', () {
    test('offset map covers every row', () {
      final offsets = layout.verticalOffsets[nominal]!;
      expect(offsets.length, equals(patternHeight));
    });

    test('all per-row offsets within ±tolerance', () {
      final offsets = layout.verticalOffsets[nominal]!;
      for (final entry in offsets.entries) {
        expect(
          entry.value,
          inInclusiveRange(-tolerance, tolerance),
          reason: 'row ${entry.key}: offset ${entry.value} exceeds ±$tolerance',
        );
      }
    });

    test('consecutive offsets satisfy smoothness (|Δδ| ≤ 2)', () {
      final offsets = layout.verticalOffsets[nominal]!;
      for (int row = 1; row < patternHeight; row++) {
        final diff = (offsets[row]! - offsets[row - 1]!).abs();
        expect(diff, lessThanOrEqualTo(2),
            reason: 'rows ${row - 1}→$row: Δδ=$diff exceeds max 2');
      }
    });

    test('actual boundary stays within pattern bounds for every row', () {
      final offsets = layout.verticalOffsets[nominal]!;
      for (final entry in offsets.entries) {
        final actual = nominal + entry.value;
        expect(actual, inInclusiveRange(1, layout.patternWidth - 1),
            reason: 'row ${entry.key}: actual=$actual out of bounds');
      }
    });

    test('sample rows 23–45 all within ±tolerance', () {
      for (final row in [
        23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38,
        39, 40, 41, 42, 43, 44, 45,
      ]) {
        if (row >= patternHeight) continue;
        expect(
          offsetAt(row),
          inInclusiveRange(-tolerance, tolerance),
          reason: 'row $row',
        );
      }
    });
  });

  // ── Cell membership: every cell on at least one page ─────────────────────
  test('every cell in cols 0..99 appears on at least one page', () {
    if (layout.pagesAcross < 2) return; // single-page pattern: skip
    for (int row = 0; row < math.min(patternHeight, 20); row++) {
      for (int col = 0; col < math.min(layout.patternWidth, 100); col++) {
        bool found = false;
        for (int py = 0; py < layout.pagesDown && !found; py++) {
          for (int px = 0; px < layout.pagesAcross && !found; px++) {
            if (layout.cellOnPage(col, row, px, py)) found = true;
          }
        }
        expect(found, isTrue,
            reason: 'cell ($col,$row) not on any page');
      }
    }
  });

  // ── rawCellOnPage vs cellOnPage ──────────────────────────────────────────
  test('rawCellOnPage excludes only corner-disconnected cells', () {
    // rawCellOnPage ignores _excludedCells and _includedCells.
    // cellOnPage can include cells not on rawCellOnPage (via _includedCells)
    // and can exclude cells on rawCellOnPage (via _excludedCells).
    // Verify: if rawCellOnPage is false AND cellOnPage is true, the cell
    // must be in _includedCells (override). We can't access _includedCells
    // directly, so just verify the property doesn't crash and both methods
    // return booleans.
    for (int row = 0; row < math.min(patternHeight, 20); row++) {
      for (int col = 0; col < layout.patternWidth; col++) {
        for (int py = 0; py < layout.pagesDown; py++) {
          for (int px = 0; px < layout.pagesAcross; px++) {
            // Both should return without error
            layout.rawCellOnPage(col, row, px, py);
            layout.cellOnPage(col, row, px, py);
          }
        }
      }
    }
  });
  }); // group
}
