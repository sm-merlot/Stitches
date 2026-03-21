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

// ── Inline test helpers ────────────────────────────────────────────────────

String _diffReason(String label, List<String> actual, List<String> expected) {
  final maxLen =
      actual.length > expected.length ? actual.length : expected.length;
  final lines = <String>[];
  for (var i = 0; i < maxLen; i++) {
    final a = i < actual.length ? actual[i] : '<missing>';
    final e = i < expected.length ? expected[i] : '<missing>';
    lines.add('${a == e ? '   ' : '***'} [$i] expected: $e');
    if (a != e) lines.add('         got:      $a');
  }
  return '$label:\n${lines.join('\n')}';
}

void _expect(
  String label,
  List<(int, int)> cells,
  int cols,
  int rows,
  List<String> expectedSchedule,
  List<String> expectedStitches, {
  (int, int)? startCell,
}) {
  final aida = planStitching(
    title: label,
    cols: cols,
    rows: rows,
    cells: cells,
    startCell: startCell,
  );

  expect(
    aida.schedule,
    expectedSchedule,
    reason: _diffReason('$label — Pass 1', aida.schedule, expectedSchedule),
  );

  final actualStitches =
      aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList();
  expect(
    actualStitches,
    expectedStitches,
    reason: _diffReason('$label — Pass 2', actualStitches, expectedStitches),
  );
}

void main() {
  group('planStitching', () {
    test('3x3 full grid, start bottom-right (2,2)', () {
      // XXX     Start: (2,2) — bottom-right corner.
      // XXX
      // XXX
      _expect(
        '3x3 bottom-right start',
        [(0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)],
        3, 3,
        // Pass 1: sweep left along bottom; S2(2,2) deferred (all done, above
        // empty). MNC sub-sweeps run stack-order: most-recently-detected (2,0)
        // first, inserting row-0 before S2(2,1) in the final schedule.
        [
          'S1(2,2)', 'S1(1,2)', 'S1(0,2)',
          'S2(0,2)', 'S2(1,2)',
          'S1(2,1)', 'S1(1,1)', 'S1(0,1)',
          'S2(0,1)', 'S2(1,1)',
          'S1(2,0)', 'S1(1,0)', 'S1(0,0)',
          'S2(0,0)', 'S2(1,0)', 'S2(2,0)',
          'S2(2,1)', 'S2(2,2)',
        ],
        // Pass 2: directed stitch sequence
        [
          'S(2,2,BR) B(2,2,TL)',
          'B(1,2,TR) S(1,2,BR)',
          'S(1,2,BR) B(1,2,TL)',
          'B(0,2,TR) S(0,2,BR)',  // turn-around S1(0,2): H move → V back → S1 rev
          'S(0,2,BR) B(0,2,TL)',
          'B(0,2,TL) S(0,2,BL)',  // turn-around S2(0,2): V back stitch
          'S(0,2,BL) B(0,2,TR)',
          'B(0,2,TR) S(0,2,BR)',
          'S(1,2,BL) B(1,2,TR)',
          'B(2,1,BL) S(2,1,BR)',
          'S(2,1,BR) B(2,1,TL)',
          'B(1,1,TR) S(1,1,BR)',
          'S(1,1,BR) B(1,1,TL)',
          'B(0,1,TR) S(0,1,BR)',  // turn-around S1(0,1): H move → V back → S1 rev
          'S(0,1,BR) B(0,1,TL)',
          'B(0,1,TL) S(0,1,BL)',  // turn-around S2(0,1): V back stitch
          'S(0,1,BL) B(0,1,TR)',
          'B(0,1,TR) S(0,1,BR)',
          'S(1,1,BL) B(1,1,TR)',
          'B(2,0,BL) S(2,0,BR)',
          'S(2,0,BR) B(2,0,TL)',
          'B(1,0,TR) S(1,0,BR)',
          'S(1,0,BR) B(1,0,TL)',
          'B(0,0,TR) S(0,0,BR)',  // turn-around S1(0,0): H move → V back → S1 rev
          'S(0,0,BR) B(0,0,TL)',
          'B(0,0,TL) S(0,0,BL)',  // turn-around S2(0,0): V back stitch
          'S(0,0,BL) B(0,0,TR)',
          'B(0,0,TR) S(0,0,BR)',
          'S(1,0,BL) B(1,0,TR)',
          'B(2,0,TL) S(2,0,TR)',
          'S(2,0,TR) B(2,0,BL)',
          'B(2,0,BL) S(2,0,BR)',
          'S(2,1,TR) B(2,1,BL)',
          'B(2,1,BL) S(2,1,BR)',
          'S(2,2,TR) B(2,2,BL)',
        ],
        startCell: (2, 2),
      );
    });

    test('3x3 full grid, start mid-right (2,1)', () {
      // XXX     Start: (2,1) — middle of right column.
      // XXX
      // XXX
      _expect(
        '3x3 mid-right start',
        [(0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)],
        3, 3,
        // Pass 1: down right col, sweep bottom row left, S2 right; (2,1) S2
        // deferred (all lateral done, secondary=(2,0) empty) until after row 0.
        [
          'S1(2,1)', 'S1(2,2)', 'S1(1,2)', 'S1(0,2)',
          'S2(0,2)', 'S2(1,2)', 'S2(2,2)',
          'S1(1,1)', 'S1(0,1)',
          'S2(0,1)', 'S2(1,1)',
          'S1(2,0)', 'S1(1,0)', 'S1(0,0)',
          'S2(0,0)', 'S2(1,0)', 'S2(2,0)',
          'S2(2,1)',
        ],
        // Pass 2
        [
          'S(2,1,TL) B(2,1,BR)',
          'B(2,2,TR) S(2,2,BR)',
          'S(2,2,BR) B(2,2,TL)',
          'B(1,2,TR) S(1,2,BR)',
          'S(1,2,BR) B(1,2,TL)',
          'B(0,2,TR) S(0,2,BR)',  // turn-around S1(0,2): H move → V back → S1 rev
          'S(0,2,BR) B(0,2,TL)',
          'B(0,2,TL) S(0,2,BL)',  // turn-around S2(0,2): V back stitch
          'S(0,2,BL) B(0,2,TR)',
          'B(0,2,TR) S(0,2,BR)',
          'S(1,2,BL) B(1,2,TR)',
          'B(2,1,BL) S(2,1,BR)',
          'S(2,2,TR) B(2,2,BL)',
          'B(1,2,BR) S(1,2,TR)',
          'S(1,1,BR) B(1,1,TL)',
          'B(0,1,TR) S(0,1,BR)',  // turn-around S1(0,1): H move → V back → S1 rev
          'S(0,1,BR) B(0,1,TL)',
          'B(0,1,TL) S(0,1,BL)',  // turn-around S2(0,1): V back stitch
          'S(0,1,BL) B(0,1,TR)',
          'B(0,1,TR) S(0,1,BR)',
          'S(1,1,BL) B(1,1,TR)',
          'B(2,0,BL) S(2,0,BR)',
          'S(2,0,BR) B(2,0,TL)',
          'B(1,0,TR) S(1,0,BR)',
          'S(1,0,BR) B(1,0,TL)',
          'B(0,0,TR) S(0,0,BR)',  // turn-around S1(0,0): H move → V back → S1 rev
          'S(0,0,BR) B(0,0,TL)',
          'B(0,0,TL) S(0,0,BL)',  // turn-around S2(0,0): V back stitch
          'S(0,0,BL) B(0,0,TR)',
          'B(0,0,TR) S(0,0,BR)',
          'S(1,0,BL) B(1,0,TR)',
          'B(2,0,TL) S(2,0,TR)',
          'S(2,0,TR) B(2,0,BL)',
          'B(2,0,BL) S(2,0,BR)',
          'S(2,1,TR) B(2,1,BL)',
        ],
        startCell: (2, 1),
      );
    });

    test('3x3 full grid, start top-right (2,0)', () {
      // XXX     Start: (2,0) — top of right column.
      // XXX
      // XXX
      _expect(
        '3x3 top-right start',
        [(0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)],
        3, 3,
        // Pass 1: down right col, sweep bottom row left, S2 right, move up, repeat
        [
          'S1(2,0)', 'S1(2,1)', 'S1(2,2)', 'S1(1,2)', 'S1(0,2)',
          'S2(0,2)', 'S2(1,2)', 'S2(2,2)',
          'S1(1,1)', 'S1(0,1)',
          'S2(0,1)', 'S2(1,1)', 'S2(2,1)',
          'S1(1,0)', 'S1(0,0)',
          'S2(0,0)', 'S2(1,0)', 'S2(2,0)',
        ],
        // Pass 2
        [
          'S(2,0,TL) B(2,0,BR)',
          'B(2,0,BR) S(2,0,BL)',
          'S(2,1,TL) B(2,1,BR)',
          'B(2,2,TR) S(2,2,BR)',
          'S(2,2,BR) B(2,2,TL)',
          'B(1,2,TR) S(1,2,BR)',
          'S(1,2,BR) B(1,2,TL)',
          'B(0,2,TR) S(0,2,BR)',  // turn-around S1(0,2): H move → V back → S1 rev
          'S(0,2,BR) B(0,2,TL)',
          'B(0,2,TL) S(0,2,BL)',  // turn-around S2(0,2): V back stitch
          'S(0,2,BL) B(0,2,TR)',
          'B(0,2,TR) S(0,2,BR)',
          'S(1,2,BL) B(1,2,TR)',
          'B(2,1,BL) S(2,1,BR)',
          'S(2,2,TR) B(2,2,BL)',
          'B(1,2,BR) S(1,2,TR)',
          'S(1,1,BR) B(1,1,TL)',
          'B(0,1,TR) S(0,1,BR)',  // turn-around S1(0,1): H move → V back → S1 rev
          'S(0,1,BR) B(0,1,TL)',
          'B(0,1,TL) S(0,1,BL)',  // turn-around S2(0,1): V back stitch
          'S(0,1,BL) B(0,1,TR)',
          'B(0,1,TR) S(0,1,BR)',
          'S(1,1,BL) B(1,1,TR)',
          'B(2,0,BL) S(2,0,BR)',
          'S(2,1,TR) B(2,1,BL)',
          'B(1,1,BR) S(1,1,TR)',
          'S(1,0,BR) B(1,0,TL)',
          'B(0,0,TR) S(0,0,BR)',  // turn-around S1(0,0): H move → V back → S1 rev
          'S(0,0,BR) B(0,0,TL)',
          'B(0,0,TL) S(0,0,BL)',  // turn-around S2(0,0): V back stitch
          'S(0,0,BL) B(0,0,TR)',
          'B(0,0,TR) S(0,0,BR)',
          'S(1,0,BL) B(1,0,TR)',
          'B(1,0,TR) S(1,0,BR)',
          'S(2,0,BL) B(2,0,TR)',
        ],
        startCell: (2, 0),
      );
    });
    test('3x3 full grid, start top-left (0,0)', () {
      // XXX     Start: (0,0) — top-left corner.
      // XXX
      // XXX
      _expect(
        '3x3 top-left start',
        [(0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)],
        3, 3,
        // Pass 1: down left col, sweep bottom row right, S2 left, move up, repeat
        [
          'S1(0,0)', 'S1(0,1)', 'S1(0,2)', 'S1(1,2)', 'S1(2,2)',
          'S2(2,2)', 'S2(1,2)', 'S2(0,2)',
          'S1(1,1)', 'S1(2,1)',
          'S2(2,1)', 'S2(1,1)', 'S2(0,1)',
          'S1(1,0)', 'S1(2,0)',
          'S2(2,0)', 'S2(1,0)', 'S2(0,0)',
        ],
        // Pass 2
        [
          'S(0,0,TL) B(0,0,BR)',
          'B(0,0,BR) S(0,0,BL)',
          'S(0,1,TL) B(0,1,BR)',
          'B(0,1,BR) S(0,1,BL)',
          'S(0,2,TL) B(0,2,BR)',
          'B(0,2,BR) S(0,2,TR)',
          'S(1,2,TL) B(1,2,BR)',
          'B(1,2,BR) S(1,2,TR)',
          'S(2,2,TL) B(2,2,BR)',
          'B(2,2,BR) S(2,2,TR)',
          'S(2,2,TR) B(2,2,BL)',
          'B(1,2,BR) S(1,2,TR)',
          'S(1,2,TR) B(1,2,BL)',
          'B(0,2,BR) S(0,2,BL)',
          'S(0,2,BL) B(0,2,TR)',
          'B(0,1,BR) S(0,1,TR)',
          'S(1,1,TL) B(1,1,BR)',
          'B(1,1,BR) S(1,1,TR)',
          'S(2,1,TL) B(2,1,BR)',
          'B(2,1,BR) S(2,1,TR)',
          'S(2,1,TR) B(2,1,BL)',
          'B(1,1,BR) S(1,1,TR)',
          'S(1,1,TR) B(1,1,BL)',
          'B(0,1,BR) S(0,1,BL)',
          'S(0,1,BL) B(0,1,TR)',
          'B(0,0,BR) S(0,0,TR)',
          'S(1,0,TL) B(1,0,BR)',
          'B(1,0,BR) S(1,0,TR)',
          'S(2,0,TL) B(2,0,BR)',
          'B(2,0,BR) S(2,0,TR)',
          'S(2,0,TR) B(2,0,BL)',
          'B(1,0,BR) S(1,0,TR)',
          'S(1,0,TR) B(1,0,BL)',
          'B(0,0,BR) S(0,0,TR)',
          'S(0,0,TR) B(0,0,BL)',
        ],
        startCell: (0, 0),
      );
    });

    test('3x3 full grid, start top-mid (1,0)', () {
      // XXX     Start: (1,0) — top-middle.
      // XXX
      // XXX
      _expect(
        '3x3 top-mid start',
        [(0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)],
        3, 3,
        // Pass 1: mid col down, left col, S2 left col, right to (2,2), S2 sweep
        [
          'S1(1,0)', 'S1(1,1)', 'S1(1,2)', 'S1(0,2)',
          'S2(0,2)',
          'S1(2,2)', 'S2(2,2)', 'S2(1,2)',
          'S1(0,1)', 'S2(0,1)',
          'S1(2,1)', 'S2(2,1)', 'S2(1,1)',
          'S1(0,0)', 'S2(0,0)',
          'S1(2,0)', 'S2(2,0)', 'S2(1,0)',
        ],
        // Pass 2
        [
          'S(1,0,TL) B(1,0,BR)',
          'B(1,0,BR) S(1,0,BL)',
          'S(1,1,TL) B(1,1,BR)',
          'B(1,2,TR) S(1,2,BR)',
          'S(1,2,BR) B(1,2,TL)',
          'B(0,2,TR) S(0,2,BR)',  // turn-around S1(0,2): H move → V back → S1 rev
          'S(0,2,BR) B(0,2,TL)',
          'B(0,2,TL) S(0,2,BL)',  // turn-around S2(0,2): V back stitch
          'S(0,2,BL) B(0,2,TR)',
          'B(1,1,BL) S(1,1,BR)',
          'S(2,2,TL) B(2,2,BR)',
          'B(2,2,BR) S(2,2,TR)',
          'S(2,2,TR) B(2,2,BL)',
          'B(1,2,BR) S(1,2,TR)',
          'S(1,2,TR) B(1,2,BL)',
          'B(0,2,BR) S(0,2,TR)',
          'S(0,1,BR) B(0,1,TL)',
          'B(0,1,TL) S(0,1,BL)',
          'S(0,1,BL) B(0,1,TR)',
          'B(1,0,BL) S(1,0,BR)',
          'S(2,1,TL) B(2,1,BR)',
          'B(2,1,BR) S(2,1,TR)',
          'S(2,1,TR) B(2,1,BL)',
          'B(1,1,BR) S(1,1,TR)',
          'S(1,1,TR) B(1,1,BL)',
          'B(0,1,BR) S(0,1,TR)',
          'S(0,0,BR) B(0,0,TL)',
          'B(0,0,TL) S(0,0,BL)',
          'S(0,0,BL) B(0,0,TR)',
          'B(1,0,TL) S(1,0,TR)',
          'S(2,0,TL) B(2,0,BR)',
          'B(2,0,BR) S(2,0,TR)',
          'S(2,0,TR) B(2,0,BL)',
          'B(1,0,BR) S(1,0,TR)',
          'S(1,0,TR) B(1,0,BL)',
        ],
        startCell: (1, 0),
      );
    });

    test('4x1 row, auto start right (3,0) — tiebreaker fires', () {
      // XXXX    Auto-start: (3,0) — rightmost cell.
      //
      // Pass 1 schedule: (3,0) → left → (2,0) → left → (1,0) → left → (0,0).
      //
      // Pass 2:
      //  (3,0) S1 fwd:  needle at BR(3,0).
      //  (2,0) S1: fwd=TL(2,0) diagonal from BR(3,0); rev=BR(2,0)=BL(3,0) horizontal → rev.
      //            Back H via (3,0): BR→BL. S1 rev: BR→TL. Needle at TL(2,0).
      //  (1,0) S1: fwd=TL(1,0) H dist=1; rev=BR(1,0) V dist=1 — TIE.
      //            Next cell (0,0) is horizontal (left). V departure preferred.
      //            revEnd=TL(1,0) → to BR(0,0) has dx=0 (vertical) → rev wins tiebreak.
      //            Back V via (1,0): TL(2,0)→BR(1,0) = TR(1,0)→BR(1,0). S1 rev. Needle at TL(1,0).
      //  (0,0) S1: fwd=TL(0,0) H dist=1; rev=BR(0,0) V dist=1 — TIE, no next op → fwd.
      //            Back H via (0,0): TL(1,0)=TR(0,0) → TL(0,0). S1 fwd. Needle at BR(0,0).
      _expect(
        '4x1 row tiebreaker',
        [(0, 0), (1, 0), (2, 0), (3, 0)],
        4,
        1,
        [
          'S1(3,0)', 'S1(2,0)', 'S1(1,0)', 'S1(0,0)',
          'S2(0,0)', 'S2(1,0)', 'S2(2,0)', 'S2(3,0)',
        ],
        [
          // S1 pass (sweep left)
          'S(3,0,BR) B(3,0,TL)', // S1b (3,0): next left → S1b; needle at TL(3,0)=TR(2,0)
          'B(2,0,TR) S(2,0,BR)', // back V; tiebreak rev
          'S(2,0,BR) B(2,0,TL)', // S1b (2,0); needle at TL(2,0)=TR(1,0)
          'B(1,0,TR) S(1,0,BR)', // back V; tiebreak rev
          'S(1,0,BR) B(1,0,TL)', // S1b (1,0); needle at TL(1,0)=TR(0,0)
          'B(0,0,TR) S(0,0,BR)',  // turn-around S1(0,0): H move → V back → S1 rev
          'S(0,0,BR) B(0,0,TL)', // S1 rev (0,0); needle at TL(0,0)
          // S2 pass (sweep right)
          'B(0,0,TL) S(0,0,BL)', // turn-around S2(0,0): V back stitch
          'S(0,0,BL) B(0,0,TR)', // S2b (0,0); needle at TR(0,0)
          'B(0,0,TR) S(0,0,BR)', // back V (via cell (0,0)); tiebreak rev
          'S(1,0,BL) B(1,0,TR)', // S2b (1,0); needle at TR(1,0)
          'B(1,0,TR) S(1,0,BR)', // back V (via cell (1,0)); tiebreak rev
          'S(2,0,BL) B(2,0,TR)', // S2b (2,0); needle at TR(2,0)
          'B(2,0,TR) S(2,0,BR)', // back V → BL(3,0); last-op perp approach → rev
          'S(3,0,BL) B(3,0,TR)', // S2b (3,0) rev
        ],
      );
    });

    test('MNCv2a case A — top-left diagonal inserted before trigger S1', () {
      // X .     (0,0) isolated; (1,1)+(1,2) form the main column.
      //  X      When (1,1) fires S2, the cell above (1,0) is absent →
      //  X      MNCv2a detects top-left diagonal (0,0) and schedules it
      //         before S1(1,1).
      final aida = planStitching(
        title: 'MNCv2a-A',
        cols: 2,
        rows: 3,
        cells: [(0, 0), (1, 1), (1, 2)],
      );
      expect(
        aida.schedule,
        ['S1(1,2)', 'S1(0,0)', 'S2(0,0)', 'S1(1,1)', 'S2(1,1)', 'S2(1,2)'],
        reason: 'MNCv2a-A: (0,0) must be scheduled before S1(1,1)',
      );
    });

    test('MNCv2a case B — bottom-right diagonal inserted before trigger S1', () {
      // X X     (0,0)+(1,0) form the main row; (2,1) isolated.
      //   . X   When (1,0) fires S2, the cell below (1,1) is absent →
      //         MNCv2a detects bottom-right diagonal (2,1) and schedules
      //         it before S1(1,0).
      final aida = planStitching(
        title: 'MNCv2a-B',
        cols: 3,
        rows: 2,
        cells: [(0, 0), (1, 0), (2, 1)],
      );
      expect(
        aida.schedule,
        ['S1(2,1)', 'S2(2,1)', 'S1(1,0)', 'S1(0,0)', 'S2(0,0)', 'S2(1,0)'],
        reason: 'MNCv2a-B: (2,1) must be scheduled before S1(1,0)',
      );
    });

    test('MNCv2b case A — top-right diagonal inserted after trigger S2', () {
      // . . X   (1,1)+(1,2) form the main column; (2,0) isolated.
      // . X .   When (1,1) fires S2, the cell above (1,0) is absent →
      // . X .   MNCv2b detects top-right diagonal (2,0) and schedules
      //         it after S2(1,1).
      final aida = planStitching(
        title: 'MNCv2b-A',
        cols: 3,
        rows: 3,
        cells: [(1, 1), (1, 2), (2, 0)],
      );
      expect(
        aida.schedule,
        ['S1(1,2)', 'S1(1,1)', 'S2(1,1)', 'S1(2,0)', 'S2(2,0)', 'S2(1,2)'],
        reason: 'MNCv2b-A: (2,0) must be scheduled after S2(1,1)',
      );
    });

    test('MNCv2b case B — bottom-left diagonal inserted after trigger S2', () {
      // . X X   (1,0)+(2,0) form the main row; (0,1) isolated.
      // X . .   When (1,0) fires S2, the cell below (1,1) is absent →
      //         MNCv2b detects bottom-left diagonal (0,1) and schedules
      //         it after S2(1,0).
      final aida = planStitching(
        title: 'MNCv2b-B',
        cols: 3,
        rows: 2,
        cells: [(0, 1), (1, 0), (2, 0)],
      );
      expect(
        aida.schedule,
        ['S1(2,0)', 'S1(1,0)', 'S2(1,0)', 'S1(0,1)', 'S2(0,1)', 'S2(2,0)'],
        reason: 'MNCv2b-B: (0,1) must be scheduled after S2(1,0)',
      );
    });

    // ── Diagonal chain scheduling ────────────────────────────────────────────
    //
    // When cells form a chain of diagonal-only connections all running in the
    // same direction (e.g. top-right → bottom-left, or top-left → bottom-right),
    // the correct schedule is: all S1s along the chain in traversal order, then
    // all S2s in reverse order.  Each back stitch is then only a short diagonal
    // hop rather than a pattern-spanning jump.

    test('Z-chain (top-right→bottom-left), start top-right', () {
      // . . . X X   y=0: (3,0),(4,0)
      // . . X . .   y=1: (2,1)
      // X X . . .   y=2: (0,2),(1,2)
      //
      // Correct schedule: S1s from (4,0) down the chain to (0,2), S2s back up.
      final aida = planStitching(
        title: 'z-chain-from-top',
        cols: 5,
        rows: 3,
        cells: [(3, 0), (4, 0), (2, 1), (0, 2), (1, 2)],
        startCell: (4, 0),
      );
      expect(
        aida.schedule,
        [
          'S1(4,0)', 'S1(3,0)', 'S1(2,1)', 'S1(1,2)', 'S1(0,2)',
          'S2(0,2)', 'S2(1,2)', 'S2(2,1)', 'S2(3,0)', 'S2(4,0)',
        ],
        reason: 'Z-chain from top-right: all S1s along chain, all S2s in reverse — no long back stitch',
      );
      expect(
        aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList(),
        [
          'S(4,0,BR) B(4,0,TL)',
          'B(3,0,TR) S(3,0,TL)',
          'S(3,0,TL) B(3,0,BR)',
          'B(3,1,TR) S(3,1,BL)',  // short diagonal hop (3,0)→(2,1)
          'S(2,1,BR) B(2,1,TL)',
          'B(1,1,TR) S(1,1,BL)',  // short diagonal hop (2,1)→(1,2)
          'S(1,2,TL) B(1,2,BR)',
          'B(1,2,BR) S(1,2,BL)',
          'S(0,2,BR) B(0,2,TL)',
          'B(0,2,TL) S(0,2,BL)',
          'S(0,2,BL) B(0,2,TR)',
          'B(0,2,TR) S(0,2,BR)',
          'S(1,2,BL) B(1,2,TR)',
          'S(2,1,BL) B(2,1,TR)',
          'S(3,0,BL) B(3,0,TR)',
          'B(3,0,TR) S(3,0,BR)',
          'S(4,0,BL) B(4,0,TR)',
        ],
        reason: 'Z-chain from top-right: correct stitch sequence with corners',
      );
    });

    test('Z-chain (top-right→bottom-left), start bottom-left', () {
      // . . . X X   y=0: (3,0),(4,0)
      // . . X . .   y=1: (2,1)
      // X X . . .   y=2: (0,2),(1,2)
      //
      // Correct schedule: S1s from (0,2) up the chain to (4,0), S2s back down.
      final aida = planStitching(
        title: 'z-chain-from-bottom',
        cols: 5,
        rows: 3,
        cells: [(3, 0), (4, 0), (2, 1), (0, 2), (1, 2)],
        startCell: (0, 2),
      );
      expect(
        aida.schedule,
        [
          'S1(0,2)', 'S1(1,2)', 'S1(2,1)', 'S1(3,0)', 'S1(4,0)',
          'S2(4,0)', 'S2(3,0)', 'S2(2,1)', 'S2(1,2)', 'S2(0,2)',
        ],
        reason: 'Z-chain from bottom-left: all S1s along chain, all S2s in reverse — no long back stitch',
      );
      expect(
        aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList(),
        [
          'S(0,2,TL) B(0,2,BR)',
          'B(0,2,BR) S(0,2,TR)',
          'S(1,2,TL) B(1,2,BR)',
          'B(2,2,BL) S(2,2,TR)',  // short diagonal hop (1,2)→(2,1)
          'S(2,1,BR) B(2,1,TL)',
          'B(2,0,BL) S(2,0,TR)',  // short diagonal hop (2,1)→(3,0)
          'S(3,0,TL) B(3,0,BR)',
          'B(3,0,BR) S(3,0,TR)',
          'S(4,0,TL) B(4,0,BR)',
          'B(4,0,BR) S(4,0,TR)',
          'S(4,0,TR) B(4,0,BL)',
          'B(3,0,BR) S(3,0,TR)',
          'S(3,0,TR) B(3,0,BL)',
          'S(2,1,TR) B(2,1,BL)',
          'S(1,2,TR) B(1,2,BL)',
          'B(0,2,BR) S(0,2,TR)',
          'S(0,2,TR) B(0,2,BL)',
        ],
        reason: 'Z-chain from bottom-left: correct stitch sequence with corners',
      );
    });

    test('S-chain (top-left→bottom-right), start top-left', () {
      // X X . . .   y=0: (0,0),(1,0)
      // . . X . .   y=1: (2,1)
      // . . . X X   y=2: (3,2),(4,2)
      //
      // Correct schedule: S1s from (0,0) down the chain to (4,2), S2s back up.
      final aida = planStitching(
        title: 's-chain-from-top',
        cols: 5,
        rows: 3,
        cells: [(0, 0), (1, 0), (2, 1), (3, 2), (4, 2)],
        startCell: (0, 0),
      );
      expect(
        aida.schedule,
        [
          'S1(0,0)', 'S1(1,0)', 'S1(2,1)', 'S1(3,2)', 'S1(4,2)',
          'S2(4,2)', 'S2(3,2)', 'S2(2,1)', 'S2(1,0)', 'S2(0,0)',
        ],
        reason: 'S-chain from top-left: all S1s along chain, all S2s in reverse — no long back stitch',
      );
      expect(
        aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList(),
        [
          'S(0,0,TL) B(0,0,BR)',
          'B(0,0,BR) S(0,0,TR)',
          'S(1,0,TL) B(1,0,BR)',
          'S(2,1,TL) B(2,1,BR)',
          'S(3,2,TL) B(3,2,BR)',
          'B(3,2,BR) S(3,2,TR)',
          'S(4,2,TL) B(4,2,BR)',
          'B(4,2,BR) S(4,2,TR)',
          'S(4,2,TR) B(4,2,BL)',
          'B(3,2,BR) S(3,2,TR)',
          'S(3,2,TR) B(3,2,BL)',
          'B(2,2,BR) S(2,2,TL)',  // short diagonal hop (3,2)→(2,1)
          'S(2,1,BL) B(2,1,TR)',
          'B(2,0,BR) S(2,0,TL)',  // short diagonal hop (2,1)→(1,0)
          'S(1,0,TR) B(1,0,BL)',
          'B(0,0,BR) S(0,0,TR)',
          'S(0,0,TR) B(0,0,BL)',
        ],
        reason: 'S-chain from top-left: correct stitch sequence with corners',
      );
    });

    test('S-chain (top-left→bottom-right), start bottom-right', () {
      // X X . . .   y=0: (0,0),(1,0)
      // . . X . .   y=1: (2,1)
      // . . . X X   y=2: (3,2),(4,2)
      //
      // Correct schedule: S1s from (4,2) up the chain to (0,0), S2s back down.
      final aida = planStitching(
        title: 's-chain-from-bottom',
        cols: 5,
        rows: 3,
        cells: [(0, 0), (1, 0), (2, 1), (3, 2), (4, 2)],
        startCell: (4, 2),
      );
      expect(
        aida.schedule,
        [
          'S1(4,2)', 'S1(3,2)', 'S1(2,1)', 'S1(1,0)', 'S1(0,0)',
          'S2(0,0)', 'S2(1,0)', 'S2(2,1)', 'S2(3,2)', 'S2(4,2)',
        ],
        reason: 'S-chain from bottom-right: all S1s along chain, all S2s in reverse — no long back stitch',
      );
      expect(
        aida.stitches.map((s) => _serializeStitch(s, aida.squares)).toList(),
        [
          'S(4,2,BR) B(4,2,TL)',
          'B(3,2,TR) S(3,2,BR)',
          'S(3,2,BR) B(3,2,TL)',
          'S(2,1,BR) B(2,1,TL)',
          'S(1,0,BR) B(1,0,TL)',
          'B(0,0,TR) S(0,0,BR)',
          'S(0,0,BR) B(0,0,TL)',
          'B(0,0,TL) S(0,0,BL)',
          'S(0,0,BL) B(0,0,TR)',
          'B(1,0,TL) S(1,0,TR)',
          'S(1,0,TR) B(1,0,BL)',
          'B(1,1,TL) S(1,1,BR)',  // short diagonal hop (1,0)→(2,1)
          'S(2,1,BL) B(2,1,TR)',
          'B(3,1,TL) S(3,1,BR)',  // short diagonal hop (2,1)→(3,2)
          'S(3,2,TR) B(3,2,BL)',
          'B(3,2,BL) S(3,2,BR)',
          'S(4,2,BL) B(4,2,TR)',
        ],
        reason: 'S-chain from bottom-right: correct stitch sequence with corners',
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
