import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/dmc_colors.dart';
import 'ai/ai_provider.dart';

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

  static const _kMinColors = 2;    // legend entries needed
  static const _kMinGridCells = 8; // symbols per page to count as a grid page

  // ─── Public entry point ───────────────────────────────────────────────────

  /// Try to parse [pdfPath] as a PatternKeeper-compatible PDF.
  ///
  /// Returns a [PatternScanResult] on success, or null when the PDF is raster
  /// or does not follow the PK legend/grid structure.  Never throws.
  static Future<PatternScanResult?> tryParse(String pdfPath) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);

      final pageTexts = <PdfPageText?>[];
      for (final page in doc.pages) {
        try {
          pageTexts.add(await page.loadStructuredText());
        } catch (_) {
          pageTexts.add(null);
        }
      }

      // Reject raster PDFs: need a meaningful amount of text.
      final totalChars =
          pageTexts.fold(0, (s, t) => s + (t?.fullText.length ?? 0));
      if (totalChars < 100) {
        debugPrint('[PKParser] not text-native ($totalChars chars total)');
        return null;
      }

      final legend = _parseLegend(pageTexts);
      if (legend.length < _kMinColors) {
        debugPrint(
            '[PKParser] legend too small (${legend.length} entries) — not PK format');
        return null;
      }
      debugPrint('[PKParser] legend: ${legend.length} symbol→DMC entries');

      final pageGrids = _parseAllGrids(pageTexts, legend);
      if (pageGrids.isEmpty) {
        debugPrint('[PKParser] no grid pages found');
        return null;
      }

      final result = _assembleResult(pageGrids, legend);
      if (result.stitches.isEmpty) {
        debugPrint('[PKParser] no stitches after assembly');
        return null;
      }

      debugPrint('[PKParser] success: ${result.width}×${result.height}, '
          '${result.stitches.length} stitches, ${result.threads.length} threads');
      return result;
    } catch (e, st) {
      debugPrint('[PKParser] parse error: $e\n$st');
      return null;
    } finally {
      await doc?.dispose();
    }
  }

  // ─── Legend parsing ───────────────────────────────────────────────────────

  /// Scan all pages for rows that contain a known DMC code and extract
  /// the associated symbol character.  Returns symbol → dmcCode.
  static Map<String, String> _parseLegend(List<PdfPageText?> pageTexts) {
    final legend = <String, String>{};

    for (final pageText in pageTexts) {
      if (pageText == null) continue;
      final frags = pageText.fragments;
      if (frags.isEmpty) continue;

      // Group fragments into horizontal rows by Y position.
      final rows = _groupByY(frags);

      for (final row in rows.values) {
        // Any fragment whose trimmed text is a valid DMC code?
        final dmcFrags = row.where((f) {
          final t = f.text.trim();
          return t.isNotEmpty && dmcColorByCode(t) != null;
        }).toList();
        if (dmcFrags.isEmpty) continue;

        for (final dmcFrag in dmcFrags) {
          final dmcCode = dmcFrag.text.trim();

          // Symbol: the leftmost short (1–3 char) non-numeric fragment
          // in the same row that is not itself a DMC code.
          String? symbol;
          double? symbolX;
          for (final f in row) {
            if (f == dmcFrag) continue;
            final t = f.text.trim();
            if (t.isEmpty || t.length > 3) continue;
            if (_isNumeric(t)) continue;
            if (dmcColorByCode(t) != null) continue;
            if (symbol == null || f.bounds.left < symbolX!) {
              symbol = t;
              symbolX = f.bounds.left;
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

  static List<_PageGrid> _parseAllGrids(
      List<PdfPageText?> pageTexts, Map<String, String> legend) {
    final symbolSet = legend.keys.toSet();
    final grids = <_PageGrid>[];

    for (int pi = 0; pi < pageTexts.length; pi++) {
      final pageText = pageTexts[pi];
      if (pageText == null) continue;

      final symbolFrags = pageText.fragments
          .where((f) => symbolSet.contains(f.text.trim()))
          .toList();
      if (symbolFrags.length < _kMinGridCells) continue;

      // Positions of symbol centres.
      final xCenters = symbolFrags
          .map((f) => (f.bounds.left + f.bounds.right) / 2)
          .toList()
        ..sort();
      final yCenters = symbolFrags
          .map((f) => (f.bounds.top + f.bounds.bottom) / 2)
          .toList()
        ..sort();

      final xStep = _computeStep(xCenters);
      final yStep = _computeStep(yCenters);

      if (xStep == null || yStep == null) {
        debugPrint('[PKParser] page $pi: irregular grid — skipping');
        continue;
      }

      // Grid origin: smallest X (left column) and largest Y (top row in PDF coords).
      final originX = xCenters.first;
      final originY = yCenters.last;

      final cells = <_GridCell>[];
      int maxCol = 0, maxRow = 0;

      for (final frag in symbolFrags) {
        final cx = (frag.bounds.left + frag.bounds.right) / 2;
        final cy = (frag.bounds.top + frag.bounds.bottom) / 2;
        // PDF Y increases upward → flip to get visual row (0 = top).
        final col = ((cx - originX) / xStep).round();
        final row = ((originY - cy) / yStep).round();
        if (col < 0 || row < 0) continue;
        cells.add(_GridCell(frag.text.trim(), col, row));
        if (col > maxCol) maxCol = col;
        if (row > maxRow) maxRow = row;
      }

      if (cells.isNotEmpty) {
        debugPrint('[PKParser] page $pi: ${cells.length} symbols, '
            '${maxCol + 1}×${maxRow + 1} grid, '
            'step ${xStep.toStringAsFixed(1)}×${yStep.toStringAsFixed(1)} pt');
        grids.add(_PageGrid(cells: cells, cols: maxCol + 1, rows: maxRow + 1));
      }
    }

    return grids;
  }

  // ─── Multi-page assembly ──────────────────────────────────────────────────

  static PatternScanResult _assembleResult(
      List<_PageGrid> pageGrids, Map<String, String> legend) {
    final _PageGrid combined;

    if (pageGrids.length == 1) {
      combined = pageGrids.first;
    } else {
      // Decide stacking direction from column-count consistency.
      final colCounts = pageGrids.map((g) => g.cols).toList();
      final sortedCols = [...colCounts]..sort();
      final medianCols = sortedCols[sortedCols.length ~/ 2];
      final isVertical = colCounts.every((c) => (c - medianCols).abs() <= 2);

      combined =
          isVertical ? _stackVertically(pageGrids) : _stackHorizontally(pageGrids);
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
  static Map<int, List<PdfPageTextFragment>> _groupByY(
      List<PdfPageTextFragment> frags) {
    if (frags.isEmpty) return {};

    final heights = frags.map((f) => f.bounds.height).toList()..sort();
    final medianH = heights[heights.length ~/ 2];
    final tolerance = max(medianH * 0.6, 2.0);

    // Sort descending by Y (top of page = largest Y in PDF coords).
    final sorted = [...frags]
      ..sort((a, b) => b.bounds.top.compareTo(a.bounds.top));

    final groups = <int, List<PdfPageTextFragment>>{};
    int id = 0;
    double? lastY;

    for (final frag in sorted) {
      final cy = (frag.bounds.top + frag.bounds.bottom) / 2;
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

    // Lower-quartile avoids multi-cell gaps inflating the estimate.
    final candidate = diffs[diffs.length ~/ 4];
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

  static bool _isNumeric(String s) => RegExp(r'^\d+$').hasMatch(s);
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
  const _PageGrid({required this.cells, required this.cols, required this.rows});
}
