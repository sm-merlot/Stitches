/// CLI conversion tool for PK PDF ↔ .stitches.
///
/// Must be run via `flutter test` so that rootBundle (fonts) and pdfium
/// (native lib) are available.
///
/// Usage:
///
///   # Export .stitches → PK PDF
///   flutter test tool/pk_convert.dart --no-pub
///   # Edit kMode / kInputPath / kOutputPath below first.
///
/// Set the three constants, then run. Output is written to kOutputPath.
// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart' show Color;
import 'package:stitches/data/dmc_colors.dart';
import 'package:stitches/models/layer.dart';
import 'package:stitches/models/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/pdf_pattern_keeper_parser.dart';
import 'package:stitches/services/pdf_service.dart';

// ── Edit these ─────────────────────────────────────────────────────────────

/// 'export' → .stitches → PK PDF
/// 'import' → PK PDF → .stitches
const kMode = 'export';

/// Input file path.
const kInputPath = '/tmp/my_pattern.stitches'; // for export
// const kInputPath = '/tmp/my_pattern_pk.pdf'; // for import

/// Output file path.
const kOutputPath = '/tmp/my_pattern_pk.pdf'; // for export
// const kOutputPath = '/tmp/my_pattern_imported.stitches'; // for import

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    Pdfrx.getCacheDirectory = () async =>
        Directory.systemTemp.createTemp('pdfrx_cache').then((d) => d.path);
  });

  test('pk_convert: $kMode', () async {
    switch (kMode) {
      case 'export':
        await _doExport(kInputPath, kOutputPath);
      case 'import':
        await _doImport(kInputPath, kOutputPath);
      default:
        fail("Unknown mode '$kMode'. Use 'export' or 'import'.");
    }
  });
}

// ── Export: .stitches → PK PDF ───────────────────────────────────────────────

Future<void> _doExport(String inputPath, String outputPath) async {
  print('Export: $inputPath → $outputPath');

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    fail('Input file not found: $inputPath');
  }

  final (pattern, _, _) = await FileService.openFileFromPath(inputPath);
  print('Loaded: ${pattern.name} (${pattern.width}×${pattern.height}, '
      '${pattern.threads.length} threads)');

  final pdfBytes = await PdfService.buildPdfBytes(
    pattern,
    patternKeeperMode: true,
  );

  await File(outputPath).writeAsBytes(pdfBytes);
  print('Written: $outputPath (${(pdfBytes.length / 1024).toStringAsFixed(1)} KB)');
}

// ── Import: PK PDF → .stitches ────────────────────────────────────────────────

Future<void> _doImport(String inputPath, String outputPath) async {
  print('Import: $inputPath → $outputPath');

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    fail('Input file not found: $inputPath');
  }

  final result = await PatternKeeperParser.tryParse(inputPath);
  if (result == null) {
    fail('Failed to parse $inputPath as PK PDF');
  }

  print('Parsed: ${result.width}×${result.height}, '
      '${result.threads.length} threads, '
      '${result.stitches.length} stitches');

  // Convert ScannedThread → Thread.
  final threads = result.threads.map((t) {
    final dmc = dmcColorByCode(t.dmcCode);
    final color = dmc?.color ?? _hexColor(t.colorHex);
    return Thread(dmcCode: t.dmcCode, name: t.name, color: color);
  }).toList();

  // Convert ScannedStitch → Stitch.
  final stitches = result.stitches.map((s) {
    return FullStitch(x: s.x, y: s.y, threadId: s.dmcCode);
  }).toList();

  final name = p.basenameWithoutExtension(inputPath);
  final pattern = CrossStitchPattern(
    name: name,
    width: result.width,
    height: result.height,
    threads: threads,
    layerItems: [
      LayerLeaf(
        layer: Layer(
          id: const Uuid().v4(),
          name: 'Layer 1',
          visible: true,
          opacity: 1.0,
          stitches: stitches,
        ),
      ),
    ],
  );

  final yaml = FileService.toYamlString(pattern);
  await File(outputPath).writeAsString(yaml);
  print('Written: $outputPath');
}

/// Parse '#RRGGBB' hex string to Flutter Color.
Color _hexColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  final value = int.tryParse(clean, radix: 16) ?? 0;
  return Color(0xFF000000 | value);
}
