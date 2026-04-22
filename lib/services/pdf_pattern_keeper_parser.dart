import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/dmc_colors.dart';
import 'scan_result.dart';

/// Tier-1 PDF import: parse a PatternKeeper-compatible (text-native) PDF
/// directly from its text layer — no rasterisation, no user input required.
///
/// PatternKeeper-style PDFs embed symbols as selectable TTF characters.
/// The legend table maps each symbol character to a DMC code.  The chart
/// pages are a regular grid of those same characters.
///
/// Returns null (and logs why) if the PDF is not text-native or does not
/// match the expected structure.  The caller should fall through to the
/// raster-based Tier-2 scan in that case.
class PatternKeeperParser {
  PatternKeeperParser._();

  static const _kMinColors = 5;        // legend entries needed (raise to reduce false positives)
  static const _kMinGridCells = 8;     // symbols per page to count as a grid page
  static const _kMinFillRatio = 0.02;  // assembled stitches / (w×h) must exceed this

  // ─── Public entry point ───────────────────────────────────────────────────

  /// Extract raw page text data from [pdfPath] without parsing.
  ///
  /// Returns one [PageTextData?] per page (null when a page fails extraction).
  /// Returns null if the file cannot be opened.
  /// Useful for CLI diagnostics: inspect exactly what pdfrx extracts.
  static Future<List<PageTextData?>?> extractPageText(String pdfPath) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      final pages = <PageTextData?>[];
      for (final page in doc.pages) {
        try {
          final pt = await page.loadStructuredText();
          pages.add(PageTextData(
            fullText: pt.fullText,
            fragments: pt.fragments
                .map((f) => TextFragment(
                      text: f.text,
                      left: f.bounds.left,
                      top: f.bounds.top,
                      right: f.bounds.right,
                      bottom: f.bounds.bottom,
                    ))
                .toList(),
          ));
        } catch (_) {
          pages.add(null);
        }
      }
      return pages;
    } catch (e, st) {
      debugPrint('[PKParser] extractPageText error: $e\n$st');
      return null;
    } finally {
      await doc?.dispose();
    }
  }

  /// Try to parse [pdfPath] as a PatternKeeper-compatible PDF.
  ///
  /// Returns a [PatternScanResult] on success, or null when the PDF is raster
  /// or does not follow the PK legend/grid structure.  Never throws.
  static Future<PatternScanResult?> tryParse(String pdfPath) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);

      final pages = <PageTextData?>[];
      for (final page in doc.pages) {
        try {
          final pt = await page.loadStructuredText();
          pages.add(PageTextData(
            fullText: pt.fullText,
            fragments: pt.fragments
                .map((f) => TextFragment(
                      text: f.text,
                      left: f.bounds.left,
                      top: f.bounds.top,
                      right: f.bounds.right,
                      bottom: f.bounds.bottom,
                    ))
                .toList(),
          ));
        } catch (_) {
          pages.add(null);
        }
      }

      return tryParseFromText(pages);
    } catch (e, st) {
      debugPrint('[PKParser] parse error: $e\n$st');
      return null;
    } finally {
      await doc?.dispose();
    }
  }

  /// Parse pre-extracted page text data into a [PatternScanResult].
  ///
  /// This is the core logic, decoupled from pdfrx so it can be tested
  /// without native PDF libraries.
  static PatternScanResult? tryParseFromText(List<PageTextData?> pages) {
    // Reject raster PDFs: need a meaningful amount of text.
    final totalChars =
        pages.fold(0, (s, t) => s + (t?.fullText.length ?? 0));
    if (totalChars < 100) {
      debugPrint('[PKParser] not text-native ($totalChars chars total)');
      return null;
    }

    final legend = _parseLegend(pages);
    if (legend.length < _kMinColors) {
      debugPrint(
          '[PKParser] legend too small (${legend.length} entries) — not PK format');
      return null;
    }
    debugPrint('[PKParser] legend: ${legend.length} symbol→DMC entries');

    final pageGrids = _parseAllGrids(pages, legend);
    if (pageGrids.isEmpty) {
      debugPrint('[PKParser] no grid pages found');
      return null;
    }

    final result = _assembleResult(pageGrids, legend);
    if (result.stitches.isEmpty) {
      debugPrint('[PKParser] no stitches after assembly');
      return null;
    }

    // Reject sparse results: likely a raster PDF with incidental text matches.
    final fillRatio = result.stitches.length / (result.width * result.height);
    if (fillRatio < _kMinFillRatio) {
      debugPrint('[PKParser] fill ratio too low '
          '(${result.stitches.length}/${result.width * result.height} = '
          '${(fillRatio * 100).toStringAsFixed(1)}%) — not PK format');
      return null;
    }

    debugPrint('[PKParser] success: ${result.width}×${result.height}, '
        '${result.stitches.length} stitches, ${result.threads.length} threads');
    return result;
  }

  // ─── Legend parsing ───────────────────────────────────────────────────────

  /// Scan all pages for rows that contain a known DMC code and extract
  /// the associated symbol character.  Returns symbol → dmcCode.
  ///
  /// Handles two PDF extraction modes:
  ///  • Per-word fragments (pdfrx/PDFium default): each word is its own fragment.
  ///  • Whole-line fragments (some third-party generators): one fragment per row.
  ///    In this case we split on whitespace to get sub-tokens.
  static Map<String, String> _parseLegend(List<PageTextData?> pages) {
    final legend = <String, String>{};

    for (final page in pages) {
      if (page == null) continue;
      final frags = page.fragments;
      if (frags.isEmpty) continue;

      // Skip chart pages: the PKCHART marker is only present on grid pages.
      // Scanning them for legend entries produces false positives — thread
      // name words (e.g. "Red", "Tan") and stitch counts (e.g. "301") that
      // happen to match valid DMC codes get treated as symbol→DMC mappings.
      // For third-party PDFs (no PKCHART marker), all pages are scanned as
      // before, which is the correct fallback for unknown page structures.
      if (page.fullText.contains('PKCHART:')) continue;

      // Group fragments into horizontal rows by Y position.
      final rows = _groupByY(frags);

      for (final row in rows.values) {
        // Expand each fragment into (text, approximateX, isInline) tokens.
        // A fragment may be a single word OR an entire row (third-party PDFs).
        // Splitting on whitespace handles both cases uniformly.
        // isInline=true marks sub-tokens distributed from a single multi-word
        // fragment; the proximity guard is relaxed for them (their computed
        // x-positions are approximate and may be unrealistically far apart).
        final tokens = <({String text, double left, bool isInline})>[];
        for (final f in row) {
          final raw = f.text.trim();
          if (raw.isEmpty) continue;
          final parts = raw.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            // Distribute X positions evenly across sub-tokens.
            final fWidth = f.right - f.left;
            final partW = fWidth / parts.length;
            for (int i = 0; i < parts.length; i++) {
              if (parts[i].isNotEmpty) {
                tokens.add((text: parts[i], left: f.left + i * partW, isInline: true));
              }
            }
          } else {
            tokens.add((text: raw, left: f.left, isInline: false));
          }
        }

        // Sort left-to-right so the DMC-code column (small x) is always
        // processed before the stitch-count column (large x).  pdfrx may
        // return fragments in content-stream order (e.g. right-to-left by
        // column), causing a stitch-count that happens to equal a valid DMC
        // code to steal the symbol from the real DMC code token.
        tokens.sort((a, b) => a.left.compareTo(b.left));

        // Any token that is a valid DMC code?
        final dmcTokens =
            tokens.where((t) => dmcColorByCode(t.text) != null).toList();
        if (dmcTokens.isEmpty) continue;

        for (final dmcTok in dmcTokens) {
          final dmcCode = dmcTok.text;

          // Symbol detection — two formats:
          //
          // A. StitchX/PK-style:       "[symbol] [code] [name]"
          //    "[symbol] DMC [code]"   (Dachshund / third-party)
          //    Symbol is within ~25pt of the code; proximity guard ≤ 40pt.
          //
          // B. Artecy/HAED-style: "[symbol] [strands] DMC [code] [name]"
          //    An explicit 'DMC' literal separates the symbol+strands column
          //    from the code column.  The strand count (a 1–2 digit number)
          //    sits immediately left of 'DMC' and must be skipped.
          //    No proximity guard needed — the DMC literal is the anchor.
          const kMaxSymbolDmcGap = 40.0;
          String? symbol;
          double? symbolX;

          // Detect Format B: is there a 'DMC' literal to the left of the code?
          final dmcLiteralList = tokens
              .where((t) =>
                  t.text.toUpperCase() == 'DMC' && t.left < dmcTok.left)
              .toList();
          final dmcLiteral =
              dmcLiteralList.isEmpty ? null : dmcLiteralList.last;

          if (dmcLiteral != null) {
            // Format B: collect candidates left of the 'DMC' literal.
            final candidates = tokens
                .where((t) =>
                    t.left < dmcLiteral.left &&
                    t.text.isNotEmpty &&
                    t.text.length <= 3 &&
                    dmcColorByCode(t.text) == null)
                .toList();
            // Drop the rightmost pure-digit token — that's the strands count
            // (e.g. '2' in "Ò 2 DMC 827 Blue-VY LT").  Only drop it when
            // other candidates remain so a digit symbol isn't incorrectly lost.
            final strandIdx = candidates
                .lastIndexWhere((t) => RegExp(r'^\d+$').hasMatch(t.text));
            if (strandIdx >= 0 && candidates.length > 1) {
              candidates.removeAt(strandIdx);
            }
            if (candidates.isNotEmpty) {
              final symTok =
                  candidates.reduce((a, b) => a.left > b.left ? a : b);
              symbol = symTok.text;
              symbolX = symTok.left;
            }
          } else {
            // Format A: proximity-guarded search left of the code token.
            for (final tok in tokens) {
              if (tok.text == dmcCode) continue;
              if (tok.text.isEmpty || tok.text.length > 3) continue;
              if (dmcColorByCode(tok.text) != null) continue;
              if (tok.left >= dmcTok.left) continue;
              // Proximity guard: skip when both tokens are per-word fragments
              // and the symbol is suspiciously far (> 40pt) from the code.
              // Rejects thread-name words and stitch-count false positives.
              // Not applied to inline (whole-line-split) tokens whose x
              // positions are approximate.
              if (!tok.isInline && !dmcTok.isInline &&
                  dmcTok.left - tok.left > kMaxSymbolDmcGap) {
                continue;
              }
              // Skip the literal "DMC" prefix (Dachshund/third-party format).
              if (tok.text.toUpperCase() == 'DMC') continue;
              if (symbol == null || tok.left > symbolX!) {
                symbol = tok.text;
                symbolX = tok.left;
              }
            }
          }

          if (symbol != null && !legend.containsKey(symbol)) {
            legend[symbol] = dmcCode;
          }
        }
      }
    }

    return legend;
  }

  // ─── Grid parsing ─────────────────────────────────────────────────────────

  // Regex matching the PKCHART marker embedded in StitchX-exported PK PDFs.
  //
  // Supported formats (all backward-compatible):
  //   v1: PKCHART:startCol,startRow
  //   v2: PKCHART:startCol,startRow,endCol,endRow
  //   v3: PKCHART:startCol,startRow,endCol,endRow,ox,oy
  //         ox = PDF-space centre X of local col 0
  //         oy = PDF-space centre Y of local row 0 (largest Y = visually top)
  //   v4: PKCHART:startCol,startRow,endCol,endRow,ox,oy,cellSize
  //         cellSize = exact PDF-space cell size in points (both X and Y)
  //         Using the embedded cellSize avoids the heuristic step refinement,
  //         which suffers from a systematic glyph-baseline offset that inflates
  //         the computed step and shifts the last few rows of each page.
  static final _kPkChartRe = RegExp(
      r'PKCHART:(\d+),(\d+)(?:,(\d+),(\d+)(?:,([\d.]+),([\d.]+)(?:,([\d.]+))?)?)?');

  static List<_PageGrid> _parseAllGrids(
      List<PageTextData?> pages, Map<String, String> legend) {
    final symbolSet = legend.keys.toSet();
    final grids = <_PageGrid>[];

    for (int pi = 0; pi < pages.length; pi++) {
      final page = pages[pi];
      if (page == null) continue;

      // Scan full joined text for PKCHART marker (pdfrx may split subtitle into
      // word-level fragments, so fragment-by-fragment scanning misses it).
      int? pkStartCol, pkStartRow, pkEndCol, pkEndRow;
      double? pkOriginX, pkOriginY, pkCellSize;
      final fullText = page.fullText;
      final m = _kPkChartRe.firstMatch(fullText);
      if (m != null) {
        pkStartCol = int.tryParse(m.group(1)!);
        pkStartRow = int.tryParse(m.group(2)!);
        pkEndCol   = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
        pkEndRow   = m.group(4) != null ? int.tryParse(m.group(4)!) : null;
        // v3 marker: explicit PDF-space grid origin (fixes empty-edge offset bug).
        // Guard groupCount in case binary was compiled against an older regex.
        if (m.groupCount >= 5) {
          pkOriginX = m.group(5) != null ? double.tryParse(m.group(5)!) : null;
          pkOriginY = m.group(6) != null ? double.tryParse(m.group(6)!) : null;
        }
        // v4 marker: explicit cell size — use instead of heuristic refinement.
        if (m.groupCount >= 7) {
          pkCellSize = m.group(7) != null ? double.tryParse(m.group(7)!) : null;
        }
      }

      final symbolFrags = page.fragments
          .where((f) => symbolSet.contains(f.text.trim()))
          .toList();

      // ── Text-flow detection ───────────────────────────────────────────────
      // Artecy / HAED PDFs use text-flow encoding: pdfium extracts each chart
      // row as one long multi-char fragment (e.g. "AAABBBCCC...").  These
      // fragments contain no single-char symbol matches, so symbolFrags stays
      // tiny.  Detect this case via "symbol-rich" multi-char fragments and
      // compute step / origin from them instead of from symbolFrags positions.
      final bool isTextFlow;
      if (symbolFrags.length < _kMinGridCells) {
        final richFrags = page.fragments.where((f) {
          final runes = f.text.trim().runes.toList();
          if (runes.length < 2) return false;
          final symCount =
              runes.where((r) => symbolSet.contains(String.fromCharCode(r))).length;
          return symCount >= 2 && symCount * 2 >= runes.length;
        }).toList();

        if (richFrags.length < 3) {
          debugPrint('[PKParser] page $pi: only ${symbolFrags.length} symbol '
              'fragments (need $_kMinGridCells), '
              '${page.fragments.length} total frags — '
              'likely raster grid');
          continue;
        }
        isTextFlow = true;
        debugPrint('[PKParser] page $pi: text-flow encoding '
            '(${richFrags.length} symbol-rich frags, ${symbolFrags.length} single-char)');
      } else {
        isTextFlow = false;
      }

      // Positions of symbol centres — used for step/origin in normal mode only.
      final xCenters = isTextFlow
          ? <double>[]
          : (symbolFrags.map((f) => (f.left + f.right) / 2).toList()..sort());
      final yCenters = isTextFlow
          ? <double>[]
          : (symbolFrags.map((f) => (f.top + f.bottom) / 2).toList()..sort());

      double? xStep, yStep;
      if (!isTextFlow) {
        xStep = _computeStep(xCenters);
        yStep = _computeStep(yCenters);
        if (xStep == null || yStep == null) {
          debugPrint('[PKParser] page $pi: irregular grid — skipping');
          continue;
        }
      } else {
        // Text-flow: estimate character step from fragment widths.
        final richFrags = page.fragments.where((f) {
          final runes = f.text.trim().runes.toList();
          if (runes.length < 2) return false;
          final symCount =
              runes.where((r) => symbolSet.contains(String.fromCharCode(r))).length;
          return symCount >= 2 && symCount * 2 >= runes.length;
        }).toList();

        final charWidths = richFrags.map((f) {
          final n = f.text.trim().runes.length;
          return (f.right - f.left) / n;
        }).toList()..sort();

        xStep = charWidths[charWidths.length ~/ 2];
        if (xStep < 2.0) {
          debugPrint('[PKParser] page $pi: text-flow char step too small — skip');
          continue;
        }

        // Row step: median Y-diff between adjacent rows of rich fragments.
        final richByY = _groupByY(richFrags);
        final rowYs = richByY.values
            .map((row) {
              final cy = row.map((f) => (f.top + f.bottom) / 2).reduce((a, b) => a + b) / row.length;
              return cy;
            })
            .toList()
          ..sort((a, b) => b.compareTo(a)); // descending (top of page = largest Y)

        if (rowYs.length < 2) {
          debugPrint('[PKParser] page $pi: text-flow: too few rows — skip');
          continue;
        }
        final rowDiffs = [for (int i = 1; i < rowYs.length; i++) rowYs[i - 1] - rowYs[i]];
        rowDiffs.sort();
        yStep = rowDiffs[rowDiffs.length ~/ 2];
        if (yStep < 2.0) {
          debugPrint('[PKParser] page $pi: text-flow row step too small — skip');
          continue;
        }
      }

      // Grid origin: the PDF-space centre of local col 0 / row 0.
      // pkOriginX is per-page (same physical layout on every page), so it IS
      // the per-page origin for local col 0.  Fall back to first/last symbol
      // for normal PDFs, or leftmost/topmost fragment for text-flow.
      final double originX;
      final double originY;
      if (isTextFlow) {
        // For text-flow, use the leftmost X of symbol-rich fragments as origin,
        // and the topmost row Y as the row-0 centre.
        final richFrags = page.fragments.where((f) {
          final runes = f.text.trim().runes.toList();
          if (runes.length < 2) return false;
          final symCount =
              runes.where((r) => symbolSet.contains(String.fromCharCode(r))).length;
          return symCount >= 2 && symCount * 2 >= runes.length;
        }).toList();
        originX = richFrags.map((f) => f.left).reduce(min);
        originY = richFrags.map((f) => (f.top + f.bottom) / 2).reduce(max);
      } else {
        originX = pkOriginX ?? xCenters.first;
        originY = pkOriginY ?? yCenters.last;
      }

      // ── Step refinement (v3 PKCHART only) ────────────────────────────────
      // _computeStep median can still have small errors due to render spread.
      // With explicit ox/oy (per-page origin) we compute a more accurate step
      // via median( (cx - ox) / round((cx-ox)/roughStep) ) across all symbols.
      // By this point xStep and yStep are always non-null (we continue'd otherwise).
      // Dart flow analysis promotes double? → double after the null-guarded blocks.
      double refinedXStep = xStep;
      double refinedYStep = yStep;
      if (pkOriginX != null && pkOriginY != null && !isTextFlow) {
        // Restrict to symbols in the first ~10 rows/cols from the per-page
        // origin.  With a rough step error ε = |roughStep - trueStep|, the
        // rounding error at col n is n·ε/roughStep.  For n ≤ 10 this stays
        // below 0.5 as long as ε < roughStep/20 (≈5 % error), which covers
        // typical _computeStep variation.  This avoids biasing the median
        // with symbols at large col/row indices where the rough rounding
        // already rounds to the wrong integer.
        final xRatios = <double>[];
        final yRatios = <double>[];
        // Safe radius: 8 × roughStep keeps rounding error < 0.5 when rough
        // step is within ~6 % of true step.  Using median from _computeStep
        // the actual error is typically < 2 %, so this is very conservative.
        final xLimit = xStep * 10.5;
        final yLimit = yStep * 10.5;
        for (final frag in symbolFrags) {
          final cx = (frag.left + frag.right) / 2;
          final cy = (frag.top + frag.bottom) / 2;
          final dx = cx - pkOriginX;
          final dy = pkOriginY - cy;
          if (dx > 0 && dx < xLimit) {
            final col = (dx / xStep).round();
            if (col > 0) xRatios.add(dx / col);
          }
          if (dy > 0 && dy < yLimit) {
            final row = (dy / yStep).round();
            if (row > 0) yRatios.add(dy / row);
          }
        }
        if (xRatios.length >= 10) {
          xRatios.sort();
          refinedXStep = xRatios[xRatios.length ~/ 2];
        }
        if (yRatios.length >= 10) {
          yRatios.sort();
          refinedYStep = yRatios[yRatios.length ~/ 2];
        }
      }

      // v4 marker: use the embedded cellSize directly, overriding any
      // heuristic refinement.  The heuristic is biased by the glyph baseline
      // offset (symbols are drawn at centre_y − fs*0.35), inflating the
      // computed step and misplacing the last several rows of each page.
      if (pkCellSize != null) {
        refinedXStep = pkCellSize;
        refinedYStep = pkCellSize;
      }

      final cells = <_GridCell>[];
      int maxCol = 0, maxRow = 0;

      // Single-char cell placement (skipped for text-flow; merge-recovery below
      // handles all cells for text-flow pages).
      if (!isTextFlow) {
        for (final frag in symbolFrags) {
          final cx = (frag.left + frag.right) / 2;
          final cy = (frag.top + frag.bottom) / 2;
          // PDF Y increases upward → flip to get visual row (0 = top).
          final col = ((cx - originX) / refinedXStep).round();
          final row = ((originY - cy) / refinedYStep).round();
          if (col < 0 || row < 0) continue;
          cells.add(_GridCell(frag.text.trim(), col, row));
          if (col > maxCol) maxCol = col;
          if (row > maxRow) maxRow = row;
        }
      }

      // ── Recover merged same-symbol column/row runs ──────────────────────
      // pdfium consolidates consecutive same-character draws in a column (or
      // row) into a single multi-char fragment.  These are invisible to the
      // symbolFrags filter above (which only accepts single-char fragments).
      // Columns with MIXED symbols are also merged into one fragment (each
      // char represents one row's symbol, top-to-bottom).
      // Decompose them here now that origin and step are known.
      for (final frag in page.fragments) {
        final text = frag.text.trim();
        if (text.length < 2) continue;
        final runes = text.runes.toList();
        if (runes.isEmpty) continue;

        final fragH = frag.top - frag.bottom; // PDF: top > bottom
        final fragW = frag.right - frag.left;

        // Check that at least one char is a valid symbol; pure header/footer
        // text will have no symbol chars so skip those immediately.
        final hasAnySymbol =
            runes.any((r) => symbolSet.contains(String.fromCharCode(r)));
        if (!hasAnySymbol) continue;

        if (fragH >= fragW) {
          // Column merge: each char is one row's symbol, top→bottom.
          // Guard against short header/footer text (e.g. page number "21")
          // whose fragH ≥ fragW but is much shorter than a genuine column
          // spanning N × cellHeight.  A real N-row merge has:
          //   fragH ≈ (N−1)×step + glyphHeight  ≥  N×step×0.65
          if (fragH < runes.length * refinedYStep * 0.65) continue;

          // Process char-by-char so a single unrecognised char doesn't cause
          // us to discard the entire column run.
          final col = (((frag.left + frag.right) / 2 - originX) / refinedXStep).round();
          if (col < 0) continue;
          // frag.top is ~ascent above the topmost cell centre, so
          // (originY − frag.top)/step is slightly negative for row 0 —
          // round() naturally returns 0 in that case.
          final firstRow = ((originY - frag.top) / refinedYStep).round();
          final safeFirst = firstRow < 0 ? 0 : firstRow;
          for (int i = 0; i < runes.length; i++) {
            final sym = String.fromCharCode(runes[i]);
            if (!symbolSet.contains(sym)) continue;
            cells.add(_GridCell(sym, col, safeFirst + i));
          }
        } else {
          // Row merge: each char is one column's symbol, left→right.
          final row = ((originY - (frag.top + frag.bottom) / 2) / refinedYStep).round();
          if (row < 0) continue;
          // frag.left is ~half-glyph-width left of the first cell centre;
          // adding half a step before dividing snaps to the nearest column.
          final firstCol = ((frag.left - originX + refinedXStep * 0.5) / refinedXStep).round();
          for (int i = 0; i < runes.length; i++) {
            final sym = String.fromCharCode(runes[i]);
            if (!symbolSet.contains(sym)) continue;
            final col = firstCol + i;
            if (col >= 0) cells.add(_GridCell(sym, col, row));
          }
        }
      }

      // Deduplicate: a position can appear in both the symbolFrags path and
      // the merged-run path above.  Keep the first occurrence at each
      // (col, row) coordinate so single-char fragments take priority.
      {
        final seen = <(int, int)>{};
        cells.retainWhere((c) => seen.add((c.col, c.row)));
      }

      if (cells.isNotEmpty) {
        // ── Outlier filter ────────────────────────────────────────────────
        // Footer/ruler text that matches a symbol in the legend lands at
        // out-of-range row/col values.  Two strategies:
        //
        // 1. Exact bounds (preferred): PKCHART gives us endCol/endRow so we
        //    know the precise grid dimensions — discard anything outside.
        // 2. Gap detection (fallback for third-party PDFs without PKCHART):
        //    footer phantoms are far beyond the grid — there is always a large
        //    blank band between the grid bottom and the "Colours Used" footer.
        //    Find the first gap of > kFooterGap consecutive empty rows/cols
        //    and discard everything beyond it.  This preserves sparse edge
        //    stitches (e.g. dog legs) that a p95 heuristic would clip.
        if (pkStartCol != null && pkEndCol != null &&
            pkStartRow != null && pkEndRow != null) {
          final maxLocalCol = pkEndCol - pkStartCol - 1;
          final maxLocalRow = pkEndRow - pkStartRow - 1;
          cells.retainWhere(
              (c) => c.col <= maxLocalCol && c.row <= maxLocalRow);
        } else if (cells.length > 4) {
          const kFooterGap = 8; // gap of 8+ empty rows/cols → footer content
          final uniqueRows = (cells.map((c) => c.row).toSet().toList()..sort());
          final uniqueCols = (cells.map((c) => c.col).toSet().toList()..sort());

          int maxRealRow = uniqueRows.last;
          for (int i = 1; i < uniqueRows.length; i++) {
            if (uniqueRows[i] - uniqueRows[i - 1] > kFooterGap) {
              maxRealRow = uniqueRows[i - 1];
              break;
            }
          }
          int maxRealCol = uniqueCols.last;
          for (int i = 1; i < uniqueCols.length; i++) {
            if (uniqueCols[i] - uniqueCols[i - 1] > kFooterGap) {
              maxRealCol = uniqueCols[i - 1];
              break;
            }
          }

          if (maxRealRow < uniqueRows.last || maxRealCol < uniqueCols.last) {
            cells.retainWhere(
                (c) => c.row <= maxRealRow && c.col <= maxRealCol);
          }
        }
        if (cells.isEmpty) continue;
        maxCol = cells.map((c) => c.col).reduce(max);
        maxRow = cells.map((c) => c.row).reduce(max);

        debugPrint('[PKParser] page $pi: ${cells.length} symbols, '
            '${maxCol + 1}×${maxRow + 1} grid, '
            '${isTextFlow ? "text-flow " : ""}'
            'step ${xStep.toStringAsFixed(1)}×${yStep.toStringAsFixed(1)} pt'
            '(refined ${refinedXStep.toStringAsFixed(3)}×${refinedYStep.toStringAsFixed(3)})'
            '${pkStartCol != null ? ', PKCHART $pkStartCol,$pkStartRow→$pkEndCol,$pkEndRow' : ''}'
            '${pkOriginX != null ? ', origin=(${pkOriginX.toStringAsFixed(1)},${pkOriginY!.toStringAsFixed(1)})' : ' (heuristic origin)'}');
        grids.add(_PageGrid(
          cells: cells,
          cols: maxCol + 1,
          rows: maxRow + 1,
          absStartCol: pkStartCol,
          absStartRow: pkStartRow,
        ));
      }
    }

    return grids;
  }

  // ─── Multi-page assembly ──────────────────────────────────────────────────

  static PatternScanResult _assembleResult(
      List<_PageGrid> pageGrids, Map<String, String> legend) {
    final _PageGrid combined;

    // If any page carries a PKCHART marker, discard pages without one —
    // those are colour-table or legend pages incorrectly captured as grids
    // (they contain symbol characters from the legend column but no marker).
    final hasAnyMarker = pageGrids.any((g) => g.absStartCol != null);
    final grids = hasAnyMarker
        ? pageGrids.where((g) => g.absStartCol != null).toList()
        : pageGrids;

    if (grids.isEmpty) {
      return PatternScanResult(
          width: 0, height: 0, threads: [], stitches: []);
    }

    if (grids.length == 1) {
      final g = grids.first;
      // If the single page carries a PKCHART marker, apply absolute offset
      // so stitches land at the correct canvas coordinates, not local (0,0).
      combined = (g.absStartCol != null && g.absStartRow != null)
          ? _combineAbsolute(grids)
          : g;
    } else {
      // If all remaining pages carry PKCHART absolute offsets (StitchX export),
      // place them directly — no heuristic needed.
      final allHaveMarkers =
          grids.every((g) => g.absStartCol != null && g.absStartRow != null);
      if (allHaveMarkers) {
        combined = _combineAbsolute(grids);
      } else {
        // Fallback heuristic for third-party PK PDFs.
        // Decide stacking direction from column-count consistency.
        final colCounts = grids.map((g) => g.cols).toList();
        final sortedCols = [...colCounts]..sort();
        final medianCols = sortedCols[sortedCols.length ~/ 2];
        final isVertical = colCounts.every((c) => (c - medianCols).abs() <= 2);

        combined =
            isVertical ? _stackVertically(grids) : _stackHorizontally(grids);
      }
    }

    // Threads: only those whose DMC code appears in the assembled grid.
    final usedCodes = combined.cells
        .map((c) => legend[c.symbol])
        .whereType<String>()
        .toSet();

    final threads = <ScannedThread>[];
    for (final dmcCode in usedCodes) {
      final dmc = dmcColorByCode(dmcCode);
      if (dmc == null) continue;
      final hex =
          '#${(dmc.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      threads.add(ScannedThread(dmcCode: dmcCode, name: dmc.name, colorHex: hex));
    }

    final stitches = <ScannedStitch>[];
    for (final cell in combined.cells) {
      final dmcCode = legend[cell.symbol];
      if (dmcCode == null) continue;
      stitches.add(ScannedStitch(
          x: cell.col, y: cell.row, type: 'full', dmcCode: dmcCode));
    }

    return PatternScanResult(
      width: combined.cols,
      height: combined.rows,
      threads: threads,
      stitches: stitches,
    );
  }

  /// Combine pages using absolute PKCHART offsets (StitchX exports only).
  /// Each cell's final position = page absStartCol/Row + local col/row.
  static _PageGrid _combineAbsolute(List<_PageGrid> grids) {
    final cells = <_GridCell>[];
    int maxCol = 0, maxRow = 0;

    for (final grid in grids) {
      final sc = grid.absStartCol!;
      final sr = grid.absStartRow!;
      for (final c in grid.cells) {
        final ac = sc + c.col;
        final ar = sr + c.row;
        cells.add(_GridCell(c.symbol, ac, ar));
        if (ac > maxCol) maxCol = ac;
        if (ar > maxRow) maxRow = ar;
      }
    }

    debugPrint('[PKParser] absolute assembly: ${grids.length} pages → '
        '${maxCol + 1}×${maxRow + 1}');
    return _PageGrid(cells: cells, cols: maxCol + 1, rows: maxRow + 1);
  }

  static _PageGrid _stackVertically(List<_PageGrid> grids) {
    final cells = <_GridCell>[];
    int rowOffset = 0;
    int maxCols = 0;

    for (int i = 0; i < grids.length; i++) {
      final grid = grids[i];
      final overlap = i == 0 ? 0 : _detectVerticalOverlap(grids[i - 1], grid);
      if (overlap > 0) debugPrint('[PKParser] page $i: $overlap overlap rows removed');

      for (final c in grid.cells) {
        if (c.row < overlap) continue;
        cells.add(_GridCell(c.symbol, c.col, c.row - overlap + rowOffset));
      }
      rowOffset += grid.rows - overlap;
      if (grid.cols > maxCols) maxCols = grid.cols;
    }

    final maxRow = cells.isEmpty ? 0 : cells.map((c) => c.row).reduce(max);
    return _PageGrid(cells: cells, cols: maxCols, rows: maxRow + 1);
  }

  static _PageGrid _stackHorizontally(List<_PageGrid> grids) {
    final cells = <_GridCell>[];
    int colOffset = 0;
    int maxRows = 0;

    for (int i = 0; i < grids.length; i++) {
      final grid = grids[i];
      final overlap = i == 0 ? 0 : _detectHorizontalOverlap(grids[i - 1], grid);
      if (overlap > 0) debugPrint('[PKParser] page $i: $overlap overlap cols removed');

      for (final c in grid.cells) {
        if (c.col < overlap) continue;
        cells.add(_GridCell(c.symbol, c.col - overlap + colOffset, c.row));
      }
      colOffset += grid.cols - overlap;
      if (grid.rows > maxRows) maxRows = grid.rows;
    }

    final maxCol = cells.isEmpty ? 0 : cells.map((c) => c.col).reduce(max);
    return _PageGrid(cells: cells, cols: maxCol + 1, rows: maxRows);
  }

  static int _detectVerticalOverlap(_PageGrid prev, _PageGrid curr) {
    for (int k = min(4, min(prev.rows, curr.rows)); k >= 1; k--) {
      final prevMap = <(int, int), String>{};
      for (final c in prev.cells) {
        if (c.row >= prev.rows - k) {
          prevMap[(c.col, c.row - (prev.rows - k))] = c.symbol;
        }
      }
      final currMap = <(int, int), String>{};
      for (final c in curr.cells) {
        if (c.row < k) currMap[(c.col, c.row)] = c.symbol;
      }
      if (currMap.isEmpty) continue;
      final matches = currMap.entries.where((e) => prevMap[e.key] == e.value).length;
      if (matches / currMap.length > 0.8) return k;
    }
    return 0;
  }

  static int _detectHorizontalOverlap(_PageGrid prev, _PageGrid curr) {
    for (int k = min(4, min(prev.cols, curr.cols)); k >= 1; k--) {
      final prevMap = <(int, int), String>{};
      for (final c in prev.cells) {
        if (c.col >= prev.cols - k) {
          prevMap[(c.col - (prev.cols - k), c.row)] = c.symbol;
        }
      }
      final currMap = <(int, int), String>{};
      for (final c in curr.cells) {
        if (c.col < k) currMap[(c.col, c.row)] = c.symbol;
      }
      if (currMap.isEmpty) continue;
      final matches = currMap.entries.where((e) => prevMap[e.key] == e.value).length;
      if (matches / currMap.length > 0.8) return k;
    }
    return 0;
  }

  // ─── Utility ──────────────────────────────────────────────────────────────

  /// Group fragments into horizontal rows by proximity of their Y centres.
  static Map<int, List<TextFragment>> _groupByY(
      List<TextFragment> frags) {
    if (frags.isEmpty) return {};

    final heights = frags.map((f) => f.height).toList()..sort();
    final medianH = heights[heights.length ~/ 2];
    final tolerance = max(medianH * 0.6, 2.0);

    // Sort descending by Y (top of page = largest Y in PDF coords).
    final sorted = [...frags]
      ..sort((a, b) => b.top.compareTo(a.top));

    final groups = <int, List<TextFragment>>{};
    int id = 0;
    double? lastY;

    for (final frag in sorted) {
      final cy = (frag.top + frag.bottom) / 2;
      if (lastY == null || (lastY - cy).abs() > tolerance) {
        id++;
        lastY = cy;
      }
      groups.putIfAbsent(id, () => []).add(frag);
    }
    return groups;
  }

  /// Infer the regular grid step from a sorted list of 1-D centre positions.
  ///
  /// PK grids have equal spacing except for slightly wider gaps at 10-cell
  /// boundaries (bold lines).  We use the lower-quartile of consecutive
  /// differences to find the base step and validate that other diffs are
  /// approximate multiples of it.
  static double? _computeStep(List<double> sorted) {
    if (sorted.length < 4) return null;

    final diffs = <double>[];
    for (int i = 1; i < sorted.length; i++) {
      final d = sorted[i] - sorted[i - 1];
      if (d > 0.5) diffs.add(d);
    }
    if (diffs.length < 3) return null;
    diffs.sort();

    // Median: robust to both intra-column render jitter (which populates the
    // lower tail) and multi-cell empty-column gaps (upper tail).  Multi-cell
    // gaps are valid multiples so the validation below still accepts them.
    final candidate = diffs[diffs.length ~/ 2];
    if (candidate < 1.0) return null;

    // Validate: ≥60 % of diffs should be close to a whole multiple of candidate.
    int valid = 0;
    for (final d in diffs) {
      final ratio = d / candidate;
      final rounded = ratio.round();
      if (rounded >= 1 && (ratio - rounded).abs() / rounded < 0.25) valid++;
    }
    if (valid < diffs.length * 0.6) return null;

    return candidate;
  }

}

// ─── Internal models ──────────────────────────────────────────────────────────

class _GridCell {
  final String symbol;
  final int col;
  final int row;
  const _GridCell(this.symbol, this.col, this.row);
}

class _PageGrid {
  final List<_GridCell> cells;
  final int cols;
  final int rows;
  /// Absolute column/row origin from a PKCHART marker, if present.
  final int? absStartCol;
  final int? absStartRow;
  const _PageGrid({
    required this.cells,
    required this.cols,
    required this.rows,
    this.absStartCol,
    this.absStartRow,
  });
}
