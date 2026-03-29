import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'ai/ai_provider.dart';
import '../data/dmc_colors.dart';
import '../models/snippet.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../screens/pattern_scan_cell_screen.dart';

/// Cell confidence values below this threshold are flagged for manual review.
const double kLowConfidenceThreshold = 0.10;

// ─── Symbol sample ────────────────────────────────────────────────────────────

/// One user-identified symbol type, with one or more example cell crops.
///
/// The user taps a cell in the grid for each unique symbol, assigns its DMC
/// code, and the raw PNG crops become the reference templates for matching.
/// Multiple crops per symbol are averaged to produce a more robust template.
class SymbolSample {
  /// DMC thread code (e.g. "321", "Blanc").
  final String dmcCode;

  /// Hex colour for this thread, e.g. "#FF0000". Used to build [ScannedThread]
  /// objects for the downstream pipeline.
  final String colorHex;

  /// Raw PNG-encoded crops of cells that contain this symbol, all at the same
  /// pixel size (cellW × cellH from the grid detection step).
  final List<Uint8List> crops;

  const SymbolSample({
    required this.dmcCode,
    required this.colorHex,
    required this.crops,
  });
}

// ─── Public result types ──────────────────────────────────────────────────────

/// Match result for a single grid cell.
class CellMatch {
  /// Zero-based column index within the grid.
  final int col;

  /// Zero-based row index within the grid.
  final int row;

  /// Index into [GridMatchResult.threads]; -1 means the cell is empty/background.
  final int symbolIndex;

  /// DMC thread code of the matched symbol; null for empty cells.
  final String? dmcCode;

  /// Similarity score in [0.0, 1.0].
  ///
  /// Values below [kLowConfidenceThreshold] indicate a poor pixel match and
  /// should be surfaced to the user for manual review/correction (step 4).
  final double confidence;

  const CellMatch({
    required this.col,
    required this.row,
    required this.symbolIndex,
    required this.dmcCode,
    required this.confidence,
  });

  bool get isEmpty => symbolIndex == -1;
  bool get isLowConfidence => !isEmpty && confidence < kLowConfidenceThreshold;
}

/// Pixel-match result for one cropped page grid.
class GridMatchResult {
  final List<CellMatch> cells;
  final int columns;
  final int rows;

  /// All threads from the AI legend pass (superset — not all may appear in cells).
  final List<ScannedThread> threads;

  int get lowConfidenceCount => cells.where((c) => c.isLowConfidence).length;

  const GridMatchResult({
    required this.cells,
    required this.columns,
    required this.rows,
    required this.threads,
  });

  /// Convert to a [PatternScanResult] for the existing preview / conversion pipeline.
  ///
  /// NOTE: The pixel matcher produces full stitches only. Half-stitches and
  /// backstitches cannot be distinguished from pixel data alone.
  PatternScanResult toPatternScanResult({
    String? warning,
    int? patternW,
    int? patternH,
    int rowOffset = 0,
  }) {
    final usedCodes = cells.where((c) => !c.isEmpty).map((c) => c.dmcCode!).toSet();
    final usedThreads =
        threads.where((t) => usedCodes.contains(t.dmcCode)).toList();

    final stitches = cells
        .where((c) => !c.isEmpty)
        .map((c) => ScannedStitch(
              x: c.col,
              y: c.row + rowOffset,
              type: 'full',
              dmcCode: c.dmcCode!,
            ))
        .toList();

    return PatternScanResult(
      width: columns,
      height: rows,
      threads: usedThreads,
      stitches: stitches,
      warning: warning,
      patternW: patternW,
      patternH: patternH,
    );
  }

  /// Convert this grid result into a [Snippet] ready to be added to the
  /// current pattern via [EditorNotifier.addSnippet].
  Snippet toSnippet(String name) {
    // Build thread list — only threads that actually appear in non-empty cells.
    final usedCodes =
        cells.where((c) => !c.isEmpty).map((c) => c.dmcCode!).toSet();
    final snippetThreads = threads
        .where((t) => usedCodes.contains(t.dmcCode))
        .map((t) {
          final dmc = dmcColorByCode(t.dmcCode);
          final color = dmc?.color ?? _parseHexColor(t.colorHex);
          return Thread(dmcCode: t.dmcCode, name: t.name, color: color);
        })
        .toList();

    final snippetStitches = cells
        .where((c) => !c.isEmpty)
        .map((c) => FullStitch(x: c.col, y: c.row, threadId: c.dmcCode!))
        .toList();

    return Snippet.create(
      name: name,
      width: columns,
      height: rows,
      threads: snippetThreads,
      stitches: snippetStitches,
    );
  }

  static Color _parseHexColor(String hex) {
    final h = hex.replaceAll('#', '').padRight(6, '0');
    return Color.fromARGB(
      255,
      int.parse(h.substring(0, 2), radix: 16),
      int.parse(h.substring(2, 4), radix: 16),
      int.parse(h.substring(4, 6), radix: 16),
    );
  }

  /// Build a [GridMatchResult] from an AI [PatternScanResult].
  ///
  /// All cells get confidence 1.0 (AI-stated).  Only full stitches are
  /// included (half-stitches / backstitches are preserved in [aiResult] but
  /// the review / combine pipeline works at the full-stitch level).
  static GridMatchResult fromAiScan(
    PatternScanResult aiResult, {
    int rowOffset = 0,
  }) {
    final cells = aiResult.stitches
        .where((s) => s.type == 'full')
        .map((s) {
          final idx = aiResult.threads
              .indexWhere((t) => t.dmcCode == s.dmcCode);
          return CellMatch(
            col: s.x,
            row: s.y - rowOffset,
            symbolIndex: idx < 0 ? 0 : idx,
            dmcCode: s.dmcCode,
            confidence: 1.0,
          );
        })
        .toList();

    return GridMatchResult(
      cells: cells,
      columns: aiResult.width,
      rows: aiResult.height,
      threads: aiResult.threads,
    );
  }

  /// Return a copy with user-confirmed corrections applied.
  ///
  /// [overrides] maps `"col,row"` to a DMC code string, or null to mark the
  /// cell as empty/background. Corrected cells are given confidence 1.0.
  GridMatchResult withOverrides(Map<String, String?> overrides) {
    if (overrides.isEmpty) return this;
    final updated = cells.map((c) {
      final key = '${c.col},${c.row}';
      if (!overrides.containsKey(key)) return c;
      final dmcCode = overrides[key];
      if (dmcCode == null) {
        return CellMatch(
            col: c.col, row: c.row, symbolIndex: -1, dmcCode: null, confidence: 1.0);
      }
      final idx = threads.indexWhere((t) => t.dmcCode == dmcCode);
      return CellMatch(
          col: c.col, row: c.row, symbolIndex: idx, dmcCode: dmcCode, confidence: 1.0);
    }).toList();
    return GridMatchResult(
        cells: updated, columns: columns, rows: rows, threads: threads);
  }

  /// Combine results from multiple pages into a single [PatternScanResult].
  ///
  /// Pages are stacked vertically: page N+1 starts at y = total rows of pages 0..N.
  static PatternScanResult combine(
    List<GridMatchResult> results,
    PatternScanResult legendResult,
  ) {
    if (results.isEmpty) {
      return PatternScanResult(
        width: 0,
        height: 0,
        threads: legendResult.threads,
        stitches: [],
      );
    }

    final allStitches = <ScannedStitch>[];
    int rowOffset = 0;
    int totalLowConf = 0;

    for (final r in results) {
      final pr = r.toPatternScanResult(rowOffset: rowOffset);
      allStitches.addAll(pr.stitches);
      rowOffset += r.rows;
      totalLowConf += r.lowConfidenceCount;
    }

    return PatternScanResult(
      width: results.map((r) => r.columns).reduce(math.max),
      height: results.fold(0, (s, r) => s + r.rows),
      threads: legendResult.threads,
      stitches: allStitches,
      warning: totalLowConf > 0
          ? '$totalLowConf cell(s) had low match confidence — manual review recommended'
          : null,
      patternW: legendResult.patternW,
      patternH: legendResult.patternH,
    );
  }

  /// Combine results from multiple pages using user-provided [SymbolSample]s
  /// (the AI-free pipeline).  Thread metadata is derived from the DMC database.
  static PatternScanResult combineFromSamples(
    List<GridMatchResult> results,
    List<SymbolSample> samples,
  ) {
    final threads = _threadsFromSamples(samples);

    if (results.isEmpty) {
      return PatternScanResult(width: 0, height: 0, threads: threads, stitches: []);
    }

    final allStitches = <ScannedStitch>[];
    int rowOffset    = 0;
    int totalLowConf = 0;

    for (final r in results) {
      final pr = r.toPatternScanResult(rowOffset: rowOffset);
      allStitches.addAll(pr.stitches);
      rowOffset    += r.rows;
      totalLowConf += r.lowConfidenceCount;
    }

    return PatternScanResult(
      width:    results.map((r) => r.columns).reduce(math.max),
      height:   results.fold(0, (s, r) => s + r.rows),
      threads:  threads,
      stitches: allStitches,
      warning:  totalLowConf > 0
          ? '$totalLowConf cell(s) had low match confidence — manual review recommended'
          : null,
    );
  }

  static List<ScannedThread> _threadsFromSamples(List<SymbolSample> samples) =>
      samples.map((s) {
        final dmc = dmcColorByCode(s.dmcCode);
        return ScannedThread(
          dmcCode:  s.dmcCode,
          name:     dmc?.name ?? s.dmcCode,
          colorHex: s.colorHex,
        );
      }).toList();
}

// ─── Matcher ──────────────────────────────────────────────────────────────────

class GridSymbolMatcher {
  GridSymbolMatcher._();

  /// Match every cell in [gridResult] against the user-provided [samples].
  ///
  /// Each [SymbolSample] supplies one or more example crops of a symbol.
  /// The crops are normalised and averaged into a single reference template per
  /// DMC code.  Every grid cell is then normalised the same way and compared
  /// by mean absolute pixel difference; the closest template wins.
  ///
  /// The heavy image work runs in a background isolate via [compute].
  static Future<GridMatchResult> matchGrid({
    required GridCellResult gridResult,
    required List<SymbolSample> samples,
  }) async {
    final params = _MatchParams(
      pageBytes:   gridResult.crop.pageBytes,
      cropLeft:    gridResult.crop.cropRect.left,
      cropTop:     gridResult.crop.cropRect.top,
      cellW:       gridResult.cellW,
      cellH:       gridResult.cellH,
      cellOffsetX: gridResult.cellOffsetX,
      cellOffsetY: gridResult.cellOffsetY,
      columns:     gridResult.columns,
      rows:        gridResult.rows,
      samples:     samples
          .map((s) => _SerialSample(dmcCode: s.dmcCode, crops: s.crops))
          .toList(),
    );

    final rawCells = await compute(_runMatch, params);
    return GridMatchResult(
      cells: rawCells
          .map((r) => CellMatch(
                col:         r.col,
                row:         r.row,
                symbolIndex: r.symbolIndex,
                dmcCode:     r.dmcCode,
                confidence:  r.confidence,
              ))
          .toList(),
      columns: gridResult.columns,
      rows:    gridResult.rows,
      threads: GridMatchResult._threadsFromSamples(samples),
    );
  }
}

// ─── Isolate-safe parameter / result types ────────────────────────────────────

/// Isolate-safe representation of one [SymbolSample].
class _SerialSample {
  final String dmcCode;
  final List<Uint8List> crops;

  const _SerialSample({required this.dmcCode, required this.crops});
}

class _MatchParams {
  final Uint8List pageBytes;
  final double cropLeft;
  final double cropTop;
  final double cellW;
  final double cellH;
  final double cellOffsetX;
  final double cellOffsetY;
  final int columns;
  final int rows;
  final List<_SerialSample> samples;

  const _MatchParams({
    required this.pageBytes,
    required this.cropLeft,
    required this.cropTop,
    required this.cellW,
    required this.cellH,
    required this.columns,
    required this.rows,
    required this.samples,
    this.cellOffsetX = 0,
    this.cellOffsetY = 0,
  });
}

class _RawCell {
  final int col;
  final int row;
  final int symbolIndex;
  final String? dmcCode;
  final double confidence;

  const _RawCell({
    required this.col,
    required this.row,
    required this.symbolIndex,
    required this.dmcCode,
    required this.confidence,
  });
}

// ─── Isolate entry point ──────────────────────────────────────────────────────

// Must be a top-level function for compute() to send it to the helper isolate.
List<_RawCell> _runMatch(_MatchParams p) {
  final refW = p.cellW.round().clamp(1, 9999);
  final refH = p.cellH.round().clamp(1, 9999);

  // Trim margin: exclude grid-line pixels (including the bolder every-5th /
  // every-10th lines) from both templates and cells so the comparison focuses
  // on the symbol content in the centre.  15% on each side is enough for thick
  // bold lines while still keeping a meaningful inner region.
  final trimX = (refW * 0.15).round().clamp(1, refW ~/ 3);
  final trimY = (refH * 0.15).round().clamp(1, refH ~/ 3);
  final innerW = (refW - 2 * trimX).clamp(1, refW);
  final innerH = (refH - 2 * trimY).clamp(1, refH);

  final pageImage = img.decodePng(p.pageBytes);
  if (pageImage == null) return [];

  // Build one normalised reference template per sample.
  // Each crop is trimmed to its inner region before averaging so the template
  // contains only the symbol, not the surrounding grid lines.
  final refs = <_Ref>[];
  for (final sample in p.samples) {
    final normalised = <img.Image>[];
    for (final cropBytes in sample.crops) {
      var decoded = img.decodePng(cropBytes);
      if (decoded == null) continue;
      if (decoded.width != refW || decoded.height != refH) {
        decoded = img.copyResize(decoded,
            width: refW, height: refH, interpolation: img.Interpolation.average);
      }
      normalised.add(_trimCenter(_normalise(img.grayscale(decoded)), trimX, trimY));
    }
    if (normalised.isEmpty) continue;
    refs.add(_Ref(dmcCode: sample.dmcCode, gray: _averageImages(normalised, innerW, innerH)));
  }

  debugPrint('[SymbolMatcher] refs built: ${refs.length} / ${p.samples.length} '
      '(inner ${innerW}x$innerH from ${refW}x$refH, trim ${trimX}x$trimY)');

  final cells = <_RawCell>[];

  for (int row = 0; row < p.rows; row++) {
    for (int col = 0; col < p.columns; col++) {
      final px = (p.cropLeft + p.cellOffsetX + col * p.cellW).round();
      final py = (p.cropTop + p.cellOffsetY + row * p.cellH).round();

      // Guard against crops that fall outside the rasterised page.
      if (px < 0 || py < 0 || px >= pageImage.width || py >= pageImage.height) {
        continue;
      }
      final pw = math.min(refW, pageImage.width - px);
      final ph = math.min(refH, pageImage.height - py);
      if (pw <= 0 || ph <= 0) continue;

      var cell = img.copyCrop(pageImage, x: px, y: py, width: pw, height: ph);
      if (pw != refW || ph != refH) {
        cell = img.copyResize(cell,
            width: refW,
            height: refH,
            interpolation: img.Interpolation.average);
      }
      // Normalise then trim to the inner region, consistent with templates.
      // Inversion handles white-symbol-on-dark cells.
      final normCell = _trimCenter(_normalise(img.grayscale(cell)), trimX, trimY);

      // Empty-cell detection on the trimmed centre: a blank cell has no ink in
      // its centre regardless of what the border looks like.  Checking only the
      // inner region means bold grid lines cannot mask an empty cell.
      if (_meanLuminance(normCell) > 0.92) {
        cells.add(_RawCell(
            col: col, row: row, symbolIndex: -1, dmcCode: null, confidence: 1.0));
        continue;
      }

      if (refs.isEmpty) {
        // No references available — flag cell as unresolved.
        cells.add(_RawCell(
            col: col, row: row, symbolIndex: -1, dmcCode: null, confidence: 0.0));
        continue;
      }

      // Pick the reference with the smallest mean absolute pixel difference.
      // Also track the second-best diff for ambiguity detection.
      double bestDiff = double.infinity;
      double secondBestDiff = double.infinity;
      int bestIdx = -1;
      for (int i = 0; i < refs.length; i++) {
        final d = _meanAbsDiff(normCell, refs[i].gray);
        if (d < bestDiff) {
          secondBestDiff = bestDiff;
          bestDiff = d;
          bestIdx = i;
        } else if (d < secondBestDiff) {
          secondBestDiff = d;
        }
      }

      // Absolute confidence: any best diff < 0.50 is considered a valid match
      // (0.50 MAD would mean half the pixels are completely wrong — clearly no
      // symbol matches at all).  Below that hard cutoff we always consider the
      // match valid from an absolute standpoint.
      final absoluteConf = bestDiff < 0.50 ? 1.0 : 0.0;

      // Margin confidence (multi-symbol only): relative separation between the
      // best and second-best template.  relMargin = (2nd-best − best) / best.
      // A ratio ≥ 0.10 (10% relative separation) → full confidence.
      // Single symbol: skip margin check — if it's not empty and not garbage it
      // must be that symbol.
      final confidence = refs.length <= 1
          ? absoluteConf
          : math.min(
              absoluteConf,
              ((secondBestDiff - bestDiff) / (bestDiff.clamp(1e-6, double.infinity) * 0.10))
                  .clamp(0.0, 1.0));

      cells.add(_RawCell(
        col: col,
        row: row,
        symbolIndex: bestIdx,
        dmcCode: refs[bestIdx].dmcCode,
        confidence: confidence,
      ));
    }
  }

  return cells;
}

// ─── Template averaging ───────────────────────────────────────────────────────

/// Average a list of same-sized normalised grayscale images into one template.
/// If only one image is supplied it is returned directly.
img.Image _averageImages(List<img.Image> images, int w, int h) {
  if (images.length == 1) return images[0];
  final out = img.Image(width: w, height: h, numChannels: 1);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (final im in images) {
        sum += im.getPixel(x, y).luminanceNormalized;
      }
      final v = (sum / images.length * 255).round().clamp(0, 255);
      out.setPixel(x, y, img.ColorUint8.rgb(v, v, v));
    }
  }
  return out;
}

/// Crop the inner region of an image, discarding [trimX] columns on each side
/// and [trimY] rows on each side.  Used to focus comparisons on the symbol
/// content and exclude grid-line pixels (including bold every-5th lines).
img.Image _trimCenter(img.Image src, int trimX, int trimY) {
  final w = (src.width  - 2 * trimX).clamp(1, src.width);
  final h = (src.height - 2 * trimY).clamp(1, src.height);
  return img.copyCrop(src, x: trimX, y: trimY, width: w, height: h);
}

// ─── Image helpers (run inside isolate) ──────────────────────────────────────

class _Ref {
  final String dmcCode;
  final img.Image gray;

  _Ref({required this.dmcCode, required this.gray});
}

/// Mean luminance of a grayscale image, normalised to [0.0, 1.0].
double _meanLuminance(img.Image gray) {
  final n = gray.width * gray.height;
  if (n == 0) return 0.0;
  double sum = 0.0;
  for (final pixel in gray) {
    sum += pixel.luminanceNormalized;
  }
  return sum / n;
}

/// Normalise a grayscale image so the background is always light.
/// If the median pixel luminance is below 0.5 (dark background — e.g. a cell
/// filled with a dark thread colour whose symbol is printed in white), the
/// image is inverted.  This lets [_meanAbsDiff] compare templates and cells
/// on a consistent scale regardless of whether they are black-on-white or
/// white-on-dark.
img.Image _normalise(img.Image gray) {
  final pixels = <double>[];
  for (final px in gray) {
    pixels.add(px.luminanceNormalized.toDouble());
  }
  pixels.sort();
  final median = pixels[pixels.length ~/ 2];
  return median < 0.5 ? img.invert(gray) : gray;
}

/// Mean absolute per-pixel luminance difference between two same-sized images.
/// Returns a value in [0.0, 1.0] where 0.0 = identical.
double _meanAbsDiff(img.Image a, img.Image b) {
  assert(a.width == b.width && a.height == b.height);
  final n = a.width * a.height;
  if (n == 0) return 1.0;
  double sum = 0.0;
  for (int y = 0; y < a.height; y++) {
    for (int x = 0; x < a.width; x++) {
      sum += (a.getPixel(x, y).luminanceNormalized -
              b.getPixel(x, y).luminanceNormalized)
          .abs();
    }
  }
  return sum / n;
}
