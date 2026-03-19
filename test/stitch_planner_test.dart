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
      // Pass 1 schedule: (2,2) → left → (1,2) → left → (0,2). Stop (no left).
      // Pass 2 routing:
      //   (2,2) S1 fwd:  needle at BR(2,2).
      //   (1,2) S1: fwd=TL(1,2) is diagonal from BR(2,2); rev=BR(1,2) is horizontal → rev.
      //             Back H via cell (2,2): BR→BL. Then S1 rev: BR→TL.
      //   (0,2) S1: fwd=TL(0,2) horizontal from TL(1,2); rev=BR(0,2) vertical → tie → fwd.
      //             Back H via cell (0,1): BR→BL. Then S1 fwd: TL→BR.
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
          // S1 pass (right col → bottom row sweep left)
          'S(2,2,BR) B(2,2,TL)', // S1b (2,2): next is left; needle at TL(2,2)=TR(1,2)
          'B(1,2,TR) S(1,2,BR)', // back V → BR(1,2); tiebreak rev
          'S(1,2,BR) B(1,2,TL)', // S1b (1,2); needle at TL(1,2)
          'B(0,1,BR) S(0,1,BL)', // back H → TL(0,2)
          'S(0,2,TL) B(0,2,BR)', // S1a (0,2); needle at BR(0,2)
          // S2 pass (sweep right)
          'B(0,2,BR) S(0,2,BL)', // back H → BL(0,2); tiebreak rev
          'S(0,2,BL) B(0,2,TR)', // S2b (0,2); needle at TR(0,2)
          'B(0,2,TR) S(0,2,BR)', // back V → BR(0,2)=BL(1,2); tiebreak rev (via cell (0,2))
          'S(1,2,BL) B(1,2,TR)', // S2b (1,2); needle at TR(1,2)
          'B(1,2,TR) S(1,2,BR)', // back V → BR(1,2)=BL(2,2); tiebreak rev (via cell (1,2))
          'S(2,2,BL) B(2,2,TR)', // S2b (2,2): next is (2,1) up → H dep preferred; needle at TR(2,2)
          // S1 pass mid-row (move up then sweep left)
          'S(2,1,BR) B(2,1,TL)', // S1b (2,1): needle==revStart, no back
          'B(1,1,TR) S(1,1,BR)', // back V; tiebreak rev
          'S(1,1,BR) B(1,1,TL)', // S1b (1,1); needle at TL(1,1)
          'B(0,0,BR) S(0,0,BL)', // back H → TL(0,1) (via cell (0,0))
          'S(0,1,TL) B(0,1,BR)', // S1a (0,1); needle at BR(0,1)
          // S2 pass mid-row (sweep right)
          'B(0,1,BR) S(0,1,BL)', // back H; tiebreak rev
          'S(0,1,BL) B(0,1,TR)', // S2b (0,1); needle at TR(0,1)
          'B(0,1,TR) S(0,1,BR)', // back V; tiebreak rev (via cell (0,1))
          'S(1,1,BL) B(1,1,TR)', // S2b (1,1); needle at TR(1,1)
          'B(1,1,TR) S(1,1,BR)', // back V; tiebreak rev (via cell (1,1))
          'S(2,1,BL) B(2,1,TR)', // S2b (2,1): next is (2,0) up → H dep preferred
          // S1 pass top row (move up then sweep left)
          'S(2,0,BR) B(2,0,TL)', // S1b (2,0): needle==revStart, no back
          'B(1,0,TR) S(1,0,BR)', // back V; tiebreak rev
          'S(1,0,BR) B(1,0,TL)', // S1b (1,0); needle at TL(1,0)
          'B(0,0,TR) S(0,0,TL)', // back H → TL(0,0)
          'S(0,0,TL) B(0,0,BR)', // S1a (0,0): no next S1; default fwd
          // S2 pass top row (sweep right)
          'B(0,0,BR) S(0,0,BL)', // back H; tiebreak rev
          'S(0,0,BL) B(0,0,TR)', // S2b (0,0); needle at TR(0,0)
          'B(0,0,TR) S(0,0,BR)', // back V; tiebreak rev (via cell (0,0))
          'S(1,0,BL) B(1,0,TR)', // S2b (1,0); needle at TR(1,0)
          'B(1,0,TR) S(1,0,BR)', // back V → BL(2,0); last-op perp approach → rev
          'S(2,0,BL) B(2,0,TR)', // S2b (2,0) rev
        ],
        startCell: (2, 2),
      );
    });

    test('3x3 full grid, start mid-right (2,1)', () {
      // XXX     Start: (2,1) — middle of right column.
      // XXX
      // XXX
      //
      // Pass 1 schedule: (2,1) → below → (2,2) → left → (1,2) → left → (0,2).
      //
      // Tiebreaker fires at (2,2): approach H=V=1. Next is (1,2) (H move left).
      //   revEnd=TL(2,2) can reach BR(1,2) vertically (dx=0) → rev wins.
      // Tiebreaker fires at (1,2): same pattern → rev wins.
      // (0,2) is last op → default fwd.
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
          // S1 pass: down right col then sweep bottom row left
          'S(2,1,TL) B(2,1,BR)', // S1a (2,1): next below
          'B(2,2,TR) S(2,2,BR)', // back V; tiebreak rev
          'S(2,2,BR) B(2,2,TL)', // S1b (2,2)
          'B(1,2,TR) S(1,2,BR)', // back V; tiebreak rev
          'S(1,2,BR) B(1,2,TL)', // S1b (1,2)
          'B(0,1,BR) S(0,1,BL)', // back H → TL(0,2)
          'S(0,2,TL) B(0,2,BR)', // S1a (0,2)
          // S2 bottom row: sweep right (0,2)→(1,2)
          'B(0,2,BR) S(0,2,BL)', // back H; tiebreak rev
          'S(0,2,BL) B(0,2,TR)', // S2b (0,2)
          'B(0,2,TR) S(0,2,BR)', // back V (via cell (0,2)); tiebreak rev
          'S(1,2,BL) B(1,2,TR)', // S2b (1,2); needle at TR(1,2)
          // (2,1) has s=1 and (2,2) s=0 adj? No — check: (2,1) s=1, left=(1,1) s=0 → move left
          // but first: S2(2,2) needs to happen; (1,2) moves right to (2,2) s=1, (2,2) left=(1,2) s=2 right=null, down=null → S2(2,2)
          'B(2,1,BL) S(2,1,BR)', // back to revStart=BR(2,2) (via cell (2,1) BL); tiebreak rev (next up → H dep)
          'S(2,2,TR) B(2,2,BL)', // S2b (2,2): next (2,1) has left (1,1) empty → move left first
          // Move up to (2,1) s=1; left=(1,1) s=0 → move left, then S1 mid row
          'B(1,2,BR) S(1,2,TR)', // back to TL(1,1) via (1,2)
          'S(1,1,BR) B(1,1,TL)', // S1b (1,1): needle==revStart
          'B(0,0,BR) S(0,0,BL)', // back H → TL(0,1)
          'S(0,1,TL) B(0,1,BR)', // S1a (0,1)
          // S2 mid row: sweep right
          'B(0,1,BR) S(0,1,BL)', // back H; tiebreak rev
          'S(0,1,BL) B(0,1,TR)', // S2b (0,1)
          'B(0,1,TR) S(0,1,BR)', // back V (via cell (0,1)); tiebreak rev
          'S(1,1,BL) B(1,1,TR)', // S2b (1,1)
          'B(1,1,TR) S(1,1,BR)', // back V (via cell (1,1)); tiebreak rev
          'S(2,1,BL) B(2,1,TR)', // S2b (2,1): next (2,0) up → H dep
          // Move up to (2,0) s=0 → R1 fires; sweep top row left
          'S(2,0,BR) B(2,0,TL)', // S1b (2,0): needle==revStart; next left
          'B(1,0,TR) S(1,0,BR)', // back V; tiebreak rev
          'S(1,0,BR) B(1,0,TL)', // S1b (1,0)
          'B(0,0,TR) S(0,0,TL)', // back H → TL(0,0)
          'S(0,0,TL) B(0,0,BR)', // S1a (0,0): no next S1
          // S2 top row: sweep right
          'B(0,0,BR) S(0,0,BL)', // back H; tiebreak rev
          'S(0,0,BL) B(0,0,TR)', // S2b (0,0)
          'B(0,0,TR) S(0,0,BR)', // back V (via cell (0,0)); tiebreak rev
          'S(1,0,BL) B(1,0,TR)', // S2b (1,0)
          'B(1,0,TR) S(1,0,BR)', // back V → BL(2,0); last-op perp approach → rev
          'S(2,0,BL) B(2,0,TR)', // S2b (2,0) rev
        ],
        startCell: (2, 1),
      );
    });

    test('3x3 full grid, start top-right (2,0)', () {
      // XXX     Start: (2,0) — top of right column.
      // XXX
      // XXX
      //
      // Pass 1 schedule: (2,0)→(2,1)→(2,2)→(1,2)→(0,2).
      //
      // (2,1): tie, next=(2,2) is V move down → H departure preferred → fwd wins.
      // (2,2): tie, next=(1,2) is H move left → V departure preferred → rev wins.
      // (1,2): tie, next=(0,2) is H move left → V departure preferred → rev wins.
      // (0,2): last op → default fwd.
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
          // S1 pass: down right col then sweep bottom row left
          'S(2,0,TL) B(2,0,BR)', // S1a (2,0): next below
          'B(2,0,BR) S(2,0,BL)', // back H → TL(2,1); next V → fwd
          'S(2,1,TL) B(2,1,BR)', // S1a (2,1)
          'B(2,2,TR) S(2,2,BR)', // back V; tiebreak rev
          'S(2,2,BR) B(2,2,TL)', // S1b (2,2)
          'B(1,2,TR) S(1,2,BR)', // back V; tiebreak rev
          'S(1,2,BR) B(1,2,TL)', // S1b (1,2)
          'B(0,1,BR) S(0,1,BL)', // back H → TL(0,2)
          'S(0,2,TL) B(0,2,BR)', // S1a (0,2)
          // S2 bottom row: sweep right (0,2)→(1,2)
          'B(0,2,BR) S(0,2,BL)', // back H; tiebreak rev
          'S(0,2,BL) B(0,2,TR)', // S2b (0,2)
          'B(0,2,TR) S(0,2,BR)', // back V (via cell (0,2)); tiebreak rev
          'S(1,2,BL) B(1,2,TR)', // S2b (1,2); needle at TR(1,2)
          // Move right to (2,2) s=1; (2,1) has s=1, left=(1,1) s=0 → checks adj before S2
          'B(2,1,BL) S(2,1,BR)', // back to revStart=BR(2,2) via (2,1); tiebreak rev
          'S(2,2,TR) B(2,2,BL)', // S2b (2,2)
          // Move up to (2,1) s=1; left=(1,1) s=0 → move left first
          'B(1,2,BR) S(1,2,TR)', // back to TL(1,1) via (1,2)
          'S(1,1,BR) B(1,1,TL)', // S1b (1,1): needle==revStart
          'B(0,0,BR) S(0,0,BL)', // back H → TL(0,1)
          'S(0,1,TL) B(0,1,BR)', // S1a (0,1)
          // S2 mid row: sweep right
          'B(0,1,BR) S(0,1,BL)', // back H; tiebreak rev
          'S(0,1,BL) B(0,1,TR)', // S2b (0,1)
          'B(0,1,TR) S(0,1,BR)', // back V (via cell (0,1)); tiebreak rev
          'S(1,1,BL) B(1,1,TR)', // S2b (1,1)
          // Move right to (2,1) s=1; (2,0) has s=1 and left=(1,0) s=0 → move left first
          'B(2,0,BL) S(2,0,BR)', // back to revStart=BR(2,1) via (2,0); tiebreak rev
          'S(2,1,TR) B(2,1,BL)', // S2b (2,1)
          // Move up to (2,0) s=1; left=(1,0) s=0 → move left first
          'B(1,1,BR) S(1,1,TR)', // back to TL(1,0) via (1,1)
          'S(1,0,BR) B(1,0,TL)', // S1b (1,0): needle==revStart
          'B(0,0,TR) S(0,0,TL)', // back H → TL(0,0)
          'S(0,0,TL) B(0,0,BR)', // S1a (0,0): no next S1
          // S2 top row: sweep right
          'B(0,0,BR) S(0,0,BL)', // back H; tiebreak rev
          'S(0,0,BL) B(0,0,TR)', // S2b (0,0)
          'B(0,0,TR) S(0,0,BR)', // back V (via cell (0,0)); tiebreak rev
          'S(1,0,BL) B(1,0,TR)', // S2b (1,0)
          'B(1,0,TR) S(1,0,BR)', // back V → BL(2,0); last-op perp approach → rev
          'S(2,0,BL) B(2,0,TR)', // S2b (2,0) rev
        ],
        startCell: (2, 0),
      );
    });
    test('3x3 full grid, start top-left (0,0)', () {
      // XXX     Start: (0,0) — top-left corner.
      // XXX     Pass 1: down left col → right along bottom → S2 right → up →
      // XXX             drain empties right → S2 right → up → drain right → S2.
      //
      // Key: S2(0,2)→S1(1,1) movement is diagonal; fix ensures rev is chosen
      //      for S2(0,2) so the back to (1,1) is straight (vertical), not diagonal.
      _expectV3Sequence(
        '3x3 top-left start',
        [
          (0, 0), (1, 0), (2, 0),
          (0, 1), (1, 1), (2, 1),
          (0, 2), (1, 2), (2, 2),
        ],
        3,
        3,
        [
          // S1 pass: down left col then sweep bottom row right
          'S(0,0,TL) B(0,0,BR)', // S1a (0,0): next below
          'B(0,0,BR) S(0,0,BL)', // back H → TL(0,1); next V → fwd
          'S(0,1,TL) B(0,1,BR)', // S1a (0,1)
          'B(0,1,BR) S(0,1,BL)', // back H → TL(0,2); next V → fwd
          'S(0,2,TL) B(0,2,BR)', // S1a (0,2)
          'B(0,2,BR) S(0,2,TR)', // back V → TL(1,2); next H right → fwd
          'S(1,2,TL) B(1,2,BR)', // S1a (1,2)
          'B(1,2,BR) S(1,2,TR)', // back V → TL(2,2); next H right → fwd
          'S(2,2,TL) B(2,2,BR)', // S1a (2,2)
          // S2 bottom row: sweep left (2,2)→(1,2)→(0,2)
          'B(2,2,BR) S(2,2,TR)', // back V; next H left → fwd
          'S(2,2,TR) B(2,2,BL)', // S2a (2,2)
          'B(1,2,BR) S(1,2,TR)', // back V; next H left → fwd
          'S(1,2,TR) B(1,2,BL)', // S2a (1,2)
          'B(0,2,BR) S(0,2,BL)', // back H; diagonal move next → rev wins (straight dep)
          'S(0,2,BL) B(0,2,TR)', // S2b (0,2): rev → needle at TR(0,2)=(1,2)
          // TR(0,2)=(1,2) → TL(1,1)=(1,1): vertical (dx=0) — the fixed stitch
          'B(0,1,BR) S(0,1,TR)', // back V (via (0,1)): (1,2)→(1,1); non-diagonal
          'S(1,1,TL) B(1,1,BR)', // S1a (1,1)
          'B(1,1,BR) S(1,1,TR)', // back V; next H right → fwd
          'S(2,1,TL) B(2,1,BR)', // S1a (2,1)
          // S2 mid row: sweep left (2,1)→(1,1)
          'B(2,1,BR) S(2,1,TR)', // back V; next H left → fwd
          'S(2,1,TR) B(2,1,BL)', // S2a (2,1)
          'B(1,1,BR) S(1,1,TR)', // back V; diagonal move next → rev wins
          'S(1,1,TR) B(1,1,BL)', // S2b (1,1): rev → needle at TR(1,1)
          'B(0,1,BR) S(0,1,BL)', // back H → TL(0,1)
          'S(0,1,BL) B(0,1,TR)', // S2b (0,1)
          // Move up to (0,0) s=1; right=(1,0) s=0 → move right first
          'B(0,0,BR) S(0,0,TR)', // back V (via (0,0)): TR(0,1)→TR(0,0)
          'S(1,0,TL) B(1,0,BR)', // S1a (1,0)
          'B(1,0,BR) S(1,0,TR)', // back V; next H right → fwd
          'S(2,0,TL) B(2,0,BR)', // S1a (2,0)
          // S2 top row: sweep left (2,0)→(1,0)→(0,0)
          'B(2,0,BR) S(2,0,TR)', // back V; next H left → fwd
          'S(2,0,TR) B(2,0,BL)', // S2a (2,0)
          'B(1,0,BR) S(1,0,TR)', // back V; diagonal move next → rev wins
          'S(1,0,TR) B(1,0,BL)', // S2b (1,0): rev → needle at TR(1,0)
          'B(0,0,BR) S(0,0,TR)', // back H → TR(0,0); last op default fwd
          'S(0,0,TR) B(0,0,BL)', // S2a (0,0)
        ],
        startCell: (0, 0),
      );
    });

    test('3x3 full grid, start top-mid (1,0)', () {
      // XXX     Start: (1,0) — top-middle.
      // XXX     Pass 1: down mid col → left col → right to (2,2) → up mid col.
      // XXX     Key: S2(0,2) ends at TR(0,2); step-3.5 lookahead picks rev so that
      //              the back stitch to S1(2,2) is 1 unit instead of 3.
      _expectV3Sequence(
        '3x3 top-mid start',
        [
          (0, 0), (1, 0), (2, 0),
          (0, 1), (1, 1), (2, 1),
          (0, 2), (1, 2), (2, 2),
        ],
        3,
        3,
        [
          // S1 pass: down mid col
          'S(1,0,TL) B(1,0,BR)', // S1a (1,0): next below → fwd
          'B(1,0,BR) S(1,0,BL)', // back H to TL(1,1)
          'S(1,1,TL) B(1,1,BR)', // S1a (1,1): needle already at TL
          'B(1,2,TR) S(1,2,BR)', // back V; perp dep tiebreak → rev
          'S(1,2,BR) B(1,2,TL)', // S1b (1,2) rev
          // left col
          'B(0,1,BR) S(0,1,BL)', // back H to TL(0,2)
          'S(0,2,TL) B(0,2,BR)', // S1a (0,2) fwd
          // S2(0,2): step-3.5 lookahead: rev end is 1 unit from TL(2,2), fwd end is 2.24 → rev
          'B(0,2,BR) S(0,2,BL)', // back H to BL(0,2); lookahead picks rev
          'S(0,2,BL) B(0,2,TR)', // S2b (0,2) rev; needle at TR(0,2)=TL(1,2)
          // jump to S1(2,2): non-diag approach (H=1) wins over diag (sqrt5)
          'B(1,1,BL) S(1,1,BR)', // back H to TL(2,2)=BR(1,1)
          'S(2,2,TL) B(2,2,BR)', // S1a (2,2) fwd
          // S2(2,2): next op is S2(1,2) to left; perp dep → fwd
          'B(2,2,BR) S(2,2,TR)', // back V up; perp dep → fwd
          'S(2,2,TR) B(2,2,BL)', // S2a (2,2) fwd
          // S2(1,2): next op is S1(0,1) diag; perp dep → fwd
          'B(1,2,BR) S(1,2,TR)', // back V up; perp dep → fwd
          'S(1,2,TR) B(1,2,BL)', // S2a (1,2) fwd
          // S1(0,1): non-diag rev approach (V=1) wins over diag fwd (sqrt5)
          'B(0,2,BR) S(0,2,TR)', // back V up to BR(0,1)=revStart
          'S(0,1,BR) B(0,1,TL)', // S1b (0,1) rev; needle==revStart
          // S2(0,1): step-3.5 lookahead: rev end closer to TL(2,1) → rev
          'B(0,1,TL) S(0,1,BL)', // back V; lookahead picks rev
          'S(0,1,BL) B(0,1,TR)', // S2b (0,1) rev; needle at TR(0,1)=TL(1,1)
          // S1(2,1): non-diag fwd approach (H=1) wins over diag rev (sqrt5)
          'B(1,0,BL) S(1,0,BR)', // back H to TL(2,1)=BR(1,0)
          'S(2,1,TL) B(2,1,BR)', // S1a (2,1) fwd
          // S2(2,1): next op S2(1,1) to left; perp dep → fwd
          'B(2,1,BR) S(2,1,TR)', // back V up; perp dep → fwd
          'S(2,1,TR) B(2,1,BL)', // S2a (2,1) fwd
          // S2(1,1): next op S1(0,0) diag; both perp → default fwd
          'B(1,1,BR) S(1,1,TR)', // back V up; default fwd
          'S(1,1,TR) B(1,1,BL)', // S2a (1,1) fwd
          // S1(0,0): non-diag rev approach (V=1) wins over diag fwd (sqrt5)
          'B(0,1,BR) S(0,1,TR)', // back V up to BR(0,0)=revStart
          'S(0,0,BR) B(0,0,TL)', // S1b (0,0) rev
          // S2(0,0): step-3.5 lookahead: rev end closer to TL(2,0) → rev
          'B(0,0,TL) S(0,0,BL)', // back V; lookahead picks rev
          'S(0,0,BL) B(0,0,TR)', // S2b (0,0) rev; needle at TR(0,0)=TL(1,0)
          // S1(2,0): non-diag fwd approach (H=1) wins over diag rev (sqrt5)
          'B(1,0,TL) S(1,0,TR)', // back H to TL(2,0)=TR(1,0)
          'S(2,0,TL) B(2,0,BR)', // S1a (2,0) fwd
          // S2(2,0): next op S2(1,0) to left; perp dep → fwd
          'B(2,0,BR) S(2,0,TR)', // back V up; perp dep → fwd
          'S(2,0,TR) B(2,0,BL)', // S2a (2,0) fwd
          // S2(1,0): last op; incoming direction right (2,0→1,0 is left); perp approach → fwd
          'B(1,0,BR) S(1,0,TR)', // back V up; last-op perp approach → fwd
          'S(1,0,TR) B(1,0,BL)', // S2a (1,0) fwd
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
      _expectV3Sequence(
        '4x1 row tiebreaker',
        [(0, 0), (1, 0), (2, 0), (3, 0)],
        4,
        1,
        [
          // S1 pass (sweep left)
          'S(3,0,BR) B(3,0,TL)', // S1b (3,0): next left → S1b; needle at TL(3,0)=TR(2,0)
          'B(2,0,TR) S(2,0,BR)', // back V; tiebreak rev
          'S(2,0,BR) B(2,0,TL)', // S1b (2,0); needle at TL(2,0)=TR(1,0)
          'B(1,0,TR) S(1,0,BR)', // back V; tiebreak rev
          'S(1,0,BR) B(1,0,TL)', // S1b (1,0); needle at TL(1,0)=TR(0,0)
          'B(0,0,TR) S(0,0,TL)', // back H → TL(0,0)
          'S(0,0,TL) B(0,0,BR)', // S1a (0,0): no next S1, default fwd; needle at BR(0,0)
          // S2 pass (sweep right)
          'B(0,0,BR) S(0,0,BL)', // back H; tiebreak rev
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
