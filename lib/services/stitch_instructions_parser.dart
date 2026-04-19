// Parses a hand-crafted stitch-instructions JSON file into a [PlannedAida].
//
// JSON schema
// -----------
// {
//   "title":   "optional string",          // default: "Pattern"
//   "cols":    3,                           // required: grid width
//   "rows":    2,                           // required: grid height
//   "cells":   [[0,0],[1,0]],              // optional: cells shown with a grid box
//                                           //   defaults to every cell referenced in stitches
//   "stitches": [                           // ordered stitch list
//     {
//       "type": "front1"|"front2"|"back1"|"back2"|"back3",
//       "from": {"x": 0, "y": 0, "corner": "topLeft"|"topRight"|"bottomLeft"|"bottomRight"},
//       "to":   {"x": 0, "y": 0, "corner": "topLeft"|"topRight"|"bottomLeft"|"bottomRight"}
//     },
//     ...
//   ]
// }
//
// "from" and "to" reference corners of grid squares.  When both corners belong
// to the same square the entry is emitted as a [PlanSimpleStitch]; otherwise
// as a [PlanCrossStitch].

import 'dart:convert';

import '../models/stitch_plan.dart';

/// Parses [jsonText] and returns a [PlannedAida] ready for rendering.
///
/// Throws [FormatException] on any schema violation.
PlannedAida parseStitchInstructions(String jsonText) {
  final dynamic root;
  try {
    root = jsonDecode(jsonText);
  } catch (e) {
    throw FormatException('Invalid JSON: $e');
  }

  if (root is! Map<String, dynamic>) {
    throw const FormatException('Root must be a JSON object.');
  }

  final title = (root['title'] as String?) ?? 'Pattern';

  final cols = _requireInt(root, 'cols');
  final rows = _requireInt(root, 'rows');

  if (cols <= 0 || rows <= 0) {
    throw const FormatException('"cols" and "rows" must be positive integers.');
  }

  // ── Build squares (all non-removed cells in reading order) ─────────────────
  final squares = <PlannedSquare>[];
  final cellToId = <(int, int), int>{};
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final id = squares.length;
      squares.add(PlannedSquare(id: id, x: x, y: y));
      cellToId[(x, y)] = id;
    }
  }

  // ── Parse stitches ─────────────────────────────────────────────────────────
  final rawStitches = root['stitches'];
  if (rawStitches == null) {
    throw const FormatException('"stitches" array is required.');
  }
  if (rawStitches is! List) {
    throw const FormatException('"stitches" must be an array.');
  }

  final stitchList = <PlanStitchEntry>[];
  final referencedCells = <(int, int)>{};

  for (var i = 0; i < rawStitches.length; i++) {
    final entry = rawStitches[i];
    if (entry is! Map<String, dynamic>) {
      throw FormatException('stitches[$i] must be an object.');
    }

    final type = _parseStitchType(entry, i);
    final fromPt = _parseStitchPoint(entry, 'from', i, cellToId, referencedCells);
    final toPt = _parseStitchPoint(entry, 'to', i, cellToId, referencedCells);

    if (fromPt.squareId == toPt.squareId) {
      stitchList.add(PlanSimpleStitch(
        squareId: fromPt.squareId,
        fro: fromPt.corner,
        to: toPt.corner,
        type: type,
      ));
    } else {
      stitchList.add(PlanCrossStitch(
        fro: fromPt,
        to: toPt,
        type: type,
      ));
    }
  }

  // ── Active cells ───────────────────────────────────────────────────────────
  // Explicit "cells" array takes precedence; falls back to every cell touched
  // by a stitch so that grid boxes are always drawn around stitched squares.
  final Set<int> activeSquareIds;
  final rawCells = root['cells'];
  if (rawCells != null) {
    if (rawCells is! List) {
      throw const FormatException('"cells" must be an array of [x, y] pairs.');
    }
    activeSquareIds = {};
    for (var i = 0; i < rawCells.length; i++) {
      final pair = rawCells[i];
      if (pair is! List || pair.length < 2) {
        throw FormatException('cells[$i] must be a two-element array [x, y].');
      }
      final x = pair[0] as int;
      final y = pair[1] as int;
      _checkBounds(x, y, cols, rows, 'cells[$i]');
      final id = cellToId[(x, y)];
      if (id == null) {
        throw FormatException('cells[$i]: ($x,$y) is out of grid bounds.');
      }
      activeSquareIds.add(id);
    }
  } else {
    // Infer from stitches.
    activeSquareIds = referencedCells.map((c) => cellToId[c]!).toSet();
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

// ── Helpers ───────────────────────────────────────────────────────────────────

int _requireInt(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v == null) throw FormatException('"$key" is required.');
  if (v is! int) throw FormatException('"$key" must be an integer.');
  return v;
}

StitchType _parseStitchType(Map<String, dynamic> entry, int idx) {
  final raw = entry['type'];
  if (raw == null) throw FormatException('stitches[$idx]: "type" is required.');
  return switch (raw as String) {
    'front1' => StitchType.frontOne,
    'front2' => StitchType.frontTwo,
    'back1' => StitchType.backOne,
    'back2' => StitchType.backTwo,
    'back3' => StitchType.backThree,
    'auto' || 'automatic' => StitchType.automatic,
    _ => throw FormatException(
        'stitches[$idx]: unknown type "$raw". '
        'Valid: front1, front2, back1, back2, back3, auto.'),
  };
}

StitchPoint _parseStitchPoint(
  Map<String, dynamic> entry,
  String field,
  int idx,
  Map<(int, int), int> cellToId,
  Set<(int, int)> referencedCells,
) {
  final raw = entry[field];
  if (raw == null) {
    throw FormatException('stitches[$idx]: "$field" is required.');
  }
  if (raw is! Map<String, dynamic>) {
    throw FormatException('stitches[$idx].$field must be an object.');
  }

  final x = raw['x'];
  final y = raw['y'];
  if (x is! int || y is! int) {
    throw FormatException('stitches[$idx].$field: "x" and "y" must be integers.');
  }

  final cornerRaw = raw['corner'] as String?;
  if (cornerRaw == null) {
    throw FormatException('stitches[$idx].$field: "corner" is required.');
  }
  final corner = switch (cornerRaw) {
    'topLeft' || 'tl' || 'TL' => Corner.topLeft,
    'topRight' || 'tr' || 'TR' => Corner.topRight,
    'bottomLeft' || 'bl' || 'BL' => Corner.bottomLeft,
    'bottomRight' || 'br' || 'BR' => Corner.bottomRight,
    _ => throw FormatException(
        'stitches[$idx].$field: unknown corner "$cornerRaw". '
        'Valid: topLeft, topRight, bottomLeft, bottomRight (or TL/TR/BL/BR).'),
  };

  final id = cellToId[(x, y)];
  if (id == null) {
    throw FormatException(
        'stitches[$idx].$field: cell ($x,$y) is outside the grid ($cellToId).');
  }
  referencedCells.add((x, y));
  return (squareId: id, corner: corner);
}

void _checkBounds(int x, int y, int cols, int rows, String label) {
  if (x < 0 || x >= cols || y < 0 || y >= rows) {
    throw FormatException('$label: ($x,$y) is outside the $cols×$rows grid.');
  }
}

