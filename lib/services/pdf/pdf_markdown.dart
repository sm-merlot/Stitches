part of '../pdf_service.dart';

typedef _TextRun = ({String text, bool bold, bool italic, bool sym});

// ── Markdown renderer ─────────────────────────────────────────────────────

/// Parses markdown source into layout blocks for PDF rendering.
({
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
List<_TextRun> _collectRuns(
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
List<List<_TextRun>> _wrapRuns(
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
double _renderMarkdown(
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
