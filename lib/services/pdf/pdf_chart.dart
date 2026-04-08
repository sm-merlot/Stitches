part of '../pdf_service.dart';

// ── Chart page ────────────────────────────────────────────────────────────

void _drawChartPage(
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
(double, double) _stitchSymbolCenter(
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
double _stitchSubRegionSize(Stitch s, double cs) => switch (s) {
      FullStitch() || HalfStitch() => cs,
      QuarterStitch() ||
      QuarterCrossStitch() ||
      HalfCrossStitch(half: HalfOrientation.left || HalfOrientation.right) =>
        cs / 2,
      HalfCrossStitch() => cs / 2,
      BackStitch() => cs,
    };

int _stitches(Stitch s) => switch (s) {
      FullStitch(x: final x) => x,
      HalfStitch(x: final x) => x,
      QuarterStitch(x: final x) => x,
      HalfCrossStitch(x: final x) => x,
      QuarterCrossStitch(x: final x) => x,
      BackStitch() => 0,
    };

int _stitchY(Stitch s) => switch (s) {
      FullStitch(y: final y) => y,
      HalfStitch(y: final y) => y,
      QuarterStitch(y: final y) => y,
      HalfCrossStitch(y: final y) => y,
      QuarterCrossStitch(y: final y) => y,
      BackStitch() => 0,
    };

// ── Realistic stitch line-art ─────────────────────────────────────────────

/// Draws stitch shapes as diagonal line-art (X, half-X, etc.).
/// gx/gy = bottom-left of the cell in PDF coords (y increases up).
/// Stroke colour and width must be set by the caller.
void _drawRealisticStitch(
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
