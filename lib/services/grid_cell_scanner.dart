import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'scan_result.dart';
import 'color_space.dart';
import 'grid_symbol_matcher.dart';

/// Scans a cropped cross-stitch grid image cell by cell.
///
/// Each cell is analysed by sampling its ink pixels (pixels darker or more
/// saturated than the paper background).  The median ink colour is then matched
/// to the closest thread in the legend using CIE-76 Lab distance.  No AI or
/// network requests are required.
///
/// This is much faster and more reliable than asking an AI to identify every
/// symbol in a dense grid image.
class GridCellScanner {
  GridCellScanner._();

  /// Scan [gridBytes] (PNG, already cropped to the grid area) and return a
  /// [GridMatchResult] whose cells are matched against [threads].
  ///
  /// [cellWFrac] / [cellHFrac] — cell width/height as a fraction of the
  /// cropped-image width/height (so the result is scale-invariant even when
  /// [_cropAndDownsample] has resized the image).
  ///
  /// [phaseXFrac] / [phaseYFrac] — distance from the crop origin to the first
  /// grid line, also as a fraction of the image dimensions.
  static Future<GridMatchResult> scan({
    required Uint8List gridBytes,
    required int cols,
    required int rows,
    required double cellWFrac,
    required double cellHFrac,
    required double phaseXFrac,
    required double phaseYFrac,
    required List<ScannedThread> threads,
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('Scanning $cols×$rows cells…');

    final params = _ScanParams(
      gridBytes: gridBytes,
      cols: cols,
      rows: rows,
      cellWFrac: cellWFrac,
      cellHFrac: cellHFrac,
      phaseXFrac: phaseXFrac,
      phaseYFrac: phaseYFrac,
      legendR: threads.map((t) => _hexComponent(t.colorHex, 1)).toList(),
      legendG: threads.map((t) => _hexComponent(t.colorHex, 3)).toList(),
      legendB: threads.map((t) => _hexComponent(t.colorHex, 5)).toList(),
      legendCodes: threads.map((t) => t.dmcCode).toList(),
    );

    final raw = await compute(_runCellScan, params);

    final cells = raw
        .map((e) => CellMatch(
              col: e[0] as int,
              row: e[1] as int,
              symbolIndex: e[2] as int,
              dmcCode: e[3] as String,
              confidence: e[4] as double,
            ))
        .toList();

    onProgress?.call('${cells.length} stitches found');
    return GridMatchResult(
      cells: cells,
      columns: cols,
      rows: rows,
      threads: threads,
    );
  }

  static int _hexComponent(String hex, int offset) =>
      int.parse(hex.substring(offset, offset + 2), radix: 16);
}

// ─── Isolate-safe params ──────────────────────────────────────────────────────

class _ScanParams {
  final Uint8List gridBytes;
  final int cols;
  final int rows;
  final double cellWFrac;
  final double cellHFrac;
  final double phaseXFrac;
  final double phaseYFrac;

  /// Pre-parsed R/G/B components for each legend thread.
  final List<int> legendR;
  final List<int> legendG;
  final List<int> legendB;
  final List<String> legendCodes;

  const _ScanParams({
    required this.gridBytes,
    required this.cols,
    required this.rows,
    required this.cellWFrac,
    required this.cellHFrac,
    required this.phaseXFrac,
    required this.phaseYFrac,
    required this.legendR,
    required this.legendG,
    required this.legendB,
    required this.legendCodes,
  });
}

// ─── Isolate entry point ──────────────────────────────────────────────────────

/// Returns a list of [col, row, symbolIndex, dmcCode, confidence] for every
/// occupied cell.  Runs in a background isolate via [compute].
List<List<dynamic>> _runCellScan(_ScanParams p) {
  final image = img.decodePng(p.gridBytes);
  if (image == null) {
    debugPrint('[CellScanner] ERROR: failed to decode grid image');
    return [];
  }

  final W = image.width.toDouble();
  final H = image.height.toDouble();

  // Convert fractions back to pixel values for this (possibly scaled) image.
  final cellW  = p.cellWFrac  * W;
  final cellH  = p.cellHFrac  * H;
  final phaseX = p.phaseXFrac * W;
  final phaseY = p.phaseYFrac * H;

  debugPrint('[CellScanner] image=${W.round()}×${H.round()} '
      'cellW=${cellW.toStringAsFixed(1)} cellH=${cellH.toStringAsFixed(1)} '
      'phaseX=${phaseX.toStringAsFixed(1)} phaseY=${phaseY.toStringAsFixed(1)} '
      'grid=${p.cols}×${p.rows} legend=${p.legendR.length}');

  // Pre-convert legend colours to CIE Lab once.
  final legendLab = List.generate(p.legendR.length,
      (i) => rgbToLab(p.legendR[i], p.legendG[i], p.legendB[i]));

  final results = <List<dynamic>>[];

  // Trim a proportional margin from every cell edge to exclude the grid-line
  // pixels and their anti-aliasing halo.  At 300 DPI (then downsampled) the
  // grid lines are typically 1-2 px wide; a 10% trim at 20px cell size = 2px,
  // which reliably clears the line plus halo on both sides.
  final trimPx = math.max(2, (math.min(cellW, cellH) * 0.10).round());

  for (int row = 0; row < p.rows; row++) {
    for (int col = 0; col < p.cols; col++) {
      // Cell pixel bounds with proportional trim.
      final left   = (phaseX + col       * cellW).round() + trimPx;
      final top    = (phaseY + row       * cellH).round() + trimPx;
      final right  = (phaseX + (col + 1) * cellW).round() - trimPx;
      final bottom = (phaseY + (row + 1) * cellH).round() - trimPx;

      final x0 = left.clamp(0, image.width  - 1);
      final y0 = top .clamp(0, image.height - 1);
      final x1 = right .clamp(0, image.width  - 1);
      final y1 = bottom.clamp(0, image.height - 1);

      if (x1 <= x0 || y1 <= y0) continue;

      // Collect ink pixels.
      // A pixel is "ink" if its luminance is below 0.82 OR its saturation is
      // above 0.12.  This catches both coloured ink (high saturation) and black
      // ink (low luminance) while ignoring the white/cream paper background.
      final inkR = <int>[];
      final inkG = <int>[];
      final inkB = <int>[];
      int total = 0;

      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          final px = image.getPixel(x, y);
          final r = px.r.toInt();
          final g = px.g.toInt();
          final b = px.b.toInt();
          total++;

          final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
          final maxC = math.max(r, math.max(g, b)) / 255.0;
          final minC = math.min(r, math.min(g, b)) / 255.0;
          final sat  = maxC > 0 ? (maxC - minC) / maxC : 0.0;

          if (lum < 0.82 || sat > 0.04) {
            inkR.add(r);
            inkG.add(g);
            inkB.add(b);
          }
        }
      }

      // Skip cell if fewer than 5% of pixels are ink (empty / background).
      if (col == 0 && row == 0) {
        debugPrint('[CellScanner] cell(0,0): bounds=($x0,$y0)-($x1,$y1) '
            'total=$total ink=${inkR.length} '
            '(${(inkR.length * 100.0 / math.max(1, total)).toStringAsFixed(1)}%)');
        if (inkR.isNotEmpty) {
          inkR.sort(); inkG.sort(); inkB.sort();
          final mid = inkR.length ~/ 2;
          debugPrint('[CellScanner] cell(0,0) median ink RGB: '
              '(${inkR[mid]},${inkG[mid]},${inkB[mid]})');
          inkR.sort(); inkG.sort(); inkB.sort(); // re-sort after read
        }
      }
      if (inkR.isEmpty || inkR.length < total * 0.05) continue;

      // Median ink colour (sort each channel independently).
      inkR.sort();
      inkG.sort();
      inkB.sort();
      final mid = inkR.length ~/ 2;
      final mr = inkR[mid];
      final mg = inkG[mid];
      final mb = inkB[mid];

      // Find closest legend thread by CIE-76 Lab distance.
      final inkLab  = rgbToLab(mr, mg, mb);
      final bestIdx = nearestLabIndex(legendLab, inkLab);
      if (bestIdx < 0) continue;
      final bestDist = labDistance(inkLab, legendLab[bestIdx]);

      // Normalise distance to a confidence score.
      // Lab distance of 0 → 1.0; distance of 40 → 0.0 (linear).
      final confidence = (1.0 - bestDist / 40.0).clamp(0.0, 1.0);

      results.add([col, row, bestIdx, p.legendCodes[bestIdx], confidence]);
    }
  }

  debugPrint('[CellScanner] done: ${results.length} occupied cells '
      'out of ${p.cols * p.rows} total');
  return results;
}

