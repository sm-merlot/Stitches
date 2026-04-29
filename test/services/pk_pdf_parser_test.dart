/// Tests for PatternKeeper PDF parser logic and round-trip fidelity.
///
/// Uses [PatternKeeperParser.tryParseFromText] with synthetic [PageTextData]
/// so tests run in pure Dart without native pdfium libraries.
///
/// Coverage:
///   • Legend parsing: symbol ↔ DMC code extraction from text fragments
///   • Grid parsing: symbol placement, PKCHART markers, outlier filtering
///   • Multi-page assembly: absolute offsets, vertical/horizontal stacking
///   • Round-trip: pattern → PK PDF text repr → re-parse → compare
///
/// Run with: flutter test test/pk_pdf_parser_test.dart --no-pub
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:stitches/data/dmc_colors.dart';
import 'package:stitches/services/pdf_pattern_keeper_parser.dart';
import 'package:stitches/services/scan/scan_result.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Create a text fragment at a given position. Height defaults to 10 pt.
TextFragment _frag(String text, double x, double y,
    {double w = 10, double h = 10}) {
  return TextFragment(
    text: text,
    left: x,
    top: y,
    right: x + w,
    bottom: y - h, // PDF Y goes up, so bottom < top
  );
}

/// Build a legend page: rows of [symbol, dmcCode, name] fragments.
/// Each row is spaced 12pt apart vertically starting from y=700.
PageTextData _legendPage(List<(String symbol, String dmcCode, String name)> entries) {
  final fragments = <TextFragment>[];
  final textParts = <String>[];

  for (int i = 0; i < entries.length; i++) {
    final (symbol, dmc, name) = entries[i];
    final y = 700.0 - i * 12.0;
    fragments.add(_frag(symbol, 50, y, w: 10));
    fragments.add(_frag(dmc, 70, y, w: 30));
    fragments.add(_frag(name, 110, y, w: 80));
    textParts.addAll([symbol, dmc, name]);
  }

  return PageTextData(
    fullText: textParts.join(' '),
    fragments: fragments,
  );
}

/// Build a grid page with symbols placed at regular intervals.
/// [cells] is a list of (col, row, symbol) tuples.
/// Grid spacing is [step] pt, origin at (50, 700).
PageTextData _gridPage(
  List<(int col, int row, String symbol)> cells, {
  double step = 8.0,
  String? pkChartMarker,
}) {
  final fragments = <TextFragment>[];
  final originX = 50.0;
  final originY = 700.0;

  for (final (col, row, symbol) in cells) {
    final x = originX + col * step;
    final y = originY - row * step; // PDF Y goes up
    fragments.add(_frag(symbol, x, y, w: step * 0.8, h: step * 0.8));
  }

  final subtitle = pkChartMarker ?? '';
  final symbolTexts = cells.map((c) => c.$3).join(' ');
  final fullText = subtitle.isEmpty ? symbolTexts : '$subtitle $symbolTexts';

  if (subtitle.isNotEmpty) {
    // Add the PKCHART marker as a fragment too.
    fragments.add(_frag(subtitle, 50, 750, w: 200, h: 10));
  }

  return PageTextData(fullText: fullText, fragments: fragments);
}

/// Standard assertions for a successfully-parsed result.
void _assertValid(PatternScanResult result, String label) {
  expect(result.width, greaterThan(0), reason: '$label: width > 0');
  expect(result.height, greaterThan(0), reason: '$label: height > 0');
  expect(result.threads, isNotEmpty, reason: '$label: has threads');
  expect(result.stitches, isNotEmpty, reason: '$label: has stitches');

  final threadCodes = result.threads.map((t) => t.dmcCode).toSet();
  for (final s in result.stitches) {
    expect(threadCodes, contains(s.dmcCode),
        reason: '$label: stitch (${s.x},${s.y}) → unknown DMC ${s.dmcCode}');
  }

  for (final t in result.threads) {
    expect(dmcColorByCode(t.dmcCode), isNotNull,
        reason: '$label: ${t.dmcCode} not a valid DMC code');
  }
}

// ─── Legend entries using real DMC codes ─────────────────────────────────────

const _kLegend = [
  ('A', '310', 'Black'),
  ('B', '666', 'Bright Red'),
  ('C', '820', 'Royal Blue'),
  ('D', '702', 'Kelly Green'),
  ('E', 'White', 'White'),
  ('F', '3371', 'Black Brown'),
  ('G', '816', 'Garnet'),
  ('H', '321', 'Red'),
];

void main() {
  // ─── Legend parsing ─────────────────────────────────────────────────────

  group('Legend parsing', () {
    test('extracts symbol→DMC from per-word fragments', () {
      final page = _legendPage(_kLegend);
      // 8 legend entries + a 10x10 grid → should parse.
      // Build a grid with all 8 symbols to exceed min thresholds.
      final gridCells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          gridCells.add((col, row, _kLegend[(col + row) % _kLegend.length].$1));
        }
      }
      final grid = _gridPage(gridCells);

      final result = PatternKeeperParser.tryParseFromText([page, grid]);
      expect(result, isNotNull);
      _assertValid(result!, 'legend');
      expect(result.threads.length, equals(8));
    });

    test('handles whole-line fragments (space-separated)', () {
      // Simulate third-party PDFs that emit one fragment per line.
      final fragments = <TextFragment>[];
      final texts = <String>[];
      for (int i = 0; i < _kLegend.length; i++) {
        final (symbol, dmc, name) = _kLegend[i];
        final y = 700.0 - i * 12.0;
        // One fragment containing the whole line.
        final line = '$symbol $dmc $name';
        fragments.add(_frag(line, 50, y, w: 200));
        texts.add(line);
      }
      final legendPage = PageTextData(
        fullText: texts.join('\n'),
        fragments: fragments,
      );

      // Grid with all symbols.
      final gridCells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          gridCells.add((col, row, _kLegend[(col + row) % _kLegend.length].$1));
        }
      }
      final grid = _gridPage(gridCells);

      final result = PatternKeeperParser.tryParseFromText([legendPage, grid]);
      expect(result, isNotNull);
      expect(result!.threads.length, equals(8));
    });

    test('rejects too few legend entries', () {
      // Only 3 entries — below _kMinColors (5).
      final page = _legendPage(_kLegend.take(3).toList());
      final gridCells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          gridCells.add((col, row, _kLegend[col % 3].$1));
        }
      }
      final grid = _gridPage(gridCells);

      final result = PatternKeeperParser.tryParseFromText([page, grid]);
      expect(result, isNull);
    });

    test('skips DMC-as-symbol collision', () {
      // If a token looks like both a symbol candidate and a DMC code,
      // it should be treated as DMC code not symbol.
      final page = _legendPage([
        ('A', '310', 'Black'),
        ('B', '666', 'Bright Red'),
        ('C', '820', 'Royal Blue'),
        ('D', '702', 'Kelly Green'),
        ('E', 'White', 'White'),
      ]);

      final gridCells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          gridCells.add((col, row, ['A', 'B', 'C', 'D', 'E'][(col + row) % 5]));
        }
      }
      final grid = _gridPage(gridCells);

      final result = PatternKeeperParser.tryParseFromText([page, grid]);
      expect(result, isNotNull);
      // DMC code '310' should NOT appear as a symbol.
      for (final s in result!.stitches) {
        expect(s.dmcCode, isNot(equals('A')),
            reason: 'symbol A should map to DMC code, not be used as dmcCode');
      }
    });
  });

  // ─── Grid parsing ───────────────────────────────────────────────────────

  group('Grid parsing', () {
    test('single page grid with regular spacing', () {
      final legend = _legendPage(_kLegend.take(6).toList());
      final cells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          cells.add((col, row, _kLegend[(col + row) % 6].$1));
        }
      }
      final grid = _gridPage(cells);

      final result = PatternKeeperParser.tryParseFromText([legend, grid]);
      expect(result, isNotNull);
      expect(result!.width, equals(10));
      expect(result.height, equals(10));
      expect(result.stitches.length, equals(100));
    });

    test('PKCHART marker sets grid bounds', () {
      final legend = _legendPage(_kLegend.take(6).toList());

      // Grid with 8x8 symbols + some outlier "footer" symbols far away.
      final cells = <(int, int, String)>[];
      for (int row = 0; row < 8; row++) {
        for (int col = 0; col < 8; col++) {
          cells.add((col, row, _kLegend[(col + row) % 6].$1));
        }
      }
      // Add footer-like outliers at row 50 (would be clipped by PKCHART).
      cells.add((0, 50, 'A'));
      cells.add((1, 50, 'B'));

      final grid = _gridPage(cells, pkChartMarker: 'PKCHART:0,0,8,8');

      final result = PatternKeeperParser.tryParseFromText([legend, grid]);
      expect(result, isNotNull);
      // Should be 8×8 (outliers at row 50 clipped by PKCHART bounds).
      expect(result!.width, equals(8));
      expect(result.height, equals(8));
      expect(result.stitches.length, equals(64));
    });

    test('rejects page with too few grid symbols', () {
      final legend = _legendPage(_kLegend.take(6).toList());
      // Only 4 symbols — below _kMinGridCells (8).
      final grid = _gridPage([
        (0, 0, 'A'),
        (1, 0, 'B'),
        (0, 1, 'C'),
        (1, 1, 'D'),
      ]);

      final result = PatternKeeperParser.tryParseFromText([legend, grid]);
      expect(result, isNull);
    });

    test('rejects raster PDF with too little text', () {
      // Only 50 chars total — below 100-char threshold.
      final page = PageTextData(
        fullText: 'A short raster page',
        fragments: [_frag('A short raster page', 50, 700, w: 200)],
      );
      final result = PatternKeeperParser.tryParseFromText([page]);
      expect(result, isNull);
    });

    test('v3 PKCHART origin fixes empty leading rows/cols', () {
      // Regression test for the empty-edge coordinate offset bug.
      //
      // A page where local cols 0-1 and rows 0-2 have NO stitches.
      // Without v3 origin embedded in the marker, the parser anchors
      // from the first ACTUAL symbol (col 2, row 3) and computes all
      // absolute coords 2 cols and 3 rows too low.
      //
      // With v3 origin (ox, oy = true PDF-space centre of col 0 / row 0),
      // all absolute coords must be exactly pkStartCol+localCol.
      const threads = [
        ('A', '310', 'Black'),
        ('B', '666', 'Bright Red'),
        ('C', '820', 'Royal Blue'),
        ('D', '702', 'Kelly Green'),
        ('E', 'White', 'White'),
        ('F', '3371', 'Black Brown'),
      ];
      final legend = _legendPage(threads);

      const step = 8.0;
      const trueOriginX = 50.0; // PDF-space centre of local col 0
      const trueOriginY = 700.0; // PDF-space centre of local row 0 (largest Y)

      // pkStartCol=30, pkStartRow=20; page grid is 10×10.
      // Symbols only in local cols 2-9, rows 3-9 (empty top+left edges).
      final cellFrags = <TextFragment>[];
      final expectedMap = <(int, int), String>{};

      for (int row = 3; row < 10; row++) {
        for (int col = 2; col < 10; col++) {
          final idx = (col + row) % threads.length;
          final sym = threads[idx].$1;
          final x = trueOriginX + col * step;
          final y = trueOriginY - row * step; // PDF Y up
          cellFrags.add(_frag(sym, x, y, w: step * 0.8, h: step * 0.8));
          // Absolute canvas position:
          expectedMap[(30 + col, 20 + row)] = threads[idx].$2;
        }
      }

      // v3 marker: startCol,startRow,endCol,endRow,ox,oy
      final pkMarker =
          'PKCHART:30,20,40,30,${trueOriginX.toStringAsFixed(3)},${trueOriginY.toStringAsFixed(3)}';
      cellFrags.add(_frag(pkMarker, 50, 750, w: 300));

      final gridPage = PageTextData(
        fullText: '$pkMarker ${cellFrags.map((f) => f.text).join(' ')}',
        fragments: cellFrags,
      );

      final result = PatternKeeperParser.tryParseFromText([legend, gridPage]);
      expect(result, isNotNull, reason: 'should parse');

      final parsedMap = <(int, int), String>{};
      for (final s in result!.stitches) {
        parsedMap[(s.x, s.y)] = s.dmcCode;
      }

      final mismatches = <String>[];
      for (final entry in expectedMap.entries) {
        final got = parsedMap[entry.key];
        if (got != entry.value) {
          mismatches.add('${entry.key}: expected ${entry.value}, got $got');
        }
      }
      expect(mismatches, isEmpty,
          reason: 'Origin offset bug — ${mismatches.length} wrong positions:\n'
              '${mismatches.take(5).join('\n')}');
      expect(parsedMap.length, equals(expectedMap.length));
    });
  });

  // ─── Multi-page assembly ────────────────────────────────────────────────

  group('Multi-page assembly', () {
    test('absolute PKCHART offsets combine pages correctly', () {
      final legend = _legendPage(_kLegend.take(6).toList());

      // Page 1: cols 0–9, rows 0–9.
      final page1Cells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          page1Cells.add((col, row, _kLegend[(col + row) % 6].$1));
        }
      }
      final page1 = _gridPage(page1Cells, pkChartMarker: 'PKCHART:0,0,10,10');

      // Page 2: cols 10–19, rows 0–9 (right of page 1).
      final page2Cells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          page2Cells.add((col, row, _kLegend[(col + row + 3) % 6].$1));
        }
      }
      final page2 = _gridPage(page2Cells, pkChartMarker: 'PKCHART:10,0,20,10');

      final result = PatternKeeperParser.tryParseFromText([legend, page1, page2]);
      expect(result, isNotNull);
      expect(result!.width, equals(20));
      expect(result.height, equals(10));
      expect(result.stitches.length, equals(200));
    });

    test('pages without PKCHART are discarded when some pages have it', () {
      final legend = _legendPage(_kLegend.take(6).toList());

      // Grid page WITH marker.
      final gridCells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          gridCells.add((col, row, _kLegend[(col + row) % 6].$1));
        }
      }
      final gridPage = _gridPage(gridCells, pkChartMarker: 'PKCHART:0,0,10,10');

      // A legend-like page that happens to have enough symbol fragments
      // to look like a grid — but no PKCHART marker.
      final fakeCells = <(int, int, String)>[];
      for (int i = 0; i < 10; i++) {
        fakeCells.add((i, 0, _kLegend[i % 6].$1));
      }
      final fakeGrid = _gridPage(fakeCells);

      final result =
          PatternKeeperParser.tryParseFromText([legend, fakeGrid, gridPage]);
      expect(result, isNotNull);
      // Should use only the PKCHART page.
      expect(result!.width, equals(10));
      expect(result.height, equals(10));
      expect(result.stitches.length, equals(100));
    });
  });

  // ─── Round-trip: synthetic pattern → text data → re-parse ──────────────

  group('Round-trip', () {
    test('pattern data survives legend+grid round-trip', () {
      // Build what a PK PDF export would produce: legend + grid pages.
      const threads = [
        ('A', '310', 'Black'),
        ('B', '666', 'Bright Red'),
        ('C', '820', 'Royal Blue'),
        ('D', '702', 'Kelly Green'),
        ('E', 'White', 'White'),
        ('F', '3371', 'Black Brown'),
      ];
      final legend = _legendPage(threads);

      // 15×12 grid — every cell filled.
      final expectedMap = <(int, int), String>{};
      final cells = <(int, int, String)>[];
      for (int row = 0; row < 12; row++) {
        for (int col = 0; col < 15; col++) {
          final idx = (col + row) % threads.length;
          cells.add((col, row, threads[idx].$1));
          expectedMap[(col, row)] = threads[idx].$2; // dmcCode
        }
      }
      final grid = _gridPage(cells);

      final result = PatternKeeperParser.tryParseFromText([legend, grid]);
      expect(result, isNotNull);
      _assertValid(result!, 'round-trip');

      expect(result.width, equals(15));
      expect(result.height, equals(12));
      expect(result.stitches.length, equals(180));

      // Verify every stitch position and thread assignment.
      final parsedMap = <(int, int), String>{};
      for (final s in result.stitches) {
        parsedMap[(s.x, s.y)] = s.dmcCode;
      }

      for (final entry in expectedMap.entries) {
        expect(parsedMap[entry.key], equals(entry.value),
            reason: 'mismatch at ${entry.key}');
      }

      expect(parsedMap.length, equals(expectedMap.length));
    });

    test('multi-page round-trip with PKCHART markers', () {
      const threads = [
        ('A', '310', 'Black'),
        ('B', '666', 'Bright Red'),
        ('C', '820', 'Royal Blue'),
        ('D', '702', 'Kelly Green'),
        ('E', 'White', 'White'),
        ('F', '3371', 'Black Brown'),
      ];
      final legend = _legendPage(threads);

      // Simulate a 20×15 pattern split across 4 pages (2×2 grid of pages).
      final expectedMap = <(int, int), String>{};
      final pages = <PageTextData>[legend];

      for (int pr = 0; pr < 2; pr++) {
        for (int pc = 0; pc < 2; pc++) {
          final startCol = pc * 10;
          final startRow = pr * 8;
          final endCol = pc == 1 ? 20 : 10;
          final endRow = pr == 1 ? 15 : 8;
          final localW = endCol - startCol;
          final localH = endRow - startRow;

          final cells = <(int, int, String)>[];
          for (int row = 0; row < localH; row++) {
            for (int col = 0; col < localW; col++) {
              final absCol = startCol + col;
              final absRow = startRow + row;
              final idx = (absCol + absRow) % threads.length;
              cells.add((col, row, threads[idx].$1));
              expectedMap[(absCol, absRow)] = threads[idx].$2;
            }
          }

          pages.add(_gridPage(cells,
              pkChartMarker: 'PKCHART:$startCol,$startRow,$endCol,$endRow'));
        }
      }

      final result = PatternKeeperParser.tryParseFromText(pages);
      expect(result, isNotNull);
      expect(result!.width, equals(20));
      expect(result.height, equals(15));
      expect(result.stitches.length, equals(300));

      final parsedMap = <(int, int), String>{};
      for (final s in result.stitches) {
        parsedMap[(s.x, s.y)] = s.dmcCode;
      }

      final mismatches = <(int, int), (String, String?)>{};
      for (final entry in expectedMap.entries) {
        if (parsedMap[entry.key] != entry.value) {
          mismatches[entry.key] = (entry.value, parsedMap[entry.key]);
        }
      }

      expect(mismatches, isEmpty,
          reason: '${mismatches.length} mismatches in multi-page round-trip');
      expect(parsedMap.length, equals(expectedMap.length));
    });

    test('sparse pattern with non-full cells preserves filled positions', () {
      const threads = [
        ('X', '310', 'Black'),
        ('Y', '666', 'Bright Red'),
        ('Z', '820', 'Royal Blue'),
        ('W', '702', 'Kelly Green'),
        ('V', 'White', 'White'),
      ];
      final legend = _legendPage(threads);

      // 10×10 grid, only ~50% filled (checkerboard).
      final expectedMap = <(int, int), String>{};
      final cells = <(int, int, String)>[];
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          if ((col + row) % 2 == 0) {
            final idx = (col + row) ~/ 2 % threads.length;
            cells.add((col, row, threads[idx].$1));
            expectedMap[(col, row)] = threads[idx].$2;
          }
        }
      }
      final grid = _gridPage(cells);

      final result = PatternKeeperParser.tryParseFromText([legend, grid]);
      expect(result, isNotNull);
      expect(result!.stitches.length, equals(expectedMap.length));

      final parsedMap = <(int, int), String>{};
      for (final s in result.stitches) {
        parsedMap[(s.x, s.y)] = s.dmcCode;
      }

      for (final entry in expectedMap.entries) {
        expect(parsedMap[entry.key], equals(entry.value),
            reason: 'mismatch at ${entry.key}');
      }
    });
  });
}
