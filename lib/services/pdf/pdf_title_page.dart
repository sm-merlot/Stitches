part of '../pdf_service.dart';

// ── Title page ────────────────────────────────────────────────────────────

void _drawTitlePage(
  PdfGraphics canvas, {
  required PdfPage page,
  required PdfPageFormat format,
  required CrossStitchPattern pattern,
  required List<Stitch> nonBack,
  required List<BackStitch> backstitches,
  required Map<String, Thread> threadMap,
  required Map<Cell, Color> blendedColors,
  required double margin,
  required double footerH,
  required int pageNum,
  required int totalPages,
  required _PdfFonts fonts,
  required bool realistic,
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
    realistic: realistic,
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

void _drawMaterialsSection({
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
