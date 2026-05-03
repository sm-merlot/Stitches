part of '../pdf_service.dart';

// ── Chart page ────────────────────────────────────────────────────────────

void _drawChartPage(
  PdfGraphics canvas, {
  required PdfPageFormat format,
  required CrossStitchPattern pattern,
  required List<Stitch> nonBack,
  required List<BackStitch> backstitches,
  required Map<String, Thread> threadMap,
  required Map<Cell, Color> blendedColors,
  required Map<Cell, Color> blendedCellColors,
  required Map<Cell, String> blendedCellSymbols,
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
  required bool realistic,
  bool patternKeeperMode = false,
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
  // In PatternKeeper mode embed an absolute-origin marker so the parser can
  // reassemble multi-page exports without relying on fragile heuristics.
  //
  // The marker includes the PDF-space centre of local col 0 (ox) and local
  // row 0 (oy) so the parser knows the true grid origin even when the first
  // visible rows/columns of a page are empty.
  //
  // v4 also embeds cellSize so the parser uses the exact grid step instead
  // of the heuristic refinement, which suffers from a systematic glyph-
  // baseline offset (text is drawn at baseline – fs*0.35 rather than at the
  // cell centre) that inflates the computed step and shifts the last few rows.
  //
  // ox = centre X of local col 0  = gridOriginX + cellSize/2
  // oy = centre Y of local row 0  = gridOriginY + (rows-1)*cellSize + cellSize/2
  //   (PDF Y increases upward, so row 0 has the LARGEST Y on the page)
  final pkOx = gridOriginX + cellSize / 2;
  final pkOy = gridOriginY + (rows - 1) * cellSize + cellSize / 2;
  final subtitle = patternKeeperMode
      ? 'PKCHART:$startX,$startY,$endX,$endY,${pkOx.toStringAsFixed(3)},${pkOy.toStringAsFixed(3)},${cellSize.toStringAsFixed(3)}'
          '  |  Cols ${startX + 1}-$endX, Rows ${startY + 1}-$endY  |  Page $pageNum of $totalPages'
      : 'Cols ${startX + 1}-$endX, Rows ${startY + 1}-$endY  |  Page $pageNum of $totalPages';
  _drawPageHeader(
    canvas,
    format: format,
    pattern: pattern,
    margin: margin,
    headerH: headerH,
    subtitle: subtitle,
    fonts: fonts,
  );

  // ── Background ───────────────────────────────────────────────────────
  // PatternKeeper mode: white background, no colour fills — symbols only.
  canvas.setFillColor(patternKeeperMode ? PdfColors.white : _pdfColor(pattern.aidaColor));
  canvas.drawRect(gridOriginX, gridOriginY, gridW, gridH);
  canvas.fillPath();

  // ── Stitch cells ─────────────────────────────────────────────────────
  for (final s in nonBack) {
    final cx = _stitches(s);
    final cy = _stitchY(s);
    if (cx < startX || cx >= endX || cy < startY || cy >= endY) continue;
    final thread = threadMap[s.threadId];
    if (thread == null) continue;

    final gx = gridOriginX + (cx - startX) * cellSize;
    final gy = gridOriginY + (rows - (cy - startY) - 1) * cellSize;

    final cellKey = Cell(cx, cy);
    final effectiveColor =
        blendedCellColors[cellKey] ?? blendedColors[cellKey] ?? thread.color;

    // Colour fill: skip in PatternKeeper mode (B&W symbols only).
    if (!patternKeeperMode) {
      canvas.setFillColor(_pdfColor(effectiveColor));
      _fillStitch(canvas, s, gx, gy, cellSize);
    }

    // Symbol centred in the stitch's sub-region (shown when sub-region >= 4 pt).
    // Blended cells use the composite symbol so the PDF grid matches the canvas.
    // In PK mode every cell always shows a symbol at the full-cell centre —
    // PatternKeeper treats all stitches as full cells, and sub-region sizes for
    // QuarterStitch / HalfCrossStitch (cs/2 ≈ 3.5 pt) would fail the 4 pt guard.
    //
    // In PatternKeeper mode: always use pdfSymbols[thread.dmcCode] (the symbolStitch
    // thread's own symbol) and never the composite blend-result symbol from
    // blendedCellSymbols.  Using the composite symbol would cause the import to
    // read the blend-result DMC code instead of the symbolStitch thread's DMC code,
    // breaking the round trip.  The symbolStitch thread IS guaranteed to be in
    // pdfSymbols because _buildPdfBytes augments crossStitchEquiv with all
    // symbolStitch threads in PK mode.
    final sym = patternKeeperMode
        ? pdfSymbols[thread.dmcCode] ?? ''
        : blendedCellSymbols[Cell(cx, cy)] ?? pdfSymbols[thread.dmcCode] ?? '';
    if (symbolIsVisible(sym)) {
      final double subSize;
      final double sx, sy;
      if (patternKeeperMode) {
        subSize = cellSize;
        sx = gx + cellSize / 2;
        sy = gy + cellSize / 2;
      } else {
        subSize = _stitchSubRegionSize(s, cellSize);
        (sx, sy) = _stitchSymbolCenter(s, gx, gy, cellSize);
      }
      if (subSize >= 4) {
        // In PK mode always use black text (white background).
        // In standard mode contrast against the fill colour.
        final PdfColor textColor;
        if (patternKeeperMode) {
          textColor = PdfColors.black;
        } else {
          final lum = effectiveColor.computeLuminance();
          textColor = lum > 0.35 ? PdfColors.black : PdfColors.white;
        }
        final fs = math.max(3.5, subSize * 0.44);
        canvas.setFillColor(textColor);
        final symFont = _fontFor(sym, fonts.regular, fonts.symbol);
        canvas.drawString(symFont, fs, sym,
            sx - _textWidth(symFont, fs, sym) / 2, sy - fs * 0.35);
      }
    }
  }

  // ── Backstitch lines (drawn above fills, before grid lines) ──────────
  // PatternKeeper does not support backstitches; skip in PK mode.
  if (!patternKeeperMode) canvas.setLineWidth(math.max(0.6, cellSize * 0.15));
  for (final bs in backstitches) {
    if (patternKeeperMode) break;
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
      final y = gridOriginY + gridH - r * cellSize; // mirrors row ruler formula
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

// ── Stitch fill helpers ─────────────────────────────────────────────────────

/// Fills the region of a stitch in PDF graphics coords.
/// gx/gy = bottom-left corner of the cell in PDF coords (y increases up).
void _fillStitch(
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

    // ThreeQuarterStitch: fill 3/4 of the cell anchored at quadrant corner
    case ThreeQuarterStitch(quadrant: QuadrantPosition.topLeft):
      canvas.drawRect(gx, gy + cs * 0.25, cs * 0.75, cs * 0.75);
      canvas.fillPath();
    case ThreeQuarterStitch(quadrant: QuadrantPosition.topRight):
      canvas.drawRect(gx + cs * 0.25, gy + cs * 0.25, cs * 0.75, cs * 0.75);
      canvas.fillPath();
    case ThreeQuarterStitch(quadrant: QuadrantPosition.bottomLeft):
      canvas.drawRect(gx, gy, cs * 0.75, cs * 0.75);
      canvas.fillPath();
    case ThreeQuarterStitch(quadrant: QuadrantPosition.bottomRight):
      canvas.drawRect(gx + cs * 0.25, gy, cs * 0.75, cs * 0.75);
      canvas.fillPath();

    case BackStitch():
      break;
  }
}

/// Returns the centre of the stitch's filled sub-region in PDF coordinates.
(double, double) _stitchSymbolCenter(
    Stitch s, double gx, double gy, double cs) {
  return switch (s) {
    FullStitch() || HalfStitch() => (gx + cs / 2, gy + cs / 2),
    // Screen topLeft  = PDF upper-left  → centre (gx+cs/4,   gy+3*cs/4)
    QuarterStitch(quadrant: QuadrantPosition.topLeft) =>
      (gx + cs / 4, gy + 3 * cs / 4),
    QuarterStitch(quadrant: QuadrantPosition.topRight) =>
      (gx + 3 * cs / 4, gy + 3 * cs / 4),
    QuarterStitch(quadrant: QuadrantPosition.bottomLeft) =>
      (gx + cs / 4, gy + cs / 4),
    QuarterStitch(quadrant: QuadrantPosition.bottomRight) =>
      (gx + 3 * cs / 4, gy + cs / 4),
    // ThreeQuarterStitch symbol in the middle of its 3/4 region
    ThreeQuarterStitch(quadrant: QuadrantPosition.topLeft) =>
      (gx + cs * 3 / 8, gy + cs * 5 / 8),
    ThreeQuarterStitch(quadrant: QuadrantPosition.topRight) =>
      (gx + cs * 5 / 8, gy + cs * 5 / 8),
    ThreeQuarterStitch(quadrant: QuadrantPosition.bottomLeft) =>
      (gx + cs * 3 / 8, gy + cs * 3 / 8),
    ThreeQuarterStitch(quadrant: QuadrantPosition.bottomRight) =>
      (gx + cs * 5 / 8, gy + cs * 3 / 8),
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
double _stitchSubRegionSize(Stitch s, double cs) => switch (s) {
      FullStitch() || HalfStitch() => cs,
      QuarterStitch() ||
      HalfCrossStitch(half: HalfOrientation.left || HalfOrientation.right) =>
        cs / 2,
      ThreeQuarterStitch() => cs * 0.75,
      HalfCrossStitch() => cs / 2,
      BackStitch() => cs,
    };

int _stitches(Stitch s) => switch (s) {
      FullStitch(x: final x) => x,
      HalfStitch(x: final x) => x,
      QuarterStitch(x: final x) => x,
      HalfCrossStitch(x: final x) => x,
      ThreeQuarterStitch(x: final x) => x,
      BackStitch() => 0,
    };

int _stitchY(Stitch s) => switch (s) {
      FullStitch(y: final y) => y,
      HalfStitch(y: final y) => y,
      QuarterStitch(y: final y) => y,
      HalfCrossStitch(y: final y) => y,
      ThreeQuarterStitch(y: final y) => y,
      BackStitch() => 0,
    };

// ── Realistic stitch line-art ─────────────────────────────────────────────

/// Draws a single thread line as a lens shape (thin at endpoints, thicker in
/// the middle) to mimic real thread bulging where it crosses.
/// Fill colour must be set by the caller.
void _drawThreadLensPdf(PdfGraphics canvas,
    double x1, double y1, double x2, double y2, double endW, double midW) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001) return;
  final px = -dy / len;
  final py = dx / len;
  final eOff = endW / 2;
  final mOff = midW / 2;
  final mx = (x1 + x2) / 2;
  final my = (y1 + y2) / 2;

  canvas.moveTo(x1 + px * eOff, y1 + py * eOff);
  canvas.curveTo(mx + px * mOff, my + py * mOff,
      mx + px * mOff, my + py * mOff, x2 + px * eOff, y2 + py * eOff);
  canvas.curveTo(mx - px * mOff, my - py * mOff,
      mx - px * mOff, my - py * mOff, x1 - px * eOff, y1 - py * eOff);
  canvas.closePath();
  canvas.fillPath();
}

/// Draws stitch shapes as lens-shaped thread lines.
/// gx/gy = bottom-left of the cell in PDF coords (y increases up).
/// Fill colour must be set by the caller; endW/midW control thread thickness.
void _drawRealisticStitch(PdfGraphics canvas, Stitch s,
    double gx, double gy, double cs, double endW, double midW) {
  void lens(double x1, double y1, double x2, double y2) =>
      _drawThreadLensPdf(canvas, x1, y1, x2, y2, endW, midW);

  switch (s) {
    case FullStitch():
      lens(gx, gy, gx + cs, gy + cs);
      lens(gx, gy + cs, gx + cs, gy);
    case HalfStitch(isForward: true):
      lens(gx, gy, gx + cs, gy + cs);
    case HalfStitch(isForward: false):
      lens(gx, gy + cs, gx + cs, gy);
    case QuarterStitch(quadrant: QuadrantPosition.topLeft):
      lens(gx, gy + cs / 2, gx + cs / 2, gy + cs);
    case QuarterStitch(quadrant: QuadrantPosition.topRight):
      lens(gx + cs / 2, gy + cs, gx + cs, gy + cs / 2);
    case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
      lens(gx, gy + cs / 2, gx + cs / 2, gy);
    case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
      lens(gx + cs / 2, gy, gx + cs, gy + cs / 2);
    case HalfCrossStitch(half: HalfOrientation.left):
      lens(gx, gy, gx + cs / 2, gy + cs);
      lens(gx, gy + cs, gx + cs / 2, gy);
    case HalfCrossStitch(half: HalfOrientation.right):
      lens(gx + cs / 2, gy, gx + cs, gy + cs);
      lens(gx + cs / 2, gy + cs, gx + cs, gy);
    case HalfCrossStitch(half: HalfOrientation.top):
      lens(gx, gy + cs / 2, gx + cs, gy + cs);
      lens(gx, gy + cs, gx + cs, gy + cs / 2);
    case HalfCrossStitch(half: HalfOrientation.bottom):
      lens(gx, gy, gx + cs, gy + cs / 2);
      lens(gx, gy + cs / 2, gx + cs, gy);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.topLeft, isForward: true):
      lens(gx + cs, gy + cs, gx, gy);
      lens(gx, gy + cs, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.topLeft, isForward: false):
      lens(gx, gy, gx + cs, gy + cs);
      lens(gx, gy + cs, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.topRight, isForward: true):
      lens(gx + cs, gy + cs, gx, gy);
      lens(gx + cs, gy + cs, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.topRight, isForward: false):
      lens(gx, gy, gx + cs, gy + cs);
      lens(gx + cs, gy + cs, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.bottomLeft, isForward: true):
      lens(gx + cs, gy + cs, gx, gy);
      lens(gx, gy, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.bottomLeft, isForward: false):
      lens(gx, gy, gx + cs, gy + cs);
      lens(gx, gy, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.bottomRight, isForward: true):
      lens(gx + cs, gy + cs, gx, gy);
      lens(gx + cs, gy, gx + cs / 2, gy + cs / 2);
    case ThreeQuarterStitch(quadrant: QuadrantPosition.bottomRight, isForward: false):
      lens(gx, gy, gx + cs, gy + cs);
      lens(gx + cs, gy, gx + cs / 2, gy + cs / 2);
    case BackStitch():
      break;
  }
}
