// StitchX CLI — animate a stitching plan as a GIF.
//
// Compile to a standalone binary:
//   dart compile exe bin/stitchx_cli.dart -o stitchx-cli
//
// Input methods (pick one):
//   stitchx-cli -i grid.txt -o out.gif          # file
//   cat grid.txt | stitchx-cli -o out.gif        # stdin pipe
//   stitchx-cli -p "╳ ▞\n▚ ╳" -o out.gif        # inline (\n = newline)
//
// Grid format: rows separated by newlines, cells separated by single spaces.
// Use two consecutive spaces for an empty cell inside a row.
//
// Color scheme: purple=front1  green=front2  gold=back1  red=back2  blue=back3

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:stitchx/services/gif_renderer.dart'
    show kDemoSubFrames, renderDemoGif;
import 'package:stitchx/services/stitch_planner.dart';
import 'package:stitchx/services/stitch_renderer.dart';

// ── Grid character set ────────────────────────────────────────────────────────

// All recognised stitch characters. Any of these in the grid = active cell.
const _stitchChars = {
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

// ── Grid parser ───────────────────────────────────────────────────────────────

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
      if (_stitchChars.contains(ch)) {
        cells.add((x, y));
      } else {
        stderr.writeln('Warning: unknown character "$ch" at ($x, $y) — skipped.');
      }
    }
  }

  return (cells: cells, cols: maxCols, rows: lines.length);
}

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input',
        abbr: 'i',
        help: 'Path to grid text file. Use - to read from stdin.')
    ..addOption('pattern',
        abbr: 'p',
        help: 'Inline grid pattern. Rows are separated by \\n '
            '(or actual newlines in a quoted string).')
    ..addOption('output',
        abbr: 'o',
        help: 'Path to output GIF file. (required)')
    ..addOption('title',
        abbr: 't',
        help: 'Pattern title shown in progress output. '
            'Defaults to the filename (without extension) or "Pattern".')
    ..addOption('fps',
        defaultsTo: '8',
        help: 'Frames per second for the animation. (default: 8)')
    ..addOption('cell-size',
        defaultsTo: '40',
        help: 'Pixels per grid cell. (default: 40)')
    ..addOption('padding',
        defaultsTo: '20',
        help: 'Padding around the pattern in pixels. (default: 20)')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show this help message.');

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error: $e\n');
    _printUsage(parser);
    exit(1);
  }

  if (args['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  // Validate --output.
  final outputPath = args['output'] as String?;
  if (outputPath == null) {
    stderr.writeln('Error: --output (-o) is required.\n');
    _printUsage(parser);
    exit(1);
  }

  // --input and --pattern are mutually exclusive.
  if (args['input'] != null && args['pattern'] != null) {
    stderr.writeln('Error: --input and --pattern are mutually exclusive.\n');
    _printUsage(parser);
    exit(1);
  }

  final fps = int.parse(args['fps'] as String);
  final cellSize = double.parse(args['cell-size'] as String);
  final padding = double.parse(args['padding'] as String);

  // ── Read grid text ────────────────────────────────────────────────────────

  String gridText;
  String defaultTitle;

  if (args['pattern'] != null) {
    // Inline: support literal \n as a row separator escape.
    gridText = (args['pattern'] as String).replaceAll(r'\n', '\n');
    defaultTitle = 'Pattern';
  } else if (args['input'] != null) {
    final inputArg = args['input'] as String;
    if (inputArg == '-') {
      gridText = await _readStdin();
      defaultTitle = 'Pattern';
    } else {
      final file = File(inputArg);
      if (!file.existsSync()) {
        stderr.writeln('Error: file not found: $inputArg');
        exit(1);
      }
      gridText = file.readAsStringSync();
      // Derive default title from filename without extension.
      final basename = inputArg.split(Platform.pathSeparator).last;
      defaultTitle = basename.contains('.')
          ? basename.substring(0, basename.lastIndexOf('.'))
          : basename;
    }
  } else {
    // No source given — read from stdin.
    try {
      if (stdin.hasTerminal) {
        stderr.writeln('Reading grid from stdin (press Ctrl-D when done):');
      }
    } catch (_) {}
    gridText = await _readStdin();
    defaultTitle = 'Pattern';
  }

  final title = (args['title'] as String?) ?? defaultTitle;

  // ── Parse grid ────────────────────────────────────────────────────────────

  final (:cells, :cols, :rows) = parseGrid(gridText);

  if (cells.isEmpty) {
    stderr.writeln('Error: no stitch cells found in the input.');
    exit(1);
  }

  // ── Plan stitching ────────────────────────────────────────────────────────

  print('Planning "$title" ($cols×$rows grid, ${cells.length} cells)…');
  final aida = planStitching(title: title, cols: cols, rows: rows, cells: cells);

  if (aida.stitches.isEmpty) {
    stderr.writeln('Error: planner produced no stitches.');
    exit(1);
  }

  print('Planned ${aida.stitches.length} stitches.');

  // ── Render and encode GIF ─────────────────────────────────────────────────

  final bounds = computeGridBounds(aida, cellSize);
  final canvasWidth = (bounds.width + padding * 2).ceil();
  final canvasHeight = (bounds.height + padding * 2).ceil();
  final totalFrames = aida.stitches.length * kDemoSubFrames + 1;

  print('Rendering $totalFrames frames at $fps fps ($canvasWidth×${canvasHeight}px)…');

  final gifBytes = renderDemoGif(
    aida: aida,
    fps: fps,
    cellSize: cellSize,
    padding: padding,
  );

  print('Encoding GIF…');
  File(outputPath).writeAsBytesSync(gifBytes);
  print('Saved to $outputPath');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<String> _readStdin() =>
    stdin.transform(utf8.decoder).join();

void _printUsage(ArgParser parser) {
  print('''
StitchX CLI — animate a stitching plan as a GIF.

Usage:
  stitchx-cli -i <grid.txt> -o <out.gif>          file input
  cat grid.txt | stitchx-cli -o <out.gif>          stdin input
  stitchx-cli -p "╳ ▞\\n▚ ╳" -o <out.gif>         inline input

Grid format:
  Rows are separated by newlines.
  Cells within a row are separated by a single space.
  Use two consecutive spaces (double space) for an empty cell mid-row.

  Symbol  Stitch
  ------  ------
     ╳    Full cross stitch
     ▞    / half stitch
     ▚    \\ half stitch
     ▌    Left half-fill          ▐    Right half-fill
     ▀    Top half-fill           ▄    Bottom half-fill
     ▘    Top-left quarter        ▝    Top-right quarter
     ▖    Bottom-left quarter     ▗    Bottom-right quarter
     ▛    Three-quarter (−BR)     ▜    Three-quarter (−BL)
     ▙    Three-quarter (−TR)     ▟    Three-quarter (−TL)
  (space) Empty cell

Options:
${parser.usage}''');
}

