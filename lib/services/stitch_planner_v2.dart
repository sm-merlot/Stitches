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

// Returns the leftmost (then topmost) cell in a component.
(int, int) _topLeft(List<(int, int)> cells) => cells.reduce((a, b) {
      if (a.$1 != b.$1) return a.$1 < b.$1 ? a : b;
      return a.$2 < b.$2 ? a : b;
    });

/// State-machine cross-stitch planner (v2).
///
/// Each cell is a graph node progressing through three phases:
///   0 = empty  →  do S1 (TL→BR)
///   1 = S1-done →  find empty neighbour (below > left > right) and do S1
///                  there; if none, mark diagonal empties as "possibly needed"
///                  and do S2 on this cell.
///   2 = complete → move left to do S2 on next cell; special-case for row/
///                  diagonal transitions per the rules below.
///
/// After the main sweep stalls:
///   1. Stitch any "possibly needed" cells that remain empty.
///   2. BFS from the needle position to find and stitch remaining cells.
PlannedAida planStitchingV2({
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

  // ---- Cell phase: 0=empty, 1=S1-done, 2=complete ----
  final phase = <int, int>{for (final id in activeSqIds) id: 0};
  final possiblyNeeded = <int>{};
  int? needleNode; // current needle position as graph node id

  int? activeSqAt(int x, int y) {
    final id = cellToId[(x, y)];
    return (id != null && activeSqIdsSet.contains(id)) ? id : null;
  }

  // S1: TL → BR  (\)
  void doS1(int sqId) {
    final cn = cellNodes[sqId]!;
    final startN = cn[Corner.topLeft]!;
    final endN = cn[Corner.bottomRight]!;
    if (needleNode != null && needleNode != startN) emitBack(needleNode!, startN);
    emitFront(sqId, 'front1', 'fwd');
    needleNode = endN;
    phase[sqId] = 1;
  }

  // S2 forward:  TR → BL  (/)
  void doS2(int sqId) {
    final cn = cellNodes[sqId]!;
    final startN = cn[Corner.topRight]!;
    final endN = cn[Corner.bottomLeft]!;
    if (needleNode != null && needleNode != startN) emitBack(needleNode!, startN);
    emitFront(sqId, 'front2', 'fwd');
    needleNode = endN;
    phase[sqId] = 2;
  }

  // S2 reversed: BL → TR  (/)
  // Used when the next stitch is S1 on the upper-right diagonal (sq.x+1, sq.y-1).
  // TR of this cell == BL of that diagonal cell, so the needle lands exactly
  // at the entry point for the next S1 with no diagonal backstitch needed.
  void doS2Rev(int sqId) {
    final cn = cellNodes[sqId]!;
    final startN = cn[Corner.bottomLeft]!;
    final endN = cn[Corner.topRight]!;
    if (needleNode != null && needleNode != startN) emitBack(needleNode!, startN);
    emitFront(sqId, 'front2', 'rev');
    needleNode = endN;
    phase[sqId] = 2;
  }

  // Choose between doS2 and doS2Rev for a given cell.
  //
  // Priority 1 — left neighbour still needs S2 (phase==1): do S2 forward so
  //   the needle lands at BL (= BR of the left cell), enabling a clean
  //   horizontal backstitch into it rather than a diagonal jump.
  //
  // Priority 2 — upper-right diagonal still needs S1: do S2 reversed so
  //   the needle lands at TR (= BL of that diagonal cell), enabling a clean
  //   vertical backstitch to its TL for the next S1.
  //
  // Otherwise: do S2 forward.
  void doS2Smart(int sqId) {
    final sq = squares[sqId];
    final leftId = activeSqAt(sq.x - 1, sq.y);
    if (leftId != null && phase[leftId] == 1) {
      doS2(sqId);
      return;
    }
    final upRightId = activeSqAt(sq.x + 1, sq.y - 1);
    if (upRightId != null && phase[upRightId] == 0) {
      doS2Rev(sqId);
    } else {
      doS2(sqId);
    }
  }

  // ---- Find start ----
  final maxX = valid.map((c) => c.$1).reduce(max);

  final (int, int) startCoord;
  if (startCell != null && valid.contains(startCell)) {
    startCoord = startCell;
  } else {
    // BFS to find all connected components (H/V adjacency).
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

    // Pick the largest component; break ties by leftmost then topmost cell.
    components.sort((a, b) {
      if (b.length != a.length) return b.length.compareTo(a.length);
      final aMin = _topLeft(a);
      final bMin = _topLeft(b);
      if (aMin.$1 != bMin.$1) return aMin.$1.compareTo(bMin.$1);
      return aMin.$2.compareTo(bMin.$2);
    });

    // Within the largest component, start at the leftmost then topmost cell.
    startCoord = _topLeft(components.first);
  }
  var currentSqId = cellToId[startCoord]!;

  doS1(currentSqId);

  // ---- Main state-machine sweep ----
  // Returns true if at least one stitch or movement was made.
  bool sweep() {
    var progressed = false;
    var changed = true;
    while (changed) {
      changed = false;
      final sq = squares[currentSqId];
      final p = phase[currentSqId]!;

      if (p == 0) {
        doS1(currentSqId);
        changed = true;
        progressed = true;
      } else if (p == 1) {
        // Mark empty diagonal neighbours as "possibly needed".
        for (final (dx, dy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
          final diagId = activeSqAt(sq.x + dx, sq.y + dy);
          if (diagId != null && phase[diagId] == 0) possiblyNeeded.add(diagId);
        }

        final belowId = activeSqAt(sq.x, sq.y + 1);
        final leftId = activeSqAt(sq.x - 1, sq.y);
        final rightId = activeSqAt(sq.x + 1, sq.y);

        // Priority: below > left > right for continuing S1 sweep.
        if (belowId != null && phase[belowId] == 0) {
          currentSqId = belowId;
          doS1(currentSqId);
          changed = true;
          progressed = true;
        } else if (leftId != null && phase[leftId] == 0) {
          currentSqId = leftId;
          doS1(currentSqId);
          changed = true;
          progressed = true;
        } else if (rightId != null && phase[rightId] == 0) {
          currentSqId = rightId;
          doS1(currentSqId);
          changed = true;
          progressed = true;
        } else {
          // No empty adjacent cell: complete the cross on this cell.
          doS2Smart(currentSqId);
          changed = true;
          progressed = true;
        }
      } else {
        // p == 2: cross complete — decide where to move next.
        final rightId = activeSqAt(sq.x + 1, sq.y);
        final leftId = activeSqAt(sq.x - 1, sq.y);
        final aboveId = activeSqAt(sq.x, sq.y - 1);
        final aboveRightId = activeSqAt(sq.x + 1, sq.y - 1);

        final rightIsS1 = rightId != null && phase[rightId] == 1;

        // "Last stitch in row": no unfinished cells remain to the right.
        var lastInRow = true;
        for (var x = sq.x + 1; x <= maxX; x++) {
          final id = activeSqAt(x, sq.y);
          if (id != null && phase[id]! < 2) {
            lastInRow = false;
            break;
          }
        }

        // Above-right is occupied (has at least S1).
        final aboveRightNotFree =
            aboveRightId != null && phase[aboveRightId]! > 0;

        if ((rightIsS1 && lastInRow) || aboveRightNotFree) {
          // Rule: go above with S1 if free, else go to the right stitch.
          if (aboveId != null && phase[aboveId] == 0) {
            currentSqId = aboveId;
            doS1(currentSqId);
            changed = true;
            progressed = true;
          } else if (rightId != null && phase[rightId]! < 2) {
            currentSqId = rightId;
            changed = true;
            progressed = true;
          }
          // else stalled — fall through to exit the loop
        } else if (leftId != null && phase[leftId] == 1) {
          // Default: sweep left to complete S2 on the next S1-done cell.
          currentSqId = leftId;
          doS2Smart(currentSqId);
          changed = true;
          progressed = true;
        } else if (rightId != null && phase[rightId]! < 2) {
          currentSqId = rightId;
          changed = true;
          progressed = true;
        } else if (aboveId != null && phase[aboveId]! < 2) {
          currentSqId = aboveId;
          changed = true;
          progressed = true;
        }
        // else: no valid move — stalled, exit the while loop
      }
    }
    return progressed;
  }

  sweep();

  // ---- Phase 2: stitch any "possibly needed" cells still empty ----
  for (final sqId in [...possiblyNeeded]) {
    if (phase[sqId]! < 2) {
      if (phase[sqId] == 0) doS1(sqId);
      doS2(sqId);
      currentSqId = sqId;
      sweep();
    }
  }

  // ---- Phase 3: proximity search for remaining unstitched cells ----
  while (activeSqIds.any((id) => phase[id]! < 2)) {
    final unfinished = activeSqIds.where((id) => phase[id]! < 2).toList();

    // Find unfinished cell whose entry-point is closest to the needle.
    int nearest = unfinished.first;
    if (needleNode != null) {
      final (nx, ny) = nodeCoords[needleNode!]!;
      var bestDist = double.infinity;
      for (final sqId in unfinished) {
        final cn = cellNodes[sqId]!;
        // Approach to TL for S1, TR for S2.
        final entryN = phase[sqId] == 0 ? cn[Corner.topLeft]! : cn[Corner.topRight]!;
        final (tx, ty) = nodeCoords[entryN]!;
        final d = sqrt((tx - nx) * (tx - nx) + (ty - ny) * (ty - ny));
        if (d < bestDist) {
          bestDist = d;
          nearest = sqId;
        }
      }
    }

    currentSqId = nearest;
    if (phase[nearest] == 0) doS1(nearest);
    if (phase[nearest] == 1) doS2(nearest);
    sweep();
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
