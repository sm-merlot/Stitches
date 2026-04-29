// Regenerates test/fixtures/*.expected from the corresponding *.pattern pattern files.
//
// Run with:
//   dart run tool/generate_fixtures.dart
//
// Each line of an .expected file encodes one stitch segment:
//   S(x,y,corner) B(x,y,corner)  — front stroke: surface→back
//   B(x,y,corner) S(x,y,corner)  — back travel:  back→surface
//
// Corner notation per cell:
//   TL───TC───TR
//   │         │
//   LC   CC   RC
//   │         │
//   BL───BC───BR

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:stitches/models/stitch/stitch_plan.dart';
import 'package:stitches/services/scan/grid_parser.dart';
import 'package:stitches/services/stitch_planner.dart';

// ── Corner serialisation ───────────────────────────────────────────────────

String _cornerStr(Corner c) => switch (c) {
      Corner.topLeft => 'TL',
      Corner.topRight => 'TR',
      Corner.bottomLeft => 'BL',
      Corner.bottomRight => 'BR',
    };

// ── Stitch serialisation ───────────────────────────────────────────────────

/// Serialises one [PlanStitchEntry] as a single line.
///
/// Front stitches (frontOne / frontTwo): needle travels surface→back.
///   fro corner = surface entry (S), to corner = back exit (B).
/// Back stitches (backOne/Two/Three): needle travels back→surface.
///   fro corner = back entry (B), to corner = surface exit (S).
String serializeStitch(PlanStitchEntry stitch, List<PlannedSquare> squares) {
  final isFront =
      stitch.type == StitchType.frontOne || stitch.type == StitchType.frontTwo;

  if (stitch is PlanSimpleStitch) {
    final sq = squares[stitch.squareId];
    final froTag = isFront ? 'S' : 'B';
    final toTag = isFront ? 'B' : 'S';
    final from = '$froTag(${sq.x},${sq.y},${_cornerStr(stitch.fro)})';
    final to = '$toTag(${sq.x},${sq.y},${_cornerStr(stitch.to)})';
    return '$from $to';
  }

  if (stitch is PlanCrossStitch) {
    // Cross stitches are always back stitches: back→surface across cells.
    final froSq = squares[stitch.fro.squareId];
    final toSq = squares[stitch.to.squareId];
    final from = 'B(${froSq.x},${froSq.y},${_cornerStr(stitch.fro.corner)})';
    final to = 'S(${toSq.x},${toSq.y},${_cornerStr(stitch.to.corner)})';
    return '$from $to';
  }

  throw ArgumentError('Unknown PlanStitchEntry subtype: $stitch');
}

// ── Main ──────────────────────────────────────────────────────────────────

void main() {
  final fixturesDir = Directory('test/fixtures');
  if (!fixturesDir.existsSync()) {
    stderr.writeln('Error: test/fixtures/ not found. Run from project root.');
    exit(1);
  }

  final txtFiles = fixturesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pattern'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in txtFiles) {
    final content = file.readAsStringSync();
    final (:cells, :cols, :rows) = parseGrid(content);

    if (cells.isEmpty) {
      print('Skipped ${file.path} — no cells found.');
      continue;
    }

    final name = file.uri.pathSegments.last.replaceAll('.pattern', '');
    final aida = planStitching(title: name, cols: cols, rows: rows, cells: cells);

    final lines =
        aida.stitches.map((s) => serializeStitch(s, aida.squares)).toList();

    final out = File('test/fixtures/$name.expected');
    out.writeAsStringSync('${lines.join('\n')}\n');
    print('${out.path}  (${lines.length} stitches)');
  }
}
