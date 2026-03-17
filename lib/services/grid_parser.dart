import 'dart:io';

// All recognised stitch characters. Any of these in the grid = active cell.
const stitchChars = {
  '╳', // full cross stitch
  '▞', // / half stitch
  '▚', // \ half stitch
  '▌', // left half-fill
  '▐', // right half-fill
  '▀', // top half-fill
  '▄', // bottom half-fill
  '▘', // top-left quarter
  '▝', // top-right quarter
  '▖', // bottom-left quarter
  '▗', // bottom-right quarter
  '▛', // three-quarter (missing bottom-right)
  '▜', // three-quarter (missing bottom-left)
  '▙', // three-quarter (missing top-right)
  '▟', // three-quarter (missing top-left)
};

/// Parses a grid text into a list of active cell coordinates.
///
/// Rows are newline-separated; cells within a row are separated by a single
/// space. An empty string token (produced by two consecutive spaces) is an
/// empty cell. Any unrecognised non-empty token prints a warning and is skipped.
({List<(int, int)> cells, int cols, int rows}) parseGrid(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trimRight())
      .toList();

  // Drop trailing blank lines.
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  if (lines.isEmpty) return (cells: [], cols: 0, rows: 0);

  final cells = <(int, int)>[];
  var maxCols = 0;

  for (var y = 0; y < lines.length; y++) {
    // Split on every single space so double-space produces an empty token.
    final tokens = lines[y].split(' ');
    if (tokens.length > maxCols) maxCols = tokens.length;
    for (var x = 0; x < tokens.length; x++) {
      final ch = tokens[x];
      if (ch.isEmpty) continue; // empty cell
      if (stitchChars.contains(ch)) {
        cells.add((x, y));
      } else {
        stderr.writeln('Warning: unknown character "$ch" at ($x, $y) — skipped.');
      }
    }
  }

  return (cells: cells, cols: maxCols, rows: lines.length);
}
