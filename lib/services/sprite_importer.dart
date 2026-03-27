import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../data/dmc_colors.dart';
import '../models/snippet.dart';
import '../models/snippet_palette.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

/// Pre-computed CIE Lab entry for a single DMC colour.
typedef _LabEntry = ({
  String code,
  String name,
  Color color,
  double l,
  double a,
  double b,
});

/// Service that converts image pixel regions into cross-stitch data by matching
/// each pixel to the nearest DMC thread colour in CIE Lab space.
class SpriteImporter {
  SpriteImporter._();

  static List<_LabEntry>? _palette;

  // ── Lab palette ─────────────────────────────────────────────────────────────

  static List<_LabEntry> _labPalette() {
    return _palette ??= dmcColors.map((dmc) {
      final r = (dmc.color.r * 255).round();
      final g = (dmc.color.g * 255).round();
      final b = (dmc.color.b * 255).round();
      final (l, a, bb) = _rgbToLab(r, g, b);
      return (code: dmc.code, name: dmc.name, color: dmc.color, l: l, a: a, b: bb);
    }).toList();
  }

  // ── Colour space conversion ──────────────────────────────────────────────────

  /// sRGB (0–255 ints) → CIE Lab (D65 illuminant).
  static (double l, double a, double b) _rgbToLab(int r, int g, int b) {
    double lin(int c) {
      final v = c / 255.0;
      return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final rl = lin(r), gl = lin(g), bl = lin(b);

    // Linear RGB → XYZ (D65)
    final x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
    final y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
    final z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;

    // XYZ → Lab
    double f(double t) {
      const d = 6.0 / 29.0;
      return t > d * d * d ? pow(t, 1.0 / 3.0).toDouble() : t / (3 * d * d) + 4.0 / 29.0;
    }

    const xn = 0.95047, yn = 1.00000, zn = 1.08883;
    final fx = f(x / xn), fy = f(y / yn), fz = f(z / zn);
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Matches a pixel to the nearest DMC colour by CIE Lab Euclidean distance.
  /// Returns null for transparent pixels (alpha < 128).
  static DmcColor? matchPixel(int r, int g, int b, int a) {
    if (a < 128) return null;
    final palette = _labPalette();
    final (pl, pa, pb) = _rgbToLab(r, g, b);

    double best = double.infinity;
    _LabEntry? bestEntry;
    for (final entry in palette) {
      final dl = pl - entry.l;
      final da = pa - entry.a;
      final db = pb - entry.b;
      final dist = dl * dl + da * da + db * db;
      if (dist < best) {
        best = dist;
        bestEntry = entry;
      }
    }
    return bestEntry == null ? null : dmcColorByCode(bestEntry.code);
  }

  /// Imports a rectangular region from [image] (image-space coordinates) as
  /// cross-stitch data.
  ///
  /// [mergeThreshold] — merge DMC colours appearing fewer than this many times
  /// into their nearest retained colour.  Set to 0 to disable.
  ///
  /// Returns (threads, stitches) where stitches are normalised to start at
  /// (0, 0) relative to the top-left of the region.
  static ({List<Thread> threads, List<Stitch> stitches}) importRegion(
    img.Image image,
    int x,
    int y,
    int w,
    int h, {
    int mergeThreshold = 0,
  }) {
    // Clamp to image bounds.
    final x0 = x.clamp(0, image.width);
    final y0 = y.clamp(0, image.height);
    final x1 = (x + w).clamp(x0, image.width);
    final y1 = (y + h).clamp(y0, image.height);

    // Match each pixel to a DMC code, keyed by normalised position.
    final Map<int, Map<int, String>> grid = {}; // grid[sy][sx] = dmcCode
    final Map<String, int> codeCounts = {};

    // Images without an alpha channel (e.g. 4-bit palette PNGs) return
    // pixel.a == 0, which would falsely mark every pixel as transparent.
    // Treat missing-alpha images as fully opaque.
    final hasAlpha = image.numChannels >= 4;

    for (var py = y0; py < y1; py++) {
      for (var px = x0; px < x1; px++) {
        final pixel = image.getPixel(px, py);
        final match = matchPixel(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(),
          hasAlpha ? pixel.a.toInt() : 255,
        );
        if (match == null) continue;
        final sx = px - x0;
        final sy = py - y0;
        (grid[sy] ??= {})[sx] = match.code;
        codeCounts[match.code] = (codeCounts[match.code] ?? 0) + 1;
      }
    }

    // Palette reduction: remap rare colours to nearest frequent colour.
    if (mergeThreshold > 1 && codeCounts.length > 1) {
      final frequent = codeCounts.entries
          .where((e) => e.value >= mergeThreshold)
          .map((e) => e.key)
          .toSet();

      if (frequent.isNotEmpty && frequent.length < codeCounts.length) {
        final palette = _labPalette();

        // Build Lab lookup for quick access.
        Map<String, _LabEntry> labFor = {for (final e in palette) e.code: e};

        final Map<String, String> remap = {};
        for (final code in codeCounts.keys) {
          if (frequent.contains(code)) continue;
          final src = labFor[code]!;
          double best = double.infinity;
          String bestCode = frequent.first;
          for (final fCode in frequent) {
            final dst = labFor[fCode]!;
            final dl = src.l - dst.l;
            final da = src.a - dst.a;
            final db = src.b - dst.b;
            final dist = dl * dl + da * da + db * db;
            if (dist < best) {
              best = dist;
              bestCode = fCode;
            }
          }
          remap[code] = bestCode;
        }

        // Apply remap.
        for (final row in grid.values) {
          for (final sx in row.keys.toList()) {
            final code = row[sx]!;
            if (remap.containsKey(code)) row[sx] = remap[code]!;
          }
        }
      }
    }

    // Collect used codes and build Thread list.
    final usedCodes = <String>{};
    for (final row in grid.values) {
      usedCodes.addAll(row.values);
    }

    final threads = usedCodes.map((code) {
      final dmc = dmcColorByCode(code)!;
      return Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
    }).toList();

    // Build FullStitch list.
    final stitches = <Stitch>[];
    for (final entry in grid.entries) {
      final sy = entry.key;
      for (final cell in entry.value.entries) {
        stitches.add(FullStitch(x: cell.key, y: sy, threadId: cell.value));
      }
    }

    return (threads: threads, stitches: stitches);
  }

  // ── Palette strip detection ──────────────────────────────────────────────────

  /// Detects colour blocks in a palette strip region.
  /// Returns list of dominant colours (one per slot), ordered left-to-right or
  /// top-to-bottom depending on [horizontal].
  static List<Color> detectPaletteStrip(
      img.Image image, Rect region, bool horizontal) {
    final x0 = region.left.round().clamp(0, image.width - 1);
    final y0 = region.top.round().clamp(0, image.height - 1);
    final x1 = region.right.round().clamp(0, image.width);
    final y1 = region.bottom.round().clamp(0, image.height);
    if (x1 <= x0 || y1 <= y0) return [];

    final colours = <Color>[];
    Color? lastColour;
    int consecutiveCount = 0;
    const minBlockWidth = 3;

    void processPixel(int x, int y) {
      final pixel = image.getPixel(x, y);
      final c = Color.fromARGB(
          pixel.a.toInt(), pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
      final quantized = _quantizeColor(c);
      if (lastColour == null || _colorDistance(quantized, lastColour!) > 20) {
        if (consecutiveCount >= minBlockWidth && lastColour != null) {
          colours.add(lastColour!);
        }
        lastColour = quantized;
        consecutiveCount = 1;
      } else {
        consecutiveCount++;
      }
    }

    if (horizontal) {
      final midY = ((y0 + y1) / 2).round().clamp(y0, y1 - 1);
      for (int x = x0; x < x1; x++) processPixel(x, midY);
    } else {
      final midX = ((x0 + x1) / 2).round().clamp(x0, x1 - 1);
      for (int y = y0; y < y1; y++) processPixel(midX, y);
    }
    if (consecutiveCount >= minBlockWidth && lastColour != null) {
      colours.add(lastColour!);
    }
    return colours;
  }

  static Color _quantizeColor(Color c) {
    int q(double v) => ((v * 255 / 16).round() * 16).clamp(0, 255);
    return Color.fromARGB(255, q(c.r), q(c.g), q(c.b));
  }

  static double _colorDistance(Color a, Color b) {
    final dr = (a.r - b.r) * 255;
    final dg = (a.g - b.g) * 255;
    final db = (a.b - b.b) * 255;
    return sqrt(dr * dr + dg * dg + db * db);
  }

  /// Like [importRegion] but also builds extra palettes from detected strip
  /// colours. Returns a fully constructed [Snippet].
  static Future<Snippet> importRegionWithPalettes({
    required img.Image image,
    required Rect region,
    required String name,
    required int mergeThreshold,
    List<List<Color>> paletteStrips = const [],
  }) async {
    final x = region.left.round();
    final y = region.top.round();
    final w = region.width.round();
    final h = region.height.round();

    final imported = importRegion(
      image,
      x,
      y,
      w,
      h,
      mergeThreshold: mergeThreshold,
    );

    final primaryPalette =
        SnippetPalette.create(name: 'Palette 1', threads: imported.threads);
    final slotCount = primaryPalette.threads.length;
    final palettes = <SnippetPalette>[primaryPalette];

    for (int i = 0; i < paletteStrips.length; i++) {
      final stripColours = paletteStrips[i];
      List<Thread> threads;
      if (stripColours.length == slotCount) {
        threads = stripColours.map((c) {
          final r = (c.r * 255).round();
          final g = (c.g * 255).round();
          final b = (c.b * 255).round();
          final dmc = matchPixel(r, g, b, 255);
          if (dmc != null) {
            return Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
          }
          final idx = stripColours.indexOf(c) % slotCount;
          return primaryPalette.threads[idx];
        }).toList();
      } else {
        threads = List<Thread>.from(primaryPalette.threads);
      }
      palettes.add(SnippetPalette(
        id: const Uuid().v4(),
        name: 'Palette ${i + 2}',
        threads: threads,
      ));
    }

    return Snippet(
      id: const Uuid().v4(),
      name: name,
      width: w.clamp(1, image.width),
      height: h.clamp(1, image.height),
      stitches: imported.stitches,
      palettes: palettes,
    );
  }
}
