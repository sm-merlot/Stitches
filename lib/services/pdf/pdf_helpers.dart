part of '../pdf_service.dart';

typedef _PdfFonts = ({
  PdfFont regular,
  PdfFont bold,
  PdfFont italic,
  PdfFont symbol
});

// ── Shared page components ────────────────────────────────────────────────

/// Draws the title + subtitle + separator rule at the top of any page.
void _drawPageHeader(
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
void _drawPageFooter(
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
PdfFont _fontFor(String text, PdfFont base, PdfFont sym) {
  for (final rune in text.runes) {
    if (rune >= 0x2200) return sym;
  }
  return base;
}

/// Returns the advance width of [text] rendered at [fontSize] with [font].
double _textWidth(PdfFont font, double fontSize, String text) =>
    font.stringMetrics(text).advanceWidth * fontSize;

// kPdfUnsupportedSymbols is the canonical source — defined in symbols.dart.

Map<String, String> _buildPdfSymbolMap(
  List<Thread> threads, {
  bool autoAssignMissing = false,
}) {
  final usedSymbols = <String>{};
  final result = <String, String>{};

  // First pass: use each thread's assigned symbol where valid (both modes).
  for (final t in threads) {
    if (symbolIsVisible(t.symbol) && !kPdfUnsupportedSymbols.contains(t.symbol)) {
      result[t.dmcCode] = t.symbol;
      usedSymbols.add(t.symbol);
    }
  }

  if (!autoAssignMissing) return result;

  // Second pass (PK mode): auto-assign from kPatternSymbols for threads with
  // no symbol, so every thread has a unique identifier in the legend and chart.
  final pool = kPatternSymbols
      .where((s) => !kPdfUnsupportedSymbols.contains(s) && !usedSymbols.contains(s))
      .toList();
  int poolIdx = 0;
  for (final t in threads) {
    if (result.containsKey(t.dmcCode)) continue;
    if (poolIdx >= pool.length) break;
    result[t.dmcCode] = pool[poolIdx++];
  }
  return result;
}

PdfColor _pdfColor(Color c) =>
    PdfColor(c.r.toDouble(), c.g.toDouble(), c.b.toDouble());
