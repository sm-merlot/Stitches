import 'dart:math';

import '../models/stitch_plan.dart';

// FrontOne (\): TopLeft -> BottomRight
// FrontTwo (/): TopRight -> BottomLeft
const _frontCorners = {
  'front1': {
    'fwd': (Corner.topLeft, Corner.bottomRight),
    'rev': (Corner.bottomRight, Corner.topLeft),
  },
  'front2': {
    'fwd': (Corner.topRight, Corner.bottomLeft),
    'rev': (Corner.bottomLeft, Corner.topRight),
  },
};

// Returns the rightmost (then bottommost) cell in a component.
(int, int) _bottomRight(List<(int, int)> cells) => cells.reduce((a, b) {
      if (a.$1 != b.$1) return a.$1 > b.$1 ? a : b;
      return a.$2 > b.$2 ? a : b;
    });


/// State-machine cross-stitch planner (v3).
///
/// Two-pass approach:
///
/// Pass 1 — scheduling: determines the order in which each cell receives its
///   S1 and S2 stitches, producing an ordered list of (cellId, kind) ops.
///   No directions or back stitches are chosen here.
///
///   Current rules (applied in order; scheduling stops when no rule fires):
///     R1. Empty cell → schedule S1.
///         If there is an empty cell directly below, move there.
///
/// Pass 2 — routing: walks the schedule and for each op chooses 'fwd' or
///   'rev' to minimise back-stitch cost (non-diagonal preferred, then
///   shorter), then emits the back stitch and the front stitch.
PlannedAida planStitchingV3({
  required String title,
  required int cols,
  required int rows,
  required List<(int, int)> cells,
  List<(int, int)>? removed,
  (int, int)? startCell,
}) {
  final cellsSet = cells.map((c) => (c.$1, c.$2)).toSet();
  final removedSet = removed?.map((c) => (c.$1, c.$2)).toSet() ?? <(int, int)>{};

  // ---- Build grid ----
  final squares = <PlannedSquare>[];
  final cellToId = <(int, int), int>{};
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if (!removedSet.contains((x, y))) {
        final id = squares.length;
        squares.add(PlannedSquare(id: id, x: x, y: y));
        cellToId[(x, y)] = id;
      }
    }
  }

  final valid = cellsSet.where(cellToId.containsKey).toSet();

  if (valid.isEmpty) {
    return PlannedAida(
      title: title,
      cols: cols,
      rows: rows,
      squares: squares,
      activeSquareIds: {},
      stitches: [],
    );
  }

  final activeSqIds = valid.map((c) => cellToId[c]!).toList()..sort();
  final activeSqIdsSet = activeSqIds.toSet();
  final stitchList = <PlanStitchEntry>[];

  // ---- Node canonicalization ----
  var nodeCounter = 0;
  final nodeMap = <(double, double), int>{};
  for (final sq in squares) {
    for (final corner in Corner.values) {
      nodeMap.putIfAbsent(sq.cornerCoord(corner), () => nodeCounter++);
    }
  }

  final nodeCoords = {for (final e in nodeMap.entries) e.value: e.key};

  final cellNodes = <int, Map<Corner, int>>{};
  for (var sqId = 0; sqId < squares.length; sqId++) {
    cellNodes[sqId] = {
      for (final c in Corner.values) c: nodeMap[squares[sqId].cornerCoord(c)]!,
    };
  }

  final nodeToSqCorners = <int, List<(int, Corner)>>{};
  for (final e in cellNodes.entries) {
    for (final ce in e.value.entries) {
      nodeToSqCorners.putIfAbsent(ce.value, () => []).add((e.key, ce.key));
    }
  }

  // ---- Segment tracking for back-stitch layer ----
  final segmentUsage = <String, int>{};

  List<String> unitSegments(int fromNode, int toNode) {
    final (fx, fy) = nodeCoords[fromNode]!;
    final (tx, ty) = nodeCoords[toNode]!;
    final segs = <String>[];
    if ((fy - ty).abs() < 1e-9) {
      var x = min(fx, tx);
      final xHi = max(fx, tx);
      while (x < xHi - 1e-9) {
        segs.add('h:${(fy * 2).round()}:${(x * 2).round()}');
        x += 1.0;
      }
    } else {
      var y = min(fy, ty);
      final yHi = max(fy, ty);
      while (y < yHi - 1e-9) {
        segs.add('v:${(fx * 2).round()}:${(y * 2).round()}');
        y += 1.0;
      }
    }
    return segs;
  }

  void emitFront(int sqId, String kind, String direction) {
    final corners = _frontCorners[kind]![direction]!;
    stitchList.add(PlanSimpleStitch(
      squareId: sqId,
      fro: corners.$1,
      to: corners.$2,
      type: kind == 'front1' ? StitchType.frontOne : StitchType.frontTwo,
    ));
  }

  void emitBack(int fromNode, int toNode) {
    final segs = unitSegments(fromNode, toNode);
    final count = segs.isEmpty ? 0 : segs.map((s) => segmentUsage[s] ?? 0).reduce(max);
    for (final s in segs) {
      segmentUsage[s] = (segmentUsage[s] ?? 0) + 1;
    }
    final btype = count == 0
        ? StitchType.backOne
        : count == 1
            ? StitchType.backTwo
            : StitchType.backThree;
    final fromReps = nodeToSqCorners[fromNode]!;
    final toReps = nodeToSqCorners[toNode]!;
    final shared = {for (final r in fromReps) r.$1}
        .intersection({for (final r in toReps) r.$1});
    if (shared.isNotEmpty) {
      final sqId = shared.first;
      stitchList.add(PlanSimpleStitch(
        squareId: sqId,
        fro: fromReps.firstWhere((r) => r.$1 == sqId).$2,
        to: toReps.firstWhere((r) => r.$1 == sqId).$2,
        type: btype,
      ));
    } else {
      final (fromSq, froC) = fromReps.first;
      final (toSq, toC) = toReps.first;
      stitchList.add(PlanCrossStitch(
        fro: (squareId: fromSq, corner: froC),
        to: (squareId: toSq, corner: toC),
        type: btype,
      ));
    }
  }

  // ---- Find start: rightmost then bottommost in largest component ----
  final (int, int) startCoord;
  if (startCell != null && valid.contains(startCell)) {
    startCoord = startCell;
  } else {
    final visited = <(int, int)>{};
    final components = <List<(int, int)>>[];
    for (final seed in valid) {
      if (visited.contains(seed)) continue;
      final component = <(int, int)>[];
      final queue = [seed];
      while (queue.isNotEmpty) {
        final curr = queue.removeLast();
        if (!visited.add(curr)) continue;
        component.add(curr);
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nb = (curr.$1 + d.$1, curr.$2 + d.$2);
          if (valid.contains(nb) && !visited.contains(nb)) queue.add(nb);
        }
      }
      components.add(component);
    }
    components.sort((a, b) {
      if (b.length != a.length) return b.length.compareTo(a.length);
      final aBR = _bottomRight(a);
      final bBR = _bottomRight(b);
      if (aBR.$1 != bBR.$1) return bBR.$1.compareTo(aBR.$1);
      return bBR.$2.compareTo(aBR.$2);
    });
    startCoord = _bottomRight(components.first);
  }

  // ---- Pass 1: scheduling ----
  // Produces an ordered list of (cellId, kind) ops — no directions yet.
  // 'kind' is 'S1' or 'S2'.

  final schedule = <({int cellId, String kind})>[];

  // scheduled[id]: 0 = not scheduled, 1 = S1 scheduled, 2 = both scheduled.
  final scheduled = <int, int>{for (final id in activeSqIds) id: 0};

  int? activeSqAt(int x, int y) {
    final id = cellToId[(x, y)];
    return (id != null && activeSqIdsSet.contains(id)) ? id : null;
  }

  // mncSet: shared dedup guard — prevents the same cell being added to MNC twice.
  final mncSet = <int>{};

  // Runs one complete sweep from [startId] using the same down/left/right
  // logic regardless of whether this is Phase 1 or an MNC sub-sweep.
  // Results go into caller-supplied [ops] and [mncs] lists.
  // [ops]  — the (cellId, kind) ops produced by this sweep.
  // [mncs] — MNC detections: (afterIdx, cellId, goUp).
  //           afterIdx is the position in [ops] after which the sub-sweep
  //           for cellId should be spliced into the final schedule.
  void runOneSweep(
    int startId,
    bool goUp,
    List<({int cellId, String kind})> ops,
    List<({int afterIdx, int cellId, bool goUp})> mncs,
  ) {
    var cur = startId;
    bool moved = true;
    while (moved) {
      moved = false;
      final sq = squares[cur];
      final aboveId = activeSqAt(sq.x, sq.y - 1);
      final belowId = activeSqAt(sq.x, sq.y + 1);
      final leftId = activeSqAt(sq.x - 1, sq.y);
      final rightId = activeSqAt(sq.x + 1, sq.y);
      final primaryId = goUp ? aboveId : belowId;
      final secondaryId = goUp ? belowId : aboveId;

      // R1: Empty cell → schedule S1; move primary/left/right.
      if (scheduled[cur] == 0) {
        ops.add((cellId: cur, kind: 'S1'));
        scheduled[cur] = 1;
        if (primaryId != null && scheduled[primaryId] == 0) {
          cur = primaryId; moved = true;
        } else if (leftId != null && scheduled[leftId] == 0) {
          cur = leftId; moved = true;
        } else if (rightId != null && scheduled[rightId] == 0) {
          cur = rightId; moved = true;
        }
      }

      // R2: S1-only cell — check empties, then schedule S2 and record MNC.
      if (!moved && scheduled[cur] == 1) {
        if (primaryId != null && scheduled[primaryId] == 0) {
          cur = primaryId; moved = true;
        } else if (leftId != null && scheduled[leftId] == 0) {
          cur = leftId; moved = true;
        } else if (rightId != null && scheduled[rightId] == 0) {
          cur = rightId; moved = true;
        } else {
          // If all primary/lateral neighbours are done and secondary is empty,
          // defer this cell's S2 and visit secondary first — it can only be
          // reached from here, and doing S2 now would force a long back stitch
          // to get back after visiting secondary's region.
          final allDone = (primaryId == null || scheduled[primaryId] == 2) &&
              (leftId == null || scheduled[leftId] == 2) &&
              (rightId == null || scheduled[rightId] == 2);
          if (allDone && secondaryId != null && scheduled[secondaryId] == 0) {
            cur = secondaryId; moved = true;
          } else {
            ops.add((cellId: cur, kind: 'S2'));
            scheduled[cur] = 2;

            // MNC: opposite-primary neighbour is empty → it may be unreachable by
            // this sweep direction.  Record it so its sub-sweep can be spliced in
            // immediately after this S2 in the final schedule.
            if (secondaryId != null &&
                scheduled[secondaryId] == 0 &&
                !mncSet.contains(secondaryId)) {
              mncSet.add(secondaryId);
              mncs.add((afterIdx: ops.length - 1, cellId: secondaryId, goUp: goUp));
            }

            bool isDone(int? id) => id == null || scheduled[id] == 2;
            if (primaryId != null && scheduled[primaryId] == 1) {
              cur = primaryId; moved = true;
            } else if (leftId != null && scheduled[leftId] == 1) {
              cur = leftId; moved = true;
            } else if (rightId != null && scheduled[rightId] == 1) {
              cur = rightId; moved = true;
            } else if (isDone(primaryId) &&
                isDone(leftId) &&
                isDone(rightId) &&
                secondaryId != null) {
              cur = secondaryId; moved = true;
            }
          }
        }
      }
    }
  }

  // Expand a sweep result by splicing each MNC's sub-sweep into [ops] at its
  // recorded insertion point.  Sub-sweeps are themselves expanded recursively,
  // so MNCs discovered inside sub-sweeps are also inserted at the right place.
  // The shared [scheduled] map means cells already covered by an earlier sweep
  // are skipped (scheduled != 0).
  //
  // MNCs are processed in LIFO order (stack) so that the most-recently
  // detected MNC runs first and schedules its cells before earlier MNCs are
  // evaluated.  Results are then assembled in ascending afterIdx order so
  // each sub-sweep is inserted at the correct position in the final schedule.
  List<({int cellId, String kind})> expandSweep(
    List<({int cellId, String kind})> ops,
    List<({int afterIdx, int cellId, bool goUp})> mncs,
  ) {
    if (mncs.isEmpty) return ops;
    // Run sub-sweeps in LIFO order so the most-recently detected MNC is
    // processed first.  afterIdx is unique per MNC (each fires on a distinct
    // S2 op), so it serves as a stable key for later assembly.
    final subResults = <int, List<({int cellId, String kind})>>{};
    for (final mnc in mncs.reversed) {
      if (scheduled[mnc.cellId] != 0) continue;
      final subOps = <({int cellId, String kind})>[];
      final subMncs = <({int afterIdx, int cellId, bool goUp})>[];
      runOneSweep(mnc.cellId, mnc.goUp, subOps, subMncs);
      subResults[mnc.afterIdx] = expandSweep(subOps, subMncs);
    }
    // Splice sub-sweeps into ops in ascending afterIdx order.
    final result = <({int cellId, String kind})>[];
    int prev = 0;
    for (final mnc in mncs) {
      final sub = subResults[mnc.afterIdx];
      if (sub == null) continue;
      result.addAll(ops.getRange(prev, mnc.afterIdx));
      prev = mnc.afterIdx;
      result.addAll(sub);
    }
    result.addAll(ops.getRange(prev, ops.length));
    return result;
  }

  // ---- Phase 1: downward sweep, with MNC sub-sweeps spliced inline ----
  final p1Ops = <({int cellId, String kind})>[];
  final p1Mncs = <({int afterIdx, int cellId, bool goUp})>[];
  runOneSweep(cellToId[startCoord]!, false, p1Ops, p1Mncs);
  schedule.addAll(expandSweep(p1Ops, p1Mncs));

  // ---- Pass 2: routing ----
  // For each scheduled op, choose fwd/rev to minimise back-stitch cost,
  // then emit the back stitch (if needed) and the front stitch.
  //
  // Direction priority:
  //   1. Needle already at the candidate start → use that direction (no back needed).
  //   2. One approach is diagonal and the other isn't → prefer non-diagonal.
  //   3. Approaches differ in length → prefer shorter.
  //   4. Tie → prefer the end position whose departure to the next cell is
  //      perpendicular to the movement direction (H movement → V departure,
  //      V movement → H departure).
  //   5. Still tied → default to 'fwd'.

  // Local helper: choose direction for a single op.
  String chooseDir(
    int? fromNode,
    int fwdStart,
    int fwdEnd,
    int revStart,
    int revEnd,
    int currentCellId,
    int opIdx,
  ) {
    if (fromNode == null) {
      // Starting cell: choose direction based on where the next cell is.
      if (opIdx + 1 < schedule.length) {
        final nextOp = schedule[opIdx + 1];
        final currentSq = squares[currentCellId];
        final nextSq = squares[nextOp.cellId];
        final moveDx = nextSq.x - currentSq.x;
        final moveDy = nextSq.y - currentSq.y;
        // Next is left or above → S1b (rev); next is right or below → S1a (fwd).
        if (moveDx < 0 || moveDy < 0) return 'rev';
      }
      return 'fwd';
    }
    if (fromNode == fwdStart) return 'fwd';
    if (fromNode == revStart) return 'rev';

    (bool isDiag, double dist) approachCost(int toNode) {
      final (fx, fy) = nodeCoords[fromNode]!;
      final (tx, ty) = nodeCoords[toNode]!;
      final dx = (tx - fx).abs();
      final dy = (ty - fy).abs();
      return (dx > 1e-9 && dy > 1e-9, sqrt(dx * dx + dy * dy));
    }

    final (fwdDiag, fwdDist) = approachCost(fwdStart);
    final (revDiag, revDist) = approachCost(revStart);

    if (fwdDiag != revDiag) return fwdDiag ? 'rev' : 'fwd';
    if ((fwdDist - revDist).abs() > 1e-9) return fwdDist < revDist ? 'fwd' : 'rev';

    // 3.5 Lookahead: if approach distances tie, prefer the end closer to the
    // nearest start of the next op (minimises the following back stitch).
    if (opIdx + 1 < schedule.length) {
      final nextOp = schedule[opIdx + 1];
      final nextCn = cellNodes[nextOp.cellId]!;
      final nextStarts = nextOp.kind == 'S1'
          ? [nextCn[Corner.topLeft]!, nextCn[Corner.bottomRight]!]
          : [nextCn[Corner.topRight]!, nextCn[Corner.bottomLeft]!];

      double minDepDist(int endNode) {
        final (ex, ey) = nodeCoords[endNode]!;
        double best = double.infinity;
        for (final ns in nextStarts) {
          final (nx, ny) = nodeCoords[ns]!;
          final d = sqrt((nx - ex) * (nx - ex) + (ny - ey) * (ny - ey));
          if (d < best) best = d;
        }
        return best;
      }

      final fwdDep = minDepDist(fwdEnd);
      final revDep = minDepDist(revEnd);
      if ((fwdDep - revDep).abs() > 1e-9) return fwdDep < revDep ? 'fwd' : 'rev';
    }

    // Tie: prefer end that allows a perpendicular departure toward the next cell.
    // For the last op, mirror the logic using the incoming direction instead.
    if (opIdx + 1 < schedule.length) {
      final nextOp = schedule[opIdx + 1];
      final currentSq = squares[currentCellId];
      final nextSq = squares[nextOp.cellId];
      final moveDx = nextSq.x - currentSq.x;
      final moveDy = nextSq.y - currentSq.y;

      if (moveDx != 0 || moveDy != 0) {
        final nextCn = cellNodes[nextOp.cellId]!;
        final nextStarts = nextOp.kind == 'S1'
            ? [nextCn[Corner.topLeft]!, nextCn[Corner.bottomRight]!]
            : [nextCn[Corner.topRight]!, nextCn[Corner.bottomLeft]!];

        bool hasPerpDeparture(int endNode) {
          for (final ns in nextStarts) {
            final (ex, ey) = nodeCoords[endNode]!;
            final (nx, ny) = nodeCoords[ns]!;
            final ddx = (nx - ex).abs();
            final ddy = (ny - ey).abs();
            // H movement → want V departure (ddx≈0).
            // V movement → want H departure (ddy≈0).
            // Diagonal movement → want any straight departure (ddx≈0 or ddy≈0).
            if (moveDy == 0 && ddx < 1e-9) return true;
            if (moveDx == 0 && ddy < 1e-9) return true;
            if (moveDx != 0 && moveDy != 0 && (ddx < 1e-9 || ddy < 1e-9)) return true;
          }
          return false;
        }

        final fwdPerp = hasPerpDeparture(fwdEnd);
        final revPerp = hasPerpDeparture(revEnd);
        if (fwdPerp != revPerp) return fwdPerp ? 'fwd' : 'rev';
      }
    } else if (opIdx > 0) {
      // Last op: use incoming direction (previous cell → current cell) to prefer
      // the start node reachable with a perpendicular approach from the needle.
      final prevOp = schedule[opIdx - 1];
      final currentSq = squares[currentCellId];
      final prevSq = squares[prevOp.cellId];
      final moveDx = currentSq.x - prevSq.x;
      final moveDy = currentSq.y - prevSq.y;

      if (moveDx != 0 || moveDy != 0) {
        bool hasPerpApproach(int startNode) {
          final (fx, fy) = nodeCoords[fromNode]!;
          final (sx, sy) = nodeCoords[startNode]!;
          final ddx = (sx - fx).abs();
          final ddy = (sy - fy).abs();
          // H move → want V approach (ddx≈0). V move → want H approach (ddy≈0).
          // Diagonal → want any straight approach.
          if (moveDy == 0 && ddx < 1e-9) return true;
          if (moveDx == 0 && ddy < 1e-9) return true;
          if (moveDx != 0 && moveDy != 0 && (ddx < 1e-9 || ddy < 1e-9)) return true;
          return false;
        }

        final fwdPerp = hasPerpApproach(fwdStart);
        final revPerp = hasPerpApproach(revStart);
        if (fwdPerp != revPerp) return fwdPerp ? 'fwd' : 'rev';
      }
    }

    return 'fwd';
  }

  int? needleNode;

  for (var opIdx = 0; opIdx < schedule.length; opIdx++) {
    final op = schedule[opIdx];
    final cn = cellNodes[op.cellId]!;

    final int fwdStart, fwdEnd, revStart, revEnd;
    if (op.kind == 'S1') {
      fwdStart = cn[Corner.topLeft]!;
      fwdEnd = cn[Corner.bottomRight]!;
      revStart = cn[Corner.bottomRight]!;
      revEnd = cn[Corner.topLeft]!;
    } else {
      fwdStart = cn[Corner.topRight]!;
      fwdEnd = cn[Corner.bottomLeft]!;
      revStart = cn[Corner.bottomLeft]!;
      revEnd = cn[Corner.topRight]!;
    }

    final dir = chooseDir(
      needleNode, fwdStart, fwdEnd, revStart, revEnd, op.cellId, opIdx,
    );

    final startN = dir == 'fwd' ? fwdStart : revStart;
    final endN = dir == 'fwd' ? fwdEnd : revEnd;

    if (needleNode != null && needleNode != startN) emitBack(needleNode!, startN);
    emitFront(op.cellId, op.kind == 'S1' ? 'front1' : 'front2', dir);
    needleNode = endN;
  }

  return PlannedAida(
    title: title,
    cols: cols,
    rows: rows,
    squares: squares,
    activeSquareIds: activeSqIdsSet,
    schedule: schedule
        .map((op) => '${op.kind}(${squares[op.cellId].x},${squares[op.cellId].y})')
        .toList(),
    stitches: stitchList,
  );
}
