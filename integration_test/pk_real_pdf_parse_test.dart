/// Integration test: parse real-world copyrighted PatternKeeper PDFs.
///
/// These fixtures live in the private scme0/stitches-test-fixtures repo.
/// Locally: clone that repo as a sibling of this one.
/// CI: checked out via FIXTURES_TOKEN secret.
///
/// Assertions are intentionally minimal — parser support for these PDFs is
/// in progress. Add dimension/stitch-count expectations once each file parses
/// correctly.
///
/// Run with:
///   flutter test integration_test/pk_real_pdf_parse_test.dart -d macos --no-pub
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/test_fixtures.dart';

import 'package:stitches/services/pdf_pattern_keeper_parser.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Pdfrx.getCacheDirectory = () async =>
        Directory.systemTemp.createTemp('pdfrx_cache').then((d) => d.path);
  });

  group('PK parser — real-world PDFs', () {
    for (final filename in ['Artecy-church.pdf', 'HAED-galaxy.pdf']) {
      test('$filename — fixture reachable and parse attempted', () async {
        final path = testFixturePath(filename);
        expect(File(path).existsSync(), isTrue,
            reason: 'fixture not found: $path');

        final result = await PatternKeeperParser.tryParse(path);

        if (result == null) {
          debugPrint('[$filename] parser returned null — not yet supported');
        } else {
          debugPrint('[$filename] ${result.width}×${result.height}, '
              '${result.stitches.length} stitches, '
              '${result.threads.length} threads'
              '${result.warning != null ? ', WARNING: ${result.warning}' : ''}');
          for (final t in result.threads) {
            debugPrint('  thread ${t.dmcCode} ${t.name}');
          }
        }

        // TODO: once parser supports these files, replace with:
        //   expect(result, isNotNull);
        //   expect(result!.width, <known width>);
        //   expect(result.height, <known height>);
        //   expect(result.stitches.length, greaterThan(<min count>));
      });
    }
  });
}
