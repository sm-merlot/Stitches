// test/debug_snap_test.dart
//
// One-shot diagnostic test: loads the real .stitches file, builds the
// snap-colour map exactly as PageLayout.compute() does (topmost layer wins),
// and prints the boundary region + per-row DP offsets.
//
// Run with:
//   flutter test test/debug_snap_test.dart --reporter=expanded
//
// Skipped by default (diagnostic only). Remove @Skip to run manually.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page/page_layout.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/stitch_compositor.dart';
import '../../test_fixtures.dart';

void main() {
  final filePath = testFixturePath('sm_test.stitches');

  test('debug: DP boundary offsets rows 17–45 at first vertical boundary',
      skip: 'diagnostic only — run manually to inspect snap output',
      () async {
    // ── Load pattern
    final bytes = await File(filePath).readAsBytes();
    final (pattern, _) = await FileService.parseBytesToPattern(bytes);

    final config = pattern.pageConfig;
    printOnFailure('Pattern: ${pattern.width}×${pattern.height}, '
        '${pattern.threads.length} threads, ${pattern.layers.length} layers');
    printOnFailure('Page config: ${config.pageWidth}×${config.pageHeight} '
        'tolerance=${config.tolerance} enabled=${config.enabled}');

    // ── Build snap-colour map via StitchCompositor (mirrors PageLayout.compute)
    final composite = StitchCompositor.computeComposite(pattern);
    final threadList = pattern.threads.values.toList();
    final threadIndex = <String, int>{
      for (int i = 0; i < threadList.length; i++)
        threadList[i].dmcCode: i,
    };
    final indexToSym = <int, String>{
      for (int i = 0; i < threadList.length; i++)
        i: threadList[i].symbol,
    };
    final snapColor = <int, int?>{};
    for (final entry in composite.fullStitches.entries) {
      final col = entry.key.x;
      final row = entry.key.y;
      snapColor[(col << 16) | row] = threadIndex[entry.value.resolvedThread.dmcCode];
    }

    int? colorAt(int col, int row) => snapColor[(col << 16) | row];
    String symAt(int col, int row) {
      final idx = colorAt(col, row);
      return idx == null ? '.' : (indexToSym[idx] ?? '?');
    }

    // ── Canvas view
    final nominal = config.pageWidth; // first vertical boundary
    const startRow = 17;
    const endRow = 46;
    final startCol = nominal - 10;
    final endCol = nominal + 9;

    final sb = StringBuffer();
    sb.writeln('\nCanvas view (thread symbols, cols $startCol–${endCol - 1}):');
    sb.writeln('Nominal boundary at col $nominal');
    sb.write('row  ');
    for (int c = startCol; c < endCol; c++) {
      sb.write(c == nominal ? '|' : (c % 10).toString());
    }
    sb.writeln();
    for (int row = startRow; row < endRow; row++) {
      sb.write(' ${row.toString().padLeft(2)}: ');
      for (int col = startCol; col < endCol; col++) {
        sb.write(symAt(col, row));
      }
      sb.writeln();
    }

    // ── Compute full layout for DP offsets
    final layout = PageLayout.compute(config, pattern);
    final offsets = layout.verticalOffsets[nominal]!;

    sb.writeln('\nDP offsets — boundary=$nominal tolerance=${config.tolerance}:');
    for (int row = startRow; row < endRow; row++) {
      final offset = offsets[row] ?? 0;
      final cutCol = nominal + offset;
      final leftSym = symAt(cutCol - 1, row);
      final rightSym = symAt(cutCol, row);
      sb.writeln('  row $row: offset=${offset.toString().padLeft(3)} → '
          'cut at col $cutCol  ($leftSym | $rightSym)');
    }

    printOnFailure(sb.toString());
    // Always fail so Flutter prints the output.
    fail(sb.toString());
  });
}
