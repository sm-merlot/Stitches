// test/page_layout_integration_test.dart
//
// Integration tests for PageLayout.compute() using a real .stitches file.
//
// The fixture is Super Metroid – Samus battles Ridley, configured with
// pageWidth=50, pageHeight=50, fuzzyAmount=1.  The first vertical boundary
// sits at col 50 and exercises all of the snap heuristics across a wide range
// of row types:
//
//   rows 17–20  decorative border  q9*****q  → snaps to (q | 9) at col 49
//   rows 21–22  solid q band       no transition → random fallback ±1
//   rows 23–29  main sprite body   A/8/P mix → snaps to colour transitions
//   row  30     solid A band       no transition → random fallback ±1
//   rows 31–35  mixed C/A/D/E      → snaps to colour transitions
//   rows 36–37  long C run right   → snaps at far edge (offset ±4)
//   row  38     solid A around col 50 → random fallback ±1
//   rows 39–45  C/A/q region       → snaps to colour transitions

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page/page_layout.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/stitch_compositor.dart';
import 'test_fixtures.dart';

void main() {
  final fixturePath = testFixturePath('sm_test.stitches');
  // The fixture is configured with pageWidth=50 — the first boundary is col 50.
  const nominal = 50;

  late PageLayout layout;
  late Map<int, int?> snapColor;
  late Map<int, String> indexToSym;

  setUpAll(() async {
    final bytes = await File(fixturePath).readAsBytes();
    final (pattern, _) = await FileService.parseBytesToPattern(bytes);

    layout = PageLayout.compute(pattern.pageConfig, pattern);

    // Mirror PageLayout.compute: use StitchCompositor for the canonical
    // visible-stitch view (same source of truth as the algo).
    final composite = StitchCompositor.computeLayer(pattern);
    final threadList = pattern.threads.values.toList();
    final threadIndex = <String, int>{
      for (int i = 0; i < threadList.length; i++)
        threadList[i].dmcCode: i,
    };
    indexToSym = {
      for (int i = 0; i < threadList.length; i++)
        i: threadList[i].symbol,
    };
    snapColor = {};
    for (final entry in composite.fullStitches.entries) {
      final col = entry.key.x;
      final row = entry.key.y;
      final idx = threadIndex[entry.value.resolvedThread.dmcCode];
      if (idx != null) snapColor[(col << 16) | row] = idx;
    }
  });

  String symAt(int col, int row) {
    final idx = snapColor[(col << 16) | row];
    return idx == null ? '.' : (indexToSym[idx] ?? '?');
  }

  int offsetAt(int row) => layout.verticalOffsets[nominal]![row]!;

  // ── Decorative border rows ────────────────────────────────────────────────
  // Rows 17–20 have the repeating pattern q9*****q across the boundary.
  // Thread '9' is a single isolated stitch at col 49 — it should NOT be left
  // stranded on the left page.  The snap must step back one to q|9 (col 48|49)
  // so that '9' starts the right page along with the '****' block it belongs to.
  group('first vertical boundary (col $nominal) — decorative border rows 17–20', () {
    for (final row in [17, 18, 19, 20]) {
      test('row $row snaps to (q | 9) offset=-1', () {
        final offset = offsetAt(row);
        expect(offset, -1,
            reason: 'row $row: expected cut at col 49 (q|9), '
                'got offset=$offset → col ${nominal + offset}');
        expect(symAt(nominal + offset - 1, row), 'q');
        expect(symAt(nominal + offset, row), '9');
      });
    }
  });

  // ── Main sprite body rows ─────────────────────────────────────────────────
  // Rows 23–29 sit in the sprite area with A/8/P colour blocks crossing the
  // boundary.  Each row should snap to a genuine colour transition nearby.
  group('first vertical boundary (col $nominal) — sprite body rows 23–29', () {
    for (final row in [23, 24, 25, 26, 27, 28, 29]) {
      test('row $row snaps to a colour transition within ±2', () {
        final offset = offsetAt(row);
        final cutCol = nominal + offset;
        expect(
          symAt(cutCol - 1, row),
          isNot(equals(symAt(cutCol, row))),
          reason: 'row $row offset=$offset: cut at col $cutCol should be '
              'between two different colours, '
              'got (${symAt(cutCol - 1, row)} | ${symAt(cutCol, row)})',
        );
        expect(offset, inInclusiveRange(-2, 1),
            reason: 'row $row: offset=$offset is outside expected range');
      });
    }
  });

  // ── Random-fallback rows ──────────────────────────────────────────────────
  // Rows 21–22 are a solid 'q' band with no colour transition near the
  // boundary.  The algorithm falls back to a seeded random offset.
  group('first vertical boundary (col $nominal) — solid band rows 21–22', () {
    for (final row in [21, 22]) {
      test('row $row falls back within fuzzyAmount=1', () {
        final offset = offsetAt(row);
        expect(offset, inInclusiveRange(-1, 1),
            reason: 'row $row solid band: offset=$offset outside ±1');
      });
    }
  });

  // ── Mixed C/A/D/E region rows 31–35 ──────────────────────────────────────
  // Each row in the mixed region should snap to a genuine colour transition.
  group('first vertical boundary (col $nominal) — mixed C/A/D/E rows 31–35', () {
    for (final row in [31, 32, 33, 34, 35]) {
      test('row $row snaps to a colour transition', () {
        final offset = offsetAt(row);
        final cutCol = nominal + offset;
        expect(
          symAt(cutCol - 1, row),
          isNot(equals(symAt(cutCol, row))),
          reason: 'row $row offset=$offset: cut at col $cutCol should be '
              'between two different colours, '
              'got (${symAt(cutCol - 1, row)} | ${symAt(cutCol, row)})',
        );
      });
    }
  });

  // ── Solid A row 30 and row 38 ─────────────────────────────────────────────
  // Rows 30 and 38 have only A stitches near the boundary — random fallback.
  group('first vertical boundary (col $nominal) — solid A rows 30, 38', () {
    for (final row in [30, 38]) {
      test('row $row falls back within fuzzyAmount=1', () {
        expect(offsetAt(row), inInclusiveRange(-1, 1));
      });
    }
  });

  // ── Long-C-run rows 36–37 ─────────────────────────────────────────────────
  // Rows 36–37 have a long C block around the boundary.  With vertical-column
  // scoring, the algorithm now prefers the C column at col 45–46 (consistent
  // with adjacent rows 31–35) over the far-right C|q at col 54.
  group('first vertical boundary (col $nominal) — long C run rows 36–37', () {
    for (final row in [36, 37]) {
      test('row $row snaps to a colour transition (vertical-column consistent)', () {
        final offset = offsetAt(row);
        final cutCol = nominal + offset;
        expect(
          symAt(cutCol - 1, row),
          isNot(equals(symAt(cutCol, row))),
          reason: 'row $row should snap to a colour transition, '
              'got (${symAt(cutCol - 1, row)} | ${symAt(cutCol, row)})',
        );
      });
    }
  });

  // ── C/A/q region rows 39–45 ──────────────────────────────────────────────
  // Each row in this region should snap to a genuine colour transition.
  group('first vertical boundary (col $nominal) — C/A/q region rows 39–45', () {
    for (final row in [39, 40, 41, 42, 43, 44, 45]) {
      test('row $row snaps to a colour transition', () {
        final offset = offsetAt(row);
        final cutCol = nominal + offset;
        expect(
          symAt(cutCol - 1, row),
          isNot(equals(symAt(cutCol, row))),
          reason: 'row $row offset=$offset: cut at col $cutCol should be '
              'between two different colours, '
              'got (${symAt(cutCol - 1, row)} | ${symAt(cutCol, row)})',
        );
      });
    }
  });
}

