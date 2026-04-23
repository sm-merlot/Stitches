import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../data/dmc_colors.dart';
import '../models/snippet.dart';
import '../models/snippet_palette.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import 'color_space.dart';

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
/// each pixel to the nearest DMC thread colour using CIEDE2000.
class SpriteImporter {
  SpriteImporter._();

  static List<_LabEntry>? _palette;

  /// Per-pixel match cache keyed by packed RGB (bits 23-0).
  /// Sprite sheets typically reuse a small set of colours, so cache hit rates
  /// are very high and make the CIEDE2000 cost negligible in practice.
  static final Map<int, DmcColor?> _matchCache = {};

  // ── Lab palette ─────────────────────────────────────────────────────────────

  static List<_LabEntry> _labPalette() {
    return _palette ??= dmcColors.map((dmc) {
      final r = (dmc.color.r * 255).round();
      final g = (dmc.color.g * 255).round();
      final b = (dmc.color.b * 255).round();
      final (l, a, bb) = rgbToLab(r, g, b);
      return (code: dmc.code, name: dmc.name, color: dmc.color, l: l, a: a, b: bb);
    }).toList();
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Matches a pixel to the nearest DMC colour using CIEDE2000.
  ///
  /// Results are cached by RGB value — repeated colours (common in sprite art)
  /// are free after the first lookup.
  ///
  /// Returns null for transparent pixels (alpha < 128).
  static DmcColor? matchPixel(int r, int g, int b, int a) {
    if (a < 128) return null;
    final key = (r << 16) | (g << 8) | b;
    return _matchCache.putIfAbsent(key, () => _matchUncached(r, g, b));
  }

  static DmcColor? _matchUncached(int r, int g, int b) {
    final palette = _labPalette();
    final pixelLab = rgbToLab(r, g, b);

    double best = double.infinity;
    _LabEntry? bestEntry;
    for (final entry in palette) {
      final dist = ciede2000(pixelLab, (entry.l, entry.a, entry.b));
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
          final srcLab = (src.l, src.a, src.b);
          double best = double.infinity;
          String bestCode = frequent.first;
          for (final fCode in frequent) {
            final dst = labFor[fCode]!;
            final dist = ciede2000(srcLab, (dst.l, dst.a, dst.b));
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

  // ── Palette preview rendering ────────────────────────────────────────────────

  /// Re-renders a crop [region] of [image] matching each pixel against
  /// [matchPalette] (Palette 1 colours) by CIE Lab Euclidean distance.
  ///
  /// Pixels whose nearest match exceeds [dropThreshold] Lab units are dropped
  /// (left transparent) — this removes background colours not in the palette.
  ///
  /// If [outputPalette] is provided (Palette N, N > 1), the matched index is
  /// used to look up the replacement colour positionally:
  ///   matchPalette[i] → outputPalette[i]
  /// This implements slot-based palette swapping for subsequent palettes.
  ///
  /// Transparent pixels (alpha < 128) remain transparent.
  /// Returns null if [matchPalette] is empty or the region is empty/out-of-bounds.
  static Uint8List? renderCropWithPalette(
    img.Image image,
    Rect region,
    List<Color> matchPalette, {
    List<Color>? outputPalette,
    double dropThreshold = 30.0,
  }) {
    if (matchPalette.isEmpty) return null;
    final x0 = region.left.round().clamp(0, image.width);
    final y0 = region.top.round().clamp(0, image.height);
    final x1 = region.right.round().clamp(x0, image.width);
    final y1 = region.bottom.round().clamp(y0, image.height);
    final w = x1 - x0;
    final h = y1 - y0;
    if (w <= 0 || h <= 0) return null;

    // Pre-compute Lab values for the match palette.
    final paletteLab = matchPalette.map((c) {
      final r = (c.r * 255).round();
      final g = (c.g * 255).round();
      final b = (c.b * 255).round();
      final (l, a, bb) = rgbToLab(r, g, b);
      return (color: c, l: l, a: a, b: bb);
    }).toList();

    final out = img.Image(width: w, height: h);

    for (var py = y0; py < y1; py++) {
      for (var px = x0; px < x1; px++) {
        final pixel = image.getPixel(px, py);
        // Do not skip low-alpha pixels here: indexed PNGs (e.g. SNES rips) mark
        // background palette entries as transparent even when the pixels carry
        // real colour data. The drop threshold below handles background exclusion.

        final pixelLab =
            rgbToLab(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

        double best = double.infinity;
        int bestIdx = 0;
        for (int i = 0; i < paletteLab.length; i++) {
          final entry = paletteLab[i];
          final dist = ciede2000(pixelLab, (entry.l, entry.a, entry.b));
          if (dist < best) {
            best = dist;
            bestIdx = i;
          }
        }

        // Drop pixel if it doesn't closely match any palette colour (= background).
        if (best > dropThreshold) continue;

        // Use outputPalette positionally if provided, else matched colour.
        final Color outColor;
        if (outputPalette != null && bestIdx < outputPalette.length) {
          outColor = outputPalette[bestIdx];
        } else {
          outColor = matchPalette[bestIdx];
        }

        out.setPixelRgba(
          px - x0,
          py - y0,
          (outColor.r * 255).round(),
          (outColor.g * 255).round(),
          (outColor.b * 255).round(),
          255,
        );
      }
    }

    return Uint8List.fromList(img.encodePng(out));
  }

  // ── Palette strip detection ──────────────────────────────────────────────────

  /// Detects colour slots in a palette strip region.
  ///
  /// Returns the **exact raw pixel colour** of each distinct slot, ordered
  /// left-to-right or top-to-bottom depending on [horizontal].
  ///
  /// Assumes the strip is a clean, indexed PNG where every pixel within a slot
  /// is the same uniform colour. A new slot is recorded whenever the midline
  /// pixel has a different RGB value from the previous pixel — no colour-space
  /// conversion or distance calculation is involved.
  ///
  /// Raw pixel values are returned without any averaging, quantisation, or DMC
  /// mapping so that downstream matching compares sprite pixels against the
  /// same unmodified values that appear in the source image.
  static List<Color> detectPaletteStrip(
      img.Image image, Rect region, bool horizontal) {
    final x0 = region.left.round().clamp(0, image.width - 1);
    final y0 = region.top.round().clamp(0, image.height - 1);
    final x1 = region.right.round().clamp(0, image.width);
    final y1 = region.bottom.round().clamp(0, image.height);
    if (x1 <= x0 || y1 <= y0) return [];

    final colours = <Color>[];
    int? lastPacked;

    void processPixel(int x, int y) {
      final px = image.getPixel(x, y);
      final packed = (px.r.toInt() << 16) | (px.g.toInt() << 8) | px.b.toInt();
      if (packed != lastPacked) {
        colours.add(Color.fromARGB(255, px.r.toInt(), px.g.toInt(), px.b.toInt()));
        lastPacked = packed;
      }
    }

    if (horizontal) {
      final midY = ((y0 + y1) / 2).round().clamp(y0, y1 - 1);
      for (int x = x0; x < x1; x++) { processPixel(x, midY); }
    } else {
      final midX = ((x0 + x1) / 2).round().clamp(x0, x1 - 1);
      for (int y = y0; y < y1; y++) { processPixel(midX, y); }
    }
    return colours;
  }


  /// Imports a crop region and builds palettes from detected palette strips.
  ///
  /// When [paletteStrips] is empty: auto-detects all DMC colours (existing
  /// behaviour — one palette, no restrictions).
  ///
  /// When [paletteStrips] is non-empty:
  ///   - Strip 0 becomes Palette 1 (the primary/base palette).
  ///   - The crop is matched against Palette 1 colours only; background pixels
  ///     (Lab distance > 30) are dropped.
  ///   - Strips 1, 2, … become Palette 2, 3, … via positional slot mapping:
  ///     strip[N][i] replaces strip[0][i] when Palette N+1 is active.
  ///
  /// The auto-detected palette is NOT included when strips are provided.
  static Future<Snippet> importRegionWithPalettes({
    required img.Image image,
    required Rect region,
    required String name,
    int mergeThreshold = 0,
    List<List<Color>> paletteStrips = const [],
  }) async {
    final x = region.left.round();
    final y = region.top.round();
    final w = region.width.round();
    final h = region.height.round();

    if (paletteStrips.isEmpty) {
      // ── No strips: auto-detect all DMC colours ──────────────────────────
      final imported =
          importRegion(image, x, y, w, h, mergeThreshold: mergeThreshold);
      return Snippet(
        id: const Uuid().v4(),
        name: name,
        width: w.clamp(1, image.width),
        height: h.clamp(1, image.height),
        stitches: imported.stitches,
        palettes: [
          SnippetPalette.create(name: 'Palette 1', threads: imported.threads),
        ],
      );
    }

    // ── Strips provided: strip 0 is the primary palette ─────────────────────
    final primaryThreads = _dmcMatchStrip(paletteStrips[0]);
    if (primaryThreads.isEmpty) {
      // Strip 0 produced no threads — fall back to auto detection.
      final imported =
          importRegion(image, x, y, w, h, mergeThreshold: mergeThreshold);
      return Snippet(
        id: const Uuid().v4(),
        name: name,
        width: w.clamp(1, image.width),
        height: h.clamp(1, image.height),
        stitches: imported.stitches,
        palettes: [
          SnippetPalette.create(name: 'Palette 1', threads: imported.threads),
        ],
      );
    }

    // Import crop pixels: match against raw strip colours for accuracy,
    // then assign the corresponding DMC thread code.
    final stitches = _importRegionRestrictedFromRaw(
        image, x, y, w, h, paletteStrips[0], primaryThreads);

    final palettes = <SnippetPalette>[
      SnippetPalette.create(name: 'Palette 1', threads: primaryThreads),
    ];

    // Build subsequent palettes using positional slot mapping.
    final slotCount = primaryThreads.length;
    for (int i = 1; i < paletteStrips.length; i++) {
      final stripThreads = _dmcMatchStrip(paletteStrips[i]);
      // Pad or truncate to match primary slot count.
      final threads = List<Thread>.generate(slotCount, (j) =>
        j < stripThreads.length ? stripThreads[j] : primaryThreads[j]);
      palettes.add(SnippetPalette.create(
          name: 'Palette ${i + 1}', threads: threads));
    }

    return Snippet(
      id: const Uuid().v4(),
      name: name,
      width: w.clamp(1, image.width),
      height: h.clamp(1, image.height),
      stitches: stitches,
      palettes: palettes,
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  /// Like [_importRegionRestricted] but matches crop pixels against [rawStripColors]
  /// (the original palette-strip pixel colours) rather than their DMC translations.
  /// This avoids the double-approximation error where a pixel fails the drop
  /// threshold only because the DMC translation shifted the strip colour.
  /// [dmcThreads] must be parallel to [rawStripColors]; the winning slot's
  /// DMC code is used as the stitch threadId.
  static List<Stitch> _importRegionRestrictedFromRaw(
    img.Image image,
    int x,
    int y,
    int w,
    int h,
    List<Color> rawStripColors,
    List<Thread> dmcThreads,
  ) {
    final x0 = x.clamp(0, image.width);
    final y0 = y.clamp(0, image.height);
    final x1 = (x + w).clamp(x0, image.width);
    final y1 = (y + h).clamp(y0, image.height);

    final stripLab = List.generate(rawStripColors.length, (i) {
      final c = rawStripColors[i];
      final r = (c.r * 255).round();
      final g = (c.g * 255).round();
      final b = (c.b * 255).round();
      final (l, a, bb) = rgbToLab(r, g, b);
      return (thread: dmcThreads[i], l: l, a: a, b: bb);
    });

    const dropThreshold = 30.0; // CIEDE2000 units
    final stitches = <Stitch>[];

    for (var py = y0; py < y1; py++) {
      for (var px = x0; px < x1; px++) {
        final pixel = image.getPixel(px, py);
        // Do not skip low-alpha pixels: indexed PNGs (e.g. SNES rips) mark
        // background entries as transparent even when they carry real colour.
        // The drop threshold below provides background exclusion instead.

        final pixelLab =
            rgbToLab(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

        double best = double.infinity;
        Thread? bestThread;
        for (final entry in stripLab) {
          final dist = ciede2000(pixelLab, (entry.l, entry.a, entry.b));
          if (dist < best) {
            best = dist;
            bestThread = entry.thread;
          }
        }

        if (best > dropThreshold || bestThread == null) continue;

        stitches.add(FullStitch(
            x: px - x0, y: py - y0, threadId: bestThread.dmcCode));
      }
    }

    return stitches;
  }

  /// DMC-matches each raw [Color] in [stripColours] in order.
  /// Preserves position so that index N here maps to slot N.
  static List<Thread> _dmcMatchStrip(List<Color> stripColours) {
    return stripColours.map((c) {
      final dmc = matchPixel(
          (c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255);
      if (dmc == null) return null;
      return Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
    }).whereType<Thread>().toList();
  }

  /// Imports crop pixels matching only against [allowedThreads].
  /// Pixels whose nearest match exceeds 30 Lab units are dropped (background).
}
