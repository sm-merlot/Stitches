import 'dart:math';

// ─── Constants ────────────────────────────────────────────────────────────────

const double dmcSkeinMetres = 8.0;
const int dmcTotalStrands = 6;
const double wasteFactor = 1.3;

// ─── Skein calculator ─────────────────────────────────────────────────────────

/// Returns the number of skeins required for [dmcCode], in quarter-skein
/// increments (0.25, 0.5, 0.75, 1.0, 1.25, …). Minimum is ¼ skein.
///
/// [crossEquiv] maps dmcCode → cross-stitch equivalents
///   (FullStitch=1.0, HalfStitch=0.5, QuarterStitch=0.25, etc.)
/// [backCells] maps dmcCode → backstitch Euclidean cell-unit length
double calculateSkeins({
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

  // Round up to the nearest quarter-skein; minimum ¼.
  final quartersNeeded = (totalMetres / usableMetresPerSkein * 4).ceil();
  return max(1, quartersNeeded) / 4.0;
}

/// Formats a quarter-precision skein count as a human-readable label.
///
/// Examples: 0.25 → '¼', 0.5 → '½', 0.75 → '¾', 1.0 → '1', 1.75 → '1¾'
String skeinLabel(double n) {
  final whole = n.truncate();
  final rem = (n * 4).round() % 4; // 0, 1, 2, or 3 quarters
  const fracs = ['', '¼', '½', '¾'];
  return whole == 0 ? fracs[rem] : '$whole${fracs[rem]}';
}
