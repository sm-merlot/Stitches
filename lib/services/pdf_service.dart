import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

    // Per-thread approximate full-stitch equivalents
    final stitchEquiv = <String, double>{};
    for (final s in pattern.stitches) {
      final v = switch (s) {
        FullStitch() => 1.0,
        HalfStitch() => 0.5,
        QuarterStitch() => 0.25,
        HalfCrossStitch() => 0.5,
        QuarterCrossStitch() => 0.25,
        BackStitch(x1: final x1, y1: final y1, x2: final x2, y2: final y2) =>
          math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2)),
      };
      stitchEquiv[s.threadId] = (stitchEquiv[s.threadId] ?? 0) + v;
    }

    final backstitches = pattern.stitches.whereType<BackStitch>().toList();
    final nonBack = pattern.stitches.where((s) => s is! BackStitch).toList();
    final threadMap = {for (final t in pattern.threads) t.dmcCode: t};

    // Symbol map: last non-backstitch stitch drawn per cell -> thread
    final symbolMap = <(int, int), Thread>{};
    for (final s in nonBack) {
      final cx = _stitchX(s), cy = _stitchY(s);
      final t = threadMap[s.threadId];
      if (t != null) symbolMap[(cx, cy)] = t;
    }

    // ── Grid layout ────────────────────────────────────────────────────────

    final landscapeFormat = PdfPageFormat.a4.landscape;
    const margin = 36.0;
    const headerH = 18.0;
    final usableW = landscapeFormat.width - 2 * margin;
    final usableH = landscapeFormat.height - 2 * margin - headerH - 6;

    final cellByW = usableW / pattern.width;
    final cellByH = usableH / pattern.height;
    final cellSize = math.min(18.0, math.max(3.0, math.min(cellByW, cellByH)));

    final colsPerPage = (usableW / cellSize).floor().clamp(1, pattern.width);
    final rowsPerPage = (usableH / cellSize).floor().clamp(1, pattern.height);
    final pagesCols = (pattern.width / colsPerPage).ceil();
    final pagesRows = (pattern.height / rowsPerPage).ceil();
    final totalGridPages = pagesCols * pagesRows;

    // ── Grid pages ─────────────────────────────────────────────────────────

    for (int pr = 0; pr < pagesRows; pr++) {
      for (int pc = 0; pc < pagesCols; pc++) {
        final startX = pc * colsPerPage;
        final startY = pr * rowsPerPage;
        final endX = math.min(startX + colsPerPage, pattern.width);
        final endY = math.min(startY + rowsPerPage, pattern.height);
        final pageNum = pr * pagesCols + pc + 1;

        final page = PdfPage(doc.document, pageFormat: landscapeFormat);
        final canvas = page.getGraphics();

        _drawGridPage(
          canvas,
          format: landscapeFormat,
          pattern: pattern,
          nonBack: nonBack,
          backstitches: backstitches,
          threadMap: threadMap,
          symbolMap: symbolMap,
          cellSize: cellSize,
          startX: startX,
          startY: startY,
          endX: endX,
          endY: endY,
          margin: margin,
          headerH: headerH,
          pageNum: pageNum,
          totalPages: totalGridPages,
          pdfFont: pdfFont,
          pdfFontBold: pdfFontBold,
        );
      }
    }

    // ── Legend page ────────────────────────────────────────────────────────

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => _buildLegendPage(
        pattern: pattern,
        stitchEquiv: stitchEquiv,
      ),
    ));

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

  // ── Grid page ─────────────────────────────────────────────────────────────

  static void _drawGridPage(
    PdfGraphics canvas, {
    required PdfPageFormat format,
    required CrossStitchPattern pattern,
    required List<Stitch> nonBack,
    required List<BackStitch> backstitches,
    required Map<String, Thread> threadMap,
    required Map<(int, int), Thread> symbolMap,
    required double cellSize,
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    required double margin,
    required double headerH,
    required int pageNum,
    required int totalPages,
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
  }) {
    final cols = endX - startX;
    final rows = endY - startY;
    final gridW = cols * cellSize;
    final gridH = rows * cellSize;

    // Grid origin: bottom-left in PDF coords (y=0 at page bottom)
    final gridOriginX = margin;
    final gridOriginY = format.height - margin - headerH - 6 - gridH;

    // ── Header ──────────────────────────────────────────────────────────
    final headerY = format.height - margin - 11;
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(pdfFontBold, 11, _ascii(pattern.name), margin, headerY);

    final pageLabel =
        'Page $pageNum of $totalPages  |  '
        'Cols ${startX + 1}-$endX  Rows ${startY + 1}-$endY  |  '
        '${pattern.width} x ${pattern.height} stitches';
    final labelW = pageLabel.length * 8 * 0.55;
    canvas.drawString(pdfFont, 8, pageLabel,
        format.width - margin - labelW, headerY - 1);

    // ── Aida background ─────────────────────────────────────────────────
    canvas.setFillColor(_pdfColor(pattern.aidaColor));
    canvas.drawRect(gridOriginX, gridOriginY, gridW, gridH);
    canvas.fillPath();

    // ── Stitch lines (mirrors canvas_painter.dart exactly) ──────────────
    final lineWidth = math.max(0.5, cellSize * 0.12);
    canvas.setLineWidth(lineWidth);

    for (final s in nonBack) {
      final cx = _stitchX(s);
      final cy = _stitchY(s);
      if (cx < startX || cx >= endX || cy < startY || cy >= endY) continue;

      final thread = threadMap[s.threadId];
      if (thread == null) continue;
      canvas.setStrokeColor(_pdfColor(thread.color));

      // Cell corners in PDF coords
      final gx = gridOriginX + (cx - startX) * cellSize;
      final gy = gridOriginY + (rows - (cy - startY) - 1) * cellSize;
      // Shorthand: PDF top of cell = gy+cellSize, bottom = gy
      // Flutter top-left  -> PDF (gx,        gy+cellSize)
      // Flutter top-right -> PDF (gx+cellSize, gy+cellSize)
      // Flutter bot-left  -> PDF (gx,        gy)
      // Flutter bot-right -> PDF (gx+cellSize, gy)
      final tl = (gx, gy + cellSize);
      final tr = (gx + cellSize, gy + cellSize);
      final bl = (gx, gy);
      final br = (gx + cellSize, gy);
      final cx2 = gx + cellSize / 2;
      final cy2 = gy + cellSize / 2;
      final midLT = (gx, gy + cellSize / 2);          // left edge mid
      final midRT = (gx + cellSize, gy + cellSize / 2); // right edge mid
      final midTT = (gx + cellSize / 2, gy + cellSize); // top edge mid
      final midBT = (gx + cellSize / 2, gy);            // bottom edge mid

      switch (s) {
        case FullStitch():
          _line(canvas, tl, br); // \
          _line(canvas, tr, bl); // /
        case HalfStitch(isForward: true):
          _line(canvas, tr, bl); // /
        case HalfStitch(isForward: false):
          _line(canvas, tl, br); // \
        case QuarterStitch(quadrant: QuadrantPosition.topLeft):
          _line(canvas, tl, (cx2, cy2));
        case QuarterStitch(quadrant: QuadrantPosition.topRight):
          _line(canvas, tr, (cx2, cy2));
        case QuarterStitch(quadrant: QuadrantPosition.bottomLeft):
          _line(canvas, bl, (cx2, cy2));
        case QuarterStitch(quadrant: QuadrantPosition.bottomRight):
          _line(canvas, br, (cx2, cy2));
        case HalfCrossStitch(half: HalfOrientation.left):
          _line(canvas, tl, (cx2, gy));    // \ in left half
          _line(canvas, (cx2, gy + cellSize), bl); // / in left half
        case HalfCrossStitch(half: HalfOrientation.right):
          _line(canvas, (cx2, gy + cellSize), br); // \ in right half
          _line(canvas, tr, (cx2, gy));             // / in right half
        case HalfCrossStitch(half: HalfOrientation.top):
          _line(canvas, tl, midRT);  // \ in top half
          _line(canvas, tr, midLT);  // / in top half
        case HalfCrossStitch(half: HalfOrientation.bottom):
          _line(canvas, midLT, br);  // \ in bottom half
          _line(canvas, midRT, bl);  // / in bottom half
        case QuarterCrossStitch(quadrant: QuadrantPosition.topLeft):
          _line(canvas, tl, (cx2, cy2));       // \ in top-left quarter
          _line(canvas, midTT, midLT);          // / in top-left quarter
        case QuarterCrossStitch(quadrant: QuadrantPosition.topRight):
          _line(canvas, midTT, midRT);          // \ in top-right quarter
          _line(canvas, tr, (cx2, cy2));        // / in top-right quarter
        case QuarterCrossStitch(quadrant: QuadrantPosition.bottomLeft):
          _line(canvas, midLT, midBT);          // \ in bottom-left quarter
          _line(canvas, (cx2, cy2), bl);        // / in bottom-left quarter
        case QuarterCrossStitch(quadrant: QuadrantPosition.bottomRight):
          _line(canvas, (cx2, cy2), br);        // \ in bottom-right quarter
          _line(canvas, midRT, midBT);          // / in bottom-right quarter
        case BackStitch():
          break;
      }
    }

    // ── Minor grid lines ─────────────────────────────────────────────────
    canvas.setStrokeColor(PdfColors.grey400);
    canvas.setLineWidth(0.25);
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
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.75);
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

    // ── Symbol overlay (one per cell, cellSize >= 8pt) ───────────────────
    if (cellSize >= 8) {
      for (final entry in symbolMap.entries) {
        final (cx, cy) = entry.key;
        if (cx < startX || cx >= endX || cy < startY || cy >= endY) continue;
        final thread = entry.value;
        if (thread.symbol.isEmpty) continue;

        final gx = gridOriginX + (cx - startX) * cellSize;
        final gy = gridOriginY + (rows - (cy - startY) - 1) * cellSize;
        final fs = math.max(4.0, cellSize * 0.46);
        final lum = thread.color.computeLuminance();
        final textColor = lum > 0.35 ? PdfColors.black : PdfColors.white;

        // Badge background
        final bgW = fs * 0.9 + 4;
        final bgH = fs + 3;
        final bgX = gx + (cellSize - bgW) / 2;
        final bgY = gy + (cellSize - bgH) / 2;
        canvas.setFillColor(_pdfColor(thread.color));
        canvas.drawRRect(bgX, bgY, bgW, bgH, 2, 2);
        canvas.fillPath();

        canvas.setFillColor(textColor);
        final sym = _ascii(thread.symbol);
        if (sym.isNotEmpty) {
          final tx = gx + (cellSize - fs * 0.55) / 2;
          final ty = gy + (cellSize - fs) / 2;
          canvas.drawString(pdfFont, fs, sym, tx, ty);
        }
      }
    }

    // ── Ruler labels at every 10th line ──────────────────────────────────
    if (cellSize >= 6) {
      const labelFs = 5.0;
      canvas.setFillColor(PdfColors.grey700);
      for (int c = 1; c <= cols; c++) {
        if ((startX + c) % 10 == 0) {
          canvas.drawString(pdfFont, labelFs, '${startX + c}',
              gridOriginX + c * cellSize + 1,
              gridOriginY + gridH - labelFs - 1);
        }
      }
      for (int r = 1; r <= rows; r++) {
        if ((startY + r) % 10 == 0) {
          canvas.drawString(pdfFont, labelFs, '${startY + r}',
              gridOriginX + 1,
              gridOriginY + gridH - r * cellSize - labelFs - 1);
        }
      }
    }

    // ── Backstitch lines ─────────────────────────────────────────────────
    canvas.setLineWidth(math.max(0.5, cellSize * 0.08));
    for (final bs in backstitches) {
      final minBx = math.min(bs.x1, bs.x2);
      final maxBx = math.max(bs.x1, bs.x2);
      final minBy = math.min(bs.y1, bs.y2);
      final maxBy = math.max(bs.y1, bs.y2);
      if (maxBx < startX || minBx > endX || maxBy < startY || minBy > endY) continue;

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
  }

  // ── Legend page ───────────────────────────────────────────────────────────

  static pw.Widget _buildLegendPage({
    required CrossStitchPattern pattern,
    required Map<String, double> stitchEquiv,
  }) {
    final totalEquiv = stitchEquiv.values.fold(0.0, (a, b) => a + b);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(_ascii(pattern.name),
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${pattern.width} x ${pattern.height} stitches  |  '
          '${pattern.threads.length} colours  |  '
          '${totalEquiv.round()} stitch equivalents',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Thread Legend',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(18),
            1: pw.FixedColumnWidth(42),
            2: pw.FlexColumnWidth(3),
            3: pw.FixedColumnWidth(38),
            4: pw.FixedColumnWidth(80),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: ['', 'DMC', 'Name', 'Symbol', 'Stitches (approx)']
                  .map(_headerCell)
                  .toList(),
            ),
            ...pattern.threads.map((t) {
              final equiv = stitchEquiv[t.dmcCode] ?? 0;
              final equivStr = equiv == equiv.truncateToDouble()
                  ? equiv.toInt().toString()
                  : equiv.toStringAsFixed(1);
              return pw.TableRow(children: [
                pw.Container(width: 18, height: 18, color: _pdfColor(t.color)),
                _dataCell(_ascii(t.dmcCode)),
                _dataCell(_ascii(t.name)),
                _dataCell(_ascii(t.symbol)),
                _dataCell(equivStr),
              ]);
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _headerCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _dataCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Draw a line between two (x, y) record points and stroke immediately.
  static void _line(
      PdfGraphics canvas, (double, double) from, (double, double) to) {
    canvas.moveTo(from.$1, from.$2);
    canvas.lineTo(to.$1, to.$2);
    canvas.strokePath();
  }

  static int _stitchX(Stitch s) => switch (s) {
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
      s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  static PdfColor _pdfColor(Color c) =>
      PdfColor(c.r.toDouble(), c.g.toDouble(), c.b.toDouble());
}
