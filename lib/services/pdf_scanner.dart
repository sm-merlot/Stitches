import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// Rasterises a single page of a PDF file to PNG bytes at ~300 DPI.
class PdfScanner {
  PdfScanner._();

  static const _dpi = 300.0;

  /// Returns PNG-encoded bytes of [pageNumber] (1-based) from the PDF at [path].
  static Future<Uint8List> rasterisePage(String path, int pageNumber) async {
    final pages = await rasterisePages(path, [pageNumber]);
    return pages.first;
  }

  /// Returns PNG-encoded bytes for each page number in [pageNumbers] (1-based),
  /// in the order they are supplied.
  static Future<List<Uint8List>> rasterisePages(
      String path, List<int> pageNumbers) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final results = <Uint8List>[];
      for (final pageNumber in pageNumbers) {
        final pageIndex = (pageNumber - 1).clamp(0, doc.pages.length - 1);
        final page = doc.pages[pageIndex];

        final scale = _dpi / 72.0;
        final pdfImage = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          backgroundColor: 0xffffffff,
        );
        if (pdfImage == null) {
          throw Exception('Failed to render page $pageNumber.');
        }

        final uiImage = await pdfImage.createImage();
        pdfImage.dispose();

        final byteData =
            await uiImage.toByteData(format: ui.ImageByteFormat.png);
        uiImage.dispose();

        if (byteData == null) {
          throw Exception('Failed to encode page $pageNumber as PNG.');
        }
        final bytes = byteData.buffer.asUint8List();

        // DEBUG: save rasterised pages to disk for inspection.
        if (kDebugMode) {
          try {
            const debugDir = '/tmp/stitchx_pages';
            await Directory(debugDir).create(recursive: true);
            final pageNum = pageNumber.toString().padLeft(2, '0');
            await File('$debugDir/page_$pageNum.png').writeAsBytes(bytes);
            debugPrint('[PdfScanner] debug image saved: $debugDir/page_$pageNum.png');
          } catch (e) {
            debugPrint('[PdfScanner] debug save failed: $e');
          }
        }

        results.add(bytes);
      }
      return results;
    } finally {
      await doc.dispose();
    }
  }
}
