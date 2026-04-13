part of '../pdf_service.dart';

// ── Colour table page ─────────────────────────────────────────────────────

double _drawColourTablePage(
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

void _drawThreadRow(
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

// ── Stitch preview (line-art X shapes, no symbols) ───────────────────────

void _drawStitchPreview(
  PdfGraphics canvas, {
  required double originX,
  required double originY,
  required CrossStitchPattern pattern,
  required List<Stitch> nonBack,
  required List<BackStitch> backstitches,
  required Map<String, Thread> threadMap,
  required Map<String, Color> blendedColors,
  required double cellSize,
  bool realistic = true,
}) {
  final pw2 = pattern.width * cellSize;
  final ph2 = pattern.height * cellSize;
  final rows = pattern.height;

  // Aida background
  canvas.setFillColor(_pdfColor(pattern.aidaColor));
  canvas.drawRect(originX, originY, pw2, ph2);
  canvas.fillPath();

  if (realistic) {
    // Cross-type stitches as line-art using composited (deduplicated) stitches.
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineWidth(math.max(0.3, cellSize * 0.12));
    for (final s in nonBack) {
      final cx = _stitches(s);
      final cy = _stitchY(s);
      final thread = threadMap[s.threadId];
      if (thread == null) continue;
      final effectiveColor = blendedColors['$cx,$cy'] ?? thread.color;
      canvas.setStrokeColor(_pdfColor(effectiveColor));
      final gx = originX + cx * cellSize;
      final gy = originY + (rows - cy - 1) * cellSize;
      _drawRealisticStitch(canvas, s, gx, gy, cellSize);
    }
  } else {
    // Block rendering: solid colour rects.
    for (final s in nonBack) {
      final cx = _stitches(s);
      final cy = _stitchY(s);
      final thread = threadMap[s.threadId];
      if (thread == null) continue;
      final effectiveColor = blendedColors['$cx,$cy'] ?? thread.color;
      canvas.setFillColor(_pdfColor(effectiveColor));
      final gx = originX + cx * cellSize;
      final gy = originY + (rows - cy - 1) * cellSize;
      _fillStitch(canvas, s, gx, gy, cellSize);
    }
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

/// Draws a single table row.
/// - [swatchColor] + [swatchSymbol]: col 0 filled with colour + symbol text centred on top.
/// - [linePreviewColor]: col 0 shows a thick coloured horizontal line (for backstitches).
void _drawTableRow(
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
