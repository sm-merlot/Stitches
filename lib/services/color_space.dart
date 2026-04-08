import 'dart:math' as math;

/// Pure-Dart colour space utilities.
///
/// No Flutter imports — safe to use from background isolates (see
/// [grid_cell_scanner]) as well as from widget code.
///
/// CIE Lab is used throughout the app for perceptual colour comparison
/// (matching DMC threads, contrast checks, palette merging) because Euclidean
/// distance in sRGB is a poor proxy for perceived colour difference.

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
