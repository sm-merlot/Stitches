import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'app.dart';
import 'services/file_service.dart';
import 'services/incoming_file_service.dart';
import 'services/pdf_pattern_keeper_parser.dart';
import 'services/pdf_service.dart';
import 'services/scan_result.dart';

// Flutter on Windows uses BoringSSL with bundled root certs instead of the
// Windows certificate store, causing TLS failures against Google endpoints.
// This override trusts the platform certs on Windows only.
class _WindowsHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) =>
          defaultTargetPlatform == TargetPlatform.windows;
  }
}

void main(List<String> args) async {
  // ── CLI mode ──────────────────────────────────────────────────────────────
  // Allows headless testing of PDF import/export from the command line.
  //
  //   --import-pdf <path>   Parse a PK PDF, print JSON result to stdout.
  //   --inspect-pdf <path>  Dump raw pdfrx text fragments for debugging.
  //
  // Usage (debug build):
  //   flutter run -d macos --dart-entrypoint-args='--import-pdf,/path/to/file.pdf'
  //
  // Usage (release/debug binary):
  //   ./Stitches.app/Contents/MacOS/Stitches --import-pdf /path/to/file.pdf
  final importIdx = args.indexOf('--import-pdf');
  final inspectIdx = args.indexOf('--inspect-pdf');
  final exportIdx = args.indexOf('--export-pk-pdf');

  if (importIdx >= 0 || inspectIdx >= 0 || exportIdx >= 0) {
    // Redirect debugPrint to stderr so [PKParser] messages are visible.
    debugPrint = (String? message, {int? wrapWidth}) {
      stderr.writeln(message ?? '');
    };

    WidgetsFlutterBinding.ensureInitialized();

    // pdfrx requires a cache directory before opening any document.
    Pdfrx.getCacheDirectory = () async =>
        (await getTemporaryDirectory()).path;

    if (inspectIdx >= 0 && inspectIdx + 1 < args.length) {
      await _cliInspectPdf(args[inspectIdx + 1]);
    } else if (importIdx >= 0 && importIdx + 1 < args.length) {
      await _cliImportPdf(args[importIdx + 1]);
    } else if (exportIdx >= 0 && exportIdx + 2 < args.length) {
      await _cliExportPkPdf(args[exportIdx + 1], args[exportIdx + 2]);
    } else {
      stderr.writeln('Usage:');
      stderr.writeln('  --import-pdf <path>');
      stderr.writeln('  --inspect-pdf <path>');
      stderr.writeln('  --export-pk-pdf <stitches_path> <output_pdf_path>');
      exit(2);
    }
    return;
  }

  // ── Normal app mode ───────────────────────────────────────────────────────
  if (defaultTargetPlatform == TargetPlatform.windows) {
    HttpOverrides.global = _WindowsHttpOverrides();
  }
  WidgetsFlutterBinding.ensureInitialized();
  IncomingFileService.listen();
  runApp(
    const ProviderScope(
      child: StitchesApp(),
    ),
  );
}

// ── CLI helpers ───────────────────────────────────────────────────────────────

Future<void> _cliImportPdf(String pdfPath) async {
  final result = await PatternKeeperParser.tryParse(pdfPath);
  if (result == null) {
    stdout.writeln(jsonEncode({'error': 'not_pk_format', 'path': pdfPath}));
    exit(1);
  }
  stdout.writeln(jsonEncode(_scanResultToJson(result)));
  exit(0);
}

Future<void> _cliInspectPdf(String pdfPath) async {
  // Dump raw pdfrx text fragments then run the parser.
  // Both outputs go to stdout as a JSON object; [PKParser] debug lines → stderr.
  final pages = await PatternKeeperParser.extractPageText(pdfPath);
  if (pages == null) {
    stdout.writeln(jsonEncode({'error': 'could_not_open', 'path': pdfPath}));
    exit(1);
  }

  final pagesJson = pages.asMap().entries.map((e) {
    final pi = e.key;
    final page = e.value;
    if (page == null) return {'page': pi, 'error': 'extraction_failed'};
    return {
      'page': pi,
      'charCount': page.fullText.length,
      'fragmentCount': page.fragments.length,
      'fullTextPreview': page.fullText.length > 300
          ? page.fullText.substring(0, 300)
          : page.fullText,
      'fragments': page.fragments.take(60).map((f) => {
            'text': f.text,
            'codepoints': f.text.runes
                .map((r) => 'U+${r.toRadixString(16).padLeft(4, '0').toUpperCase()}')
                .toList(),
            'left': f.left,
            'top': f.top,
            'right': f.right,
            'bottom': f.bottom,
          }).toList(),
      if (page.fragments.length > 60)
        'fragmentsTruncated': page.fragments.length - 60,
    };
  }).toList();

  // Also run the parser so parse result is included.
  final result = PatternKeeperParser.tryParseFromText(pages);

  stdout.writeln(jsonEncode({
    'path': pdfPath,
    'pages': pagesJson,
    'parseResult': result == null
        ? null
        : {
            'width': result.width,
            'height': result.height,
            'threadCount': result.threads.length,
            'stitchCount': result.stitches.length,
          },
  }));
  exit(result == null ? 1 : 0);
}

Future<void> _cliExportPkPdf(String stitchesPath, String outputPdfPath) async {
  final content = File(stitchesPath).readAsStringSync();
  final pattern = FileService.parseYamlString(content);
  final bytes = await PdfService.buildPdfBytes(
    pattern,
    patternKeeperMode: true,
  );
  File(outputPdfPath).writeAsBytesSync(bytes);
  stderr.writeln('[export] wrote ${bytes.length} bytes → $outputPdfPath');
  stdout.writeln(jsonEncode({'exported': outputPdfPath, 'patternWidth': pattern.width, 'patternHeight': pattern.height}));
  exit(0);
}

Map<String, dynamic> _scanResultToJson(PatternScanResult r) => {
      'width': r.width,
      'height': r.height,
      'threadCount': r.threads.length,
      'stitchCount': r.stitches.length,
      'threads': r.threads
          .map((t) => {'dmcCode': t.dmcCode, 'name': t.name, 'colorHex': t.colorHex})
          .toList(),
      'stitches': r.stitches
          .map((s) => {
                'x': s.x,
                'y': s.y,
                'type': s.type,
                'dmcCode': s.dmcCode,
                if (s.x2 != null) 'x2': s.x2,
                if (s.y2 != null) 'y2': s.y2,
              })
          .toList(),
      if (r.warning != null) 'warning': r.warning,
    };

