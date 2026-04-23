import 'dart:math' as math;

/// Pure-Dart colour space utilities.
///
/// No Flutter imports — safe to use from background isolates (see
/// [grid_cell_scanner]) as well as from widget code.
///
/// CIE Lab is used throughout the app for perceptual colour comparison
/// (matching DMC threads, contrast checks, palette merging) because Euclidean
/// distance in sRGB is a poor proxy for perceived colour difference.
///
/// DMC thread matching uses [ciede2000] for the highest perceptual accuracy.
/// CIE-76 helpers ([labDistance], [labDistanceSquared], [nearestLabIndex]) are
/// retained for cases where speed matters more than precision.

/// A record representing a CIE L*a*b* colour.
typedef LabColor = (double l, double a, double b);

/// Converts sRGB (0–255 ints, D65 illuminant) to CIE L*a*b*.
LabColor rgbToLab(int r, int g, int b) {
  double lin(int v) {
    final t = v / 255.0;
    return t <= 0.04045
        ? t / 12.92
        : math.pow((t + 0.055) / 1.055, 2.4).toDouble();
  }

  final rl = lin(r), gl = lin(g), bl = lin(b);

  // Linear RGB → XYZ (D65)
  final x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
  final y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
  final z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;

  // XYZ → Lab (D65 white point)
  double f(double t) {
    const d = 6.0 / 29.0;
    return t > d * d * d
        ? math.pow(t, 1.0 / 3.0).toDouble()
        : t / (3 * d * d) + 4.0 / 29.0;
  }

  const xn = 0.95047, yn = 1.00000, zn = 1.08883;
  final fx = f(x / xn), fy = f(y / yn), fz = f(z / zn);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// Squared CIE-76 ΔE between two Lab colours. Cheaper than [labDistance]
/// when only ordering matters (e.g. nearest-neighbour searches).
double labDistanceSquared(LabColor a, LabColor b) {
  final dl = a.$1 - b.$1;
  final da = a.$2 - b.$2;
  final db = a.$3 - b.$3;
  return dl * dl + da * da + db * db;
}

/// CIE-76 ΔE between two Lab colours.
double labDistance(LabColor a, LabColor b) =>
    math.sqrt(labDistanceSquared(a, b));

// ── CIEDE2000 ────────────────────────────────────────────────────────────────

/// CIEDE2000 ΔE between two CIE L*a*b* colours.
///
/// Significantly more perceptually accurate than CIE-76, particularly in:
///   - Blue/violet regions (hue-rotation correction)
///   - Dark/near-neutral colours (chroma and lightness weighting)
///   - Saturated colours (hue-dependent SH term)
///
/// Uses the standard formula from Luo, Cui & Rigg (2001).
/// Returns a value where ΔE ≈ 1 is just noticeable to the human eye.
double ciede2000(LabColor lab1, LabColor lab2) {
  final L1 = lab1.$1, a1 = lab1.$2, b1 = lab1.$3;
  final L2 = lab2.$1, a2 = lab2.$2, b2 = lab2.$3;

  // Step 1 — adjusted a' values (chroma-weighted hue rotation)
  final C1ab = math.sqrt(a1 * a1 + b1 * b1);
  final C2ab = math.sqrt(a2 * a2 + b2 * b2);
  final Cabavg = (C1ab + C2ab) / 2.0;
  final Cabavg7 = math.pow(Cabavg, 7).toDouble();
  const p25_7 = 6103515625.0; // 25^7
  final G = 0.5 * (1.0 - math.sqrt(Cabavg7 / (Cabavg7 + p25_7)));
  final a1p = a1 * (1.0 + G);
  final a2p = a2 * (1.0 + G);
  final C1p = math.sqrt(a1p * a1p + b1 * b1);
  final C2p = math.sqrt(a2p * a2p + b2 * b2);

  // h' angle [0°, 360°)
  double hprime(double ap, double bp) {
    if (ap == 0.0 && bp == 0.0) return 0.0;
    final h = math.atan2(bp, ap) * 180.0 / math.pi;
    return h >= 0.0 ? h : h + 360.0;
  }
  final h1p = hprime(a1p, b1);
  final h2p = hprime(a2p, b2);

  // Step 2 — ΔL', ΔC', ΔH'
  final dLp = L2 - L1;
  final dCp = C2p - C1p;

  final double dhp;
  if (C1p * C2p == 0.0) {
    dhp = 0.0;
  } else if ((h2p - h1p).abs() <= 180.0) {
    dhp = h2p - h1p;
  } else if (h2p - h1p > 180.0) {
    dhp = h2p - h1p - 360.0;
  } else {
    dhp = h2p - h1p + 360.0;
  }
  final dHp =
      2.0 * math.sqrt(C1p * C2p) * math.sin(dhp * math.pi / 360.0);

  // Step 3 — arithmetic means
  final Lp_avg = (L1 + L2) / 2.0;
  final Cp_avg = (C1p + C2p) / 2.0;

  final double hp_avg;
  if (C1p * C2p == 0.0) {
    hp_avg = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180.0) {
    hp_avg = (h1p + h2p) / 2.0;
  } else if (h1p + h2p < 360.0) {
    hp_avg = (h1p + h2p + 360.0) / 2.0;
  } else {
    hp_avg = (h1p + h2p - 360.0) / 2.0;
  }

  // Step 4 — weighting functions
  double deg(double d) => d * math.pi / 180.0;

  final T = 1.0
      - 0.17 * math.cos(deg(hp_avg - 30.0))
      + 0.24 * math.cos(deg(2.0 * hp_avg))
      + 0.32 * math.cos(deg(3.0 * hp_avg + 6.0))
      - 0.20 * math.cos(deg(4.0 * hp_avg - 63.0));

  final SL = 1.0 +
      0.015 *
          math.pow(Lp_avg - 50.0, 2) /
          math.sqrt(20.0 + math.pow(Lp_avg - 50.0, 2));
  final SC = 1.0 + 0.045 * Cp_avg;
  final SH = 1.0 + 0.015 * Cp_avg * T;

  // Rotation term
  final Cp_avg7 = math.pow(Cp_avg, 7).toDouble();
  final RC = 2.0 * math.sqrt(Cp_avg7 / (Cp_avg7 + p25_7));
  final dTheta =
      30.0 * math.exp(-math.pow((hp_avg - 275.0) / 25.0, 2).toDouble());
  final RT = -math.sin(deg(2.0 * dTheta)) * RC;

  return math.sqrt(
    math.pow(dLp / SL, 2) +
        math.pow(dCp / SC, 2) +
        math.pow(dHp / SH, 2) +
        RT * (dCp / SC) * (dHp / SH),
  );
}

// ── Additional distance metrics ──────────────────────────────────────────────

/// CIE94 ΔE between two CIE L*a*b* colours.
///
/// Intermediate accuracy between CIE-76 and CIEDE2000. Uses the graphic-arts
/// weighting factors (kL = kC = kH = 1, K1 = 0.045, K2 = 0.015).
double cie94(LabColor lab1, LabColor lab2) {
  final dL = lab1.$1 - lab2.$1;
  final C1 = math.sqrt(lab1.$2 * lab1.$2 + lab1.$3 * lab1.$3);
  final C2 = math.sqrt(lab2.$2 * lab2.$2 + lab2.$3 * lab2.$3);
  final dC = C1 - C2;
  final da = lab1.$2 - lab2.$2;
  final db = lab1.$3 - lab2.$3;
  final dH = math.sqrt(math.max(0.0, da * da + db * db - dC * dC));
  final SC = 1.0 + 0.045 * C1;
  final SH = 1.0 + 0.015 * C1;
  return math.sqrt(dL * dL + math.pow(dC / SC, 2) + math.pow(dH / SH, 2));
}

/// Redmean weighted sRGB distance between two colours (0–255 ints).
///
/// Fast — requires no colour-space conversion. Weights the R and B channels
/// by the average redness of the two colours to approximate eye sensitivity.
double redmeanDist(int r1, int g1, int b1, int r2, int g2, int b2) {
  final rBar = (r1 + r2) / 2.0;
  final dR = (r1 - r2).toDouble();
  final dG = (g1 - g2).toDouble();
  final dB = (b1 - b2).toDouble();
  return math.sqrt(
    (2.0 + rBar / 256.0) * dR * dR +
    4.0 * dG * dG +
    (2.0 + (255.0 - rBar) / 256.0) * dB * dB,
  );
}

// ── Algorithm enum ────────────────────────────────────────────────────────────

/// Selectable colour-distance algorithms for DMC thread matching.
///
/// All algorithms operate on the ~450-colour DMC palette. The chosen algorithm
/// affects both the live preview and the final imported thread assignments.
enum MatchAlgorithm {
  /// CIEDE2000 — industry-standard perceptual distance (recommended).
  ciede2000,

  /// CIE94 — good accuracy, simpler than CIEDE2000.
  cie94,

  /// CIE-76 — simple Lab Euclidean; fast but less accurate in blues/darks.
  cie76,

  /// Weighted sRGB (redmean) — no Lab conversion; fast for similar colours.
  redmean,
}

/// Human-readable label for each [MatchAlgorithm].
String matchAlgorithmLabel(MatchAlgorithm algo) => switch (algo) {
      MatchAlgorithm.ciede2000 => 'CIEDE2000 (recommended)',
      MatchAlgorithm.cie94     => 'CIE94',
      MatchAlgorithm.cie76     => 'CIE-76',
      MatchAlgorithm.redmean   => 'Weighted sRGB',
    };

/// Returns the index of the entry in [labValues] whose Lab distance to
/// [target] is smallest. Returns `-1` if [labValues] is empty.
int nearestLabIndex(List<LabColor> labValues, LabColor target) {
  var bestIdx = -1;
  var best = double.infinity;
  for (var i = 0; i < labValues.length; i++) {
    final d = labDistanceSquared(labValues[i], target);
    if (d < best) {
      best = d;
      bestIdx = i;
    }
  }
  return bestIdx;
}
