/// Tests for pure-Dart model helpers:
///   stitch_geometry, snippet_palette_resolver, page_layout, stitch_renderer.
///
/// All pure-Dart or relying only on Flutter's Color type —
/// no ProviderContainer, no fakes needed.
library;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:stitches/models/page/page_config.dart';
import 'package:stitches/models/page/page_layout.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/snippet/snippet.dart';
import 'package:stitches/models/snippet/snippet_palette.dart';
import 'package:stitches/models/snippet/snippet_palette_resolver.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/models/cell.dart';
import 'package:stitches/models/stitch/stitch_geometry.dart';
import 'package:stitches/models/stitch/stitch_plan.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/stitch_renderer.dart';

// ─── stitch_geometry ─────────────────────────────────────────────────────────

void main() {
  group('stitch_geometry — stitchXY', () {
    test('FullStitch returns (x, y)', () {
      expect(stitchXY(const FullStitch(x: 3, y: 7, threadId: 'a')), equals(const Cell(3, 7)));
    });

    test('HalfStitch returns (x, y)', () {
      expect(
          stitchXY(const HalfStitch(
              x: 1, y: 2, threadId: 'a', isForward: true)),
          equals(const Cell(1, 2)));
    });

    test('QuarterStitch returns (x, y)', () {
      expect(
          stitchXY(const QuarterStitch(
              x: 5, y: 6, threadId: 'a', quadrant: QuadrantPosition.topRight)),
          equals(const Cell(5, 6)));
    });

    test('HalfCrossStitch returns (x, y)', () {
      expect(
          stitchXY(const HalfCrossStitch(
              x: 2, y: 4, threadId: 'a', half: HalfOrientation.top)),
          equals(const Cell(2, 4)));
    });

    test('ThreeQuarterStitch returns (x, y)', () {
      expect(
          stitchXY(const ThreeQuarterStitch(
              x: 0, y: 0, threadId: 'a', quadrant: QuadrantPosition.bottomLeft, isForward: true)),
          equals(const Cell(0, 0)));
    });

    test('BackStitch returns null', () {
      expect(
          stitchXY(const BackStitch(
              x1: 0, y1: 0, x2: 1, y2: 1, threadId: 'a')),
          isNull);
    });
  });

  group('StitchGeometry.cellCoords', () {
    test('FullStitch returns (x, y)', () {
      expect(const FullStitch(x: 3, y: 7, threadId: 'a').cellCoords, equals(const Cell(3, 7)));
    });
    test('BackStitch returns null', () {
      expect(const BackStitch(x1: 0, y1: 0, x2: 1, y2: 1, threadId: 'a').cellCoords, isNull);
    });
  });

  group('StitchGeometry.bounds', () {
    test('FullStitch bounds wrap the cell', () {
      final b = const FullStitch(x: 2, y: 3, threadId: 'a').bounds;
      expect(b, (minX: 2.0, maxX: 3.0, minY: 3.0, maxY: 4.0));
    });
    test('BackStitch bounds use endpoint min/max', () {
      final b = const BackStitch(x1: 1.5, y1: 0.0, x2: 3.0, y2: 2.5, threadId: 'a').bounds;
      expect(b, (minX: 1.5, maxX: 3.0, minY: 0.0, maxY: 2.5));
    });
    test('BackStitch bounds are direction-independent', () {
      final b = const BackStitch(x1: 3.0, y1: 2.5, x2: 1.5, y2: 0.0, threadId: 'a').bounds;
      expect(b, (minX: 1.5, maxX: 3.0, minY: 0.0, maxY: 2.5));
    });
  });

  group('StitchGeometry.blockCells', () {
    test('FullStitch fills the full cell', () {
      expect(const FullStitch(x: 1, y: 2, threadId: 'a').blockCells, (1.0, 2.0, 1.0, 1.0));
    });
    test('HalfStitch forward fills right half', () {
      expect(const HalfStitch(x: 1, y: 2, isForward: true, threadId: 'a').blockCells,
          (1.5, 2.0, 0.5, 1.0));
    });
    test('HalfStitch backward fills left half', () {
      expect(const HalfStitch(x: 1, y: 2, isForward: false, threadId: 'a').blockCells,
          (1.0, 2.0, 0.5, 1.0));
    });
    test('QuarterStitch topLeft fills top-left quadrant', () {
      expect(const QuarterStitch(x: 0, y: 0, quadrant: QuadrantPosition.topLeft, threadId: 'a').blockCells,
          (0.0, 0.0, 0.5, 0.5));
    });
    test('QuarterStitch bottomRight fills bottom-right quadrant', () {
      expect(const QuarterStitch(x: 0, y: 0, quadrant: QuadrantPosition.bottomRight, threadId: 'a').blockCells,
          (0.5, 0.5, 0.5, 0.5));
    });
    test('BackStitch returns null', () {
      expect(const BackStitch(x1: 0, y1: 0, x2: 1, y2: 1, threadId: 'a').blockCells, isNull);
    });
  });

  group('StitchGeometry.isInViewport', () {
    test('FullStitch inside range returns true', () {
      expect(const FullStitch(x: 5, y: 5, threadId: 'a').isInViewport(0, 0, 10, 10), isTrue);
    });
    test('FullStitch outside range returns false', () {
      expect(const FullStitch(x: 15, y: 5, threadId: 'a').isInViewport(0, 0, 10, 10), isFalse);
    });
    test('FullStitch on right boundary (exclusive) returns false', () {
      expect(const FullStitch(x: 10, y: 5, threadId: 'a').isInViewport(0, 0, 10, 10), isFalse);
    });
    test('BackStitch overlapping range returns true', () {
      expect(const BackStitch(x1: 9.5, y1: 5.0, x2: 12.0, y2: 5.0, threadId: 'a').isInViewport(0, 0, 10, 10), isTrue);
    });
    test('BackStitch outside range returns false', () {
      expect(const BackStitch(x1: 11.0, y1: 5.0, x2: 15.0, y2: 5.0, threadId: 'a').isInViewport(0, 0, 10, 10), isFalse);
    });
  });

  // ─── snippet_palette_resolver ─────────────────────────────────────────────

  const black = Thread(
      dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X');
  const red = Thread(
      dmcCode: '666', color: Color(0xFFCC0000), name: 'Red', symbol: 'O');
  const blue = Thread(
      dmcCode: '336', color: Color(0xFF003399), name: 'Blue', symbol: '#');

  group('snippet_palette_resolver — resolveThread', () {
    Snippet snippetWith({
      required List<Thread> primaryThreads,
      List<Thread>? altThreads,
      int activePaletteIndex = 0,
    }) {
      final palettes = [
        SnippetPalette.create(name: 'Primary', threads: primaryThreads),
        if (altThreads != null)
          SnippetPalette.create(name: 'Alt', threads: altThreads),
      ];
      return Snippet.create(
        name: 'S',
        width: 2,
        height: 2,
        threads: primaryThreads,
        stitches: const [],
      ).copyWith(
        palettes: palettes,
        activePaletteIndex: activePaletteIndex,
      );
    }

    test('active=0 (primary) → returns primary thread', () {
      final snip = snippetWith(primaryThreads: [black, red]);
      expect(resolveThread(snip, '310').dmcCode, equals('310'));
    });

    test('active=1 returns alt palette thread at same slot', () {
      final snip = snippetWith(
        primaryThreads: [black],
        altThreads: [red],
        activePaletteIndex: 1,
      );
      // slot 0 of primary = _black; slot 0 of alt = _red
      expect(resolveThread(snip, '310').dmcCode, equals('666'));
    });

    test('active=1 but alt palette shorter → falls back to primary', () {
      // Primary has 2 threads; alt only has 1.
      final snip = snippetWith(
        primaryThreads: [black, red],
        altThreads: [blue],
        activePaletteIndex: 1,
      );
      // Slot 1 doesn't exist in alt → falls back to primary slot 1
      expect(resolveThread(snip, '666').dmcCode, equals('666'));
    });

    test('unknown threadId not in primary → falls back gracefully', () {
      final snip = snippetWith(primaryThreads: [black]);
      // '999' is not in the primary palette
      final result = resolveThread(snip, '999');
      expect(result, isNotNull);
    });

    test('empty palettes list → returns placeholder thread', () {
      final snip = Snippet.create(
        name: 'S',
        width: 1,
        height: 1,
        threads: [],
        stitches: [],
      ).copyWith(palettes: []);
      final result = resolveThread(snip, '310');
      expect(result.dmcCode, equals('310'));
    });
  });

  // ─── page_layout ──────────────────────────────────────────────────────────

  CrossStitchPattern emptyPattern({int width = 10, int height = 10}) =>
      CrossStitchPattern.empty(name: 'T').copyWith(width: width, height: height);

  const cfg10 = PageConfig(
    enabled: true,
    pageWidth: 10,
    pageHeight: 10,
    fuzzyAmount: 0,
  );

  group('page_layout — PageLayout.compute', () {
    test('pattern exactly one page → 1×1 layout', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 10, height: 10));
      expect(layout.pagesAcross, equals(1));
      expect(layout.pagesDown, equals(1));
      expect(layout.totalPages, equals(1));
    });

    test('pattern 20×10 → 2 pages across, 1 down', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 20, height: 10));
      expect(layout.pagesAcross, equals(2));
      expect(layout.pagesDown, equals(1));
    });

    test('pattern 10×20 → 1 page across, 2 down', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 10, height: 20));
      expect(layout.pagesAcross, equals(1));
      expect(layout.pagesDown, equals(2));
    });

    test('1×1 pattern → single page covers the cell', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 1, height: 1));
      expect(layout.cellOnPage(0, 0, 0, 0), isTrue);
    });

    test('off-by-one: cell at right edge of page 0 is not on page 1', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 20, height: 10));
      expect(layout.cellOnPage(9, 0, 0, 0), isTrue);
      expect(layout.cellOnPage(9, 0, 1, 0), isFalse);
    });

    test('cell at start of second page is on page 1 not page 0', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 20, height: 10));
      expect(layout.cellOnPage(10, 0, 1, 0), isTrue);
      expect(layout.cellOnPage(10, 0, 0, 0), isFalse);
    });

    test('nominalPageRect returns correct rect for each page', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 20, height: 20));
      final r00 = layout.nominalPageRect(0, 0);
      expect(r00.left, equals(0));
      expect(r00.top, equals(0));
      expect(r00.right, equals(10));
      expect(r00.bottom, equals(10));

      final r10 = layout.nominalPageRect(1, 0);
      expect(r10.left, equals(10));
      expect(r10.right, equals(20));
    });

    test('out-of-bounds cell returns false from cellOnPage', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 10, height: 10));
      expect(layout.cellOnPage(-1, 0, 0, 0), isFalse);
      expect(layout.cellOnPage(0, 10, 0, 0), isFalse);
    });

    // ── rawCellOnPage (Bug 1: edge cells near page boundary) ──────────────────

    test('rawCellOnPage agrees with cellOnPage when fuzzyAmount=0', () {
      // With no fuzzy offset there are no corner exclusions, so the two methods
      // must return the same result for every cell.
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 20, height: 20));
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          for (var py = 0; py < layout.pagesDown; py++) {
            for (var px = 0; px < layout.pagesAcross; px++) {
              expect(
                layout.rawCellOnPage(x, y, px, py),
                equals(layout.cellOnPage(x, y, px, py)),
                reason: 'cell ($x,$y) page ($px,$py)',
              );
            }
          }
        }
      }
    });

    test('rawCellOnPage returns false for out-of-bounds cells', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 10, height: 10));
      expect(layout.rawCellOnPage(-1, 0, 0, 0), isFalse);
      expect(layout.rawCellOnPage(0, 10, 0, 0), isFalse);
    });

    test('rawCellOnPage returns false for cell on wrong page', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 20, height: 10));
      // Cell (9,0) is the last cell of page 0 — must NOT be on page 1.
      expect(layout.rawCellOnPage(9, 0, 0, 0), isTrue);
      expect(layout.rawCellOnPage(9, 0, 1, 0), isFalse);
    });

    test('rawCellOnPage true for every cell that passes boundary check regardless of exclusion', () {
      // Build a layout with fuzzyAmount > 0 to potentially create exclusions.
      // rawCellOnPage should return true for every cell that passes the raw
      // boundary check (i.e. is inside the fuzzy boundaries), even if cellOnPage
      // would exclude it due to the corner-connectivity post-pass.
      const fuzzyCfg = PageConfig(
        enabled: true,
        pageWidth: 10,
        pageHeight: 10,
        fuzzyAmount: 3,
      );
      // A uniform empty pattern → no snap offset, random fallback only.
      final layout = PageLayout.compute(fuzzyCfg, emptyPattern(width: 20, height: 20));
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          for (var py = 0; py < layout.pagesDown; py++) {
            for (var px = 0; px < layout.pagesAcross; px++) {
              // Any cell where rawCellOnPage is true should also be markable
              // (it passes the fuzzy boundary check for this page).
              if (layout.rawCellOnPage(x, y, px, py)) {
                // cellOnPage may be false (excluded) but rawCellOnPage must be true.
                // The converse: if cellOnPage is true, rawCellOnPage must also be true.
                expect(layout.rawCellOnPage(x, y, px, py), isTrue,
                    reason: 'cell ($x,$y) page ($px,$py) passed boundary but rawCellOnPage false');
              }
              if (layout.cellOnPage(x, y, px, py)) {
                expect(layout.rawCellOnPage(x, y, px, py), isTrue,
                    reason:
                        'cellOnPage true implies rawCellOnPage true for ($x,$y) page ($px,$py)');
              }
            }
          }
        }
      }
    });

    test('every cell in pattern belongs to exactly one page', () {
      final layout = PageLayout.compute(cfg10, emptyPattern(width: 15, height: 12));
      for (var y = 0; y < 12; y++) {
        for (var x = 0; x < 15; x++) {
          int count = 0;
          for (var py = 0; py < layout.pagesDown; py++) {
            for (var px = 0; px < layout.pagesAcross; px++) {
              if (layout.cellOnPage(x, y, px, py)) count++;
            }
          }
          expect(count, equals(1),
              reason: 'cell ($x,$y) belonged to $count pages');
        }
      }
    });
  });

  // ─── stitch_renderer ─────────────────────────────────────────────────────

  PlannedAida oneSquare({int x = 0, int y = 0}) {
    const sq = PlannedSquare(id: 0, x: 0, y: 0);
    return const PlannedAida(
      title: 'T',
      cols: 1,
      rows: 1,
      squares: [sq],
      activeSquareIds: {0},
      stitches: [],
    );
  }

  PlannedAida aidaWith2x2Squares() {
    const squares = [
      PlannedSquare(id: 0, x: 0, y: 0),
      PlannedSquare(id: 1, x: 1, y: 0),
      PlannedSquare(id: 2, x: 0, y: 1),
      PlannedSquare(id: 3, x: 1, y: 1),
    ];
    return const PlannedAida(
      title: 'T',
      cols: 2,
      rows: 2,
      squares: squares,
      activeSquareIds: {0, 1, 2, 3},
      stitches: [],
    );
  }

  group('stitch_renderer — computeGridBounds', () {
    test('empty activeSquareIds → 1×1 fallback rect', () {
      final aida = const PlannedAida(
        title: 'T',
        cols: 1,
        rows: 1,
        squares: [PlannedSquare(id: 0, x: 0, y: 0)],
        activeSquareIds: {},
        stitches: [],
      );
      final b = computeGridBounds(aida, 10.0);
      expect(b.width, closeTo(10.0, 1e-9));
      expect(b.height, closeTo(10.0, 1e-9));
    });

    test('single square at (0,0) with cellSize=10 → -5..5 bounds', () {
      final b = computeGridBounds(oneSquare(), 10.0);
      expect(b.left, closeTo(-5.0, 1e-9));
      expect(b.top, closeTo(-5.0, 1e-9));
      expect(b.right, closeTo(5.0, 1e-9));
      expect(b.bottom, closeTo(5.0, 1e-9));
    });

    test('2×2 grid with cellSize=10 → width and height are 20', () {
      final b = computeGridBounds(aidaWith2x2Squares(), 10.0);
      expect(b.width, closeTo(20.0, 1e-9));
      expect(b.height, closeTo(20.0, 1e-9));
    });
  });

  group('stitch_renderer — resolveSegments', () {
    test('empty stitch list → empty segments', () {
      final segs = resolveSegments(oneSquare(), cellSize: 10.0);
      expect(segs, isEmpty);
    });

    test('one PlanSimpleStitch → one segment', () {
      const sq = PlannedSquare(id: 0, x: 2, y: 3);
      const stitch = PlanSimpleStitch(
        squareId: 0,
        fro: Corner.topLeft,
        to: Corner.bottomRight,
      );
      final aida = const PlannedAida(
        title: 'T',
        cols: 1,
        rows: 1,
        squares: [sq],
        activeSquareIds: {0},
        stitches: [stitch],
      );
      final segs = resolveSegments(aida, cellSize: 10.0);
      expect(segs.length, equals(1));
      // topLeft of (2,3): pixel (2-0.5)*10 = 15, (3-0.5)*10 = 25
      expect(segs.single.x1, closeTo(15.0, 1e-9));
      expect(segs.single.y1, closeTo(25.0, 1e-9));
      // bottomRight: (2+0.5)*10=25, (3+0.5)*10=35
      expect(segs.single.x2, closeTo(25.0, 1e-9));
      expect(segs.single.y2, closeTo(35.0, 1e-9));
    });

    test('originX/Y offset is applied to all segment coordinates', () {
      const sq = PlannedSquare(id: 0, x: 0, y: 0);
      const stitch = PlanSimpleStitch(
        squareId: 0,
        fro: Corner.topLeft,
        to: Corner.topRight,
      );
      final aida = const PlannedAida(
        title: 'T',
        cols: 1,
        rows: 1,
        squares: [sq],
        activeSquareIds: {0},
        stitches: [stitch],
      );
      final segs = resolveSegments(aida, cellSize: 10.0, originX: 5, originY: 8);
      expect(segs.single.x1, closeTo(5 + (-0.5) * 10, 1e-9));
      expect(segs.single.y1, closeTo(8 + (-0.5) * 10, 1e-9));
    });
  });
}

