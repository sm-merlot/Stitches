import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Result of automatic grid detection on a single rasterised PDF page.
class GridDetectionResult {
  /// Estimated stitch-grid bounding box in full-page image pixels.
  final double gridLeft;
  final double gridTop;
  final double gridRight;
  final double gridBottom;

  /// Detected cell size in image pixels.
  final double cellW;
  final double cellH;

  /// Position of the first grid line within the detected grid rect
  /// (0 ≤ phaseX < cellW, 0 ≤ phaseY < cellH).
  final double phaseX;
  final double phaseY;

  /// Overall detection confidence in [0, 1].
  /// Values ≥ 0.25 are generally reliable; below that treat as undetected.
  final double confidence;

  const GridDetectionResult({
    required this.gridLeft,
    required this.gridTop,
    required this.gridRight,
    required this.gridBottom,
    required this.cellW,
    required this.cellH,
    required this.phaseX,
    required this.phaseY,
    required this.confidence,
  });

  double get gridWidth  => gridRight  - gridLeft;
  double get gridHeight => gridBottom - gridTop;

  /// Initial cell rect for [PatternScanCellScreen], in crop-relative pixels.
  /// Assumes the crop matches [gridLeft/Top/Right/Bottom].
  Rect get initialCellRect => Rect.fromLTWH(phaseX, phaseY, cellW, cellH);
}

/// Automatic stitch-grid detector.
///
/// Analyses a rasterised PDF page (PNG bytes) using 1-D gradient projections
/// and autocorrelation to find the cell size, grid origin, and grid extent.
/// Works for both solid and dotted grid lines.
class GridDetector {
  GridDetector._();

  static Future<GridDetectionResult?> detectPage(Uint8List pageBytes) async {
    final raw = await compute(_runDetect, pageBytes);
    return raw?.toDetectionResult();
  }

  static Future<List<GridDetectionResult?>> detectPages(
      List<Uint8List> pages) =>
      Future.wait(pages.map(detectPage));
}

// ─── Isolate-safe raw result ──────────────────────────────────────────────────

class _RawResult {
  final double gridLeft, gridTop, gridRight, gridBottom;
  final double cellW, cellH;
  final double phaseX, phaseY;
  final double confidence;

  const _RawResult({
    required this.gridLeft,
    required this.gridTop,
    required this.gridRight,
    required this.gridBottom,
    required this.cellW,
    required this.cellH,
    required this.phaseX,
    required this.phaseY,
    required this.confidence,
  });
}

// ─── Isolate entry point ──────────────────────────────────────────────────────

_RawResult? _runDetect(Uint8List pageBytes) {
  final pageImage = img.decodePng(pageBytes);
  if (pageImage == null) return null;

  final gray = img.grayscale(pageImage);
  final W = gray.width;
  final H = gray.height;

  // ── Build gradient projections ──────────────────────────────────────────────
  // hProj[y] = mean |row_y − row_{y-1}| across all x  → peaks at H. grid lines
  // vProj[x] = mean |col_x − col_{x-1}| across all y  → peaks at V. grid lines
  //
  // Gradient highlights thin lines far better than raw darkness because grid
  // lines are narrow transitions between lighter cell interiors.  Even dotted
  // lines accumulate enough edge signal across a full row/column.
  final hProj = List<double>.filled(H, 0.0);
  final vProj = List<double>.filled(W, 0.0);

  for (int y = 1; y < H; y++) {
    for (int x = 1; x < W; x++) {
      final curr  = gray.getPixel(x, y).luminanceNormalized;
      final above = gray.getPixel(x, y - 1).luminanceNormalized;
      final left  = gray.getPixel(x - 1, y).luminanceNormalized;
      hProj[y] += (curr - above).abs();
      vProj[x] += (curr - left).abs();
    }
  }
  for (int y = 1; y < H; y++) { hProj[y] /= (W - 1); }
  for (int x = 1; x < W; x++) { vProj[x] /= (H - 1); }

  // ── Find cell period ────────────────────────────────────────────────────────
  const minCell = 6;
  final maxCell = math.min(W, H) ~/ 4; // require at least 4 cells visible

  final xResult = _findPeriod(vProj, minCell, maxCell);
  final yResult = _findPeriod(hProj, minCell, maxCell);
  if (xResult == null || yResult == null) return null;

  final (cellW, rawPhaseX, confX, gridStartX, gridEndX) = xResult;
  final (cellH, rawPhaseY, confY, gridStartY, gridEndY) = yResult;

  // ── Derive grid bounds ──────────────────────────────────────────────────────
  // gridStartX/Y and gridEndX/Y are the positions of the outermost grid lines,
  // which already represent the true crop boundaries.  No padding is added.
  final gridLeft   = gridStartX.clamp(0.0, W.toDouble());
  final gridRight  = gridEndX  .clamp(0.0, W.toDouble());
  final gridTop    = gridStartY.clamp(0.0, H.toDouble());
  final gridBottom = gridEndY  .clamp(0.0, H.toDouble());

  if (gridRight <= gridLeft || gridBottom <= gridTop) return null;

  // Phase relative to the detected grid rect origin.
  final phaseX = (rawPhaseX - gridLeft) % cellW;
  final phaseY = (rawPhaseY - gridTop)  % cellH;

  final confidence = math.sqrt(confX * confY);

  debugPrint('[GridDetector] cellW=$cellW cellH=$cellH '
      'gridRect=($gridLeft,$gridTop,$gridRight,$gridBottom) '
      'phase=($phaseX,$phaseY) conf=${confidence.toStringAsFixed(2)}');

  return _RawResult(
    gridLeft: gridLeft,
    gridTop: gridTop,
    gridRight: gridRight,
    gridBottom: gridBottom,
    cellW: cellW.toDouble(),
    cellH: cellH.toDouble(),
    phaseX: phaseX.clamp(0.0, cellW.toDouble()),
    phaseY: phaseY.clamp(0.0, cellH.toDouble()),
    confidence: confidence,
  );
}

// ─── Period finder ────────────────────────────────────────────────────────────

/// Returns (period, phase, normalised_confidence, gridStart, gridEnd) or null.
///
/// gridStart/gridEnd are the positions (in signal coordinates) of the first
/// and last detected grid line, accounting for both strong (solid) lines and
/// weaker (dotted) lines that lie outside the strong-line range.
(int, double, double, double, double)? _findPeriod(
  List<double> signal,
  int minPeriod,
  int maxPeriod,
) {
  final N = signal.length;
  if (N < minPeriod * 4) return null;

  // ── Trim outer margins for autocorrelation ──────────────────────────────────
  // Skip the outer ~14% on each side (ruler numbers, title text, copyright)
  // which produce spurious high-gradient rows that contaminate period detection.
  final trimStart = N ~/ 7;
  final trimEnd   = N - N ~/ 7;
  final trimLen   = trimEnd - trimStart;
  if (trimLen < minPeriod * 4) return null;

  // Mean-centre the trimmed signal.
  double mean = 0;
  for (int i = trimStart; i < trimEnd; i++) { mean += signal[i]; }
  mean /= trimLen;
  final s = [for (int i = trimStart; i < trimEnd; i++) signal[i] - mean];

  // Variance (= autocorr[0] / N).
  final variance = s.fold(0.0, (sum, v) => sum + v * v) / s.length;
  if (variance < 1e-10) return null; // blank / uniform column

  final effectiveMax = math.min(maxPeriod, trimLen ~/ 3);
  if (effectiveMax < minPeriod) return null;

  // ── Normalised autocorrelation on trimmed region ────────────────────────────
  double bestConf = -1;
  int    bestPeriod = minPeriod;

  for (int lag = minPeriod; lag <= effectiveMax; lag++) {
    double ac = 0;
    final len = s.length - lag;
    for (int i = 0; i < len; i++) { ac += s[i] * s[i + lag]; }
    ac /= (len * variance);
    if (ac > bestConf) {
      bestConf   = ac;
      bestPeriod = lag;
    }
  }

  if (bestConf < 0.10) return null; // no meaningful periodicity

  // ── Sub-harmonic check ──────────────────────────────────────────────────────
  // If the detected period is e.g. 10× the true cell size (because only the
  // major every-10-cells gridlines are prominent), try smaller divisors.
  // Always compare against the ORIGINAL confidence so the threshold stays
  // fixed regardless of which sub-harmonics were previously accepted.
  final originalConf = bestConf;
  for (final divisor in [2, 3, 4, 5, 7, 10]) {
    final candidate = bestPeriod ~/ divisor;
    if (candidate < minPeriod) break;
    double ac = 0;
    final len = s.length - candidate;
    for (int i = 0; i < len; i++) { ac += s[i] * s[i + candidate]; }
    ac /= (len * variance);
    // Accept the smallest sub-harmonic whose autocorrelation is at least
    // 50% of the original detected-period confidence.
    if (ac > originalConf * 0.50) {
      bestPeriod = candidate;
      bestConf   = ac;
    }
  }

  // ── Phase detection (full signal) ───────────────────────────────────────────
  // For each offset p in [0, period), sum signal[p + k*period] for all k.
  // The offset with the highest sum is where the grid lines are.
  final phaseScores = List<double>.filled(bestPeriod, 0.0);
  for (int i = 0; i < N; i++) { phaseScores[i % bestPeriod] += signal[i]; }
  int bestPhase = 0;
  for (int p = 1; p < bestPeriod; p++) {
    if (phaseScores[p] > phaseScores[bestPhase]) { bestPhase = p; }
  }

  // ── On-phase thresholds ──────────────────────────────────────────────────────
  // Collect signal values at all on-phase positions and use their median as a
  // reference for "typical grid-line signal strength". This is far more accurate
  // than global percentiles, which are dominated by blank background values.
  final onPhase = <double>[];
  for (int k = 0; ; k++) {
    final pos = bestPhase + k * bestPeriod;
    if (pos >= N) break;
    onPhase.add(signal[pos]);
  }
  onPhase.sort();
  final onPhaseMedian = onPhase[onPhase.length ~/ 2];

  // High threshold (60% of median on-phase) → confirms a solid grid line.
  // Low  threshold (20% of median on-phase) → accepts faint dotted-line edges.
  final highThreshold = onPhaseMedian * 0.60;
  final lowThreshold  = onPhaseMedian * 0.20;

  // ── Grid extent (forward scan with 1-skip tolerance) ────────────────────────
  // Allow one consecutive weak position before declaring end of grid, so that
  // a single faint dotted line at the pattern edge does not prematurely stop
  // the scan.
  double gridStart   = -1;
  double gridEnd     = -1;
  bool   inGrid      = false;
  int    weakStreak  = 0;

  for (int k = 0; ; k++) {
    final pos = bestPhase + k * bestPeriod;
    if (pos >= N) break;
    final sig = signal[pos];
    if (!inGrid) {
      if (sig >= highThreshold) {
        inGrid     = true;
        gridStart  = pos.toDouble();
        gridEnd    = pos.toDouble();
        weakStreak = 0;
      }
    } else {
      if (sig >= lowThreshold) {
        gridEnd    = pos.toDouble();
        weakStreak = 0;
      } else {
        weakStreak++;
        if (weakStreak >= 2) break; // two consecutive blanks → end of grid
      }
    }
  }

  if (gridStart < 0) return null; // no strong line found at all

  // Extend BACKWARD from gridStart, picking up dotted lines that precede
  // the first solid line (with the same 1-skip tolerance).
  int backWeak = 0;
  for (int k = 1; ; k++) {
    final pos = gridStart - k * bestPeriod;
    if (pos < 0) break;
    if (signal[pos.round()] >= lowThreshold) {
      gridStart = pos;
      backWeak  = 0;
    } else {
      backWeak++;
      if (backWeak >= 2) break;
    }
  }

  return (bestPeriod, bestPhase.toDouble(), bestConf.clamp(0.0, 1.0),
      gridStart, gridEnd);
}

// ─── Main-thread conversion ───────────────────────────────────────────────────

extension _RawResultExt on _RawResult {
  GridDetectionResult toDetectionResult() => GridDetectionResult(
        gridLeft:   gridLeft,
        gridTop:    gridTop,
        gridRight:  gridRight,
        gridBottom: gridBottom,
        cellW:      cellW,
        cellH:      cellH,
        phaseX:     phaseX,
        phaseY:     phaseY,
        confidence: confidence,
      );
}
