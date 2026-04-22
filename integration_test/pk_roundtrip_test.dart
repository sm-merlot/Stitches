/// Integration test: full PK PDF round-trip using real pdfium + rootBundle.
///
/// Requires a device (macOS/iOS/Android) so that:
///   • rootBundle can load font assets (needed by PdfService)
///   • pdfium native lib is linked (needed by PatternKeeperParser.tryParse)
///
/// Run with:
///   flutter test integration_test/pk_roundtrip_test.dart -d macos --no-pub
///
/// This test is NOT a plain `flutter test` test — it lives in integration_test/
/// and needs the full Flutter engine.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/test_fixtures.dart';

import 'package:stitches/models/stitch.dart';
import 'package:stitches/services/file_service.dart';
import 'package:stitches/services/pdf_pattern_keeper_parser.dart';
import 'package:stitches/services/pdf_service.dart';
import 'package:stitches/services/stitch_compositor.dart';

/// Flatten visible layers to a position→dmcCode map (full stitches only).
Map<(int, int), String> _flattenedStitchMap(dynamic pattern) {
  final result = StitchCompositor.compute(pattern);
  final map = <(int, int), String>{};
  for (final s in result.dedupedNonBack) {
    if (s is FullStitch) map[(s.x, s.y)] = s.threadId;
  }
  return map;
}

/// Position→dmcCode map from PatternScanResult stitches.
Map<(int, int), String> _scanStitchMap(dynamic result) => {
      for (final s in result.stitches) (s.x as int, s.y as int): s.dmcCode as String,
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Pdfrx.getCacheDirectory = () async =>
        Directory.systemTemp.createTemp('pdfrx_cache').then((d) => d.path);
  });

  group('PK PDF full round-trip (integration)', () {
    test('.stitches fixture → PK PDF → parse → same stitches', () async {
      final stitchesPath = testFixturePath('sm_test.stitches');
      expect(File(stitchesPath).existsSync(), isTrue,
          reason: 'fixture not found: $stitchesPath');

      // 1. Load fixture.
      final (original, _, _) = await FileService.openFileFromPath(stitchesPath);

      // 2. Flatten to ground truth.
      final expectedMap = _flattenedStitchMap(original);
      expect(expectedMap, isNotEmpty);

      // 3. Export → PK PDF bytes.
      final pdfBytes = await PdfService.buildPdfBytes(
        original,
        patternKeeperMode: true,
      );
      expect(pdfBytes.length, greaterThan(1000));

      // 4. Write to temp file.
      final tmpDir = await Directory.systemTemp.createTemp('pk_integration_');
      final tmpPdf = File(p.join(tmpDir.path, 'roundtrip.pdf'));
      await tmpPdf.writeAsBytes(pdfBytes);

      try {
        // 5. Re-parse.
        final parsed = await PatternKeeperParser.tryParse(tmpPdf.path);
        expect(parsed, isNotNull, reason: 'exported PDF should re-parse');

        // 6. Dimensions.
        expect(parsed!.width, equals(original.width));
        expect(parsed.height, equals(original.height));

        // 7. Stitch-by-stitch comparison.
        final parsedMap = _scanStitchMap(parsed);

        final missing = expectedMap.keys
            .where((pos) => !parsedMap.containsKey(pos))
            .toList();
        final extra = parsedMap.keys
            .where((pos) => !expectedMap.containsKey(pos))
            .toList();
        final wrong = <(int, int), (String, String)>{};
        for (final entry in expectedMap.entries) {
          if (parsedMap.containsKey(entry.key) &&
              parsedMap[entry.key] != entry.value) {
            wrong[entry.key] = (entry.value, parsedMap[entry.key]!);
          }
        }

        if (missing.isNotEmpty) {
          debugPrint('Missing ${missing.length} stitches (first 10): ${missing.take(10)}');
        }
        if (extra.isNotEmpty) {
          debugPrint('Extra ${extra.length} stitches (first 10): ${extra.take(10)}');
        }
        if (wrong.isNotEmpty) {
          debugPrint('Wrong thread at ${wrong.length} positions (first 10):');
          for (final e in wrong.entries.take(10)) {
            debugPrint('  ${e.key}: expected ${e.value.$1}, got ${e.value.$2}');
          }
        }

        // Linux pdfium deduplicates adjacent identical-symbol runs differently
        // from macOS, causing O(1–5) stitches per 57k to be missed. Allow a
        // small absolute tolerance so CI catches real regressions (≥10 missing)
        // without failing on platform rendering noise.
        const kMissingTolerance = 10;
        expect(missing.length, lessThanOrEqualTo(kMissingTolerance),
            reason: '${missing.length} stitches lost in round-trip '
                '(tolerance $kMissingTolerance)');
        expect(extra, isEmpty,
            reason: '${extra.length} extra stitches after round-trip');
        expect(wrong, isEmpty,
            reason: '${wrong.length} stitches changed thread in round-trip');

        // 8. Thread sets match.
        final expectedThreads = expectedMap.values.toSet();
        final parsedThreads = parsed.threads.map((t) => t.dmcCode).toSet();
        expect(parsedThreads, equals(expectedThreads));

        debugPrint(
          'Integration round-trip OK: ${expectedMap.length} stitches, '
          '${expectedThreads.length} threads',
        );
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });
}
