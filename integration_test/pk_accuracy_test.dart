/// Round-trip accuracy test: sm_test.stitches → PK PDF → parse → compare.
///
/// Compares flattened canvas (position + thread) after the round-trip.
/// Ordering and IDs are irrelevant — only stitch content is checked.
///
/// Artifacts (PK PDF + reference PDF) are written to:
///   /tmp/pk_accuracy_test/   (or PK_ARTIFACTS_DIR env var)
/// and kept after the test so they can be inspected manually.
///
/// Requires macOS so that pdfium native lib and rootBundle are available.
///
/// Run with:
///   flutter test integration_test/pk_accuracy_test.dart -d macos --no-pub
///
/// Override artifact output dir:
///   PK_ARTIFACTS_DIR=~/Desktop/pk_out \
///     flutter test integration_test/pk_accuracy_test.dart -d macos --no-pub
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'package:stitches/models/stitch.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/pdf_pattern_keeper_parser.dart';
import 'package:stitches/services/pdf_service.dart';
import 'package:stitches/services/stitch_compositor.dart';

/// Where artifacts are written. Override with PK_ARTIFACTS_DIR env var.
const _kDefaultArtifactsDir = '/tmp/pk_accuracy_test';

/// Flatten visible layers to position→dmcCode (full stitches only, order-independent).
Map<(int, int), String> _flattenedStitchMap(dynamic pattern) {
  final result = StitchCompositor.compute(pattern);
  final map = <(int, int), String>{};
  for (final s in result.dedupedNonBack) {
    if (s is FullStitch) map[(s.x, s.y)] = s.threadId;
  }
  return map;
}

/// Position→dmcCode map from PatternScanResult (order-independent).
Map<(int, int), String> _scanStitchMap(dynamic result) => {
      for (final s in result.stitches) (s.x as int, s.y as int): s.dmcCode as String,
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Pdfrx.getCacheDirectory = () async =>
        Directory.systemTemp.createTemp('pdfrx_cache').then((d) => d.path);
  });

  group('PK PDF round-trip accuracy (sm_test)', () {
    test('sm_test.stitches → PK PDF → parse → identical canvas', () async {
      final fixturePath = p.join(
        Directory.current.path,
        'test', 'fixtures', 'sm_test.stitches',
      );
      expect(File(fixturePath).existsSync(), isTrue,
          reason: 'Fixture not found: $fixturePath');

      // Artifact output directory — persisted for manual inspection.
      final artifactsDir = Directory(
        Platform.environment['PK_ARTIFACTS_DIR'] ?? _kDefaultArtifactsDir,
      );
      await artifactsDir.create(recursive: true);

      // 1. Load fixture.
      final (original, _, _) = await FileService.openFileFromPath(fixturePath);
      debugPrint('Loaded: ${original.name} ${original.width}×${original.height}');

      // 2. Ground truth — flatten all visible layers, ignore ordering.
      final expectedMap = _flattenedStitchMap(original);
      final expectedThreads = expectedMap.values.toSet();
      debugPrint(
        'Ground truth: ${expectedMap.length} stitches, '
        '${expectedThreads.length} threads',
      );

      // 3. Export reference PDF (normal mode — for visual comparison).
      final refPdfBytes = await PdfService.buildPdfBytes(original);
      final refPdfFile = File(p.join(artifactsDir.path, 'reference.pdf'));
      await refPdfFile.writeAsBytes(refPdfBytes);
      debugPrint('Reference PDF: ${refPdfFile.path}');

      // 4. Export PK PDF.
      final pkPdfBytes = await PdfService.buildPdfBytes(
        original,
        patternKeeperMode: true,
      );
      expect(pkPdfBytes.length, greaterThan(1000));
      final pkPdfFile = File(p.join(artifactsDir.path, 'roundtrip_pk.pdf'));
      await pkPdfFile.writeAsBytes(pkPdfBytes);
      debugPrint('PK PDF: ${pkPdfFile.path}  '
          '(${(pkPdfBytes.length / 1024).toStringAsFixed(1)} KB)');

      // 5. Re-parse from a temp copy (parser needs a file path).
      final tmpDir = await Directory.systemTemp.createTemp('pk_accuracy_');
      final tmpPdf = File(p.join(tmpDir.path, 'roundtrip.pdf'));
      await tmpPdf.writeAsBytes(pkPdfBytes);

      try {
        final parsed = await PatternKeeperParser.tryParse(tmpPdf.path);
        expect(parsed, isNotNull, reason: 'Exported PK PDF should re-parse');

        // 6. Dimensions.
        expect(parsed!.width, equals(original.width), reason: 'Width mismatch');
        expect(parsed.height, equals(original.height), reason: 'Height mismatch');

        // 7. Build parsed map — order- and ID-independent.
        final parsedMap = _scanStitchMap(parsed);

        // 8. Diff.
        final missing = expectedMap.keys
            .where((pos) => !parsedMap.containsKey(pos))
            .toList();
        final extra = parsedMap.keys
            .where((pos) => !expectedMap.containsKey(pos))
            .toList();
        final wrongThread = <(int, int), (String expected, String got)>{};
        for (final entry in expectedMap.entries) {
          final got = parsedMap[entry.key];
          if (got != null && got != entry.value) {
            wrongThread[entry.key] = (entry.value, got);
          }
        }

        final correct = expectedMap.keys
            .where((pos) =>
                parsedMap.containsKey(pos) &&
                parsedMap[pos] == expectedMap[pos])
            .length;
        final total = expectedMap.length;
        final pct = total > 0 ? (correct / total * 100).toStringAsFixed(2) : '?';

        // Thread sets (by DMC code only — no IDs/ordering).
        final parsedThreadSet = parsed.threads.map((t) => t.dmcCode).toSet();
        final missingThreads = expectedThreads.difference(parsedThreadSet);
        final extraThreads = parsedThreadSet.difference(expectedThreads);

        // 9. Accuracy report — always printed so CI logs show context on failure.
        debugPrint('');
        debugPrint('══════════════════════════════════════════');
        debugPrint('  ROUND-TRIP ACCURACY REPORT');
        debugPrint('══════════════════════════════════════════');
        debugPrint('  Dimensions       : ${parsed.width}×${parsed.height}');
        debugPrint('  Expected stitches: $total');
        debugPrint('  Correct          : $correct  ($pct%)');
        debugPrint('  Missing          : ${missing.length}');
        debugPrint('  Extra            : ${extra.length}');
        debugPrint('  Wrong thread     : ${wrongThread.length}');
        debugPrint('  Expected threads : ${expectedThreads.length}');
        debugPrint('  Parsed threads   : ${parsedThreadSet.length}');
        if (missingThreads.isNotEmpty) {
          debugPrint('  Missing threads  : $missingThreads');
        }
        if (extraThreads.isNotEmpty) {
          debugPrint('  Extra threads    : $extraThreads');
        }
        if (missing.isNotEmpty) {
          debugPrint('  First 20 missing (x,y) → expected thread:');
          for (final pos in missing.take(20)) {
            debugPrint('    $pos → ${expectedMap[pos]}');
          }
        }
        if (extra.isNotEmpty) {
          debugPrint('  First 20 extra (x,y) → parsed thread:');
          for (final pos in extra.take(20)) {
            debugPrint('    $pos → ${parsedMap[pos]}');
          }
        }
        if (wrongThread.isNotEmpty) {
          debugPrint('  First 20 wrong-thread positions:');
          for (final e in wrongThread.entries.take(20)) {
            debugPrint('    ${e.key}  expected: ${e.value.$1}  got: ${e.value.$2}');
          }
        }
        debugPrint('');
        debugPrint('  Artifacts written to: ${artifactsDir.path}');
        debugPrint('    reference.pdf    — normal PDF render for visual comparison');
        debugPrint('    roundtrip_pk.pdf — exported PK PDF that was re-parsed');
        debugPrint('══════════════════════════════════════════');
        debugPrint('');

        // 10. Strict assertions.
        expect(missing, isEmpty,
            reason: '${missing.length}/$total stitches missing after round-trip');
        expect(extra, isEmpty,
            reason: '${extra.length} extra stitches after round-trip');
        expect(wrongThread, isEmpty,
            reason: '${wrongThread.length} stitches have wrong thread after round-trip');
        expect(missingThreads, isEmpty,
            reason: 'Threads missing from legend: $missingThreads');
      } finally {
        await tmpDir.delete(recursive: true);
        // Artifact dir is intentionally NOT deleted — open to inspect manually.
      }
    });
  });
}
