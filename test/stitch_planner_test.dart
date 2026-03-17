// File-based stitch planner tests.
//
// Each test case lives in test/fixtures/:
//   <name>.pattern      — grid pattern (same format as the CLI accepts)
//   <name>.expected — expected stitch sequence, one per line:
//
//     S(x,y,corner) B(x,y,corner)  — front stroke: surface→back
//     B(x,y,corner) S(x,y,corner)  — back travel:  back→surface
//
// Corner notation per cell:
//   TL───TC───TR
//   │         │
//   LC   CC   RC
//   │         │
//   BL───BC───BR
//
// To regenerate .expected files from the current algorithm:
//   dart run tool/generate_fixtures.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stitchx/models/stitch_plan.dart';
import 'package:stitchx/services/grid_parser.dart';
import 'package:stitchx/services/stitch_planner.dart';

// ── Corner helpers ─────────────────────────────────────────────────────────

String _cornerStr(Corner c) => switch (c) {
      Corner.topLeft => 'TL',
      Corner.topRight => 'TR',
      Corner.bottomLeft => 'BL',
      Corner.bottomRight => 'BR',
    };

// ── Stitch serialisation (used in failure messages) ────────────────────────

String _serializeStitch(PlanStitchEntry stitch, List<PlannedSquare> squares) {
  final isFront =
      stitch.type == StitchType.frontOne || stitch.type == StitchType.frontTwo;

  if (stitch is PlanSimpleStitch) {
    final sq = squares[stitch.squareId];
    final froTag = isFront ? 'S' : 'B';
    final toTag = isFront ? 'B' : 'S';
    return '$froTag(${sq.x},${sq.y},${_cornerStr(stitch.fro)}) '
        '$toTag(${sq.x},${sq.y},${_cornerStr(stitch.to)})';
  }

  if (stitch is PlanCrossStitch) {
    final froSq = squares[stitch.fro.squareId];
    final toSq = squares[stitch.to.squareId];
    return 'B(${froSq.x},${froSq.y},${_cornerStr(stitch.fro.corner)}) '
        'S(${toSq.x},${toSq.y},${_cornerStr(stitch.to.corner)})';
  }

  throw ArgumentError('Unknown stitch type: $stitch');
}

// ── Expected-line parsing ──────────────────────────────────────────────────

typedef _StitchSpec = ({
  bool froIsSurface, // true → fro is S (surface), false → fro is B (back)
  int x1,
  int y1,
  String c1, // raw corner string, supports TC/BC/LC/RC/CC for future use
  bool toIsSurface,
  int x2,
  int y2,
  String c2,
});

final _lineRe =
    RegExp(r'([SB])\((\d+),(\d+),([A-Z]+)\)\s+([SB])\((\d+),(\d+),([A-Z]+)\)');

_StitchSpec _parseLine(String line) {
  final m = _lineRe.firstMatch(line.trim());
  if (m == null) throw FormatException('Cannot parse fixture line: "$line"');
  return (
    froIsSurface: m.group(1) == 'S',
    x1: int.parse(m.group(2)!),
    y1: int.parse(m.group(3)!),
    c1: m.group(4)!,
    toIsSurface: m.group(5) == 'S',
    x2: int.parse(m.group(6)!),
    y2: int.parse(m.group(7)!),
    c2: m.group(8)!,
  );
}

// ── Stitch→spec matching ───────────────────────────────────────────────────

bool _matches(
    PlanStitchEntry stitch, _StitchSpec spec, List<PlannedSquare> squares) {
  final isFront =
      stitch.type == StitchType.frontOne || stitch.type == StitchType.frontTwo;

  // Front stitches: fro = surface (S), to = back (B).
  // Back stitches:  fro = back (B),    to = surface (S).
  final froIsSurface = isFront;
  final toIsSurface = !isFront;

  if (froIsSurface != spec.froIsSurface) return false;
  if (toIsSurface != spec.toIsSurface) return false;

  int x1, y1, x2, y2;
  String c1, c2;

  if (stitch is PlanSimpleStitch) {
    final sq = squares[stitch.squareId];
    x1 = sq.x; y1 = sq.y; c1 = _cornerStr(stitch.fro);
    x2 = sq.x; y2 = sq.y; c2 = _cornerStr(stitch.to);
  } else if (stitch is PlanCrossStitch) {
    final froSq = squares[stitch.fro.squareId];
    final toSq = squares[stitch.to.squareId];
    x1 = froSq.x; y1 = froSq.y; c1 = _cornerStr(stitch.fro.corner);
    x2 = toSq.x; y2 = toSq.y; c2 = _cornerStr(stitch.to.corner);
  } else {
    return false;
  }

  return x1 == spec.x1 &&
      y1 == spec.y1 &&
      c1 == spec.c1 &&
      x2 == spec.x2 &&
      y2 == spec.y2 &&
      c2 == spec.c2;
}

// ── Test runner ────────────────────────────────────────────────────────────

void main() {
  final fixturesDir = Directory('test/fixtures');

  final txtFiles = fixturesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pattern'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final patternFile in txtFiles) {
    final name = patternFile.uri.pathSegments.last.replaceAll('.pattern', '');
    final expectedFile = File('test/fixtures/$name.expected');

    if (!expectedFile.existsSync()) {
      // No expected file yet — skip (run generate_fixtures.dart to create one).
      continue;
    }

    test(name, () {
      // Parse pattern.
      final (:cells, :cols, :rows) = parseGrid(patternFile.readAsStringSync());
      expect(cells, isNotEmpty, reason: '$name: no cells in pattern file');

      // Run planner.
      final aida =
          planStitching(title: name, cols: cols, rows: rows, cells: cells);

      // Load expected lines.
      final expectedLines = expectedFile
          .readAsStringSync()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      // Validate parseability of expected lines upfront.
      final specs = expectedLines.map(_parseLine).toList();

      // Check count.
      expect(
        aida.stitches.length,
        specs.length,
        reason: '$name: wrong stitch count\n'
            '  expected ${specs.length}, got ${aida.stitches.length}',
      );

      // Check each stitch in order.
      for (var i = 0; i < specs.length; i++) {
        final actual = aida.stitches[i];
        final spec = specs[i];
        expect(
          _matches(actual, spec, aida.squares),
          isTrue,
          reason: '$name: stitch $i mismatch\n'
              '  expected: ${expectedLines[i]}\n'
              '  got:      ${_serializeStitch(actual, aida.squares)}',
        );
      }
    });
  }
}
