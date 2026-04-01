import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/aida_presets.dart';
import '../data/dmc_colors.dart';
import '../data/symbols.dart';
import '../models/layer_blend_mode.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import 'skein_calculator.dart';
import 'sprite_importer.dart';

typedef _PdfFonts = ({
  PdfFont regular,
  PdfFont bold,
  PdfFont italic,
  PdfFont symbol
});
typedef _TextRun = ({String text, bool bold, bool italic, bool sym});

class PdfService {
  /// Generate PDF and save via file picker.
  static Future<void> exportPattern(
    CrossStitchPattern pattern, {
    bool useDmc = true,
  }) async {
    final doc = pw.Document(title: pattern.name);
    final fonts = (
      regular: PdfTtfFont(doc.document,
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')),
      bold: PdfTtfFont(doc.document,
          await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')),
      italic: PdfTtfFont(doc.document,
          await rootBundle.load('assets/fonts/NotoSans-Italic.ttf')),
      symbol: PdfTtfFont(doc.document,
          await rootBundle.load('assets/fonts/NotoSansSymbols2-Regular.ttf')),
    ) as _PdfFonts;

    // ── Data prep ──────────────────────────────────────────────────────────

    final threadMap = {for (final t in pattern.threads) t.dmcCode: t};

    // Composite non-back stitches across visible layers: deduplicates FullStitches
    // at the same cell using each layer's blend mode — matches 'stitch mode' canvas.
    final (:nonBack, :blendedColors) = _compositeNonBack(pattern, threadMap);

    // For blended cells, snap to the nearest-DMC colour and symbol so the PDF
    // grid matches the canvas composite view exactly. The raw blend colour
    // (blendedColors) is kept as a fallback only when matchPixel fails.
    final blendedCellColors = <String, Color>{};
    final blendedCellSymbols = <String, String>{};
    for (final entry in blendedColors.entries) {
      final c = entry.value;
      final r = (c.r * 255).round();
      final g = (c.g * 255).round();
      final b = (c.b * 255).round();
      final dmc = SpriteImporter.matchPixel(r, g, b, 255);
      if (dmc != null) {
        blendedCellColors[entry.key] = dmc.color; // exact DMC colour, not raw blend
        final sym = pattern.compositeSymbols[dmc.code] ?? '';
        if (symbolIsVisible(sym) && !kPdfUnsupportedSymbols.contains(sym)) {
          blendedCellSymbols[entry.key] = sym;
        }
      }
    }

    // Backstitches: no deduplication needed (backstitches never fully occlude).
    final backstitches = pattern.layers
        .where((l) => l.visible)
        .expand((l) => l.stitches)
        .whereType<BackStitch>()
        .toList();

    // Stitch counts from all raw layer stitches — not the deduped composites —
    // so every thread (including blend-layer overlays) gets a correct count.
    final crossStitchEquiv = <String, double>{};
    final backStitchEquiv = <String, double>{};
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final s in layer.stitches) {
        if (s is BackStitch) {
          final v = math.sqrt(
              math.pow(s.x2 - s.x1, 2) + math.pow(s.y2 - s.y1, 2));
          backStitchEquiv[s.threadId] =
              (backStitchEquiv[s.threadId] ?? 0) + v;
        } else {
          final v = switch (s) {
            FullStitch() => 1.0,
            HalfStitch() => 0.5,
            HalfCrossStitch() => 0.5,
            QuarterStitch() => 0.25,
            QuarterCrossStitch() => 0.25,
            BackStitch() => 0.0, // unreachable
          };
          if (v > 0) {
            crossStitchEquiv[s.threadId] =
                (crossStitchEquiv[s.threadId] ?? 0) + v;
          }
        }
      }
    }

    // Threads that have cross-type stitches / backstitches respectively,
    // sorted by DMC number so colour tables are easy to reference.
    int dmcSort(Thread a, Thread b) {
      final ia = int.tryParse(a.dmcCode) ?? 999999;
      final ib = int.tryParse(b.dmcCode) ?? 999999;
      return ia != ib ? ia.compareTo(ib) : a.dmcCode.compareTo(b.dmcCode);
    }

    final crossThreads = pattern.threads
        .where((t) => crossStitchEquiv.containsKey(t.dmcCode))
        .toList()
      ..sort(dmcSort);
    final backThreads = pattern.threads
        .where((t) => backStitchEquiv.containsKey(t.dmcCode))
        .toList()
      ..sort(dmcSort);

    // Build per-export symbol map
    final pdfSymbols = _buildPdfSymbolMap([
      ...crossThreads,
      ...backThreads.where((t) => !crossThreads.any((c) => c.dmcCode == t.dmcCode)),
    ]);

    // ── Page layout constants ───────────────────────────────────────────────
    const pageFormat = PdfPageFormat.a4; // portrait
    const margin = 40.0;
    const rulerW = 24.0;
    const rulerH = 16.0;
    const headerH = 44.0;
    const footerH = 20.0;

    final usableW = pageFormat.width - 2 * margin - rulerW;
    final usableH = pageFormat.height - 2 * margin - headerH - footerH - rulerH;

    final cellByW = usableW / pattern.width;
    final cellByH = usableH / pattern.height;
    // Target: fill the page comfortably. Clamp 4–12 pt per cell.
    final cellSize = math.min(12.0, math.max(4.0, math.min(cellByW, cellByH)));

    final colsPerPage = (usableW / cellSize).floor().clamp(1, pattern.width);
    final rowsPerPage = (usableH / cellSize).floor().clamp(1, pattern.height);
    final pagesCols = (pattern.width / colsPerPage).ceil();
    final pagesRows = (pattern.height / rowsPerPage).ceil();
    final totalGridPages = pagesCols * pagesRows;

    // ── Thread table pagination ─────────────────────────────────────────────
    // How many rows fit in one column of a colour table page
    const tableRowH = 14.0;
    const tableHeadRowH = 16.0;
    const tableSectionHeadH = 9.0 + 6.0; // sectionHeadFs + gap
    final tableUsableH =
        pageFormat.height - 2 * margin - headerH - footerH - tableSectionHeadH - tableHeadRowH;
    final rowsPerCol = (tableUsableH / tableRowH).floor().clamp(1, 9999);

    int tablePageCount(List<Thread> threads) {
      if (threads.isEmpty) return 0;
      if (threads.length <= rowsPerCol) return 1;
      return (threads.length / (rowsPerCol * 2)).ceil();
    }

    final crossTablePageCount = tablePageCount(crossThreads).clamp(1, 9999);
    final backTablePageCount = tablePageCount(backThreads);
    final colourTablePages = crossTablePageCount + backTablePageCount;
    final totalPages = 1 + colourTablePages + totalGridPages;

    // ── Page 1: Title page ────────────────────────────────────────────────

    final titlePage = PdfPage(doc.document, pageFormat: pageFormat);
    _drawTitlePage(
      titlePage.getGraphics(),
      page: titlePage,
      format: pageFormat,
      pattern: pattern,
      nonBack: nonBack,
      backstitches: backstitches,
      threadMap: threadMap,
      blendedColors: blendedColors,
      margin: margin,
      footerH: footerH,
      pageNum: 1,
      totalPages: totalPages,
      fonts: fonts,
    );

    // ── Cross stitch colour table pages ───────────────────────────────────

    PdfGraphics? lastTableCanvas;
    double lastTableY = 0;

    for (int i = 0; i < crossTablePageCount; i++) {
      final pageNum = 2 + i;
      final List<Thread> pageThreads;
      final bool twoCol;
      if (crossThreads.length <= rowsPerCol) {
        pageThreads = crossThreads;
        twoCol = false;
      } else {
        final threadsPerPage = rowsPerCol * 2;
        final start = i * threadsPerPage;
        final end = math.min(start + threadsPerPage, crossThreads.length);
        pageThreads = crossThreads.sublist(start, end);
        final remaining = crossThreads.length - start;
        twoCol = remaining > rowsPerCol;
      }
      final crossTablePage = PdfPage(doc.document, pageFormat: pageFormat);
      final crossCanvas = crossTablePage.getGraphics();
      lastTableY = _drawColourTablePage(
        crossCanvas,
        format: pageFormat,
        pattern: pattern,
        threads: pageThreads,
        stitchEquiv: crossStitchEquiv,
        isBackstitch: false,
        twoColumn: twoCol,
        pdfSymbols: pdfSymbols,
        margin: margin,
        headerH: headerH,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        fonts: fonts,
      );
      lastTableCanvas = crossCanvas;
    }

    // ── Backstitch colour table pages (optional) ──────────────────────────

    for (int i = 0; i < backTablePageCount; i++) {
      final pageNum = 2 + crossTablePageCount + i;
      final List<Thread> pageThreads;
      final bool twoCol;
      if (backThreads.length <= rowsPerCol) {
        pageThreads = backThreads;
        twoCol = false;
      } else {
        final threadsPerPage = rowsPerCol * 2;
        final start = i * threadsPerPage;
        final end = math.min(start + threadsPerPage, backThreads.length);
        pageThreads = backThreads.sublist(start, end);
        final remaining = backThreads.length - start;
        twoCol = remaining > rowsPerCol;
      }
      final backTablePage = PdfPage(doc.document, pageFormat: pageFormat);
      final backCanvas = backTablePage.getGraphics();
      lastTableY = _drawColourTablePage(
        backCanvas,
        format: pageFormat,
        pattern: pattern,
        threads: pageThreads,
        stitchEquiv: backStitchEquiv,
        isBackstitch: true,
        twoColumn: twoCol,
        pdfSymbols: pdfSymbols,
        margin: margin,
        headerH: headerH,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        fonts: fonts,
      );
      lastTableCanvas = backCanvas;
    }

    // ── Materials section (optional) ──────────────────────────────────────

    if (pattern.materialsSuggestions.isNotEmpty && lastTableCanvas != null) {
      final allThreads = [...crossThreads, ...backThreads]
          .fold<Map<String, Thread>>({}, (m, t) => m..[t.dmcCode] = t)
          .values
          .toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.dmcCode) ?? 999999;
          final ib = int.tryParse(b.dmcCode) ?? 999999;
          return ia != ib ? ia.compareTo(ib) : a.dmcCode.compareTo(b.dmcCode);
        });

      final enoughRoom = lastTableY - margin - footerH >= 120;
      final materialsCanvas = enoughRoom
          ? lastTableCanvas
          : PdfPage(doc.document, pageFormat: pageFormat).getGraphics();
      final materialsStartY = enoughRoom
          ? lastTableY
          : pageFormat.height - margin - headerH;

      _drawMaterialsSection(
        doc: doc.document,
        canvas: materialsCanvas,
        format: pageFormat,
        pattern: pattern,
        threads: allThreads,
        crossEquiv: crossStitchEquiv,
        backCells: backStitchEquiv,
        useDmc: useDmc,
        pdfSymbols: pdfSymbols,
        y: materialsStartY,
        margin: margin,
        headerH: headerH,
        footerH: footerH,
        pageNum: 1 + colourTablePages + 1,
        totalPages: totalPages,
        fonts: fonts,
        drawInitialFooter: !enoughRoom,
      );
    }

    // ── Chart pages ───────────────────────────────────────────────────────

    final chartPageOffset = 1 + colourTablePages + 1; // 1-based
    for (int pr = 0; pr < pagesRows; pr++) {
      for (int pc = 0; pc < pagesCols; pc++) {
        final startX = pc * colsPerPage;
        final startY = pr * rowsPerPage;
        final endX = math.min(startX + colsPerPage, pattern.width);
        final endY = math.min(startY + rowsPerPage, pattern.height);
        final pageNum = chartPageOffset + pr * pagesCols + pc;

        final page = PdfPage(doc.document, pageFormat: pageFormat);
        final canvas = page.getGraphics();

        _drawChartPage(
          canvas,
          format: pageFormat,
          pattern: pattern,
          nonBack: nonBack,
          backstitches: backstitches,
          threadMap: threadMap,
          blendedColors: blendedColors,
          blendedCellColors: blendedCellColors,
          blendedCellSymbols: blendedCellSymbols,
          pdfSymbols: pdfSymbols,
          cellSize: cellSize,
          startX: startX,
          startY: startY,
          endX: endX,
          endY: endY,
          margin: margin,
          rulerW: rulerW,
          rulerH: rulerH,
          headerH: headerH,
          footerH: footerH,
          pageNum: pageNum,
          totalPages: totalPages,
          fonts: fonts,
        );
      }
    }

    // ── Save ───────────────────────────────────────────────────────────────

    final bytes = await doc.save();
    final suggestedName = pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final path = await FilePicker.platform.saveFile(
      fileName: isMobile ? '$suggestedName.pdf' : suggestedName,
      type: isMobile ? FileType.any : FileType.custom,
      allowedExtensions: isMobile ? null : ['pdf'],
    );
    if (path == null) return;
    final finalPath = path.endsWith('.pdf') ? path : '$path.pdf';
    await File(finalPath).writeAsBytes(bytes);
  }

  // ── Chart page ────────────────────────────────────────────────────────────

  static void _drawChartPage(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Stitch> nonBack,
    required List<BackStitch> backstitches,
    required Map<String, Thread> threadMap,
    required Map<String, Color> blendedColors,
    required Map<String, Color> blendedCellColors,
    required Map<String, String> blendedCellSymbols,
    required Map<String, String> pdfSymbols,
    required double cellSize,
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    required double margin,
    required double rulerW,
    required double rulerH,
    required double headerH,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required _PdfFonts fonts,
  }) {
    final cols = endX - startX;
    final rows = endY - startY;
    final gridW = cols * cellSize;
    final gridH = rows * cellSize;

    // Grid origin (bottom-left in PDF coords; y=0 is page bottom).
    // Sits below the header+rulerH, to the right of the left row-ruler.
    final gridOriginX = margin + rulerW;
    final gridOriginY = format.height - margin - headerH - rulerH - gridH;

    // ── Header ───────────────────────────────────────────────────────────
    _drawPageHeader(
      canvas,
      format: format,
      pattern: pattern,
      margin: margin,
      headerH: headerH,
      subtitle:
          'Cols ${startX + 1}-$endX, Rows ${startY + 1}-$endY  |  Page $pageNum of $totalPages',
      fonts: fonts,
    );

    // ── Aida background ──────────────────────────────────────────────────
    canvas.setFillColor(_pdfColor(pattern.aidaColor));
    canvas.drawRect(gridOriginX, gridOriginY, gridW, gridH);
    canvas.fillPath();

    // ── Stitch fills (each stitch drawn individually, preserving partial shapes) ─
    for (final s in nonBack) {
      final cx = _stitches(s);
      final cy = _stitchY(s);
      if (cx < startX || cx >= endX || cy < startY || cy >= endY) continue;
      final thread = threadMap[s.threadId];
      if (thread == null) continue;

      final gx = gridOriginX + (cx - startX) * cellSize;
      final gy = gridOriginY + (rows - (cy - startY) - 1) * cellSize;

      final cellKey = '$cx,$cy';
      // Use nearest-DMC colour (matches canvas), falling back to raw blend or
      // the source thread colour when no nearest-DMC match was found.
      final effectiveColor =
          blendedCellColors[cellKey] ?? blendedColors[cellKey] ?? thread.color;
      canvas.setFillColor(_pdfColor(effectiveColor));
      _fillStitch(canvas, s, gx, gy, cellSize);

      // Symbol centred in the stitch's sub-region (shown when sub-region >= 4 pt).
      // Blended cells use the composite symbol so the PDF grid matches the canvas.
      final sym = blendedCellSymbols[cellKey] ?? pdfSymbols[thread.dmcCode] ?? '';
      if (symbolIsVisible(sym)) {
        final subSize = _stitchSubRegionSize(s, cellSize);
        if (subSize >= 4) {
          final (sx, sy) = _stitchSymbolCenter(s, gx, gy, cellSize);
          final lum = effectiveColor.computeLuminance();
          final textColor = lum > 0.35 ? PdfColors.black : PdfColors.white;
          final fs = math.max(3.5, subSize * 0.44);
          canvas.setFillColor(textColor);
          final symFont = _fontFor(sym, fonts.regular, fonts.symbol);
          canvas.drawString(symFont, fs, sym,
              sx - _textWidth(symFont, fs, sym) / 2, sy - fs * 0.35);
        }
      }
    }

    // ── Backstitch lines (drawn above fills, before grid lines) ──────────
    canvas.setLineWidth(math.max(0.6, cellSize * 0.15));
    for (final bs in backstitches) {
      final minBx = math.min(bs.x1, bs.x2);
      final maxBx = math.max(bs.x1, bs.x2);
      final minBy = math.min(bs.y1, bs.y2);
      final maxBy = math.max(bs.y1, bs.y2);
      if (maxBx < startX || minBx > endX || maxBy < startY || minBy > endY) {
        continue;
      }
      final thread = threadMap[bs.threadId];
      if (thread == null) continue;
      canvas.setStrokeColor(_pdfColor(thread.color));
      final px1 = gridOriginX + (bs.x1 - startX) * cellSize;
      final py1 = gridOriginY + (rows - (bs.y1 - startY)) * cellSize;
      final px2 = gridOriginX + (bs.x2 - startX) * cellSize;
      final py2 = gridOriginY + (rows - (bs.y2 - startY)) * cellSize;
      canvas.moveTo(px1, py1);
      canvas.lineTo(px2, py2);
      canvas.strokePath();
    }

    // ── Minor grid lines ─────────────────────────────────────────────────
    canvas.setStrokeColor(PdfColors.grey500);
    canvas.setLineWidth(0.2);
    for (int c = 0; c <= cols; c++) {
      final x = gridOriginX + c * cellSize;
      canvas.moveTo(x, gridOriginY);
      canvas.lineTo(x, gridOriginY + gridH);
      canvas.strokePath();
    }
    for (int r = 0; r <= rows; r++) {
      final y = gridOriginY + r * cellSize;
      canvas.moveTo(gridOriginX, y);
      canvas.lineTo(gridOriginX + gridW, y);
      canvas.strokePath();
    }

    // ── Bold lines every 10 cells ────────────────────────────────────────
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.6);
    for (int c = 0; c <= cols; c++) {
      if ((startX + c) % 10 == 0) {
        final x = gridOriginX + c * cellSize;
        canvas.moveTo(x, gridOriginY);
        canvas.lineTo(x, gridOriginY + gridH);
        canvas.strokePath();
      }
    }
    for (int r = 0; r <= rows; r++) {
      if ((startY + r) % 10 == 0) {
        final y = gridOriginY + r * cellSize;
        canvas.moveTo(gridOriginX, y);
        canvas.lineTo(gridOriginX + gridW, y);
        canvas.strokePath();
      }
    }

    // ── Outer border ─────────────────────────────────────────────────────
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    canvas.drawRect(gridOriginX, gridOriginY, gridW, gridH);
    canvas.strokePath();

    // ── Column ruler (above grid) ────────────────────────────────────────
    const rulerFs = 5.5;
    canvas.setFillColor(PdfColors.grey700);
    canvas.setStrokeColor(PdfColors.grey600);
    canvas.setLineWidth(0.4);
    for (int c = 0; c <= cols; c++) {
      final col = startX + c;
      if (col % 10 == 0 && col > 0) {
        final x = gridOriginX + c * cellSize;
        final label = '$col';
        final lw = label.length * rulerFs * 0.55;
        canvas.drawString(
            fonts.regular, rulerFs, label, x - lw / 2, gridOriginY + gridH + 3.5);
        canvas.moveTo(x, gridOriginY + gridH);
        canvas.lineTo(x, gridOriginY + gridH + 3);
        canvas.strokePath();
      }
    }

    // ── Row ruler (left of grid) ──────────────────────────────────────────
    for (int r = 0; r <= rows; r++) {
      final row = startY + r;
      if (row % 10 == 0 && row > 0) {
        final y = gridOriginY + gridH - r * cellSize;
        final label = '$row';
        final lw = label.length * rulerFs * 0.55;
        canvas.setFillColor(PdfColors.grey700);
        canvas.drawString(
            fonts.regular, rulerFs, label, gridOriginX - lw - 4, y - rulerFs / 2);
        canvas.setStrokeColor(PdfColors.grey600);
        canvas.setLineWidth(0.4);
        canvas.moveTo(gridOriginX - 3, y);
        canvas.lineTo(gridOriginX, y);
        canvas.strokePath();
      }
    }

    // ── Footer ───────────────────────────────────────────────────────────
    _drawPageFooter(canvas,
        format: format,
        margin: margin,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        fonts: fonts,
        copyright: pattern.copyright);
  }

  // ── Colour table page ─────────────────────────────────────────────────────

  static double _drawColourTablePage(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Thread> threads,
    required Map<String, double> stitchEquiv,
    required bool isBackstitch,
    required bool twoColumn,
    required Map<String, String> pdfSymbols,
    required double margin,
    required double headerH,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required _PdfFonts fonts,
  }) {
    final subtitle = isBackstitch
        ? 'Backstitch Colour Table  |  Page $pageNum of $totalPages'
        : 'Cross Stitch Colour Table  |  Page $pageNum of $totalPages';

    _drawPageHeader(
      canvas,
      format: format,
      pattern: pattern,
      margin: margin,
      headerH: headerH,
      subtitle: subtitle,
      fonts: fonts,
    );

    const tableFs = 7.5;
    const rowH = 14.0;
    const headRowH = 16.0;
    const sectionHeadFs = 9.0;
    const swatchW = 22.0;
    const dmcW = 44.0;
    const countW = 60.0;
    const gutterW = 12.0;
    final tableW = format.width - 2 * margin;

    final startY = format.height - margin - headerH;

    // Section heading
    final sectionLabel = isBackstitch ? 'Backstitches' : 'Cross Stitches';
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(
        fonts.bold, sectionHeadFs, sectionLabel, margin, startY - sectionHeadFs);

    final contentTopY = startY - sectionHeadFs - 6;
    final countHeader = isBackstitch ? 'Units' : 'Stitches';

    double finalY;

    if (!twoColumn) {
      // ── Single column ───────────────────────────────────────────────────
      final nameW = tableW - swatchW - dmcW - countW;
      final colWidths = [swatchW, dmcW, nameW, countW];

      _drawTableRow(canvas,
          x: margin,
          y: contentTopY,
          colWidths: colWidths,
          rowH: headRowH,
          bgColor: PdfColors.grey200,
          cells: ['', 'DMC', 'Name', countHeader],
          fonts: fonts,
          fontSize: tableFs,
          isHeader: true);
      double y = contentTopY - headRowH;

      for (final t in threads) {
        _drawThreadRow(canvas,
            x: margin,
            y: y,
            colWidths: colWidths,
            rowH: rowH,
            t: t,
            stitchEquiv: stitchEquiv,
            isBackstitch: isBackstitch,
            pdfSymbols: pdfSymbols,
            fonts: fonts,
            tableFs: tableFs);
        y -= rowH;
      }
      finalY = y;
    } else {
      // ── Two columns ─────────────────────────────────────────────────────
      final colW = (tableW - gutterW) / 2;
      final nameW = colW - swatchW - dmcW - countW;
      final colWidths = [swatchW, dmcW, nameW, countW];

      final mid = (threads.length / 2).ceil();
      final leftThreads = threads.sublist(0, mid);
      final rightThreads = threads.sublist(mid);

      for (int col = 0; col < 2; col++) {
        final colThreads = col == 0 ? leftThreads : rightThreads;
        if (colThreads.isEmpty) continue;
        final x = margin + col * (colW + gutterW);

        _drawTableRow(canvas,
            x: x,
            y: contentTopY,
            colWidths: colWidths,
            rowH: headRowH,
            bgColor: PdfColors.grey200,
            cells: ['', 'DMC', 'Name', countHeader],
            fonts: fonts,
            fontSize: tableFs,
            isHeader: true);
        double y = contentTopY - headRowH;

        for (final t in colThreads) {
          _drawThreadRow(canvas,
              x: x,
              y: y,
              colWidths: colWidths,
              rowH: rowH,
              t: t,
              stitchEquiv: stitchEquiv,
              isBackstitch: isBackstitch,
              pdfSymbols: pdfSymbols,
              fonts: fonts,
              tableFs: tableFs);
          y -= rowH;
        }
      }
      // Final y = left column bottom (deepest column)
      finalY = contentTopY - headRowH - leftThreads.length * rowH;
    }

    _drawPageFooter(canvas,
        format: format,
        margin: margin,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        fonts: fonts,
        copyright: pattern.copyright);

    return finalY;
  }

  // ── Draw a single thread data row ────────────────────────────────────────

  static void _drawThreadRow(
    PdfGraphics canvas, {
    required double x,
    required double y,
    required List<double> colWidths,
    required double rowH,
    required Thread t,
    required Map<String, double> stitchEquiv,
    required bool isBackstitch,
    required Map<String, String> pdfSymbols,
    required _PdfFonts fonts,
    required double tableFs,
  }) {
    final equiv = stitchEquiv[t.dmcCode] ?? 0;
    final equivStr = isBackstitch
        ? equiv.toStringAsFixed(1)
        : (equiv == equiv.truncateToDouble()
            ? equiv.toInt().toString()
            : equiv.toStringAsFixed(1));
    if (isBackstitch) {
      _drawTableRow(canvas,
          x: x,
          y: y,
          colWidths: colWidths,
          rowH: rowH,
          bgColor: null,
          cells: ['', t.dmcCode, t.name, equivStr],
          fonts: fonts,
          fontSize: tableFs,
          isHeader: false,
          linePreviewColor: _pdfColor(t.color));
    } else {
      _drawTableRow(canvas,
          x: x,
          y: y,
          colWidths: colWidths,
          rowH: rowH,
          bgColor: null,
          cells: ['', t.dmcCode, t.name, equivStr],
          fonts: fonts,
          fontSize: tableFs,
          isHeader: false,
          swatchColor: _pdfColor(t.color),
          swatchSymbol: pdfSymbols[t.dmcCode] ?? '');
    }
  }

  // ── Title page ────────────────────────────────────────────────────────────

  static void _drawTitlePage(
    PdfGraphics canvas, {
    required PdfPage page,
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Stitch> nonBack,
    required List<BackStitch> backstitches,
    required Map<String, Thread> threadMap,
    required Map<String, Color> blendedColors,
    required double margin,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required _PdfFonts fonts,
  }) {
    const titleFs = 18.0;
    const subtitleFs = 9.0;
    const titleBlockH = titleFs + 5 + subtitleFs + 12;
    const metaRowH = 13.0;
    const metaSwatchSize = 14.0;
    const metaGap = 8.0;

    final pageW = format.width;
    final pageH = format.height;
    final usableW = pageW - 2 * margin;

    // ── Estimate metadata block height ───────────────────────────────────
    final hasMetadata = pattern.designer != null ||
        pattern.difficulty != null ||
        pattern.estimatedHours != null ||
        pattern.description != null ||
        pattern.copyright != null;

    double metaBlockH = 0;
    if (hasMetadata) {
      metaBlockH += metaSwatchSize + metaGap; // aida swatch row
      if (pattern.designer != null) metaBlockH += metaRowH;
      if (pattern.difficulty != null) metaBlockH += metaRowH;
      if (pattern.estimatedHours != null) metaBlockH += metaRowH;
      if (pattern.description != null) {
        metaBlockH += _parseMarkdownBlocks(pattern.description!, usableW, fonts).totalHeight + 4;
      }
      metaBlockH += metaGap; // top gap before metadata
    }

    // ── Layout geometry ───────────────────────────────────────────────────
    // previewBudget = space between title block and footer, minus metadata
    final previewBudgetH = (pageH - 2 * margin - footerH -
            titleBlockH -
            metaBlockH)
        .clamp(80.0, 600.0);

    // ── Title (centred) ───────────────────────────────────────────────────
    final titleStr = pattern.name;
    final titleY = pageH - margin - titleFs;
    final titleW = _textWidth(fonts.bold, titleFs, titleStr);
    final titleX = margin + (usableW - titleW) / 2;
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(fonts.bold, titleFs, titleStr, titleX, titleY);

    // ── Subtitle (centred) ────────────────────────────────────────────────
    final subtitleStr = '${pattern.width} x ${pattern.height} stitches';
    final subtitleW = _textWidth(fonts.regular, subtitleFs, subtitleStr);
    final subtitleX = margin + (usableW - subtitleW) / 2;
    canvas.setFillColor(PdfColors.grey600);
    canvas.drawString(fonts.regular, subtitleFs, subtitleStr, subtitleX,
        titleY - titleFs - 5);

    // ── Pattern preview ───────────────────────────────────────────────────
    final previewTopY = titleY - titleBlockH;
    final scaleByW = usableW / pattern.width;
    final scaleByH = previewBudgetH / pattern.height;
    final previewCellSize = math.min(scaleByW, scaleByH);

    final actualPreviewW = previewCellSize * pattern.width;
    final actualPreviewH = previewCellSize * pattern.height;
    final previewOriginX = margin + (usableW - actualPreviewW) / 2;
    final previewOriginY = previewTopY - actualPreviewH;

    _drawStitchPreview(
      canvas,
      originX: previewOriginX,
      originY: previewOriginY,
      pattern: pattern,
      nonBack: nonBack,
      backstitches: backstitches,
      threadMap: threadMap,
      blendedColors: blendedColors,
      cellSize: previewCellSize,
    );

    // ── Metadata block ────────────────────────────────────────────────────
    if (hasMetadata) {
      var my = previewOriginY - metaGap;

      // Aida swatch + label
      canvas.setFillColor(_pdfColor(pattern.aidaColor));
      canvas.drawRect(margin, my - metaSwatchSize, metaSwatchSize, metaSwatchSize);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.grey400);
      canvas.setLineWidth(0.5);
      canvas.drawRect(margin, my - metaSwatchSize, metaSwatchSize, metaSwatchSize);
      canvas.strokePath();
      final aidaLabel = 'On ${aidaColorLabel(pattern.aidaColor)} Aida';
      canvas.setFillColor(PdfColors.grey700);
      canvas.drawString(fonts.regular, 9.0, aidaLabel,
          margin + metaSwatchSize + 5, my - metaSwatchSize + 2);
      my -= metaSwatchSize + metaGap;

      void metaRow(String label, String value) {
        canvas.setFillColor(PdfColors.black);
        final labelText = '$label: ';
        canvas.drawString(fonts.bold, 9.0, labelText, margin, my);
        final labelW = _textWidth(fonts.bold, 9.0, labelText);
        canvas.drawString(fonts.regular, 9.0, value, margin + labelW, my);
        my -= metaRowH;
      }

      if (pattern.designer != null) metaRow('Designer', pattern.designer!);
      if (pattern.difficulty != null) metaRow('Difficulty', pattern.difficulty!);
      if (pattern.estimatedHours != null) {
        final raw = pattern.estimatedHours!.trim();
        final display = raw.toLowerCase().contains('hour') ? raw : '$raw hours';
        metaRow('Est. time', display);
      }

      if (pattern.description != null) {
        my -= 2;
        my = _renderMarkdown(canvas, pattern.description!, my, usableW, margin, fonts);
        my -= 4;
      }

    }

    // ── App attribution (above footer rule) ──────────────────────────────
    const attrFs = 7.0;
    const attrPrefix = 'Pattern crafted with ';
    const attrLink = 'Stitches';
    const attrUrl = 'https://github.com/scme0/Stitches';
    final prefixW = _textWidth(fonts.italic, attrFs, attrPrefix);
    final linkW = _textWidth(fonts.italic, attrFs, attrLink);
    final attrX = (format.width - prefixW - linkW) / 2;
    final attrY = margin + footerH + 2;

    canvas.setFillColor(PdfColors.grey500);
    canvas.drawString(fonts.italic, attrFs, attrPrefix, attrX, attrY);

    const linkColor = PdfColor(0.18, 0.46, 0.80);
    canvas.setFillColor(linkColor);
    canvas.drawString(fonts.italic, attrFs, attrLink, attrX + prefixW, attrY);
    // Underline
    canvas.setStrokeColor(linkColor);
    canvas.setLineWidth(0.4);
    canvas.moveTo(attrX + prefixW, attrY - 1);
    canvas.lineTo(attrX + prefixW + linkW, attrY - 1);
    canvas.strokePath();

    // Clickable URL annotation over "Stitches"
    PdfAnnot(
      page,
      PdfAnnotUrlLink(
        rect: PdfRect(attrX + prefixW, attrY - 1, linkW, attrFs + 2),
        url: attrUrl,
      ),
    );

    // ── Footer ────────────────────────────────────────────────────────────
    _drawPageFooter(canvas,
        format: format,
        margin: margin,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        fonts: fonts,
        copyright: pattern.copyright);
  }

  // ── Materials section ─────────────────────────────────────────────────────

  static void _drawMaterialsSection({
    required PdfDocument doc,
    required PdfGraphics canvas,
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Thread> threads,
    required Map<String, double> crossEquiv,
    required Map<String, double> backCells,
    required bool useDmc,
    required Map<String, String> pdfSymbols,
    required double y,
    required double margin,
    required double headerH,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required _PdfFonts fonts,
    /// True when [canvas] is a fresh page with no footer yet drawn.
    /// False when [canvas] is a shared thread-table page whose footer was
    /// already drawn by [_drawColourTablePage].
    bool drawInitialFooter = false,
  }) {
    const sectionHeadFs = 9.0;
    const tableFs = 7.5;
    const rowH = 14.0;
    const headRowH = 16.0;
    const swatchSize = 10.0;

    var currentCanvas = canvas;
    var currentPageNum = pageNum;
    var onOriginalCanvas = true;

    final suggestions = pattern.materialsSuggestions;
    final tableW = format.width - 2 * margin;

    // ── Section heading ───────────────────────────────────────────────────
    y -= sectionHeadFs + 4;
    currentCanvas.setFillColor(PdfColors.black);
    currentCanvas.drawString(fonts.bold, sectionHeadFs, 'Materials', margin, y);
    y -= 6;

    // ── Aida size sub-table (header + single data row) ────────────────────
    final aidaColW = tableW / (1 + suggestions.length);
    final aidaColWidths =
        List.filled(1 + suggestions.length, aidaColW, growable: false);

    _drawTableRow(currentCanvas,
        x: margin,
        y: y,
        colWidths: aidaColWidths,
        rowH: headRowH,
        bgColor: PdfColors.grey200,
        cells: ['Aida', ...suggestions.map((s) => '${s.aidaCount}-count')],
        fonts: fonts,
        fontSize: tableFs,
        isHeader: true);
    y -= headRowH;

    // Data row: use _drawTableRow for border + size cells; overlay swatch in col 0
    final aidaColor = _pdfColor(pattern.aidaColor);
    final aidaLabel = aidaColorLabel(pattern.aidaColor);
    final sizeCells = suggestions.map((s) {
      final wCm = (pattern.width / s.aidaCount) * 2.54 + 10;
      final hCm = (pattern.height / s.aidaCount) * 2.54 + 10;
      return '${wCm.toStringAsFixed(1)}\u00D7${hCm.toStringAsFixed(1)} cm';
    }).toList();

    _drawTableRow(currentCanvas,
        x: margin,
        y: y,
        colWidths: aidaColWidths,
        rowH: rowH,
        bgColor: null,
        cells: ['', ...sizeCells],
        fonts: fonts,
        fontSize: tableFs,
        isHeader: false);
    // Overlay swatch + label in first cell
    currentCanvas.setFillColor(aidaColor);
    currentCanvas.drawRect(
        margin + 2, y - rowH + (rowH - swatchSize) / 2, swatchSize, swatchSize);
    currentCanvas.fillPath();
    currentCanvas.setStrokeColor(PdfColors.grey400);
    currentCanvas.setLineWidth(0.4);
    currentCanvas.drawRect(
        margin + 2, y - rowH + (rowH - swatchSize) / 2, swatchSize, swatchSize);
    currentCanvas.strokePath();
    currentCanvas.setFillColor(PdfColors.black);
    currentCanvas.drawString(fonts.regular, tableFs, aidaLabel,
        margin + swatchSize + 5, y - rowH + (rowH - tableFs) / 2 + 1);
    y -= rowH;

    // Border note
    const borderNoteFs = 6.5;
    currentCanvas.setFillColor(PdfColors.grey600);
    currentCanvas.drawString(fonts.regular, borderNoteFs,
        'Sizes include a 5cm border on each side for framing.', margin, y - borderNoteFs - 1);
    y -= borderNoteFs + 10;

    // ── Skeins sub-table (two-column) ────────────────────────────────────
    const gutterW = 8.0;
    final halfW = (tableW - gutterW) / 2;

    const twoSwatchW = 16.0;
    const twoCodeW = 38.0;
    const twoSkeinW = 38.0; // per Aida-size column
    final twoNameW =
        (halfW - twoSwatchW - twoCodeW - twoSkeinW * suggestions.length)
            .clamp(30.0, double.infinity);
    final halfColWidths = [
      twoSwatchW,
      twoCodeW,
      twoNameW,
      ...List.filled(suggestions.length, twoSkeinW),
    ];

    final codeHeader = useDmc ? 'DMC' : 'Anchor';
    final halfHeaders = [
      '',
      codeHeader,
      'Name',
      ...suggestions.map((s) => '${s.aidaCount}ct/${s.strands}s'),
    ];

    void drawSkeinHeader(PdfGraphics cv, double headerY) {
      for (int col = 0; col < 2; col++) {
        _drawTableRow(cv,
            x: margin + col * (halfW + gutterW),
            y: headerY,
            colWidths: halfColWidths,
            rowH: headRowH,
            bgColor: PdfColors.grey200,
            cells: halfHeaders,
            fonts: fonts,
            fontSize: tableFs,
            isHeader: true);
      }
    }

    drawSkeinHeader(currentCanvas, y);
    y -= headRowH;

    // Sub-header note clarifying the column values are skein counts
    const noteFs = 6.5;
    currentCanvas.setFillColor(PdfColors.grey600);
    currentCanvas.drawString(fonts.regular, noteFs,
        'Values are estimated skein quantities (8m/skein, 10% overlap assumed).',
        margin, y - noteFs - 1);
    y -= noteFs + 8;

    String threadDisplayCode(Thread t) =>
        useDmc ? t.dmcCode : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
    List<String> threadSkeinCells(Thread t) => suggestions.map((s) {
          final n = calculateSkeins(
            dmcCode: t.dmcCode,
            crossEquiv: crossEquiv,
            backCells: backCells,
            aidaCount: s.aidaCount,
            strands: s.strands,
          );
          return '$n';
        }).toList();

    void drawThreadRow(Thread t, int col) {
      _drawTableRow(currentCanvas,
          x: margin + col * (halfW + gutterW),
          y: y,
          colWidths: halfColWidths,
          rowH: rowH,
          bgColor: null,
          cells: ['', threadDisplayCode(t), t.name, ...threadSkeinCells(t)],
          fonts: fonts,
          fontSize: tableFs,
          isHeader: false,
          swatchColor: _pdfColor(t.color));
    }

    // Full left column first, then right column — threads[0..mid-1] on left,
    // threads[mid..end] on right, drawn row by row simultaneously.
    final mid = (threads.length / 2).ceil();
    final leftThreads = threads.sublist(0, mid);
    final rightThreads = threads.sublist(mid);

    for (int i = 0; i < leftThreads.length; i++) {
      // Paginate when near the bottom
      if (y - rowH < margin + footerH + 4) {
        _drawPageFooter(currentCanvas,
            format: format,
            margin: margin,
            footerH: footerH,
            pageNum: currentPageNum,
            totalPages: totalPages,
            fonts: fonts,
            copyright: pattern.copyright);
        currentCanvas = PdfPage(doc, pageFormat: format).getGraphics();
        onOriginalCanvas = false;
        currentPageNum++;
        _drawPageHeader(currentCanvas,
            format: format,
            pattern: pattern,
            margin: margin,
            headerH: headerH,
            subtitle:
                'Materials (continued)  |  Page $currentPageNum of $totalPages',
            fonts: fonts);
        y = format.height - margin - headerH;
        drawSkeinHeader(currentCanvas, y);
        y -= headRowH;
      }

      drawThreadRow(leftThreads[i], 0);
      if (i < rightThreads.length) drawThreadRow(rightThreads[i], 1);
      y -= rowH;
    }

    // Draw footer on the last materials page.
    // Skip if we're still on the original shared table-page (its footer was
    // already drawn by _drawColourTablePage), unless the caller flagged that
    // the initial canvas is a fresh page that still needs one.
    if (!onOriginalCanvas || drawInitialFooter) {
      _drawPageFooter(currentCanvas,
          format: format,
          margin: margin,
          footerH: footerH,
          pageNum: currentPageNum,
          totalPages: totalPages,
          fonts: fonts,
          copyright: pattern.copyright);
    }
  }

  // ── Stitch preview (line-art X shapes, no symbols) ───────────────────────

  static void _drawStitchPreview(
    PdfGraphics canvas, {
    required double originX,
    required double originY,
    required CrossStitchPattern pattern,
    required List<Stitch> nonBack,
    required List<BackStitch> backstitches,
    required Map<String, Thread> threadMap,
    required Map<String, Color> blendedColors,
    required double cellSize,
  }) {
    final pw2 = pattern.width * cellSize;
    final ph2 = pattern.height * cellSize;
    final rows = pattern.height;

    // Aida background
    canvas.setFillColor(_pdfColor(pattern.aidaColor));
    canvas.drawRect(originX, originY, pw2, ph2);
    canvas.fillPath();

    // Cross-type stitches as line-art using composited (deduplicated) stitches.
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineWidth(math.max(0.3, cellSize * 0.12));
    for (final s in nonBack) {
      final cx = _stitches(s);
      final cy = _stitchY(s);
      final thread = threadMap[s.threadId];
      if (thread == null) continue;
      // Use blended color for cells where multiple layers overlap.
      final effectiveColor = blendedColors['$cx,$cy'] ?? thread.color;
      canvas.setStrokeColor(_pdfColor(effectiveColor));
      final gx = originX + cx * cellSize;
      final gy = originY + (rows - cy - 1) * cellSize;
      _drawRealisticStitch(canvas, s, gx, gy, cellSize);
    }

    // Backstitches
    canvas.setLineWidth(math.max(0.5, cellSize * 0.22));
    for (final bs in backstitches) {
      final thread = threadMap[bs.threadId];
      if (thread == null) continue;
      canvas.setStrokeColor(_pdfColor(thread.color));
      canvas.moveTo(originX + bs.x1 * cellSize,
          originY + (rows - bs.y1) * cellSize);
      canvas.lineTo(originX + bs.x2 * cellSize,
          originY + (rows - bs.y2) * cellSize);
      canvas.strokePath();
    }
    canvas.setLineCap(PdfLineCap.butt);

    // Outer border
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.8);
    canvas.drawRect(originX, originY, pw2, ph2);
    canvas.strokePath();
  }

  // ── Shared page components ────────────────────────────────────────────────

  /// Draws the title + subtitle + separator rule at the top of any page.
  static void _drawPageHeader(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required double margin,
    required double headerH,
    required String subtitle,
    required _PdfFonts fonts,
  }) {
    // Title
    const titleFs = 14.0;
    final titleY = format.height - margin - titleFs;
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(
        fonts.bold, titleFs, pattern.name, margin, titleY);

    // Subtitle
    const subtitleFs = 8.0;
    canvas.setFillColor(PdfColors.grey600);
    canvas.drawString(
        fonts.regular, subtitleFs, subtitle, margin, titleY - titleFs - 4);

    // Separator rule
    final ruleY = format.height - margin - headerH + 8;
    canvas.setStrokeColor(PdfColors.grey400);
    canvas.setLineWidth(0.75);
    canvas.moveTo(margin, ruleY);
    canvas.lineTo(format.width - margin, ruleY);
    canvas.strokePath();
  }

  /// Draws the separator rule + centred page number at the bottom of any page.
  static void _drawPageFooter(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required double margin,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required _PdfFonts fonts,
    String? copyright,
  }) {
    const footerFs = 7.5;
    final ruleY = margin + footerH - 4;
    canvas.setStrokeColor(PdfColors.grey300);
    canvas.setLineWidth(0.5);
    canvas.moveTo(margin, ruleY);
    canvas.lineTo(format.width - margin, ruleY);
    canvas.strokePath();

    canvas.setFillColor(PdfColors.grey600);

    // Copyright on the left (if present)
    if (copyright != null) {
      final year = DateTime.now().year;
      canvas.drawString(fonts.regular, footerFs,
          'Copyright \u00A9 $copyright $year', margin, margin);
    }

    // Page number on the right
    final label = 'Page $pageNum of $totalPages';
    final lw = _textWidth(fonts.regular, footerFs, label);
    canvas.drawString(
        fonts.regular, footerFs, label, format.width - margin - lw, margin);
  }

  /// Draws a single table row.
  /// - [swatchColor] + [swatchSymbol]: col 0 filled with colour + symbol text centred on top.
  /// - [linePreviewColor]: col 0 shows a thick coloured horizontal line (for backstitches).
  static void _drawTableRow(
    PdfGraphics canvas, {
    required double x,
    required double y,
    required List<double> colWidths,
    required double rowH,
    required PdfColor? bgColor,
    required List<String> cells,
    required _PdfFonts fonts,
    required double fontSize,
    required bool isHeader,
    PdfColor? swatchColor,
    String? swatchSymbol,
    PdfColor? linePreviewColor,
  }) {
    assert(cells.length == colWidths.length);
    double cx = x;
    final totalW = colWidths.fold(0.0, (a, b) => a + b);

    // Row background
    if (bgColor != null) {
      canvas.setFillColor(bgColor);
      canvas.drawRect(cx, y - rowH, totalW, rowH);
      canvas.fillPath();
    }

    // Row border
    canvas.setStrokeColor(PdfColors.grey400);
    canvas.setLineWidth(0.4);
    canvas.drawRect(cx, y - rowH, totalW, rowH);
    canvas.strokePath();

    // Cells
    final cellFont = isHeader ? fonts.bold : fonts.regular;
    for (int i = 0; i < cells.length; i++) {
      final cw = colWidths[i];

      // Vertical divider (skip first)
      if (i > 0) {
        canvas.setStrokeColor(PdfColors.grey400);
        canvas.setLineWidth(0.4);
        canvas.moveTo(cx, y);
        canvas.lineTo(cx, y - rowH);
        canvas.strokePath();
      }

      if (i == 0 && linePreviewColor != null) {
        // Backstitch line preview: thick coloured line across the cell centre
        const pad = 4.0;
        canvas.setStrokeColor(linePreviewColor);
        canvas.setLineWidth(math.max(1.2, rowH * 0.22));
        canvas.setLineCap(PdfLineCap.round);
        canvas.moveTo(cx + pad, y - rowH / 2);
        canvas.lineTo(cx + cw - pad, y - rowH / 2);
        canvas.strokePath();
        canvas.setLineCap(PdfLineCap.butt);
        canvas.setLineWidth(0.4);
      } else if (i == 0 && swatchColor != null) {
        // Colour swatch with optional symbol overlay
        const pad = 2.0;
        canvas.setFillColor(swatchColor);
        canvas.drawRect(cx + pad, y - rowH + pad, cw - 2 * pad, rowH - 2 * pad);
        canvas.fillPath();
        // Symbol text centred on swatch
        if (swatchSymbol != null && swatchSymbol.isNotEmpty) {
          final lum = swatchColor.red * 0.299 +
              swatchColor.green * 0.587 +
              swatchColor.blue * 0.114;
          final textColor = lum > 0.35 ? PdfColors.black : PdfColors.white;
          final sf = math.max(3.5, (rowH - 2 * pad) * 0.58);
          final symFont = _fontFor(swatchSymbol, fonts.regular, fonts.symbol);
          final tw = _textWidth(symFont, sf, swatchSymbol);
          canvas.setFillColor(textColor);
          canvas.drawString(symFont, sf, swatchSymbol,
              cx + pad + (cw - 2 * pad - tw) / 2,
              y - rowH + pad + (rowH - 2 * pad) / 2 - sf * 0.35);
        }
      } else if (cells[i].isNotEmpty) {
        canvas.setFillColor(PdfColors.black);
        final ty = y - rowH + (rowH - fontSize) / 2 + 1.0;
        canvas.drawString(cellFont, fontSize, cells[i], cx + 3, ty);
      }

      cx += cw;
    }
  }

  // ── Markdown renderer ─────────────────────────────────────────────────────

  /// Parses markdown source into layout blocks for PDF rendering.
  static ({
    List<({
      List<List<_TextRun>> lines,
      double lineH,
      double indent,
      String? bulletPrefix,
      double fontSize,
      PdfColor color
    })> blocks,
    double totalHeight
  }) _parseMarkdownBlocks(String source, double maxWidth, _PdfFonts fonts) {
    final document = md.Document(encodeHtml: false);
    final nodes = document.parseLines(source.split('\n'));

    final blocks = <({
      List<List<_TextRun>> lines,
      double lineH,
      double indent,
      String? bulletPrefix,
      double fontSize,
      PdfColor color
    })>[];

    double totalHeight = 0;

    for (final node in nodes) {
      if (node is! md.Element) continue;
      final tag = node.tag;

      switch (tag) {
        case 'h1':
          const fs = 16.0;
          const gap = 8.0;
          const spacing = 1.3;
          final runs = _collectRuns(node.children, bold: true);
          final wrapped = _wrapRuns(runs, maxWidth, fonts, fs);
          final blockH = wrapped.length * fs * spacing + gap;
          totalHeight += blockH;
          blocks.add((
            lines: wrapped,
            lineH: fs * spacing,
            indent: 0,
            bulletPrefix: null,
            fontSize: fs,
            color: PdfColors.black,
          ));
        case 'h2':
          const fs = 13.0;
          const gap = 6.0;
          const spacing = 1.3;
          final runs = _collectRuns(node.children, bold: true);
          final wrapped = _wrapRuns(runs, maxWidth, fonts, fs);
          final blockH = wrapped.length * fs * spacing + gap;
          totalHeight += blockH;
          blocks.add((
            lines: wrapped,
            lineH: fs * spacing,
            indent: 0,
            bulletPrefix: null,
            fontSize: fs,
            color: PdfColors.black,
          ));
        case 'h3':
          const fs = 11.0;
          const gap = 4.0;
          const spacing = 1.3;
          final runs = _collectRuns(node.children, bold: true);
          final wrapped = _wrapRuns(runs, maxWidth, fonts, fs);
          final blockH = wrapped.length * fs * spacing + gap;
          totalHeight += blockH;
          blocks.add((
            lines: wrapped,
            lineH: fs * spacing,
            indent: 0,
            bulletPrefix: null,
            fontSize: fs,
            color: PdfColors.black,
          ));
        case 'ul':
          for (final child in node.children ?? <md.Node>[]) {
            if (child is! md.Element || child.tag != 'li') continue;
            const fs = 10.0;
            const gap = 6.0;
            const spacing = 1.3;
            const indent = 14.0;
            final runs = _collectRuns(child.children);
            final wrapped = _wrapRuns(runs, maxWidth - indent, fonts, fs);
            final blockH = wrapped.length * fs * spacing + gap;
            totalHeight += blockH;
            blocks.add((
              lines: wrapped,
              lineH: fs * spacing,
              indent: indent,
              bulletPrefix: '\u2022 ',
              fontSize: fs,
              color: PdfColors.grey800,
            ));
          }
        case 'ol':
          var idx = 1;
          for (final child in node.children ?? <md.Node>[]) {
            if (child is! md.Element || child.tag != 'li') continue;
            const fs = 10.0;
            const gap = 6.0;
            const spacing = 1.3;
            const indent = 18.0;
            final runs = _collectRuns(child.children);
            final wrapped = _wrapRuns(runs, maxWidth - indent, fonts, fs);
            final blockH = wrapped.length * fs * spacing + gap;
            totalHeight += blockH;
            blocks.add((
              lines: wrapped,
              lineH: fs * spacing,
              indent: indent,
              bulletPrefix: '$idx. ',
              fontSize: fs,
              color: PdfColors.grey800,
            ));
            idx++;
          }
        default:
          // 'p' and unknown tags: body text
          const fs = 10.0;
          const gap = 6.0;
          const spacing = 1.3;
          final runs = _collectRuns(node.children);
          final wrapped = _wrapRuns(runs, maxWidth, fonts, fs);
          final blockH = wrapped.length * fs * spacing + gap;
          totalHeight += blockH;
          blocks.add((
            lines: wrapped,
            lineH: fs * spacing,
            indent: 0,
            bulletPrefix: null,
            fontSize: fs,
            color: PdfColors.grey800,
          ));
      }
    }

    return (blocks: blocks, totalHeight: totalHeight);
  }

  /// Recursively collects text runs from a markdown node tree.
  static List<_TextRun> _collectRuns(
    List<md.Node>? nodes, {
    bool bold = false,
    bool italic = false,
  }) {
    final runs = <_TextRun>[];
    for (final node in nodes ?? <md.Node>[]) {
      if (node is md.Text) {
        runs.add((text: node.text, bold: bold, italic: italic, sym: false));
      } else if (node is md.Element) {
        final b = bold || node.tag == 'strong';
        final i = italic || node.tag == 'em';
        runs.addAll(_collectRuns(node.children, bold: b, italic: i));
      }
    }
    return runs;
  }

  /// Word-wraps a list of text runs to fit within [maxWidth].
  static List<List<_TextRun>> _wrapRuns(
      List<_TextRun> runs, double maxWidth, _PdfFonts fonts, double fontSize) {
    final lines = <List<_TextRun>>[];
    var currentLine = <_TextRun>[];
    var currentWidth = 0.0;

    for (final run in runs) {
      final runFont = run.sym
          ? fonts.symbol
          : run.bold
              ? fonts.bold
              : run.italic
                  ? fonts.italic
                  : fonts.regular;
      final words = run.text.split(' ');
      for (int wi = 0; wi < words.length; wi++) {
        final word = words[wi];
        if (word.isEmpty && wi > 0) continue;
        final wordWithSpace = (wi < words.length - 1) ? '$word ' : word;
        final wordW = _textWidth(runFont, fontSize, wordWithSpace);
        if (currentWidth + wordW > maxWidth && currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = [];
          currentWidth = 0;
        }
        // Add word to current line (strip trailing space on wrapped word)
        final wordRun = (
          text: wordWithSpace,
          bold: run.bold,
          italic: run.italic,
          sym: run.sym,
        );
        currentLine.add(wordRun);
        currentWidth += wordW;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);
    if (lines.isEmpty) lines.add([]);
    return lines;
  }

  /// Renders markdown onto [canvas] starting at [startY] (PDF y, top of text).
  /// Returns the y position after the last line.
  static double _renderMarkdown(
      PdfGraphics canvas,
      String source,
      double startY,
      double maxWidth,
      double leftX,
      _PdfFonts fonts) {
    final parsed = _parseMarkdownBlocks(source, maxWidth, fonts);
    var y = startY;

    for (final block in parsed.blocks) {
      // For bullet lists, draw the prefix before the first line
      var firstLine = true;
      for (final line in block.lines) {
        canvas.setFillColor(block.color);
        var lineX = leftX + block.indent;

        if (firstLine && block.bulletPrefix != null) {
          final prefixFont = _fontFor(block.bulletPrefix!, fonts.regular, fonts.symbol);
          canvas.drawString(
              prefixFont, block.fontSize, block.bulletPrefix!, leftX, y - block.fontSize);
          firstLine = false;
        } else {
          firstLine = false;
        }

        var runX = lineX;
        for (final run in line) {
          if (run.text.isEmpty) continue;
          final runFont = run.sym
              ? fonts.symbol
              : run.bold
                  ? fonts.bold
                  : run.italic
                      ? fonts.italic
                      : fonts.regular;
          canvas.drawString(runFont, block.fontSize, run.text, runX, y - block.fontSize);
          runX += _textWidth(runFont, block.fontSize, run.text);
        }
        y -= block.lineH;
      }
    }

    return y;
  }

  // ── Stitch fill helpers ─────────────────────────────────────────────────────

  /// Fills the region of a stitch in PDF graphics coords.
  /// gx/gy = bottom-left corner of the cell in PDF coords (y increases up).
  static void _fillStitch(
      PdfGraphics canvas, Stitch s, double gx, double gy, double cs) {
    switch (s) {
      case FullStitch():
        canvas.drawRect(gx, gy, cs, cs);
        canvas.fillPath();

      // HalfStitch "/" (isForward=true): fill the left/upper triangle
      // PDF coords: bl=(gx,gy), tl=(gx,gy+cs), tr=(gx+cs,gy+cs)
      case HalfStitch(isForward: true):
        canvas.moveTo(gx, gy);
        canvas.lineTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy + cs);
        canvas.closePath();
        canvas.fillPath();

      // HalfStitch "\" (isForward=false): fill the right/upper triangle
      // PDF coords: tl=(gx,gy+cs), tr=(gx+cs,gy+cs), br=(gx+cs,gy)
      case HalfStitch(isForward: false):
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.closePath();
        canvas.fillPath();

      // QuarterStitch: fill the relevant cell quadrant (rectangle)
      // Screen topLeft  = PDF upper-left  → drawRect(gx, gy+cs/2, cs/2, cs/2)
      // Screen topRight = PDF upper-right → drawRect(gx+cs/2, gy+cs/2, cs/2, cs/2)
      // Screen botLeft  = PDF lower-left  → drawRect(gx, gy, cs/2, cs/2)
      // Screen botRight = PDF lower-right → drawRect(gx+cs/2, gy, cs/2, cs/2)
      case QuarterStitch(quadrant: QuadrantPosition.topLeft):
        canvas.drawRect(gx, gy + cs / 2, cs / 2, cs / 2);
        canvas.fillPath();
      case QuarterStitch(quadrant: QuadrantPosition.topRight):
        canvas.drawRect(gx + cs / 2, gy + cs / 2, cs / 2, cs / 2);
        canvas.fillPath();
      case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.drawRect(gx, gy, cs / 2, cs / 2);
        canvas.fillPath();
      case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.drawRect(gx + cs / 2, gy, cs / 2, cs / 2);
        canvas.fillPath();

      // HalfCrossStitch: fill the appropriate half-cell rectangle
      case HalfCrossStitch(half: HalfOrientation.left):
        canvas.drawRect(gx, gy, cs / 2, cs);
        canvas.fillPath();
      case HalfCrossStitch(half: HalfOrientation.right):
        canvas.drawRect(gx + cs / 2, gy, cs / 2, cs);
        canvas.fillPath();
      // Screen top = PDF upper half
      case HalfCrossStitch(half: HalfOrientation.top):
        canvas.drawRect(gx, gy + cs / 2, cs, cs / 2);
        canvas.fillPath();
      // Screen bottom = PDF lower half
      case HalfCrossStitch(half: HalfOrientation.bottom):
        canvas.drawRect(gx, gy, cs, cs / 2);
        canvas.fillPath();

      // QuarterCrossStitch: fill the appropriate quarter-cell rectangle
      case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
        canvas.drawRect(gx, gy + cs / 2, cs / 2, cs / 2);
        canvas.fillPath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
        canvas.drawRect(gx + cs / 2, gy + cs / 2, cs / 2, cs / 2);
        canvas.fillPath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.drawRect(gx, gy, cs / 2, cs / 2);
        canvas.fillPath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.drawRect(gx + cs / 2, gy, cs / 2, cs / 2);
        canvas.fillPath();

      case BackStitch():
        break;
    }
  }

  /// Returns the centre of the stitch's filled sub-region in PDF coordinates.
  static (double, double) _stitchSymbolCenter(
      Stitch s, double gx, double gy, double cs) {
    return switch (s) {
      FullStitch() || HalfStitch() => (gx + cs / 2, gy + cs / 2),
      // Screen topLeft  = PDF upper-left  → centre (gx+cs/4,   gy+3*cs/4)
      QuarterStitch(quadrant: QuadrantPosition.topLeft) ||
      QuarterCrossStitch(quadrant: QuadrantPosition.topLeft) =>
        (gx + cs / 4, gy + 3 * cs / 4),
      QuarterStitch(quadrant: QuadrantPosition.topRight) ||
      QuarterCrossStitch(quadrant: QuadrantPosition.topRight) =>
        (gx + 3 * cs / 4, gy + 3 * cs / 4),
      QuarterStitch(quadrant: QuadrantPosition.bottomLeft) ||
      QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft) =>
        (gx + cs / 4, gy + cs / 4),
      QuarterStitch(quadrant: QuadrantPosition.bottomRight) ||
      QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight) =>
        (gx + 3 * cs / 4, gy + cs / 4),
      HalfCrossStitch(half: HalfOrientation.left) => (gx + cs / 4, gy + cs / 2),
      HalfCrossStitch(half: HalfOrientation.right) =>
        (gx + 3 * cs / 4, gy + cs / 2),
      // Screen top = PDF upper
      HalfCrossStitch(half: HalfOrientation.top) =>
        (gx + cs / 2, gy + 3 * cs / 4),
      HalfCrossStitch(half: HalfOrientation.bottom) =>
        (gx + cs / 2, gy + cs / 4),
      BackStitch() => (gx + cs / 2, gy + cs / 2),
    };
  }

  /// Returns the effective size (pt) of the stitch's sub-region for font sizing.
  static double _stitchSubRegionSize(Stitch s, double cs) => switch (s) {
        FullStitch() || HalfStitch() => cs,
        QuarterStitch() ||
        QuarterCrossStitch() ||
        HalfCrossStitch(half: HalfOrientation.left || HalfOrientation.right) =>
          cs / 2,
        HalfCrossStitch() => cs / 2,
        BackStitch() => cs,
      };

  // ── Helpers ───────────────────────────────────────────────────────────────

  static int _stitches(Stitch s) => switch (s) {
        FullStitch(x: final x) => x,
        HalfStitch(x: final x) => x,
        QuarterStitch(x: final x) => x,
        HalfCrossStitch(x: final x) => x,
        QuarterCrossStitch(x: final x) => x,
        BackStitch() => 0,
      };

  static int _stitchY(Stitch s) => switch (s) {
        FullStitch(y: final y) => y,
        HalfStitch(y: final y) => y,
        QuarterStitch(y: final y) => y,
        HalfCrossStitch(y: final y) => y,
        QuarterCrossStitch(y: final y) => y,
        BackStitch() => 0,
      };

  /// Returns [sym] font if [text] contains a character that requires
  /// NotoSansSymbols2, otherwise returns [base] (NotoSans-Regular).
  ///
  /// NotoSans-Regular (as bundled) covers only:
  ///   Latin, Latin-1 Supplement (¼ © £ € etc.), Greek.
  /// NotoSansSymbols2 covers from U+2200 upward, including:
  ///   Geometric Shapes (U+25A0–25FF: ■ ● ▲ ▼ ◆ ○ etc.),
  ///   Misc Symbols (U+2600–26FF: ★ ♤ ♧ ♡ ♢),
  ///   Dingbats (U+2700–27BF: ✦ ✩ ✓ ✗ ✚),
  ///   Misc Symbols and Arrows (U+2B00+: ⬡ ⬢ ⬤ ⬥),
  ///   some Math Operators (U+2299: ⊙).
  /// NOTE: Arrows (U+2190–21FF) and most Math Operators (⊕⊖⊗⊚) are absent
  /// from both fonts — they must not appear in kPatternSymbols.
  static PdfFont _fontFor(String text, PdfFont base, PdfFont sym) {
    for (final rune in text.runes) {
      if (rune >= 0x2200) return sym;
    }
    return base;
  }

  /// Returns the advance width of [text] rendered at [fontSize] with [font].
  static double _textWidth(PdfFont font, double fontSize, String text) =>
      font.stringMetrics(text).advanceWidth * fontSize;

  // kPdfUnsupportedSymbols is the canonical source — defined in symbols.dart.

  /// Build a per-export symbol map: dmcCode → symbol char.
  /// Threads with symbols absent from the PDF fonts are omitted (treated as
  /// no symbol — blank cells in the chart).
  @visibleForTesting
  static Map<String, String> buildPdfSymbolMapForTest(List<Thread> threads) =>
      _buildPdfSymbolMap(threads);

  static Map<String, String> _buildPdfSymbolMap(List<Thread> threads) {
    return {
      for (final t in threads)
        if (symbolIsVisible(t.symbol) && !kPdfUnsupportedSymbols.contains(t.symbol))
          t.dmcCode: t.symbol,
    };
  }

  static PdfColor _pdfColor(Color c) =>
      PdfColor(c.r.toDouble(), c.g.toDouble(), c.b.toDouble());

  // ── Layer compositing ─────────────────────────────────────────────────────

  /// Composites non-BackStitch stitches from all visible layers, matching the
  /// 'stitch mode' canvas. FullStitches at the same cell are deduplicated
  /// (topmost layer wins for symbol/threadId) and their colours are blended
  /// using each layer's blend mode. All other stitch types pass through as-is.
  @visibleForTesting
  static ({List<Stitch> nonBack, Map<String, Color> blendedColors})
      compositeNonBackForTest(
              CrossStitchPattern pattern, Map<String, Thread> threadMap) =>
          _compositeNonBack(pattern, threadMap);

  static ({List<Stitch> nonBack, Map<String, Color> blendedColors})
      _compositeNonBack(
          CrossStitchPattern pattern, Map<String, Thread> threadMap) {
    final cellStack = <String,
        List<({
          Stitch stitch,
          Color color,
          double opacity,
          LayerBlendMode blendMode
        })>>{};
    final otherNonBack = <Stitch>[];

    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        if (stitch is FullStitch) {
          final thread = threadMap[stitch.threadId];
          if (thread == null) continue;
          final key = '${stitch.x},${stitch.y}';
          (cellStack[key] ??= []).add((
            stitch: stitch,
            color: thread.color,
            opacity: layer.opacity,
            blendMode: layer.blendMode,
          ));
        } else {
          otherNonBack.add(stitch);
        }
      }
    }

    final deduped = <Stitch>[];
    final blendedColors = <String, Color>{};

    for (final entry in cellStack.entries) {
      final stack = entry.value;
      // Symbol/threadId: topmost layer wins only when it fully covers (Normal
      // blend at ≥99% opacity). For Add/Screen/Multiply/etc. the bottom layer
      // provides the primary thread identity — its symbol distinguishes the
      // different coloured areas of the base pattern.
      final top = stack.last;
      final symbolStitch =
          (top.blendMode == LayerBlendMode.normal && top.opacity >= 0.99)
              ? top.stitch
              : stack.first.stitch;
      deduped.add(symbolStitch);
      if (stack.length > 1) {
        var blended = stack.first.color;
        for (int i = 1; i < stack.length; i++) {
          blended = stack[i]
              .blendMode
              .apply(blended, stack[i].color, stack[i].opacity);
        }
        blendedColors[entry.key] = blended;
      }
    }

    return (nonBack: [...deduped, ...otherNonBack], blendedColors: blendedColors);
  }

  // ── Realistic stitch line-art ─────────────────────────────────────────────

  /// Draws stitch shapes as diagonal line-art (X, half-X, etc.).
  /// gx/gy = bottom-left of the cell in PDF coords (y increases up).
  /// Stroke colour and width must be set by the caller.
  static void _drawRealisticStitch(
      PdfGraphics canvas, Stitch s, double gx, double gy, double cs) {
    switch (s) {
      case FullStitch():
        canvas.moveTo(gx, gy);
        canvas.lineTo(gx + cs, gy + cs);
        canvas.strokePath();
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();

      case HalfStitch(isForward: true): // "/"
        canvas.moveTo(gx, gy);
        canvas.lineTo(gx + cs, gy + cs);
        canvas.strokePath();

      case HalfStitch(isForward: false): // "\"
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();

      case QuarterStitch(quadrant: QuadrantPosition.topLeft):
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs / 2, gy + cs);
        canvas.strokePath();
      case QuarterStitch(quadrant: QuadrantPosition.topRight):
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();
      case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();
      case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.moveTo(gx + cs / 2, gy);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();

      case HalfCrossStitch(half: HalfOrientation.left):
        canvas.moveTo(gx, gy);
        canvas.lineTo(gx + cs / 2, gy + cs);
        canvas.strokePath();
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();
      case HalfCrossStitch(half: HalfOrientation.right):
        canvas.moveTo(gx + cs / 2, gy);
        canvas.lineTo(gx + cs, gy + cs);
        canvas.strokePath();
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();
      case HalfCrossStitch(half: HalfOrientation.top):
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs, gy + cs);
        canvas.strokePath();
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();
      case HalfCrossStitch(half: HalfOrientation.bottom):
        canvas.moveTo(gx, gy);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();

      case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs / 2, gy + cs);
        canvas.strokePath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.moveTo(gx + cs / 2, gy);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();

      case BackStitch():
        break;
    }
  }
}
