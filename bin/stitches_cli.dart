// Stitches CLI — animate a stitching plan as a GIF.
//
// Compile to a standalone binary:
//   dart compile exe bin/stitches_cli.dart -o stitches-cli
//
// Input methods (pick one):
//   stitches-cli -i grid.pattern -o out.gif          # file
//   cat grid.pattern | stitches-cli -o out.gif        # stdin pipe
//   stitches-cli -p "╳ ▞\n▚ ╳" -o out.gif        # inline (\n = newline)
//
// Grid format: rows separated by newlines, cells separated by single spaces.
// Use two consecutive spaces for an empty cell inside a row.
//
// Color scheme: purple=front1  green=front2  gold=back1  red=back2  blue=back3

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:image/image.dart' as img;
import 'package:stitches/models/stitch_plan.dart' show PlannedAida;
import 'package:stitches/services/gif_renderer.dart'
    show kDemoSubFrames, renderDemoGif;
import 'package:stitches/services/grid_parser.dart';
import 'package:stitches/services/stitch_instructions_parser.dart';
import 'package:stitches/services/stitch_planner.dart';
import 'package:stitches/services/stitch_renderer.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input',
        abbr: 'i',
        help: 'Path to grid text file. Use - to read from stdin.')
    ..addOption('pattern',
        abbr: 'p',
        help: 'Inline grid pattern. Rows are separated by \\n '
            '(or actual newlines in a quoted string.')
    ..addOption('stitches',
        abbr: 's',
        help: 'Path to a hand-crafted stitch instructions JSON file. '
            'Bypasses the auto-planner; lets you specify every stitch and '
            'back-stitch in exact order. See --help for the JSON schema.')
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
        defaultsTo: '60',
        help: 'Pixels per grid cell. (default: 60)')
    ..addOption('padding',
        defaultsTo: '20',
        help: 'Padding around the pattern in pixels. (default: 20)')
    ..addOption('sampling-factor',
        defaultsTo: '1',
        help: 'GIF colour-quantisation quality: 1 = best (slow), '
            '10 = default fast. (default: 1)')
    ..addOption('dither',
        defaultsTo: 'none',
        allowed: [
          'none',
          'falseFloydSteinberg',
          'floydSteinberg',
          'stucki',
          'atkinson',
        ],
        help: 'Dithering kernel for GIF palette mapping. (default: none)')
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

  // --stitches is mutually exclusive with --input / --pattern.
  if (args['stitches'] != null &&
      (args['input'] != null || args['pattern'] != null)) {
    stderr.writeln(
        'Error: --stitches cannot be combined with --input or --pattern.\n');
    _printUsage(parser);
    exit(1);
  }

  final fps = int.parse(args['fps'] as String);
  final cellSize = double.parse(args['cell-size'] as String);
  final padding = double.parse(args['padding'] as String);
  final samplingFactor = int.parse(args['sampling-factor'] as String);
  final dither = _parseDither(args['dither'] as String);

  // ── Stitch-instructions shortcut (bypasses grid parser + planner) ─────────

  if (args['stitches'] != null) {
    final stitchesPath = args['stitches'] as String;
    final stitchesFile = File(stitchesPath);
    if (!stitchesFile.existsSync()) {
      stderr.writeln('Error: file not found: $stitchesPath');
      exit(1);
    }

    final instructionsJson = stitchesFile.readAsStringSync();
    final PlannedAida aida;
    try {
      aida = parseStitchInstructions(instructionsJson);
    } on FormatException catch (e) {
      stderr.writeln('Error parsing stitch instructions: ${e.message}');
      exit(1);
    }

    final title = (args['title'] as String?) ?? aida.title;
    print('Loaded "$title" — ${aida.stitches.length} stitches '
        '(${aida.cols}x${aida.rows} grid).');

    final gifBytes = renderDemoGif(
      aida: aida,
      fps: fps,
      cellSize: cellSize,
      padding: padding,
      samplingFactor: samplingFactor,
      dither: dither,
    );

    print('Encoding GIF…');
    File(outputPath!).writeAsBytesSync(gifBytes);
    print('Saved to $outputPath');
    return;
  }

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
    samplingFactor: samplingFactor,
    dither: dither,
  );

  print('Encoding GIF…');
  File(outputPath).writeAsBytesSync(gifBytes);
  print('Saved to $outputPath');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<String> _readStdin() =>
    stdin.transform(utf8.decoder).join();

img.DitherKernel _parseDither(String name) => switch (name) {
      'none'                => img.DitherKernel.none,
      'falseFloydSteinberg' => img.DitherKernel.falseFloydSteinberg,
      'floydSteinberg'      => img.DitherKernel.floydSteinberg,
      'stucki'              => img.DitherKernel.stucki,
      'atkinson'            => img.DitherKernel.atkinson,
      _                     => img.DitherKernel.floydSteinberg,
    };

void _printUsage(ArgParser parser) {
  print('''
Stitches CLI — animate a stitching plan as a GIF.

Usage:
  stitches-cli -i <grid.pattern> -o <out.gif>          file input
  cat grid.pattern | stitches-cli -o <out.gif>          stdin input
  stitches-cli -p "╳ ▞\\n▚ ╳" -o <out.gif>         inline input
  stitches-cli -s <plan.json>   -o <out.gif>            hand-crafted plan

Grid format:
  Rows are separated by newlines.
  Cells within a row are separated by a single space.
  Use two consecutive spaces (double space) for an empty cell mid-row.

  Symbol  Stitch
  ------  ------
  ╳ / X   Full cross stitch
  ▞ / /   / half stitch
  ▚ / \\   \\ half stitch
     ▌    Left half-fill          ▐    Right half-fill
     ▀    Top half-fill           ▄    Bottom half-fill
     ▘    Top-left quarter        ▝    Top-right quarter
     ▖    Bottom-left quarter     ▗    Bottom-right quarter
     ▛    Three-quarter (−BR)     ▜    Three-quarter (−BL)
     ▙    Three-quarter (−TR)     ▟    Three-quarter (−TL)
  (space) Empty cell

Hand-crafted stitch instructions JSON  (-s / --stitches):
  Bypasses the auto-planner so you control every stitch in exact order.

  {
    "title": "My Pattern",     // optional
    "cols":  3,                // grid width  (required)
    "rows":  2,                // grid height (required)
    "cells": [[0,0],[1,0]],   // optional — which cells show a grid box
                               //   defaults to every cell touched by a stitch
    "stitches": [
      {
        "type": "front1",      // front1 | front2 | back1 | back2 | back3 | auto
        "from": {"x":0,"y":0,"corner":"topLeft"},
        "to":   {"x":0,"y":0,"corner":"bottomRight"}
      },
      ...
    ]
  }

  Corner names:  topLeft (TL)  topRight (TR)  bottomLeft (BL)  bottomRight (BR)
  Types:
    front1 — purple  (\\-diagonal front stitch)
    front2 — green   (/-diagonal front stitch)
    back1  — grey    (first pass back stitch)
    back2  — grey    (second pass — same segment)
    back3  — grey    (third pass)
    auto   — uses the automatic colour for the stitch type

Options:
${parser.usage}''');
}

