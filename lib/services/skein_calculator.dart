import 'dart:math';

// ─── Constants ────────────────────────────────────────────────────────────────

/// Length of a standard DMC skein in metres.
const double dmcSkeinMetres = 8.0;

/// Number of strands in a standard DMC skein.
const int dmcTotalStrands = 6;

/// Total single-strand metres available in one skein (8 m × 6 strands).
const double dmcSkeinSingleStrandMetres = dmcSkeinMetres * dmcTotalStrands;

/// Extra thread for finishing, knots, and needle travel (30% overage).
const double wasteFactor = 1.3;

// Geometry helpers (private to library)
const double _mmPerInch = 25.4; // exact by definition
const double _mmPerMetre = 1000.0;

// Thread-length multipliers per stitch type (per strand, per cell)
//
// Full cross stitch: 2 front diagonal passes (/ and \) + 2 back-thread connections
// Each diagonal = √2 × cell, so total per strand = 4 × √2 × cell.
const double _crossStitchThreadFactor = 4.0;

// Backstitch: 1 front pass + 1 back-thread connection per cell unit of distance.
const double _backstitchThreadFactor = 2.0;

// ─── Skein calculator ─────────────────────────────────────────────────────────

/// Returns the number of skeins required for [dmcCode], in quarter-skein
/// increments (0.25, 0.5, 0.75, 1.0, 1.25, …). Minimum is ¼ skein.
///
/// Thread usage scales linearly with [strands]: using 3 strands needs 3×
/// as many single-strand-metres as 1 strand, divided by the fixed pool of
/// single-strand-metres in a skein (8 m × 6 strands = 48 m).
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
  final cellMm = _mmPerInch / aidaCount;

  // Single-strand metres consumed per stitch / per back-cell, then scaled by strands.
  final singleStrandMetresPerCross =
      _crossStitchThreadFactor * sqrt(2) * (cellMm / _mmPerMetre) * wasteFactor;
  final singleStrandMetresPerBackCell =
      _backstitchThreadFactor * (cellMm / _mmPerMetre) * wasteFactor;

  final totalSingleStrandMetres =
      strands * ((crossEquiv[dmcCode] ?? 0) * singleStrandMetresPerCross +
          (backCells[dmcCode] ?? 0) * singleStrandMetresPerBackCell);

  // Round up to the nearest quarter-skein; minimum ¼.
  final quartersNeeded =
      (totalSingleStrandMetres / dmcSkeinSingleStrandMetres * 4).ceil();
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
