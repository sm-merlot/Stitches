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


/// State-machine cross-stitch planner.
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
PlannedAida planStitching({
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

  // mncSet: shared dedup guard — prevents the same cell being added to MNC (v1) twice.
  final mncSet = <int>{};

  // mncv2Set: shared dedup guard — prevents the same cell being added to MNCv2 (a or b) twice.
  final mncv2Set = <int>{};

  // Runs one complete sweep from [startId] using the same down/left/right
  // logic regardless of whether this is Phase 1 or an MNC sub-sweep.
  // Results go into caller-supplied [ops], [mncs], and [mncv2s] lists.
  // [ops]    — the (cellId, kind) ops produced by this sweep.
  // [mncs]   — MNC (v1) detections: (afterIdx, cellId).
  //            afterIdx is the position in [ops] after which the sub-sweep
  //            for cellId should be spliced into the final schedule.
  // [mncv2s] — MNCv2 detections: (triggerCellId, cellId, kind).
  //            triggerCellId is the cell that was being S2-scheduled when the
  //            diagonal cell was detected.  kind='a' splices before trigger's
  //            S1; kind='b' splices after trigger's S2.
  // [cellS1Idx] — records the ops index at which each cell's S1 was emitted.
  void runOneSweep(
    int startId,
    List<({int cellId, String kind})> ops,
    List<({int afterIdx, int cellId})> mncs,
    List<({int triggerCellId, int cellId, String kind})> mncv2s,
    Map<int, int> cellS1Idx,
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
      final primaryId = belowId;
      final secondaryId = aboveId;

      // R1: Empty cell → schedule S1; move primary/left/right.
      if (scheduled[cur] == 0) {
        cellS1Idx[cur] = ops.length; // record S1 position before adding.
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

            // MNC (v1): opposite-primary neighbour is empty → it may be unreachable
            // by this sweep direction.  Record it so its sub-sweep can be spliced in
            // immediately after this S2 in the final schedule.
            if (secondaryId != null &&
                scheduled[secondaryId] == 0 &&
                !mncSet.contains(secondaryId)) {
              mncSet.add(secondaryId);
              mncs.add((afterIdx: ops.length - 1, cellId: secondaryId));
            }

            // MNCv2: diagonal cells that may be unreachable from the main sweep
            // because their only axial neighbour in this direction is already done.
            // kind='a' → splice before trigger's S1 (top-left / bottom-right).
            // kind='b' → splice after trigger's S2  (top-right / bottom-left).
            //
            // Case A: cell above is S2 (done) or absent.
            final aboveDone = aboveId == null || scheduled[aboveId] == 2;
            if (aboveDone) {
              // v2a: top-left diagonal.
              final topLeftId = activeSqAt(sq.x - 1, sq.y - 1);
              if (topLeftId != null &&
                  scheduled[topLeftId] == 0 &&
                  !mncv2Set.contains(topLeftId)) {
                mncv2Set.add(topLeftId);
                mncv2s.add((triggerCellId: cur, cellId: topLeftId, kind: 'a'));
              }
              // v2b: top-right diagonal.
              final topRightId = activeSqAt(sq.x + 1, sq.y - 1);
              if (topRightId != null &&
                  scheduled[topRightId] == 0 &&
                  !mncv2Set.contains(topRightId)) {
                mncv2Set.add(topRightId);
                mncv2s.add((triggerCellId: cur, cellId: topRightId, kind: 'b'));
              }
            }
            // Case B: cell below is S2 (done) or absent.
            final belowDone = belowId == null || scheduled[belowId] == 2;
            if (belowDone) {
              // v2a: bottom-right diagonal.
              final botRightId = activeSqAt(sq.x + 1, sq.y + 1);
              if (botRightId != null &&
                  scheduled[botRightId] == 0 &&
                  !mncv2Set.contains(botRightId)) {
                mncv2Set.add(botRightId);
                mncv2s.add((triggerCellId: cur, cellId: botRightId, kind: 'a'));
              }
              // v2b: bottom-left diagonal.
              final botLeftId = activeSqAt(sq.x - 1, sq.y + 1);
              if (botLeftId != null &&
                  scheduled[botLeftId] == 0 &&
                  !mncv2Set.contains(botLeftId)) {
                mncv2Set.add(botLeftId);
                mncv2s.add((triggerCellId: cur, cellId: botLeftId, kind: 'b'));
              }
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
  // Phase A (v1 MNCs) — processed LIFO, spliced after their trigger S2.
  // Phase B (v2 MNCs) — processed LIFO after Phase A, in combined detection
  //   order.  kind='a' splices before trigger's S1; kind='b' splices after
  //   trigger's S2 (both located by forward scan of the Phase A result).
  List<({int cellId, String kind})> expandSweep(
    List<({int cellId, String kind})> ops,
    List<({int afterIdx, int cellId})> mncs,
    List<({int triggerCellId, int cellId, String kind})> mncv2s,
  ) {
    // ---- Phase A: expand v1 MNCs ----
    List<({int cellId, String kind})> expanded = ops;
    if (mncs.isNotEmpty) {
      // Run sub-sweeps LIFO; afterIdx (index of the S2 op) is the unique key.
      final subResults = <int, List<({int cellId, String kind})>>{};
      for (final mnc in mncs.reversed) {
        if (scheduled[mnc.cellId] != 0) continue;
        final subOps = <({int cellId, String kind})>[];
        final subMncs = <({int afterIdx, int cellId})>[];
        final subMncv2s = <({int triggerCellId, int cellId, String kind})>[];
        final subCellS1Idx = <int, int>{};
        runOneSweep(mnc.cellId, subOps, subMncs, subMncv2s, subCellS1Idx);
        subResults[mnc.afterIdx] = expandSweep(subOps, subMncs, subMncv2s);
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
      expanded = result;
    }

    // ---- Phase B: expand v2 MNCs (kinds 'a' and 'b') ----
    if (mncv2s.isEmpty) return expanded;

    // Run sub-sweeps LIFO so the most-recently detected v2 claims cells first.
    // Key by position in mncv2s for stable lookup during assembly.
    final v2SubResults = <int, List<({int cellId, String kind})>>{};
    // Step 1: snapshot raw ops + mncv2s before expansion for chain detection.
    final v2RawOps    = <int, List<({int cellId, String kind})>>{};
    final v2RawMncv2s =
        <int, List<({int triggerCellId, int cellId, String kind})>>{};
    for (var i = mncv2s.length - 1; i >= 0; i--) {
      final v2 = mncv2s[i];
      if (scheduled[v2.cellId] != 0) continue;
      final subOps = <({int cellId, String kind})>[];
      final subMncs = <({int afterIdx, int cellId})>[];
      final subMncv2s = <({int triggerCellId, int cellId, String kind})>[];
      final subCellS1Idx = <int, int>{};
      runOneSweep(v2.cellId, subOps, subMncs, subMncv2s, subCellS1Idx);
      v2RawOps[i]    = List.of(subOps);
      v2RawMncv2s[i] = List.of(subMncv2s);
      v2SubResults[i] = expandSweep(subOps, subMncs, subMncv2s);
    }

    // Step 1: detect same-direction diagonal chains.
    // A chain exists for mncv2s entry i when the sub-sweep produced at least
    // one MNCv2 detection with the SAME kind — i.e. the diagonal continues in
    // the same direction (e.g. repeated bottom-right or repeated bottom-left).
    //
    // Step 2: collect chain links in traversal order (near → far).
    // For entry i  (trigger T → cell D, kind k):
    //   links[0] = D's own raw ops   (segment nearest the parent)
    //   links[1] = continuation ops  (everything further along the chain)
    //
    // The parent segment (the T-containing portion of `ops`) is NOT in links;
    // it is handled at linearisation time (Step 3).
    //
    // Extraction from the expanded sub-result:
    //   kind='b' → continuation is appended AFTER D's raw ops  → tail
    //   kind='a' → continuation is prepended BEFORE D's raw ops → head
    final chainLinks =
        <int, List<List<({int cellId, String kind})>>>{};
    for (var i = 0; i < mncv2s.length; i++) {
      final rawMncv2s = v2RawMncv2s[i];
      final rawOps    = v2RawOps[i];
      final subResult = v2SubResults[i];
      if (rawMncv2s == null || rawOps == null || subResult == null) continue;

      final entry = mncv2s[i];
      // Step 1: same-kind sub-detection present?
      if (!rawMncv2s.any((e) => e.kind == entry.kind)) continue;

      // Step 2: extract continuation and build link list.
      final n = rawOps.length;
      final List<({int cellId, String kind})> cont;
      if (entry.kind == 'b') {
        // D's raw ops are at the start; continuation follows.
        cont = subResult.length > n ? subResult.sublist(n) : const [];
      } else {
        // D's raw ops are at the end; continuation precedes.
        cont = subResult.length > n
            ? subResult.sublist(0, subResult.length - n)
            : const [];
      }
      chainLinks[i] = [rawOps, cont];
    }
    // chainLinks maps entry index → [near-segment ops, far-segment ops, …].

    // Steps 3 & 4: linearise same-direction diagonal chains.
    //
    // When every processed sub-sweep belongs to a single same-direction chain,
    // the standard point-insertion produces a large back stitch (either the
    // parent's last S2 is stranded far from its cell, or the needle teleports
    // to the far end immediately after the first S1).
    //
    // Instead, produce a flat "all S1s then all S2s" sequence across the entire
    // chain — the same schedule a straight column would receive:
    //
    //   [parent S1s | link0 S1s | … | linkN S1s | linkN S2s | … | link0 S2s | parent S2s]
    //
    // This applies to both kind='a' and kind='b' chains because the parent S1s
    // and S2s are extracted by filtering `expanded` directly.
    //
    // Restriction: only applied when there is exactly one chain entry and no
    // additional non-chain sub-sweeps at this level, ensuring correctness for
    // more complex arrangements (multiple independent diagonals, etc.).
    if (chainLinks.length == 1 && v2SubResults.length == 1) {
      final links = chainLinks.values.first;
      final parentS1s = expanded.where((op) => op.kind == 'S1').toList();
      final parentS2s = expanded.where((op) => op.kind == 'S2').toList();

      final result = <({int cellId, String kind})>[...parentS1s];
      for (final link in links) {
        result.addAll(link.where((op) => op.kind == 'S1'));
      }
      for (final link in links.reversed) {
        result.addAll(link.where((op) => op.kind == 'S2'));
      }
      result.addAll(parentS2s);
      return result;
    }

    // Build insertion maps (LIFO order so first-run sub-sweep appears first).
    // kind='a' → before trigger's S1; kind='b' → after trigger's S2.
    final insertionsBeforeS1 = <int, List<List<({int cellId, String kind})>>>{};
    final insertionsAfterS2  = <int, List<List<({int cellId, String kind})>>>{};
    for (var i = mncv2s.length - 1; i >= 0; i--) {
      final sub = v2SubResults[i];
      if (sub == null || sub.isEmpty) continue;
      final entry = mncv2s[i];
      final map = entry.kind == 'a' ? insertionsBeforeS1 : insertionsAfterS2;
      map.putIfAbsent(entry.triggerCellId, () => []).add(sub);
    }
    if (insertionsBeforeS1.isEmpty && insertionsAfterS2.isEmpty) return expanded;

    // Forward pass: insert pending sub-sweeps at their respective trigger points.
    final result = <({int cellId, String kind})>[];
    for (final op in expanded) {
      if (op.kind == 'S1') {
        final pending = insertionsBeforeS1[op.cellId];
        if (pending != null) {
          for (final sub in pending) { result.addAll(sub); }
        }
      }
      result.add(op);
      if (op.kind == 'S2') {
        final pending = insertionsAfterS2[op.cellId];
        if (pending != null) {
          for (final sub in pending) { result.addAll(sub); }
        }
      }
    }
    return result;
  }

  // ---- Phase 1: downward sweep, with MNC sub-sweeps spliced inline ----
  final p1Ops = <({int cellId, String kind})>[];
  final p1Mncs = <({int afterIdx, int cellId})>[];
  final p1Mncv2s = <({int triggerCellId, int cellId, String kind})>[];
  final p1CellS1Idx = <int, int>{};
  runOneSweep(cellToId[startCoord]!, p1Ops, p1Mncs, p1Mncv2s, p1CellS1Idx);
  schedule.addAll(expandSweep(p1Ops, p1Mncs, p1Mncv2s));

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

    // Lookahead: prefer the end node closer to the nearest start of the next op.
    // This check comes before the turn-around rule so that a clear cost
    // difference (e.g. straight vs diagonal back stitch to a v2b-inserted cell)
    // always wins over a local perpendicularity preference.
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

    // Turn-around rule: when S1 is immediately followed by S2 on the same cell,
    // choose directions so ALL back stitches are perpendicular to cell movement.
    // H cell movement → V back stitches; V cell movement → H back stitches.
    // Only fires when the lookahead above found equal departure distances.
    final currentOp = schedule[opIdx];
    if (currentOp.kind == 'S1' && opIdx + 1 < schedule.length) {
      final nextOp = schedule[opIdx + 1];
      if (nextOp.kind == 'S2' && nextOp.cellId == currentCellId) {
        // Turn-around S1: choose so approach (fromNode → S1 start) is perp to movement.
        if (opIdx > 0 && fromNode != null) {
          final prevCellId = schedule[opIdx - 1].cellId;
          final dx = squares[currentCellId].x - squares[prevCellId].x;
          final dy = squares[currentCellId].y - squares[prevCellId].y;
          if (dx != 0 || dy != 0) {
            bool approachIsPerp(int startNode) {
              final (fx, fy) = nodeCoords[fromNode]!;
              final (sx, sy) = nodeCoords[startNode]!;
              final adx = (sx - fx).abs();
              final ady = (sy - fy).abs();
              if (dy == 0 && dx != 0 && adx < 1e-9) return true; // H move → V approach
              if (dx == 0 && dy != 0 && ady < 1e-9) return true; // V move → H approach
              return false;
            }
            final fwdP = approachIsPerp(fwdStart);
            final revP = approachIsPerp(revStart);
            if (fwdP != revP) return fwdP ? 'fwd' : 'rev';
          }
        }
      }
    } else if (currentOp.kind == 'S2' && opIdx > 0) {
      final prevOp = schedule[opIdx - 1];
      if (prevOp.kind == 'S1' && prevOp.cellId == currentCellId) {
        // Turn-around S2: choose so departure (fromNode → S2 start) is perp to movement.
        if (opIdx >= 2 && fromNode != null) {
          final prevCellId = schedule[opIdx - 2].cellId;
          final dx = squares[currentCellId].x - squares[prevCellId].x;
          final dy = squares[currentCellId].y - squares[prevCellId].y;
          if (dx != 0 || dy != 0) {
            bool departureIsPerp(int startNode) {
              final (fx, fy) = nodeCoords[fromNode]!;
              final (sx, sy) = nodeCoords[startNode]!;
              final adx = (sx - fx).abs();
              final ady = (sy - fy).abs();
              if (dy == 0 && dx != 0 && adx < 1e-9) return true; // H move → V dep
              if (dx == 0 && dy != 0 && ady < 1e-9) return true; // V move → H dep
              return false;
            }
            final fwdP = departureIsPerp(fwdStart);
            final revP = departureIsPerp(revStart);
            if (fwdP != revP) return fwdP ? 'fwd' : 'rev';
          }
        }
      }
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
