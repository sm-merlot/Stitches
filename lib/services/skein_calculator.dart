import 'dart:math';

// ─── Constants ────────────────────────────────────────────────────────────────

const double dmcSkeinMetres = 8.0;
const int dmcTotalStrands = 6;
const double wasteFactor = 1.3;

// ─── Skein calculator ─────────────────────────────────────────────────────────

/// Returns the number of skeins required for [dmcCode].
///
/// [crossEquiv] maps dmcCode → cross-stitch equivalents
///   (FullStitch=1.0, HalfStitch=0.5, QuarterStitch=0.25, etc.)
/// [backCells] maps dmcCode → backstitch Euclidean cell-unit length
int calculateSkeins({
  required String dmcCode,
  required Map<String, double> crossEquiv,
  required Map<String, double> backCells,
  required int aidaCount,
  required int strands,
}) {
  final cellMm = 25.4 / aidaCount;
  final metersPerFullStitch =
      strands * 4 * sqrt(2) * (cellMm / 1000) * wasteFactor;
  final metersPerBackCell = strands * 2 * (cellMm / 1000) * wasteFactor;
  final usableMetresPerSkein = dmcSkeinMetres * (dmcTotalStrands / strands);

  final totalMetres = (crossEquiv[dmcCode] ?? 0) * metersPerFullStitch +
      (backCells[dmcCode] ?? 0) * metersPerBackCell;

  return max(1, (totalMetres / usableMetresPerSkein).ceil());
}
