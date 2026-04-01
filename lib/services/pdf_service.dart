import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/aida_presets.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

class PdfService {
  /// Generate PDF and save via file picker.
  static Future<void> exportPattern(CrossStitchPattern pattern) async {
    final doc = pw.Document(title: pattern.name);
    final pdfFont = PdfFont.helvetica(doc.document);
    final pdfFontBold = PdfFont.helveticaBold(doc.document);

    // ── Data prep ──────────────────────────────────────────────────────────

    // Only export stitches from visible layers (respects group/layer visibility).
    final visibleStitches = pattern.layers
        .where((l) => l.visible)
        .expand((l) => l.stitches)
        .toList();

    // Per-thread stitch equivalents split into cross-type and backstitch
    final crossStitchEquiv = <String, double>{};
    final backStitchEquiv = <String, double>{};
    for (final s in visibleStitches) {
      if (s is BackStitch) {
        final v = math.sqrt(
            math.pow(s.x2 - s.x1, 2) + math.pow(s.y2 - s.y1, 2));
        backStitchEquiv[s.threadId] = (backStitchEquiv[s.threadId] ?? 0) + v;
      } else {
        final v = switch (s) {
          FullStitch() => 1.0,
          HalfStitch() => 0.5,
          QuarterStitch() => 0.25,
          HalfCrossStitch() => 0.5,
          QuarterCrossStitch() => 0.25,
          BackStitch() => 0.0,
        };
        crossStitchEquiv[s.threadId] =
            (crossStitchEquiv[s.threadId] ?? 0) + v;
      }
    }

    final backstitches = visibleStitches.whereType<BackStitch>().toList();
    final nonBack = visibleStitches.where((s) => s is! BackStitch).toList();
    final threadMap = {for (final t in pattern.threads) t.dmcCode: t};

    // Threads that have cross-type stitches / backstitches respectively
    final crossThreads = pattern.threads
        .where((t) => crossStitchEquiv.containsKey(t.dmcCode))
        .toList();
    final backThreads = pattern.threads
        .where((t) => backStitchEquiv.containsKey(t.dmcCode))
        .toList();

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
    // Page 1 = title, page 2 = cross colour table,
    // page 3 = backstitch table (optional), then chart pages.
    final colourTablePages = 1 + (backThreads.isEmpty ? 0 : 1);
    final totalPages = 1 + colourTablePages + totalGridPages;

    // ── Page 1: Title page ────────────────────────────────────────────────

    final titlePage = PdfPage(doc.document, pageFormat: pageFormat);
    _drawTitlePage(
      titlePage.getGraphics(),
      format: pageFormat,
      pattern: pattern,
      nonBack: nonBack,
      backstitches: backstitches,
      threadMap: threadMap,
      margin: margin,
      footerH: footerH,
      pageNum: 1,
      totalPages: totalPages,
      pdfFont: pdfFont,
      pdfFontBold: pdfFontBold,
    );

    // ── Page 2: Cross stitch colour table ─────────────────────────────────

    final crossTablePage = PdfPage(doc.document, pageFormat: pageFormat);
    _drawColourTablePage(
      crossTablePage.getGraphics(),
      format: pageFormat,
      pattern: pattern,
      threads: crossThreads,
      stitchEquiv: crossStitchEquiv,
      isBackstitch: false,
      margin: margin,
      headerH: headerH,
      footerH: footerH,
      pageNum: 2,
      totalPages: totalPages,
      pdfFont: pdfFont,
      pdfFontBold: pdfFontBold,
    );

    // ── Page 3 (optional): Backstitch colour table ────────────────────────

    if (backThreads.isNotEmpty) {
      final backTablePage = PdfPage(doc.document, pageFormat: pageFormat);
      _drawColourTablePage(
        backTablePage.getGraphics(),
        format: pageFormat,
        pattern: pattern,
        threads: backThreads,
        stitchEquiv: backStitchEquiv,
        isBackstitch: true,
        margin: margin,
        headerH: headerH,
        footerH: footerH,
        pageNum: 3,
        totalPages: totalPages,
        pdfFont: pdfFont,
        pdfFontBold: pdfFontBold,
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
          pdfFont: pdfFont,
          pdfFontBold: pdfFontBold,
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
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
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
      pdfFont: pdfFont,
      pdfFontBold: pdfFontBold,
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

      canvas.setFillColor(_pdfColor(thread.color));
      _fillStitch(canvas, s, gx, gy, cellSize);

      // Symbol centred in the stitch's sub-region (shown when sub-region >= 4 pt)
      if (thread.symbol.isNotEmpty) {
        final subSize = _stitchSubRegionSize(s, cellSize);
        if (subSize >= 4) {
          final sym = _ascii(thread.symbol);
          if (sym.isNotEmpty) {
            final (sx, sy) = _stitchSymbolCenter(s, gx, gy, cellSize);
            final lum = thread.color.computeLuminance();
            final textColor = lum > 0.35 ? PdfColors.black : PdfColors.white;
            final fs = math.max(3.5, subSize * 0.52);
            canvas.setFillColor(textColor);
            canvas.drawString(pdfFont, fs, sym, sx - fs * 0.55 / 2, sy - fs / 2 + 0.5);
          }
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
            pdfFont, rulerFs, label, x - lw / 2, gridOriginY + gridH + 3.5);
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
            pdfFont, rulerFs, label, gridOriginX - lw - 4, y - rulerFs / 2);
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
        pdfFont: pdfFont);
  }

  // ── Colour table page ─────────────────────────────────────────────────────

  static void _drawColourTablePage(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Thread> threads,
    required Map<String, double> stitchEquiv,
    required bool isBackstitch,
    required double margin,
    required double headerH,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
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
      pdfFont: pdfFont,
      pdfFontBold: pdfFontBold,
    );

    const tableFs = 7.5;
    const rowH = 14.0;
    const headRowH = 16.0;
    const sectionHeadFs = 9.0;
    const swatchW = 22.0;
    const dmcW = 44.0;
    const countW = 72.0;
    final tableW = format.width - 2 * margin;
    final nameW = tableW - swatchW - dmcW - countW;
    final colWidths = [swatchW, dmcW, nameW, countW];

    double y = format.height - margin - headerH;

    final sectionLabel = isBackstitch ? 'Backstitches' : 'Cross Stitches';
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(
        pdfFontBold, sectionHeadFs, sectionLabel, margin, y - sectionHeadFs);
    y -= sectionHeadFs + 6;

    final countHeader = isBackstitch ? 'Units (approx)' : 'Stitches (approx)';
    _drawTableRow(canvas,
        x: margin,
        y: y,
        colWidths: colWidths,
        rowH: headRowH,
        bgColor: PdfColors.grey200,
        cells: ['', 'DMC', 'Name', countHeader],
        font: pdfFontBold,
        fontSize: tableFs,
        isHeader: true);
    y -= headRowH;

    for (final t in threads) {
      final equiv = stitchEquiv[t.dmcCode] ?? 0;
      final equivStr = isBackstitch
          ? equiv.toStringAsFixed(1)
          : (equiv == equiv.truncateToDouble()
              ? equiv.toInt().toString()
              : equiv.toStringAsFixed(1));
      if (isBackstitch) {
        _drawTableRow(canvas,
            x: margin,
            y: y,
            colWidths: colWidths,
            rowH: rowH,
            bgColor: null,
            cells: ['', _ascii(t.dmcCode), _ascii(t.name), equivStr],
            font: pdfFont,
            fontSize: tableFs,
            isHeader: false,
            linePreviewColor: _pdfColor(t.color));
      } else {
        _drawTableRow(canvas,
            x: margin,
            y: y,
            colWidths: colWidths,
            rowH: rowH,
            bgColor: null,
            cells: ['', _ascii(t.dmcCode), _ascii(t.name), equivStr],
            font: pdfFont,
            fontSize: tableFs,
            isHeader: false,
            swatchColor: _pdfColor(t.color),
            swatchSymbol: _ascii(t.symbol));
      }
      y -= rowH;
    }

    _drawPageFooter(canvas,
        format: format,
        margin: margin,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        pdfFont: pdfFont);
  }

  // ── Title page ────────────────────────────────────────────────────────────

  static void _drawTitlePage(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Stitch> nonBack,
    required List<BackStitch> backstitches,
    required Map<String, Thread> threadMap,
    required double margin,
    required double footerH,
    required int pageNum,
    required int totalPages,
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
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
        // Rough multi-line estimate: ~80 chars per line at 10pt
        final chars = pattern.description!.length;
        final lines = (chars / 80).ceil().clamp(1, 6);
        metaBlockH += lines * 12.0 + 4;
      }
      if (pattern.copyright != null) metaBlockH += 10.0;
      metaBlockH += metaGap; // top gap before metadata
    }

    // ── Layout geometry ───────────────────────────────────────────────────
    // previewBudget = space between title block and footer, minus metadata
    final previewBudgetH = (pageH - 2 * margin - footerH -
            titleBlockH -
            metaBlockH)
        .clamp(80.0, 600.0);

    // ── Title (centred) ───────────────────────────────────────────────────
    final titleStr = _ascii(pattern.name);
    final titleY = pageH - margin - titleFs;
    final titleW = titleStr.length * titleFs * 0.55;
    final titleX = margin + (usableW - titleW) / 2;
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(pdfFontBold, titleFs, titleStr, titleX, titleY);

    // ── Subtitle (centred) ────────────────────────────────────────────────
    final subtitleStr = _ascii(
        '${pattern.width} x ${pattern.height} stitches  |  Page $pageNum of $totalPages');
    final subtitleW = subtitleStr.length * subtitleFs * 0.55;
    final subtitleX = margin + (usableW - subtitleW) / 2;
    canvas.setFillColor(PdfColors.grey600);
    canvas.drawString(pdfFont, subtitleFs, subtitleStr, subtitleX,
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
      final aidaLabel = _ascii(aidaColorLabel(pattern.aidaColor));
      canvas.setFillColor(PdfColors.grey700);
      canvas.drawString(pdfFont, 9.0, aidaLabel,
          margin + metaSwatchSize + 5, my - metaSwatchSize + 2);
      my -= metaSwatchSize + metaGap;

      void metaRow(String label, String value) {
        canvas.setFillColor(PdfColors.black);
        canvas.drawString(pdfFontBold, 9.0, _ascii('$label: '), margin, my);
        final labelW = ('$label: ').length * 9.0 * 0.55;
        canvas.drawString(pdfFont, 9.0, _ascii(value), margin + labelW, my);
        my -= metaRowH;
      }

      if (pattern.designer != null) metaRow('Designer', pattern.designer!);
      if (pattern.difficulty != null) metaRow('Difficulty', pattern.difficulty!);
      if (pattern.estimatedHours != null) metaRow('Est. time', pattern.estimatedHours!);

      if (pattern.description != null) {
        my -= 2;
        canvas.setFillColor(PdfColors.grey800);
        canvas.drawString(pdfFont, 10.0, _ascii(pattern.description!), margin, my);
        my -= 12.0 * (pattern.description!.length / 80).ceil().clamp(1, 6) + 4;
      }

      if (pattern.copyright != null) {
        canvas.setFillColor(PdfColors.grey600);
        canvas.drawString(pdfFont, 7.0, _ascii(pattern.copyright!), margin, my);
      }
    }

    // ── Footer ────────────────────────────────────────────────────────────
    _drawPageFooter(canvas,
        format: format,
        margin: margin,
        footerH: footerH,
        pageNum: pageNum,
        totalPages: totalPages,
        pdfFont: pdfFont);
  }

  // ── Stitch preview (realistic line-art, no symbols) ───────────────────────

  static void _drawStitchPreview(
    PdfGraphics canvas, {
    required double originX,
    required double originY,
    required CrossStitchPattern pattern,
    required List<Stitch> nonBack,
    required List<BackStitch> backstitches,
    required Map<String, Thread> threadMap,
    required double cellSize,
  }) {
    final pw2 = pattern.width * cellSize;
    final ph2 = pattern.height * cellSize;
    final rows = pattern.height;

    // Aida background
    canvas.setFillColor(_pdfColor(pattern.aidaColor));
    canvas.drawRect(originX, originY, pw2, ph2);
    canvas.fillPath();

    // Cross-type stitches as line-art (rounded caps for a thread-like look)
    canvas.setLineCap(PdfLineCap.round);
    final lw = math.max(0.35, cellSize * 0.18);
    canvas.setLineWidth(lw);

    for (final s in nonBack) {
      final cx = _stitches(s);
      final cy = _stitchY(s);
      final thread = threadMap[s.threadId];
      if (thread == null) continue;
      canvas.setStrokeColor(_pdfColor(thread.color));

      // gx/gy = bottom-left of this cell in PDF coords
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

  /// Draws a single stitch as crossed diagonal lines (no fill, line-art only).
  static void _drawRealisticStitch(
      PdfGraphics canvas, Stitch s, double gx, double gy, double cs) {
    // PDF: y increases up. gy = bottom, gy+cs = top of cell.
    switch (s) {
      case FullStitch():
        // "\" line: top-left → bottom-right
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();
        // "/" line: top-right → bottom-left
        canvas.moveTo(gx + cs, gy + cs);
        canvas.lineTo(gx, gy);
        canvas.strokePath();

      case HalfStitch(isForward: true): // "/"
        canvas.moveTo(gx + cs, gy + cs);
        canvas.lineTo(gx, gy);
        canvas.strokePath();

      case HalfStitch(isForward: false): // "\"
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();

      case QuarterStitch(quadrant: QuadrantPosition.topLeft):
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs / 2, gy + cs / 2);
        canvas.strokePath();
      case QuarterStitch(quadrant: QuadrantPosition.topRight):
        canvas.moveTo(gx + cs, gy + cs);
        canvas.lineTo(gx + cs / 2, gy + cs / 2);
        canvas.strokePath();
      case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.moveTo(gx, gy);
        canvas.lineTo(gx + cs / 2, gy + cs / 2);
        canvas.strokePath();
      case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.moveTo(gx + cs, gy);
        canvas.lineTo(gx + cs / 2, gy + cs / 2);
        canvas.strokePath();

      case HalfCrossStitch(half: HalfOrientation.left): // X in left half
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx, gy);
        canvas.strokePath();
      case HalfCrossStitch(half: HalfOrientation.right): // X in right half
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();
        canvas.moveTo(gx + cs, gy + cs);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();
      case HalfCrossStitch(half: HalfOrientation.top): // X in top half
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();
        canvas.moveTo(gx + cs, gy + cs);
        canvas.lineTo(gx, gy + cs / 2);
        canvas.strokePath();
      case HalfCrossStitch(half: HalfOrientation.bottom): // X in bottom half
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();
        canvas.moveTo(gx + cs, gy + cs / 2);
        canvas.lineTo(gx, gy);
        canvas.strokePath();

      case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
        canvas.moveTo(gx, gy + cs);
        canvas.lineTo(gx + cs / 2, gy + cs / 2);
        canvas.strokePath();
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx, gy + cs / 2);
        canvas.strokePath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
        canvas.moveTo(gx + cs / 2, gy + cs);
        canvas.lineTo(gx + cs, gy + cs / 2);
        canvas.strokePath();
        canvas.moveTo(gx + cs, gy + cs);
        canvas.lineTo(gx + cs / 2, gy + cs / 2);
        canvas.strokePath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
        canvas.moveTo(gx, gy + cs / 2);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();
        canvas.moveTo(gx + cs / 2, gy + cs / 2);
        canvas.lineTo(gx, gy);
        canvas.strokePath();
      case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
        canvas.moveTo(gx + cs / 2, gy + cs / 2);
        canvas.lineTo(gx + cs, gy);
        canvas.strokePath();
        canvas.moveTo(gx + cs, gy + cs / 2);
        canvas.lineTo(gx + cs / 2, gy);
        canvas.strokePath();

      case BackStitch():
        break;
    }
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
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
  }) {
    // Title
    const titleFs = 14.0;
    final titleY = format.height - margin - titleFs;
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(
        pdfFontBold, titleFs, _ascii(pattern.name), margin, titleY);

    // Subtitle
    const subtitleFs = 8.0;
    canvas.setFillColor(PdfColors.grey600);
    canvas.drawString(
        pdfFont, subtitleFs, _ascii(subtitle), margin, titleY - titleFs - 4);

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
    required PdfFont pdfFont,
  }) {
    const footerFs = 7.5;
    final ruleY = margin + footerH - 4;
    canvas.setStrokeColor(PdfColors.grey300);
    canvas.setLineWidth(0.5);
    canvas.moveTo(margin, ruleY);
    canvas.lineTo(format.width - margin, ruleY);
    canvas.strokePath();

    final label = 'Page $pageNum of $totalPages';
    final lw = label.length * footerFs * 0.55;
    canvas.setFillColor(PdfColors.grey600);
    canvas.drawString(
        pdfFont, footerFs, label, format.width / 2 - lw / 2, margin);
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
    required PdfFont font,
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
          canvas.setFillColor(textColor);
          final tw = sf * 0.55;
          canvas.drawString(font, sf, swatchSymbol,
              cx + pad + (cw - 2 * pad - tw) / 2,
              y - rowH + pad + (rowH - 2 * pad - sf) / 2 + 1.0);
        }
      } else if (cells[i].isNotEmpty) {
        canvas.setFillColor(PdfColors.black);
        final ty = y - rowH + (rowH - fontSize) / 2 + 1.0;
        canvas.drawString(font, fontSize, cells[i], cx + 3, ty);
      }

      cx += cw;
    }
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

  /// Strip characters outside printable ASCII — required by built-in PDF fonts.
  static String _ascii(String s) =>
      s.replaceAll(RegExp(r'[^\x20-\x7E]'), '');

  static PdfColor _pdfColor(Color c) =>
      PdfColor(c.r.toDouble(), c.g.toDouble(), c.b.toDouble());
}
