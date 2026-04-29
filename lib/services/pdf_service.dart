import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import 'skein_calculator.dart';
import 'stitch_compositor.dart';

part 'pdf/pdf_helpers.dart';
part 'pdf/pdf_markdown.dart';
part 'pdf/pdf_chart.dart';
part 'pdf/pdf_color_table.dart';
part 'pdf/pdf_title_page.dart';

class PdfService {
  /// Generate PDF and save via file picker.
  /// Build a PDF for [pattern] and return the raw bytes.
  ///
  /// When [patternKeeperMode] is true, the output is formatted for import into
  /// PatternKeeper: no title page, ≤60 stitches per page, and the legend table
  /// uses 'Symbol'/'Number' column headers with the TTF symbol character as
  /// selectable text (PatternKeeper's required format).
  static Future<Uint8List> buildPdfBytes(
    CrossStitchPattern pattern, {
    bool useDmc = true,
    bool realistic = true,
    bool patternKeeperMode = false,
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

    // ── Data prep ──────────────────────────────────────────────────────────────

    final threadMap = pattern.threads;

    // Single composite pass — matches the canvas view exactly.
    final compositeLayer = StitchCompositor.computeLayer(pattern);

    // For blended cells, derive display color and symbol from CompositeLayer.
    final blendedCellColors = <String, Color>{};
    final blendedCellSymbols = <String, String>{};
    for (final entry in compositeLayer.fullStitches.entries) {
      if (!entry.value.isBlended) continue;
      final t = entry.value.resolvedThread;
      blendedCellColors[entry.key] = t.color;
      final sym = pattern.compositeSymbols[t.dmcCode] ?? '';
      if (symbolIsVisible(sym) && !kPdfUnsupportedSymbols.contains(sym)) {
        blendedCellSymbols[entry.key] = sym;
      }
    }

    final nonBack = [
      ...compositeLayer.fullStitches.values.map((cs) => cs.stitch),
      ...compositeLayer.otherStitches.map((cs) => cs.stitch),
    ];
    final backstitches = compositeLayer.backstitches;
    final blendedColors = blendedCellColors;

    // Stitch counts from the composite view (one stitch per cell regardless
    // of how many layers contributed to it — matches what the stitcher actually stitches).
    //
    // In PatternKeeper mode we must also ensure that every symbol-stitch thread
    // (i.e. the thread whose symbol is drawn in each cell) is present in
    // crossStitchEquiv so it gets an entry in pdfSymbols and in the legend table.
    //
    // For cells with a non-normal blend mode on the topmost layer, the compositor
    // picks the BOTTOM stitch as the symbol stitch (it provides the primary visual
    // identity). But the stitch count for that cell is attributed to the BLEND-RESULT
    // thread (e.g. '307' from a multiply blend), not to the bottom thread (e.g. '918').
    // If '918' has zero blend-result credit it is absent from crossStitchEquiv →
    // excluded from pdfSymbols → the chart cell draws a blank → the cell is lost on
    // import. Augmenting the map with a 0.0-count placeholder forces the thread into
    // the legend and fixes the blank-cell problem without changing any stitch counts.
    final Map<String, double> crossStitchEquiv;
    if (patternKeeperMode) {
      final mutable = Map<String, double>.from(compositeLayer.crossStitchEquiv);
      for (final s in nonBack) {
        if (s is FullStitch) mutable.putIfAbsent(s.threadId, () => 0.0);
      }
      crossStitchEquiv = mutable;
    } else {
      crossStitchEquiv = compositeLayer.crossStitchEquiv;
    }
    final backStitchEquiv = compositeLayer.backStitchEquiv;

    // Threads that have cross-type stitches / backstitches respectively,
    // sorted by DMC number so colour tables are easy to reference.
    int dmcSort(Thread a, Thread b) {
      final ia = int.tryParse(a.dmcCode) ?? 999999;
      final ib = int.tryParse(b.dmcCode) ?? 999999;
      return ia != ib ? ia.compareTo(ib) : a.dmcCode.compareTo(b.dmcCode);
    }

    // Build thread objects for all dmcCodes that appear in the composite counts.
    // Source threads come from pattern.threads; blended composite threads come
    // from compositeLayer.fullStitches resolved threads.
    final allCompositeThreads = <String, Thread>{
      ...pattern.threads,
      for (final cs in compositeLayer.fullStitches.values) cs.resolvedThread.dmcCode: cs.resolvedThread,
    };
    final crossThreads = allCompositeThreads.values
        .where((t) => crossStitchEquiv.containsKey(t.dmcCode))
        .toList()
      ..sort(dmcSort);
    final backThreads = allCompositeThreads.values
        .where((t) => backStitchEquiv.containsKey(t.dmcCode))
        .toList()
      ..sort(dmcSort);

    // Build per-export symbol map.
    // In PatternKeeper mode every thread must have a symbol (auto-assigned if
    // the thread has none), so the PK text-layer import can identify every cell.
    final pdfSymbols = _buildPdfSymbolMap([
      ...crossThreads,
      ...backThreads.where((t) => !crossThreads.any((c) => c.dmcCode == t.dmcCode)),
    ], autoAssignMissing: patternKeeperMode);

    // Second pass for blended cells: crossStitchEquiv keys the composite thread's
    // dmcCode, not the original layers'. So the original layer threads may not be in
    // pdfSymbols. Fill any remaining blendedCellSymbols entries using the composite
    // thread's PDF-assigned symbol so blended cells render correctly in the chart.
    for (final entry in compositeLayer.fullStitches.entries) {
      if (!entry.value.isBlended) continue;
      if (blendedCellSymbols.containsKey(entry.key)) continue; // user composite symbol already set
      final sym = pdfSymbols[entry.value.resolvedThread.dmcCode] ?? '';
      if (symbolIsVisible(sym)) blendedCellSymbols[entry.key] = sym;
    }

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
    // PatternKeeper mode: minimum 7 pt per cell so symbols are legible.
    // Standard mode: minimum 4 pt (allows very large patterns to fit).
    final minCellSize = patternKeeperMode ? 7.0 : 4.0;
    final cellSize = math.min(12.0, math.max(minCellSize, math.min(cellByW, cellByH)));

    final maxStitchesPerPage = patternKeeperMode ? 60 : pattern.width.clamp(1, 99999);
    final colsPerPage = (usableW / cellSize).floor().clamp(1, math.min(pattern.width, maxStitchesPerPage));
    final rowsPerPage = (usableH / cellSize).floor().clamp(1, math.min(pattern.height, maxStitchesPerPage));
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
    // PatternKeeper mode skips the title page — page numbering starts at 1 for colour tables.
    final titlePageOffset = patternKeeperMode ? 0 : 1;
    final totalPages = titlePageOffset + colourTablePages + totalGridPages;

    // ── Page 1: Title page (skipped in PatternKeeper mode) ───────────────────

    if (!patternKeeperMode) {
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
        realistic: realistic,
      );
    }

    // ── Cross stitch colour table pages ───────────────────────────────────

    PdfGraphics? lastTableCanvas;
    double lastTableY = 0;

    for (int i = 0; i < crossTablePageCount; i++) {
      final pageNum = titlePageOffset + 1 + i;
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
        patternKeeperMode: patternKeeperMode,
      );
      lastTableCanvas = crossCanvas;
    }

    // ── Backstitch colour table pages (optional) ──────────────────────────

    for (int i = 0; i < backTablePageCount; i++) {
      final pageNum = titlePageOffset + 1 + crossTablePageCount + i;
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
        patternKeeperMode: patternKeeperMode,
      );
      lastTableCanvas = backCanvas;
    }

    // ── Materials section (optional, not included in PatternKeeper mode) ─────

    if (!patternKeeperMode && pattern.materialsSuggestions.isNotEmpty && lastTableCanvas != null) {
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
        pageNum: titlePageOffset + colourTablePages + 1,
        totalPages: totalPages,
        fonts: fonts,
        drawInitialFooter: !enoughRoom,
      );
    }

    // ── Chart pages ───────────────────────────────────────────────────────

    final chartPageOffset = titlePageOffset + colourTablePages + 1; // 1-based
    for (int pr = 0; pr < pagesRows; pr++) {
      for (int pc = 0; pc < pagesCols; pc++) {
        final startX = pc * colsPerPage.toInt();
        final startY = pr * rowsPerPage.toInt();
        final endX = math.min(startX + colsPerPage.toInt(), pattern.width);
        final endY = math.min(startY + rowsPerPage.toInt(), pattern.height);
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
          realistic: realistic,
          patternKeeperMode: patternKeeperMode,
        );
      }
    }

    return await doc.save();
  }

  /// Generate PDF and save to a user-chosen location via the file picker.
  static Future<void> exportPattern(
    CrossStitchPattern pattern, {
    bool useDmc = true,
  }) async {
    final bytes = await buildPdfBytes(pattern, useDmc: useDmc);
    final suggestedName = pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (isMobile) {
      // On iOS/Android the platform manages writing; bytes must be provided.
      await FilePicker.saveFile(
        fileName: '$suggestedName.pdf',
        type: FileType.any,
        bytes: bytes,
      );
    } else {
      final path = await FilePicker.saveFile(
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) return;
      final finalPath = path.endsWith('.pdf') ? path : '$path.pdf';
      await File(finalPath).writeAsBytes(bytes);
    }
  }

  /// Build a per-export symbol map: dmcCode → symbol char.
  /// Threads with symbols absent from the PDF fonts are omitted (treated as
  /// no symbol — blank cells in the chart).
  @visibleForTesting
  static Map<String, String> buildPdfSymbolMapForTest(List<Thread> threads) =>
      _buildPdfSymbolMap(threads);
}
