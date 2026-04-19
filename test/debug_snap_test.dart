// test/debug_snap_test.dart
//
// One-shot diagnostic test: loads the real .stitches file, builds the
// snap-colour map exactly as PageLayout.compute() does (topmost layer wins),
// and prints the boundary region + per-row computeOffset() result.
//
// Run with:
//   flutter test test/debug_snap_test.dart --reporter=expanded
//
// This is a @Skip test by default; change to false to run.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page_layout.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/services/file_service.dart';

void main() {
  const filePath =
      '/Users/scottmerchant/dev/Stitches/worktrees/fuzzy-page-edges/'
      'Super Metroid - Samus battles Ridley.stitches';

  test('debug: snap simulation rows 22–32 at first vertical boundary',
      skip: !File(filePath).existsSync()
          ? 'file not found'
          : false, () async {
    // ── Load pattern ────────────────────────────────────────────────────────
    final bytes = await File(filePath).readAsBytes();
    final (pattern, _) = await FileService.parseBytesToPattern(bytes);

    final config = pattern.pageConfig;
    printOnFailure('Pattern: ${pattern.width}×${pattern.height}, '
        '${pattern.threads.length} threads, ${pattern.layers.length} layers');
    printOnFailure('Page config: ${config.pageWidth}×${config.pageHeight} '
        'fuzzyAmount=${config.fuzzyAmount} enabled=${config.enabled}');

    // ── Build snap-colour map (mirrors PageLayout.compute) ──────────────────
    int quantise(Color c) {
      // ignore: deprecated_member_use
      return ((c.red >> 5) << 6) | ((c.green >> 5) << 3) | (c.blue >> 5);
    }

    final threadQ = <String, int>{
      for (final t in pattern.threads) t.dmcCode: quantise(t.color),
    };
    final threadSym = <String, String>{
      for (final t in pattern.threads) t.dmcCode: t.symbol ?? '?',
    };
    // quant → symbol of first thread with that quant
    final quantToSym = <int, String>{};
    for (final t in pattern.threads) {
      quantToSym.putIfAbsent(quantise(t.color), () => t.symbol ?? '?');
    }
    // Find which thread has symbol '8'
    for (final t in pattern.threads) {
      if (t.symbol == '8') {
        printOnFailure("Symbol '8' = DMC ${t.dmcCode}  "
            "color=${t.color}  quant=${quantise(t.color)}");
      }
    }

    // layers is bottom→top; reversed = topmost first; putIfAbsent = top wins
    final snapColor = <int, int?>{};
    for (final layer in pattern.layers.reversed) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is FullStitch) {
          final key = (stitch.x << 16) | stitch.y;
          snapColor.putIfAbsent(key, () => threadQ[stitch.threadId]);
        }
      }
    }

    int? colorAt(int col, int row) => snapColor[(col << 16) | row];
    String symAt(int col, int row) {
      final q = colorAt(col, row);
      return q == null ? '.' : (quantToSym[q] ?? '?');
    }

    // ── Canvas view ──────────────────────────────────────────────────────────
    final nominal = config.pageWidth; // first vertical boundary (col 50)
    const startRow = 22;
    const endRow = 33;
    final startCol = nominal - 10;
    final endCol = nominal + 9;

    final sb = StringBuffer();
    sb.writeln('\nCanvas view cols $startCol–$endCol, rows $startRow–${endRow-1}');
    sb.writeln('Nominal boundary at col $nominal');
    sb.write('row  ');
    for (int c = startCol; c < endCol; c++) {
      sb.write(c == nominal ? '|' : (c % 10).toString());
    }
    sb.writeln();
    for (int row = startRow; row < endRow; row++) {
      sb.write(' ${row.toString().padLeft(2)}: ');
      for (int col = startCol; col < endCol; col++) sb.write(symAt(col, row));
      sb.writeln();
    }

    // ── Quant values ─────────────────────────────────────────────────────────
    sb.writeln('\nQuant values cols ${nominal-5}–${nominal+5}:');
    sb.write('row  ');
    for (int c = nominal - 5; c <= nominal + 5; c++) {
      sb.write(' ${c.toString().padLeft(4)}');
    }
    sb.writeln();
    for (int row = startRow; row < endRow; row++) {
      sb.write(' ${row.toString().padLeft(2)}: ');
      for (int c = nominal - 5; c <= nominal + 5; c++) {
        final q = colorAt(c, row);
        sb.write(' ${(q?.toString() ?? 'N').padLeft(4)}');
      }
      sb.writeln();
    }

    // ── computeOffset simulation ─────────────────────────────────────────────
    sb.writeln('\ncomputeOffset results — boundary=$nominal '
        'fuzzyAmount=${config.fuzzyAmount} snapRange=${PageLayout.snapRange}:');
    for (int row = startRow; row < endRow; row++) {
      final offset = PageLayout.computeOffset(
        nominalBoundary: nominal,
        crossIndex: row,
        fuzzyAmount: config.fuzzyAmount,
        maxBoundary: pattern.width,
        colorAt: colorAt,
        seed: 0,
      );
      final cutCol = nominal + offset;
      final leftSym = symAt(cutCol - 1, row);
      final rightSym = symAt(cutCol, row);
      sb.writeln('  row $row: offset=${offset.toString().padLeft(3)} → '
          'cut at col $cutCol  ($leftSym | $rightSym)');
    }

    printOnFailure(sb.toString());
    // Always "fail" so the output is visible without --verbose.
    // Change expect(true, isFalse) to expect(true, isTrue) to suppress.
    expect(true, isFalse, reason: sb.toString());
  });
}

