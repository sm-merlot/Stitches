/// Standalone diagnostic script: dumps pdfrx text extraction for PK PDFs.
/// Run with: flutter test test/pk_pdf_inspect.dart --no-pub
///
/// Usage: edit [kPdfPaths] below, then run.
// ignore_for_file: avoid_print
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

// ── Edit these paths ─────────────────────────────────────────────────────────
const kPdfPaths = [
  'test/fixtures/pdfs/Super Metroid - Samus battles Ridley_PatternKeeper.pdf',
  'test/fixtures/pdfs/Dachshund-PK.pdf',
];
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    Pdfrx.cacheDirectoryPath =
        (await Directory.systemTemp.createTemp('pdfrx_cache')).path;
  });

  for (final path in kPdfPaths) {
    test('inspect: $path', () async {
      PdfDocument? doc;
      try {
        doc = await PdfDocument.openFile(path);
        print('\n════════════════════════════════════════');
        print('FILE: $path');
        print('Pages: ${doc.pages.length}');

        for (int pi = 0; pi < min(doc.pages.length, 5); pi++) {
          final page = doc.pages[pi];
          final pt = await page.loadStructuredText();
          print('\n── Page ${pi + 1} ─────────────────────');
          print('fullText length: ${pt.fullText.length}');

          // Print first 500 chars of fullText
          final preview = pt.fullText.length > 500
              ? pt.fullText.substring(0, 500)
              : pt.fullText;
          print('fullText preview:\n$preview');

          // Print all fragments with bounds
          print('\nAll fragments (first 40):');
          for (int fi = 0; fi < min(pt.fragments.length, 40); fi++) {
            final f = pt.fragments[fi];
            final text = f.text;
            final runes = text.runes
                .map((r) => 'U+${r.toRadixString(16).padLeft(4, '0')}')
                .join(' ');
            print(
                '  [$fi] "${text.replaceAll('\n', '\\n')}" bounds=(${f.bounds.left.toStringAsFixed(1)},${f.bounds.top.toStringAsFixed(1)},${f.bounds.right.toStringAsFixed(1)},${f.bounds.bottom.toStringAsFixed(1)}) runes=$runes');
          }
          if (pt.fragments.length > 40) {
            print('  ... and ${pt.fragments.length - 40} more fragments');
          }

          // Check for PKCHART in fullText
          final pkMatch = RegExp(r'PKCHART:[\d,]+').firstMatch(pt.fullText);
          if (pkMatch != null) {
            print('\nPKCHART found in fullText: "${pkMatch.group(0)}"');
          } else {
            // Also check individual fragments
            bool foundInFrag = false;
            for (final f in pt.fragments) {
              if (f.text.contains('PKCHART')) {
                print('\nPKCHART found in fragment: "${f.text}"');
                foundInFrag = true;
              }
            }
            if (!foundInFrag) {
              print('\nNo PKCHART marker on page ${pi + 1}');
            }
          }
        }
      } catch (e, st) {
        print('ERROR: $e\n$st');
      } finally {
        await doc?.dispose();
      }
    });
  }
}
