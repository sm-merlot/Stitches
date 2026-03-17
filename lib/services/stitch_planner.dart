import 'dart:math';

import '../models/stitch_plan.dart';

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _Task {
  final int cellId;
  final String kind; // 'front1' or 'front2'
  final int nodeA;
  final int nodeB;

  const _Task({
    required this.cellId,
    required this.kind,
    required this.nodeA,
    required this.nodeB,
  });

  @override
  bool operator ==(Object other) =>
      other is _Task &&
      cellId == other.cellId &&
      kind == other.kind &&
      nodeA == other.nodeA &&
      nodeB == other.nodeB;

  @override
  int get hashCode => Object.hash(cellId, kind, nodeA, nodeB);
}

class _Score implements Comparable<_Score> {
  final int isDiagonal;
  final int notSameRow;
  final int penalizedJump;
  final int kindPref;
  final int isJump;
  final double d;
  final double rowDist;
  final int endPos;

  const _Score({
    required this.isDiagonal,
    required this.notSameRow,
    required this.penalizedJump,
    required this.kindPref,
    required this.isJump,
    required this.d,
    required this.rowDist,
    required this.endPos,
  });

  @override
  int compareTo(_Score other) {
    if (isDiagonal != other.isDiagonal) return isDiagonal.compareTo(other.isDiagonal);
    if (notSameRow != other.notSameRow) return notSameRow.compareTo(other.notSameRow);
    if (penalizedJump != other.penalizedJump) return penalizedJump.compareTo(other.penalizedJump);
    if (kindPref != other.kindPref) return kindPref.compareTo(other.kindPref);
    if (isJump != other.isJump) return isJump.compareTo(other.isJump);
    if (d != other.d) return d.compareTo(other.d);
    if (rowDist != other.rowDist) return rowDist.compareTo(other.rowDist);
    return endPos.compareTo(other.endPos);
  }
}

// FrontOne (\): TopLeft -> BottomRight
// FrontTwo (/): TopRight -> BottomLeft
// These are semantically correct in screen coordinates (y=0 at top).
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

bool _setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Graph-traversal cross-stitch planner.
///
/// Uses screen coordinates: y=0 is the top row, y increases downward.
/// Cell (0,0) is the top-left corner of the grid.
///
/// Rules:
///   1. Stitches alternate strictly Front / Back throughout.
///   2. Back stitches are H or V only; zero-distance back stitches are never emitted.
///   3. FrontOne (\, TL->BR) precedes FrontTwo (/, TR->BL) for every cell.
///   4. The path starts at one end of the longest straight run so the
///      thread tail is hidden under a long sequence of back stitches.
PlannedAida planStitching({
  required String title,
  required int cols,
  required int rows,
  required List<(int, int)> cells,
  List<(int, int)>? removed,
}) {
  final cellsSet = cells.map((c) => (c.$1, c.$2)).toSet();
  final removedSet = removed?.map((c) => (c.$1, c.$2)).toSet() ?? <(int, int)>{};

  // Build ALL squares in the grid (top-to-bottom, left-to-right in screen coords).
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
  final activeSquareIds = activeSqIdsSet;
  final stitchList = <PlanStitchEntry>[];

  // -------------------------------------------------------------------------
  // Connected components (H/V adjacency among active cells)
  // -------------------------------------------------------------------------
  final cellRegion = <int, int>{};
  var regionId = 0;
  for (final sqId in activeSqIds) {
    if (cellRegion.containsKey(sqId)) continue;
    final queue = [sqId];
    while (queue.isNotEmpty) {
      final cid = queue.removeLast();
      if (cellRegion.containsKey(cid)) continue;
      cellRegion[cid] = regionId;
      final sq = squares[cid];
      for (final nb in [
        (sq.x + 1, sq.y),
        (sq.x - 1, sq.y),
        (sq.x, sq.y + 1),
        (sq.x, sq.y - 1),
      ]) {
        final nbr = cellToId[nb];
        if (nbr != null && activeSqIdsSet.contains(nbr)) queue.add(nbr);
      }
    }
    regionId++;
  }

  // -------------------------------------------------------------------------
  // Node canonicalization
  // -------------------------------------------------------------------------
  var nodeCounter = 0;
  final nodeMap = <(double, double), int>{};
  for (final sq in squares) {
    for (final corner in Corner.values) {
      final coord = sq.cornerCoord(corner);
      nodeMap.putIfAbsent(coord, () => nodeCounter++);
    }
  }

  final nodeCoords = {for (final e in nodeMap.entries) e.value: e.key};

  final cellNodes = <int, Map<Corner, int>>{};
  for (var sqId = 0; sqId < squares.length; sqId++) {
    cellNodes[sqId] = {
      for (final corner in Corner.values)
        corner: nodeMap[squares[sqId].cornerCoord(corner)]!,
    };
  }

  final nodeToSqCorners = <int, List<(int, Corner)>>{};
  for (final sqEntry in cellNodes.entries) {
    for (final cEntry in sqEntry.value.entries) {
      nodeToSqCorners.putIfAbsent(cEntry.value, () => []).add((sqEntry.key, cEntry.key));
    }
  }

  // -------------------------------------------------------------------------
  // Tasks (2 per active cell: front1 and front2)
  // -------------------------------------------------------------------------
  final allTasks = <_Task>[];
  for (final sqId in activeSqIds) {
    final cn = cellNodes[sqId]!;
    allTasks.add(_Task(
      cellId: sqId,
      kind: 'front1',
      nodeA: cn[Corner.topLeft]!,
      nodeB: cn[Corner.bottomRight]!,
    ));
    allTasks.add(_Task(
      cellId: sqId,
      kind: 'front2',
      nodeA: cn[Corner.topRight]!,
      nodeB: cn[Corner.bottomLeft]!,
    ));
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  double nodeDist(int a, int b) {
    final (ax, ay) = nodeCoords[a]!;
    final (bx, by) = nodeCoords[b]!;
    return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
  }

  List<_Task> availableTasks(Set<_Task> done, Set<int> front1Done) => allTasks
      .where((t) => !done.contains(t) && (t.kind == 'front1' || front1Done.contains(t.cellId)))
      .toList();

  List<String> unitSegments(int fromNode, int toNode) {
    final (fx, fy) = nodeCoords[fromNode]!;
    final (tx, ty) = nodeCoords[toNode]!;
    final segs = <String>[];
    if ((fy - ty).abs() < 1e-9) {
      // horizontal
      var x = min(fx, tx);
      final xHi = max(fx, tx);
      while (x < xHi - 1e-9) {
        segs.add('h:${(fy * 2).round()}:${(x * 2).round()}');
        x += 1.0;
      }
    } else {
      // vertical
      var y = min(fy, ty);
      final yHi = max(fy, ty);
      while (y < yHi - 1e-9) {
        segs.add('v:${(fx * 2).round()}:${(y * 2).round()}');
        y += 1.0;
      }
    }
    return segs;
  }

  // -------------------------------------------------------------------------
  // Start position: end of the longest boundary run closest to a corner
  // -------------------------------------------------------------------------
  List<(int, int)> findStartRun() {
    final allXs = valid.map((c) => c.$1).toList();
    final allYs = valid.map((c) => c.$2).toList();
    final minX = allXs.reduce(min);
    final maxX = allXs.reduce(max);
    final minY = allYs.reduce(min);
    final maxY = allYs.reduce(max);

    // Screen coords: top-left = (minX, minY), bottom-right = (maxX, maxY)
    final preferred = {(minX, minY), (maxX, maxY)};
    final anyCorner = {(minX, minY), (maxX, minY), (minX, maxY), (maxX, maxY)};

    final allRuns = <List<(int, int)>>[];

    // Horizontal runs
    final rowMap = <int, List<int>>{};
    for (final (x, y) in valid) {
      rowMap.putIfAbsent(y, () => []).add(x);
    }
    for (final y in rowMap.keys.toList()..sort()) {
      final xs = rowMap[y]!..sort();
      var cur = [xs[0]];
      for (var i = 1; i < xs.length; i++) {
        if (xs[i] == cur.last + 1) {
          cur.add(xs[i]);
        } else {
          allRuns.add([for (final xi in cur) (xi, y)]);
          cur = [xs[i]];
        }
      }
      allRuns.add([for (final xi in cur) (xi, y)]);
    }

    // Vertical runs
    final colMap = <int, List<int>>{};
    for (final (x, y) in valid) {
      colMap.putIfAbsent(x, () => []).add(y);
    }
    for (final x in colMap.keys.toList()..sort()) {
      final ys = colMap[x]!..sort();
      var cur = [ys[0]];
      for (var i = 1; i < ys.length; i++) {
        if (ys[i] == cur.last + 1) {
          cur.add(ys[i]);
        } else {
          allRuns.add([for (final yi in cur) (x, yi)]);
          cur = [ys[i]];
        }
      }
      allRuns.add([for (final yi in cur) (x, yi)]);
    }

    (int, int, int, int) runScore(List<(int, int)> run) {
      final first = run.first;
      final last = run.last;
      final isH = first.$2 == last.$2;
      final bool onEdge;
      if (isH) {
        onEdge = first.$2 == minY || first.$2 == maxY;
      } else {
        onEdge = first.$1 == minX || first.$1 == maxX;
      }
      final hasPreferred = preferred.contains(first) || preferred.contains(last);
      final hasCorner = anyCorner.contains(first) || anyCorner.contains(last);
      return (
        -min(run.length, 4),
        onEdge ? 0 : 1,
        hasPreferred ? 0 : 1,
        hasCorner ? 0 : 1,
      );
    }

    allRuns.sort((a, b) {
      final sa = runScore(a);
      final sb = runScore(b);
      if (sa.$1 != sb.$1) return sa.$1.compareTo(sb.$1);
      if (sa.$2 != sb.$2) return sa.$2.compareTo(sb.$2);
      if (sa.$3 != sb.$3) return sa.$3.compareTo(sb.$3);
      return sa.$4.compareTo(sb.$4);
    });

    var run = allRuns.first;
    final first = run.first;
    final last = run.last;
    if (preferred.contains(last) && !preferred.contains(first)) {
      run = run.reversed.toList();
    } else if (anyCorner.contains(last) && !anyCorner.contains(first)) {
      run = run.reversed.toList();
    }
    return run;
  }

  final longestRun = findStartRun();
  final startSqId = cellToId[longestRun.first]!;
  final startTask = allTasks.firstWhere((t) => t.cellId == startSqId && t.kind == 'front1');

  final allOnRun = _setEquals(valid, longestRun.toSet());
  final endCount =
      (allOnRun && longestRun.length >= 4) ? min(3, longestRun.length - 1) : 0;
  final endRun =
      endCount > 0 ? longestRun.sublist(longestRun.length - endCount) : <(int, int)>[];
  final endSqIds = endRun.map((c) => cellToId[c]!).toSet();
  final reversedEndRun = endRun.reversed.toList();
  final endOrderMap = <int, int>{
    for (var i = 0; i < reversedEndRun.length; i++) cellToId[reversedEndRun[i]]!: i,
  };

  // -------------------------------------------------------------------------
  // Segment usage tracking
  // -------------------------------------------------------------------------
  final segmentUsage = <String, int>{};

  void emitFront(_Task task, String direction) {
    final corners = _frontCorners[task.kind]![direction]!;
    final stype = task.kind == 'front1' ? StitchType.frontOne : StitchType.frontTwo;
    stitchList.add(PlanSimpleStitch(
      squareId: task.cellId,
      fro: corners.$1,
      to: corners.$2,
      type: stype,
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
    final fromSqIds = fromReps.map((r) => r.$1).toSet();
    final toSqIds = toReps.map((r) => r.$1).toSet();
    final shared = fromSqIds.intersection(toSqIds);

    if (shared.isNotEmpty) {
      final sqId = shared.first;
      final froC = fromReps.firstWhere((r) => r.$1 == sqId).$2;
      final toC = toReps.firstWhere((r) => r.$1 == sqId).$2;
      stitchList.add(PlanSimpleStitch(squareId: sqId, fro: froC, to: toC, type: btype));
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

  // -------------------------------------------------------------------------
  // Best candidate scoring
  // -------------------------------------------------------------------------
  (_Task, String)? bestCandidate(
    int current,
    List<_Task> avail,
    int currentY,
    int currentCellId,
  ) {
    _Score? bestScore;
    _Task? bestTask;
    String? bestDir;

    final (cx, cy) = nodeCoords[current]!;
    final curRegion = cellRegion[currentCellId]!;
    final hasNonEnd = avail.any((t) => !endSqIds.contains(t.cellId));

    for (final task in avail) {
      if (hasNonEnd && endSqIds.contains(task.cellId)) continue;
      final taskY = squares[task.cellId].y;
      final endPos = endOrderMap[task.cellId] ?? 0;

      for (final direction in ['fwd', 'rev']) {
        final startNd = direction == 'fwd' ? task.nodeA : task.nodeB;
        final d = nodeDist(current, startNd);
        if (d < 1e-9) continue;

        final (sx, sy) = nodeCoords[startNd]!;
        final isDiagonal = ((sx - cx).abs() < 1e-9 || (sy - cy).abs() < 1e-9) ? 0 : 1;
        final kindPref = task.kind == 'front1' ? 0 : 1;
        final isJump = d > 1.0 + 1e-9 ? 1 : 0;
        final notSameRow = taskY == currentY ? 0 : 1;
        final sameRegion = cellRegion[task.cellId] == curRegion;
        final penalizedJump = (isJump == 1 && sameRegion) ? 1 : 0;
        final rowDist = (taskY - currentY).abs().toDouble();

        final score = _Score(
          isDiagonal: isDiagonal,
          notSameRow: notSameRow,
          penalizedJump: penalizedJump,
          kindPref: kindPref,
          isJump: isJump,
          d: d,
          rowDist: rowDist,
          endPos: endPos,
        );
        if (bestScore == null || score.compareTo(bestScore) < 0) {
          bestScore = score;
          bestTask = task;
          bestDir = direction;
        }
      }
    }

    if (bestTask == null || bestDir == null) return null;
    return (bestTask, bestDir);
  }

  // -------------------------------------------------------------------------
  // Main traversal loop
  // -------------------------------------------------------------------------
  int endNode(_Task task, String direction) =>
      direction == 'fwd' ? task.nodeB : task.nodeA;
  int startNode(_Task task, String direction) =>
      direction == 'fwd' ? task.nodeA : task.nodeB;

  final done = <_Task>{};
  final front1Done = <int>{};

  emitFront(startTask, 'fwd');
  var current = endNode(startTask, 'fwd');
  var currentY = squares[startTask.cellId].y;
  var currentCellId = startTask.cellId;
  done.add(startTask);
  front1Done.add(startTask.cellId);

  while (done.length < allTasks.length) {
    final avail = availableTasks(done, front1Done);
    final result = bestCandidate(current, avail, currentY, currentCellId);
    if (result == null) break;

    final (bestTask, bestDir) = result;
    emitBack(current, startNode(bestTask, bestDir));
    emitFront(bestTask, bestDir);
    current = endNode(bestTask, bestDir);
    currentY = squares[bestTask.cellId].y;
    currentCellId = bestTask.cellId;
    done.add(bestTask);
    if (bestTask.kind == 'front1') front1Done.add(bestTask.cellId);
  }

  return PlannedAida(
    title: title,
    cols: cols,
    rows: rows,
    squares: squares,
    activeSquareIds: activeSquareIds,
    stitches: stitchList,
  );
}
