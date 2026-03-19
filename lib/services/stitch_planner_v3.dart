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

  var currentSqId = cellToId[startCoord]!;

  bool moved = true;
  while (moved) {
    moved = false;
    final sq = squares[currentSqId];
    final s = scheduled[currentSqId]!;

    // R1: Empty cell → schedule S1; move below if empty, else left if empty,
    //     else right if empty.
    if (scheduled[currentSqId] == 0) {
      schedule.add((cellId: currentSqId, kind: 'S1'));
      scheduled[currentSqId] = 1;

      final belowId = activeSqAt(sq.x, sq.y + 1);
      final leftId = activeSqAt(sq.x - 1, sq.y);
      final rightId = activeSqAt(sq.x + 1, sq.y);
      if (belowId != null && scheduled[belowId] == 0) {
        currentSqId = belowId;
        moved = true;
      } else if (leftId != null && scheduled[leftId] == 0) {
        currentSqId = leftId;
        moved = true;
      } else if (rightId != null && scheduled[rightId] == 0) {
        currentSqId = rightId;
        moved = true;
      }
    }

    // R2: S1-only cell (and didn't just move via R1).
    //   First check if any adjacent cell (below/left/right) is still empty —
    //   if so, move there immediately (S2 waits until we return).
    //   Otherwise schedule S2, then move to an S1 neighbour or up.
    if (!moved && scheduled[currentSqId] == 1) {
      final belowId = activeSqAt(sq.x, sq.y + 1);
      final leftId = activeSqAt(sq.x - 1, sq.y);
      final rightId = activeSqAt(sq.x + 1, sq.y);

      if (belowId != null && scheduled[belowId] == 0) {
        currentSqId = belowId;
        moved = true;
      } else if (leftId != null && scheduled[leftId] == 0) {
        currentSqId = leftId;
        moved = true;
      } else if (rightId != null && scheduled[rightId] == 0) {
        currentSqId = rightId;
        moved = true;
      } else {
        // No empty neighbours — schedule S2 and move to an S1 neighbour or up.
        schedule.add((cellId: currentSqId, kind: 'S2'));
        scheduled[currentSqId] = 2;

        final aboveId = activeSqAt(sq.x, sq.y - 1);
        bool isDoneOrAbsent(int? id) => id == null || scheduled[id] == 2;

        if (belowId != null && scheduled[belowId] == 1) {
          currentSqId = belowId;
          moved = true;
        } else if (leftId != null && scheduled[leftId] == 1) {
          currentSqId = leftId;
          moved = true;
        } else if (rightId != null && scheduled[rightId] == 1) {
          currentSqId = rightId;
          moved = true;
        } else if (isDoneOrAbsent(belowId) &&
            isDoneOrAbsent(leftId) &&
            isDoneOrAbsent(rightId) &&
            aboveId != null) {
          currentSqId = aboveId;
          moved = true;
        }
      }
    }
  }

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

    // Tie: prefer end that allows a perpendicular departure toward the next cell.
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
    stitches: stitchList,
  );
}
