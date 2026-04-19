// UNUSED — see test/debug_snap_test.dart instead.
// tool/debug_snap.dart
//
// Loads the Ridley .stitches file using the real app code and dumps the
// snap-colour map and _computeOffset simulation for the boundary region
// the user is investigating.
//
// Run with:
//   dart run tool/debug_snap.dart
//
// Outputs:
//  1. Canvas-visible colours (top layer) around the first vertical boundary.
//  2. The actual offset that _computeOffset() returns for each row.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stitches/models/page_layout.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/services/file_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _hex(Color c) {
  // ignore: deprecated_member_use
  final r = c.red, g = c.green, b = c.blue;
  return '#${r.toRadixString(16).padLeft(2,'0')}'
         '${g.toRadixString(16).padLeft(2,'0')}'
         '${b.toRadixString(16).padLeft(2,'0')}';
}

int _q(Color c) {
  // ignore: deprecated_member_use
  return ((c.red >> 5) << 6) | ((c.green >> 5) << 3) | (c.blue >> 5);
}

Future<void> main() async {
  // Must initialise Flutter bindings for Color parsing etc.
  WidgetsFlutterBinding.ensureInitialized();

  const path =
      '/Users/scottmerchant/dev/Stitches/worktrees/fuzzy-page-edges/'
      'Super Metroid - Samus battles Ridley.stitches';

  stdout.writeln('Loading $path …');
  final bytes = await File(path).readAsBytes();
  final (pattern, _) = await FileService.parseBytesToPattern(bytes);
  stdout.writeln('Loaded: ${pattern.width}×${pattern.height}, '
      '${pattern.threads.length} threads, '
      '${pattern.layers.length} layers');

  final config = pattern.pageConfig;
  stdout.writeln('Page config: ${config.pageWidth}×${config.pageHeight}, '
      'fuzzyAmount=${config.fuzzyAmount}, enabled=${config.enabled}');

  // ── Build snap-colour map (mirrors PageLayout.compute) ───────────────────
  int quantise(Color c) => _q(c);

  final threadQuantColor = <String, int>{
    for (final t in pattern.threads) t.dmcCode: quantise(t.color),
  };
  final threadSymbol = <String, String>{
    for (final t in pattern.threads) t.dmcCode: t.symbol ?? '?',
  };

  // quant → first code with that quant → symbol
  final quantSym = <int, String>{};
  for (final t in pattern.threads) {
    quantSym.putIfAbsent(quantise(t.color), () => t.symbol ?? '?');
  }

  final snapColor = <int, int?>{};
  // layers.reversed = topmost first; putIfAbsent = topmost wins
  for (final layer in pattern.layers.reversed) {
    if (!layer.visible) continue;
    for (final stitch in layer.stitches) {
      if (stitch is FullStitch) {
        final key = (stitch.x << 16) | stitch.y;
        snapColor.putIfAbsent(key, () => threadQuantColor[stitch.threadId]);
      }
    }
  }

  int? colorAt(int col, int row) => snapColor[(col << 16) | row];
  String symAt(int col, int row) {
    final q = colorAt(col, row);
    if (q == null) return '.';
    return quantSym[q] ?? '?';
  }

  // ── Canvas view ───────────────────────────────────────────────────────────
  final nominal = config.pageWidth; // first vertical boundary
  final startCol = nominal - 10;
  final endCol = nominal + 8;
  const startRow = 22;
  const endRow = 33;

  stdout.writeln('\nCanvas view (top-layer colours) — '
      'cols $startCol–$endCol, rows $startRow–${endRow-1}');
  stdout.writeln('Nominal boundary at col $nominal (shown as |)');
  stdout.write('row  ');
  for (int c = startCol; c < endCol; c++) {
    stdout.write(c == nominal ? '|' : (c % 10).toString());
  }
  stdout.writeln();
  for (int row = startRow; row < endRow; row++) {
    stdout.write(' ${row.toString().padLeft(2)}: ');
    for (int col = startCol; col < endCol; col++) {
      stdout.write(symAt(col, row));
    }
    stdout.writeln();
  }

  // ── Quant values ─────────────────────────────────────────────────────────
  stdout.writeln('\nQuant values cols ${nominal-4}–${nominal+4}:');
  stdout.write('row  ');
  for (int c = nominal - 4; c <= nominal + 4; c++) stdout.write(' ${c.toString().padLeft(3)}');
  stdout.writeln();
  for (int row = startRow; row < endRow; row++) {
    stdout.write(' ${row.toString().padLeft(2)}: ');
    for (int c = nominal - 4; c <= nominal + 4; c++) {
      final q = colorAt(c, row);
      stdout.write(' ${(q?.toString() ?? 'N').padLeft(3)}');
    }
    stdout.writeln();
  }

  // ── Simulate _computeOffset for each row ──────────────────────────────────
  stdout.writeln('\n_computeOffset simulation — boundary=$nominal, '
      'fuzzyAmount=${config.fuzzyAmount}, snapRange=${PageLayout.snapRange}:');

  for (int row = startRow; row < endRow; row++) {
    final offset = PageLayout.computeOffset(
      nominalBoundary: nominal,
      crossIndex: row,
      fuzzyAmount: config.fuzzyAmount,
      maxBoundary: pattern.width,
      colorAt: colorAt,
      seed: 0, // seed=0 for reproducibility; real seeds differ but don't affect snap
    );
    final cutCol = nominal + offset;
    final leftSym = symAt(cutCol - 1, row);
    final rightSym = symAt(cutCol, row);
    stdout.writeln('  row $row: offset=$offset → cut at col $cutCol '
        '($leftSym | $rightSym)');
  }
}

