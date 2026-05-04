// Visual diagnostic test for PageLayout v2 boundary algorithm.
//
// Loads sm_test.stitches, computes layout at specified tolerance,
// and prints ASCII band strips grouped by page. Each page shows
// its right and bottom boundaries (left/top are the adjacent page's
// right/bottom).
//
// Run with: flutter test test/models/page/page_layout_visual_test.dart
//
// The output shows each boundary as a grid where:
//   - Each cell is a letter (colour) or '.' (empty)
//   - '|' marks the computed cut position
//   - Index numbers and offset values shown at left/right
//
// For vertical boundaries: each line is a ROW, left = page N, right = page N+1
// For horizontal boundaries: each line is a COLUMN, top = page N, bottom = page N+1

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page/page_config.dart';
import 'package:stitches/models/page/page_layout.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/stitch_compositor.dart';
import '../../test_fixtures.dart';

/// Map colour indices to printable characters for ASCII display.
const _colorChars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjklmnpqrstuvwxyz123456789';

String _colorChar(int? colorIndex) {
  if (colorIndex == null) return '.';
  return _colorChars[colorIndex % _colorChars.length];
}

/// Build reverse thread map for legend.
Map<int, String> _buildIndexToThread(Map<String, int> threadIndex) {
  final result = <int, String>{};
  for (final entry in threadIndex.entries) {
    result[entry.value] = entry.key;
  }
  return result;
}

/// Print an ASCII band strip for one boundary.
///
/// [label] describes which edge this is (e.g. "Right edge" or "Bottom edge").
/// [crossLabel] describes cross-axis units (e.g. "row" or "col").
void printBoundaryStrip({
  required String label,
  required String crossLabel,
  required int nominalBoundary,
  required int tolerance,
  required int maxBoundary,
  required int crossStart,
  required int crossEnd,
  required Map<int, int> offsets,
  required int? Function(int primary, int cross) colorAt,
  required Map<int, String> indexToThread,
}) {
  final bandMin = (nominalBoundary - tolerance).clamp(0, maxBoundary);
  final bandMax = (nominalBoundary + tolerance).clamp(0, maxBoundary);

  final usedColors = <int>{};
  final lines = <String>[];

  lines.add('');
  lines.add('  ${'─' * 56}');
  lines.add('  $label  nominal=$nominalBoundary  band=[$bandMin,$bandMax)');
  lines.add('  ${'─' * 56}');

  // Header: primary axis positions
  final header = StringBuffer('          ');
  for (int p = bandMin; p < bandMax; p++) {
    if (p == nominalBoundary) header.write('|');
    header.write((p % 10).toString());
  }
  lines.add(header.toString());

  // Each cross-index line
  for (int cross = crossStart; cross < crossEnd; cross++) {
    final offset = offsets[cross] ?? 0;
    final actual = nominalBoundary + offset;

    final buf = StringBuffer();
    buf.write('  ${crossLabel.substring(0, 1)}${cross.toString().padLeft(4)} : ');

    for (int p = bandMin; p < bandMax; p++) {
      if (p == actual) buf.write('|');
      final c = colorAt(p, cross);
      if (c != null) usedColors.add(c);
      buf.write(_colorChar(c));
    }
    if (actual >= bandMax) buf.write('|');

    buf.write('  δ=${offset >= 0 ? '+' : ''}$offset');
    lines.add(buf.toString());
  }

  // Legend
  lines.add('');
  lines.add('  Legend:');
  final legendEntries = usedColors.toList()..sort();
  for (final ci in legendEntries) {
    final dmc = indexToThread[ci] ?? '?';
    lines.add('    ${_colorChar(ci)} = DMC $dmc (idx $ci)');
  }

  print(lines.join('\n'));
}

void main() {
  final fixturePath = testFixturePath('sm-layers-test.stitches');

  for (final tol in [5, 6]) {
    group('Visual diagnostic — tolerance=$tol', () {
      late PageLayout layout;
      late int patternWidth, patternHeight;
      late Map<int, int?> snapColor;
      late Map<int, String> indexToThread;

      setUpAll(() async {
        final bytes = await File(fixturePath).readAsBytes();
        final (pattern, _) = await FileService.parseBytesToPattern(bytes);

        final config = pattern.pageConfig.copyWith(tolerance: tol);

        final composite = StitchCompositor.computeComposite(pattern);
        final threadIndex = <String, int>{
          for (final (i, dmcCode) in pattern.threads.keys.indexed) dmcCode: i,
        };
        snapColor = {
          for (final entry in composite.fullStitches.entries)
            (entry.key.x << 16) | entry.key.y:
                threadIndex[entry.value.resolvedThread.dmcCode],
        };
        indexToThread = _buildIndexToThread(threadIndex);

        layout = PageLayout.compute(config, pattern);
        patternWidth = pattern.width;
        patternHeight = pattern.height;
      });

      test('print pages', () {
        int? colorAt(int col, int row) => snapColor[(col << 16) | row];

        for (int py = 0; py < layout.pagesDown; py++) {
          for (int px = 0; px < layout.pagesAcross; px++) {
            final pageIdx = py * layout.pagesAcross + px;
            final hasRight = px < layout.pagesAcross - 1;
            final hasBottom = py < layout.pagesDown - 1;
            if (!hasRight && !hasBottom) continue; // nothing to show

            final lines = <String>[];
            lines.add('');
            lines.add('${'═' * 60}');
            lines.add('PAGE $pageIdx  (col=$px, row=$py)  tolerance=$tol');

            // Note adjacent pages for top/left edges
            final refs = <String>[];
            if (px > 0) {
              final leftIdx = py * layout.pagesAcross + (px - 1);
              refs.add('left edge → see PAGE $leftIdx right edge');
            }
            if (py > 0) {
              final topIdx = (py - 1) * layout.pagesAcross + px;
              refs.add('top edge → see PAGE $topIdx bottom edge');
            }
            if (refs.isNotEmpty) lines.add(refs.join('  |  '));

            lines.add('${'═' * 60}');
            print(lines.join('\n'));

            // Right edge (vertical boundary)
            if (px < layout.pagesAcross - 1) {
              final nominal = (px + 1) * layout.config.pageWidth;
              final offsets = layout.verticalOffsets[nominal]!;
              // Only show rows that belong to this page's vertical range
              final rowStart = py * layout.config.pageHeight;
              final rowEnd = py < layout.pagesDown - 1
                  ? (py + 1) * layout.config.pageHeight
                  : patternHeight;
              // Expand slightly to show context at edges
              final displayStart = (rowStart - tol).clamp(0, patternHeight);
              final displayEnd = (rowEnd + tol).clamp(0, patternHeight);

              final pageOffsets = <int, int>{
                for (int r = displayStart; r < displayEnd; r++)
                  r: offsets[r] ?? 0,
              };

              printBoundaryStrip(
                label: 'Right edge (V boundary, nominal col $nominal)',
                crossLabel: 'row',
                nominalBoundary: nominal,
                tolerance: tol,
                maxBoundary: patternWidth,
                crossStart: displayStart,
                crossEnd: displayEnd,
                offsets: pageOffsets,
                colorAt: colorAt,
                indexToThread: indexToThread,
              );
            }

            // Bottom edge (horizontal boundary)
            if (py < layout.pagesDown - 1) {
              final nominal = (py + 1) * layout.config.pageHeight;
              final offsets = layout.horizontalOffsets[nominal]!;
              // Only show cols that belong to this page's horizontal range
              final colStart = px * layout.config.pageWidth;
              final colEnd = px < layout.pagesAcross - 1
                  ? (px + 1) * layout.config.pageWidth
                  : patternWidth;
              final displayStart = (colStart - tol).clamp(0, patternWidth);
              final displayEnd = (colEnd + tol).clamp(0, patternWidth);

              final pageOffsets = <int, int>{
                for (int c = displayStart; c < displayEnd; c++)
                  c: offsets[c] ?? 0,
              };

              printBoundaryStrip(
                label: 'Bottom edge (H boundary, nominal row $nominal)',
                crossLabel: 'col',
                nominalBoundary: nominal,
                tolerance: tol,
                maxBoundary: patternHeight,
                crossStart: displayStart,
                crossEnd: displayEnd,
                offsets: pageOffsets,
                colorAt: (primary, cross) => colorAt(cross, primary),
                indexToThread: indexToThread,
              );
            }
          }
        }
      });

      test('check cell page membership', () {
        void check(int c, int r) {
          final pages = <String>[];
          for (int py = 0; py < layout.pagesDown; py++) {
            for (int px = 0; px < layout.pagesAcross; px++) {
              if (layout.cellOnPage(c, r, px, py)) {
                final idx = py * layout.pagesAcross + px;
                pages.add('PAGE$idx($px,$py)');
              }
            }
          }
          print('($c,$r) on: ${pages.join(", ")}');
        }

        // p object at c41,r50 through c39,r56
        for (final (c,r) in [(41,50),(40,51),(41,52),(41,53),(40,54),(40,55),(39,56)]) {
          check(c, r);
        }
        // (100,51) — should be on page 7
        check(100, 51);
        // Also check user's other cells
        for (final (c,r) in [(91,54),(92,54),(93,53),(94,53)]) {
          check(c, r);
        }
        // Check neighbors of (100,51) to understand the object
        for (int r = 48; r <= 56; r++) {
          check(100, r);
        }
        // Detailed boundary check
        void detailed(int c, int r) {
          print('\nDetailed ($c,$r):');
          for (int py = 0; py < layout.pagesDown; py++) {
            for (int px = 0; px < layout.pagesAcross; px++) {
              final raw = layout.rawCellOnPage(c, r, px, py);
              final cell = layout.cellOnPage(c, r, px, py);
              if (raw || cell) {
                final idx = py * layout.pagesAcross + px;
                final l = layout.leftBoundaryForRow(px, r);
                final ri = layout.rightBoundaryForRow(px, r);
                final t = layout.topBoundaryForCol(py, c);
                final b = layout.bottomBoundaryForCol(py, c);
                print('  PAGE$idx($px,$py): raw=$raw cell=$cell  L=$l R=$ri T=$t B=$b');
              }
            }
          }
        }
        detailed(97, 50);
        detailed(100, 53);
        // 4-corner area: cols 95-103, rows 48-55
        print('\n4-corner grid:');
        for (int r = 48; r <= 55; r++) {
          final buf = StringBuffer('r$r: ');
          for (int c = 95; c <= 103; c++) {
            final pages = <String>[];
            for (int py = 0; py < layout.pagesDown; py++) {
              for (int px = 0; px < layout.pagesAcross; px++) {
                if (layout.cellOnPage(c, r, px, py)) {
                  pages.add('${py * layout.pagesAcross + px}');
                }
              }
            }
            buf.write('c$c=${pages.join("/")} ');
          }
          print(buf);
        }
        // Check the 4-corner neighborhood
        for (int c = 98; c <= 102; c++) {
          for (int r = 48; r <= 55; r++) {
            check(c, r);
          }
        }
      });
    });
  }
}
