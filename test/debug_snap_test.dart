// test/debug_snap_test.dart
//
// One-shot diagnostic test: loads the real .stitches file, builds the
// snap-colour map exactly as PageLayout.compute() does (topmost layer wins),
// and prints the boundary region + per-row computeOffset() result.
//
// Run with:
//   flutter test test/debug_snap_test.dart --reporter=expanded
//
// Skipped by default (diagnostic only). Remove @Skip to run manually.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page_layout.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/stitch_compositor.dart';
import 'test_fixtures.dart';

void main() {
  final filePath = testFixturePath('sm_test.stitches');

  test('debug: snap simulation rows 17–32 at first vertical boundary',
      skip: 'diagnostic only — run manually to inspect snap output',
      () async {
    // ── Load pattern
    final bytes = await File(filePath).readAsBytes();
    final (pattern, _) = await FileService.parseBytesToPattern(bytes);

    final config = pattern.pageConfig;
    printOnFailure('Pattern: ${pattern.width}×${pattern.height}, '
        '${pattern.threads.length} threads, ${pattern.layers.length} layers');
    printOnFailure('Page config: ${config.pageWidth}×${config.pageHeight} '
        'fuzzyAmount=${config.fuzzyAmount} enabled=${config.enabled}');

    // ── Build snap-colour map via StitchCompositor (mirrors PageLayout.compute)
    final composite = StitchCompositor.computeLayer(pattern);
    final threadIndex = <String, int>{
      for (int i = 0; i < pattern.threads.length; i++)
        pattern.threads[i].dmcCode: i,
    };
    final indexToSym = <int, String>{
      for (int i = 0; i < pattern.threads.length; i++)
        i: pattern.threads[i].symbol,
    };
    final snapColor = <int, int?>{};
    for (final entry in composite.fullStitches.entries) {
      final parts = entry.key.split(',');
      final col = int.parse(parts[0]);
      final row = int.parse(parts[1]);
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

    // Wider view
    final wideStart = nominal - 15;
    final wideEnd = nominal + 15;
    sb.writeln('\nWide view cols $wideStart–${wideEnd - 1}:');
    sb.write('row  ');
    for (int c = wideStart; c < wideEnd; c++) {
      sb.write(c == nominal ? '|' : (c % 10).toString());
    }
    sb.writeln();
    for (int row = startRow; row < endRow; row++) {
      sb.write(' ${row.toString().padLeft(2)}: ');
      for (int col = wideStart; col < wideEnd; col++) {
        sb.write(symAt(col, row));
      }
      sb.writeln();
    }

    // ── Thread index values
    sb.writeln('\nThread index values cols ${nominal - 5}–${nominal + 5}:');
    sb.write('row  ');
    for (int c = nominal - 5; c <= nominal + 5; c++) {
      sb.write(' ${c.toString().padLeft(4)}');
    }
    sb.writeln();
    for (int row = startRow; row < endRow; row++) {
      sb.write(' ${row.toString().padLeft(2)}: ');
      for (int c = nominal - 5; c <= nominal + 5; c++) {
        final idx = colorAt(c, row);
        sb.write(' ${(idx?.toString() ?? 'N').padLeft(4)}');
      }
      sb.writeln();
    }

    // ── computeOffset simulation (using real seed, same as PageLayout.compute)
    sb.writeln('\ncomputeOffset results — boundary=$nominal '
        'fuzzyAmount=${config.fuzzyAmount} snapRange=${PageLayout.snapRange}:');
    for (int row = startRow; row < endRow; row++) {
      final seed = PageLayout.makeSeed(
          pattern.width, pattern.height, config, nominal * 100003 + row);
      final offset = PageLayout.computeOffset(
        nominalBoundary: nominal,
        crossIndex: row,
        fuzzyAmount: config.fuzzyAmount,
        maxBoundary: pattern.width,
        maxCross: pattern.height,
        colorAt: colorAt,
        seed: seed,
      );
      final cutCol = nominal + offset;
      final leftSym = symAt(cutCol - 1, row);
      final rightSym = symAt(cutCol, row);
      sb.writeln('  row $row: offset=${offset.toString().padLeft(3)} → '
          'cut at col $cutCol  ($leftSym | $rightSym)  seed=$seed');
    }

    printOnFailure(sb.toString());
    // Always fail so Flutter prints the output.
    fail(sb.toString());
  });
}
