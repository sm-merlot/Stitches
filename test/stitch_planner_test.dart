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

// ── V2-specific inline tests ───────────────────────────────────────────────

void _expectV2Sequence(
  String label,
  List<(int, int)> cells,
  int cols,
  int rows,
  List<String> expected,
) {
  final aida = planStitchingV2(
    title: label,
    cols: cols,
    rows: rows,
    cells: cells,
  );

  final actual =
      aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList();

  // Build a readable diff for failures.
  final maxLen = actual.length > expected.length ? actual.length : expected.length;
  final diffLines = <String>[];
  for (var i = 0; i < maxLen; i++) {
    final a = i < actual.length ? actual[i] : '<missing>';
    final e = i < expected.length ? expected[i] : '<missing>';
    final mark = a == e ? '   ' : '***';
    diffLines.add('$mark [$i] expected: $e');
    if (a != e) diffLines.add('         got:      $a');
  }

  expect(
    actual,
    expected,
    reason: '$label:\n${diffLines.join('\n')}',
  );
}

// ── V3-specific inline tests ───────────────────────────────────────────────

void _expectV3Sequence(
  String label,
  List<(int, int)> cells,
  int cols,
  int rows,
  List<String> expected, {
  (int, int)? startCell,
}) {
  final aida = planStitchingV3(
    title: label,
    cols: cols,
    rows: rows,
    cells: cells,
    startCell: startCell,
  );

  final actual =
      aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList();

  final maxLen = actual.length > expected.length ? actual.length : expected.length;
  final diffLines = <String>[];
  for (var i = 0; i < maxLen; i++) {
    final a = i < actual.length ? actual[i] : '<missing>';
    final e = i < expected.length ? expected[i] : '<missing>';
    final mark = a == e ? '   ' : '***';
    diffLines.add('$mark [$i] expected: $e');
    if (a != e) diffLines.add('         got:      $a');
  }

  expect(
    actual,
    expected,
    reason: '$label:\n${diffLines.join('\n')}',
  );
}

void main() {
  group('planStitchingV2', () {
    test('2x2 full grid', () {
      // XX
      // XX
      //
      // Expected order (from design spec):
      //   (0,0) TL->BR, BR->BL
      //   (0,1) TL->BR, BR->TR
      //   (1,1) TL->BR, BR->TR, TR->BL
      //   (0,1) BR->BL, BL->TR          ← reversed S2 to route to (1,0)
      //   (1,0) BL->TL, TL->BR, BR->TR, TR->BL
      //   (0,0) BR->TR, TR->BL
      _expectV2Sequence(
        '2x2',
        [(0, 0), (1, 0), (0, 1), (1, 1)],
        2,
        2,
        [
          'S(0,0,TL) B(0,0,BR)', // S1 (0,0)
          'B(0,0,BR) S(0,0,BL)', // back BR→BL
          'S(0,1,TL) B(0,1,BR)', // S1 (0,1)
          'B(0,1,BR) S(0,1,TR)', // back BR→TR
          'S(1,1,TL) B(1,1,BR)', // S1 (1,1)
          'B(1,1,BR) S(1,1,TR)', // back BR→TR
          'S(1,1,TR) B(1,1,BL)', // S2 (1,1)
          'B(0,1,BR) S(0,1,BL)', // back BR→BL  (reversed-S2 routing for (0,1))
          'S(0,1,BL) B(0,1,TR)', // S2 reversed (0,1)
          'B(0,0,BR) S(0,0,TR)', // back (0.5,0.5)→(0.5,−0.5), serialised via (0,0) as lowest-sqId shared cell
          'S(1,0,TL) B(1,0,BR)', // S1 (1,0)
          'B(1,0,BR) S(1,0,TR)', // back BR→TR
          'S(1,0,TR) B(1,0,BL)', // S2 (1,0)
          'B(0,0,BR) S(0,0,TR)', // back BR→TR
          'S(0,0,TR) B(0,0,BL)', // S2 (0,0)
        ],
      );
    });

    test('3x3 full grid', () {
      // XXX
      // XXX
      // XXX
      //
      // Expected traversal:
      //   S1 column: (0,0)→(0,1)→(0,2), then sweep right along bottom: (1,2)→(2,2)
      //   S2 bottom-row: (2,2) forward, (1,2) forward (H back left), (0,2) reversed → needle at TR(0,2)=BL(1,1)
      //   S1 mid-row: (1,1)→(2,1), S2: (2,1) forward, (1,1) forward (H back left), (0,1) reversed → needle at TR(0,1)=BL(1,0)
      //   S1 top-row: (1,0)→(2,0), S2: (2,0) forward, (1,0) forward, (0,0) forward
      _expectV2Sequence(
        '3x3',
        [
          (0, 0), (1, 0), (2, 0),
          (0, 1), (1, 1), (2, 1),
          (0, 2), (1, 2), (2, 2),
        ],
        3,
        3,
        [
          'S(0,0,TL) B(0,0,BR)', //  1 — S1 (0,0)
          'B(0,0,BR) S(0,0,BL)', //  2 — back H to (0,1).TL
          'S(0,1,TL) B(0,1,BR)', //  3 — S1 (0,1)
          'B(0,1,BR) S(0,1,BL)', //  4 — back H to (0,2).TL
          'S(0,2,TL) B(0,2,BR)', //  5 — S1 (0,2)
          'B(0,2,BR) S(0,2,TR)', //  6 — back V up to (1,2).TL
          'S(1,2,TL) B(1,2,BR)', //  7 — S1 (1,2)
          'B(1,2,BR) S(1,2,TR)', //  8 — back V up to (2,2).TL
          'S(2,2,TL) B(2,2,BR)', //  9 — S1 (2,2)
          'B(2,2,BR) S(2,2,TR)', // 10 — back V up: S2 (2,2)
          'S(2,2,TR) B(2,2,BL)', // 11 — S2 (2,2) forward
          'B(1,2,BR) S(1,2,TR)', // 12 — back V up to TR(1,2)
          'S(1,2,TR) B(1,2,BL)', // 13 — S2 (1,2) forward → needle at BL(1,2)=BR(0,2)
          'B(0,2,BR) S(0,2,BL)', // 14 — back H left to BL(0,2)
          'S(0,2,BL) B(0,2,TR)', // 15 — S2 (0,2) reversed → needle at TR(0,2)=BR(0,1)
          'B(0,1,BR) S(0,1,TR)', // 16 — back V up to (1,1).TL
          'S(1,1,TL) B(1,1,BR)', // 17 — S1 (1,1)
          'B(1,1,BR) S(1,1,TR)', // 18 — back V up to (2,1).TL
          'S(2,1,TL) B(2,1,BR)', // 19 — S1 (2,1)
          'B(2,1,BR) S(2,1,TR)', // 20 — back V up: S2 (2,1)
          'S(2,1,TR) B(2,1,BL)', // 21 — S2 (2,1) forward
          'B(1,1,BR) S(1,1,TR)', // 22 — back V up to TR(1,1)
          'S(1,1,TR) B(1,1,BL)', // 23 — S2 (1,1) forward → needle at BL(1,1)=BR(0,1)
          'B(0,1,BR) S(0,1,BL)', // 24 — back H left to BL(0,1)
          'S(0,1,BL) B(0,1,TR)', // 25 — S2 (0,1) reversed → needle at TR(0,1)=BR(0,0)
          'B(0,0,BR) S(0,0,TR)', // 26 — back V up to (1,0).TL
          'S(1,0,TL) B(1,0,BR)', // 27 — S1 (1,0)
          'B(1,0,BR) S(1,0,TR)', // 28 — back V up to (2,0).TL
          'S(2,0,TL) B(2,0,BR)', // 29 — S1 (2,0)
          'B(2,0,BR) S(2,0,TR)', // 30 — back V up: S2 (2,0)
          'S(2,0,TR) B(2,0,BL)', // 31 — S2 (2,0) forward
          'B(1,0,BR) S(1,0,TR)', // 32 — back V (2nd pass): S2 (1,0)
          'S(1,0,TR) B(1,0,BL)', // 33 — S2 (1,0) forward
          'B(0,0,BR) S(0,0,TR)', // 34 — back V (2nd pass): S2 (0,0)
          'S(0,0,TR) B(0,0,BL)', // 35 — S2 (0,0) forward
        ],
      );
    });
  });

  group('planStitchingV3', () {
    test('3x3 full grid, start bottom-right (2,2)', () {
      // XXX     Start: (2,2) — bottom-right corner.
      // XXX
      // XXX
      //
      // R1 with cell below empty: S1 + B(BR→BL), move below.
      // R1 with no empty cell below: S1 only.
      //
      // At (2,2): no cell below → S1 only.
      _expectV3Sequence(
        '3x3 bottom-right start',
        [
          (0, 0), (1, 0), (2, 0),
          (0, 1), (1, 1), (2, 1),
          (0, 2), (1, 2), (2, 2),
        ],
        3,
        3,
        [
          'S(2,2,TL) B(2,2,BR)', // S1 (2,2) — no cell below, S1 only
        ],
        startCell: (2, 2),
      );
    });

    test('3x3 full grid, start mid-right (2,1)', () {
      // XXX     Start: (2,1) — middle of right column.
      // XXX
      // XXX
      //
      // At (2,1): cell below (2,2) is empty → S1 + B(BR→BL), move to (2,2).
      // At (2,2): no cell below → S1 only.
      _expectV3Sequence(
        '3x3 mid-right start',
        [
          (0, 0), (1, 0), (2, 0),
          (0, 1), (1, 1), (2, 1),
          (0, 2), (1, 2), (2, 2),
        ],
        3,
        3,
        [
          'S(2,1,TL) B(2,1,BR)', // S1 (2,1)
          'B(2,1,BR) S(2,1,BL)', // B(BR→BL) — cell below is empty
          'S(2,2,TL) B(2,2,BR)', // S1 (2,2) — no cell below, S1 only
        ],
        startCell: (2, 1),
      );
    });

    test('3x3 full grid, start top-right (2,0)', () {
      // XXX     Start: (2,0) — top of right column.
      // XXX
      // XXX
      //
      // At (2,0): cell below (2,1) is empty → S1 + B(BR→BL), move to (2,1).
      // At (2,1): cell below (2,2) is empty → S1 + B(BR→BL), move to (2,2).
      // At (2,2): no cell below → S1 only.
      _expectV3Sequence(
        '3x3 top-right start',
        [
          (0, 0), (1, 0), (2, 0),
          (0, 1), (1, 1), (2, 1),
          (0, 2), (1, 2), (2, 2),
        ],
        3,
        3,
        [
          'S(2,0,TL) B(2,0,BR)', // S1 (2,0)
          'B(2,0,BR) S(2,0,BL)', // B(BR→BL) — cell below is empty
          'S(2,1,TL) B(2,1,BR)', // S1 (2,1) — needle already at TL, no back needed
          'B(2,1,BR) S(2,1,BL)', // B(BR→BL) — cell below is empty
          'S(2,2,TL) B(2,2,BR)', // S1 (2,2) — no cell below, S1 only
        ],
        startCell: (2, 0),
      );
    });
  });

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
