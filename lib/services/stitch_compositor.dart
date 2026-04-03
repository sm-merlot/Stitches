import 'dart:math' as math;
import 'package:flutter/material.dart' show Color;
import '../models/layer_blend_mode.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import 'sprite_importer.dart';

/// The flattened, stitcher-facing view of a [CrossStitchPattern].
///
/// Layers are a design-time concept. After calling [StitchCompositor.compute],
/// this object represents what the stitcher actually needs to stitch once all
/// layer blending has been resolved.
class CompositeResult {
  /// Final thread per occupied cell, keyed by `'x,y'`.
  /// Single-layer cells use their source thread; multi-layer cells use the
  /// DMC-snapped blended thread.
  final Map<String, Thread> compositeThreads;

  /// Raw blended [Color] for cells where ≥2 visible layers overlap.
  /// Not present for single-layer cells.
  final Map<String, Color> blendedColors;

  /// One stitch per FullStitch cell (symbol-winner rule applied), plus all
  /// non-back non-full stitches from all visible layers verbatim.
  /// This is the canonical stitch list for the stitcher.
  final List<Stitch> dedupedNonBack;

  /// All [BackStitch] instances from all visible layers.
  final List<BackStitch> backstitches;

  /// Cross-stitch equivalents per dmcCode.
  /// FullStitches → 1.0 against the composite thread's dmcCode.
  /// Non-full non-back types → fractional (0.5 half, 0.25 quarter) against source threadId.
  final Map<String, double> crossStitchEquiv;

  /// Backstitch Euclidean cell-unit length per threadId.
  final Map<String, double> backStitchEquiv;

  const CompositeResult({
    required this.compositeThreads,
    required this.blendedColors,
    required this.dedupedNonBack,
    required this.backstitches,
    required this.crossStitchEquiv,
    required this.backStitchEquiv,
  });
}

class StitchCompositor {
  StitchCompositor._();

  /// Compute the canonical composite view of [pattern].
  ///
  /// Single pass over all visible layer stitches; O(total stitches).
  static CompositeResult compute(CrossStitchPattern pattern) {
    final threadMap = <String, Thread>{
      for (final t in pattern.threads) t.dmcCode: t,
    };

    // ── Pass 1: bucket FullStitches per cell; collect everything else ──────────
    final cellStack = <String,
        List<({
          FullStitch stitch,
          Color color,
          double opacity,
          LayerBlendMode blendMode,
        })>>{};
    final otherNonBack = <Stitch>[];
    final backstitches = <BackStitch>[];

    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final s in layer.stitches) {
        if (s is BackStitch) {
          backstitches.add(s);
        } else if (s is FullStitch) {
          final thread = threadMap[s.threadId];
          if (thread == null) continue;
          (cellStack['${s.x},${s.y}'] ??= []).add((
            stitch: s,
            color: thread.color,
            opacity: layer.opacity,
            blendMode: layer.blendMode,
          ));
        } else {
          otherNonBack.add(s);
        }
      }
    }

    // ── Pass 2: resolve each cell → compositeThread, blendedColor, symbolStitch ─
    final compositeThreads = <String, Thread>{};
    final blendedColors = <String, Color>{};
    final dedupedFullStitches = <Stitch>[];

    for (final entry in cellStack.entries) {
      final key = entry.key;
      final stack = entry.value;

      // Symbol-winner: topmost layer when Normal blend at ≥99% opacity;
      // otherwise bottom layer provides primary thread identity.
      final top = stack.last;
      final symbolStitch =
          (top.blendMode == LayerBlendMode.normal && top.opacity >= 0.99)
              ? top.stitch
              : stack.first.stitch;
      dedupedFullStitches.add(symbolStitch);

      if (stack.length == 1) {
        final t = threadMap[stack.first.stitch.threadId];
        if (t != null) compositeThreads[key] = t;
      } else {
        // The bottom layer is always the compositing base — its own blend mode is not
        // applied (it has no layer below to blend with). Layers above it are applied
        // in order, each blending onto the accumulated result.
        var blended = stack.first.color;
        for (int i = 1; i < stack.length; i++) {
          blended = stack[i].blendMode.apply(blended, stack[i].color, stack[i].opacity);
        }
        blendedColors[key] = blended;

        final r = (blended.r * 255).round();
        final g = (blended.g * 255).round();
        final b = (blended.b * 255).round();
        final dmc = SpriteImporter.matchPixel(r, g, b, 255);
        if (dmc != null) {
          compositeThreads[key] = threadMap[dmc.code] ??
              Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
        }
      }
    }

    final dedupedNonBack = [...dedupedFullStitches, ...otherNonBack];

    // ── Pass 3: stitch counts from the composite view ────────────────────────
    final crossStitchEquiv = <String, double>{};
    final backStitchEquiv = <String, double>{};

    for (final s in dedupedNonBack) {
      final String dmcCode;
      final double v;
      if (s is FullStitch) {
        dmcCode = compositeThreads['${s.x},${s.y}']?.dmcCode ?? s.threadId;
        v = 1.0;
      } else {
        dmcCode = s.threadId;
        v = switch (s) {
          HalfStitch() => 0.5,
          HalfCrossStitch() => 0.5,
          QuarterStitch() => 0.25,
          QuarterCrossStitch() => 0.25,
          _ => 0.0,
        };
      }
      if (v > 0) crossStitchEquiv[dmcCode] = (crossStitchEquiv[dmcCode] ?? 0) + v;
    }

    for (final s in backstitches) {
      final len =
          math.sqrt(math.pow(s.x2 - s.x1, 2) + math.pow(s.y2 - s.y1, 2));
      backStitchEquiv[s.threadId] = (backStitchEquiv[s.threadId] ?? 0) + len;
    }

    return CompositeResult(
      compositeThreads: compositeThreads,
      blendedColors: blendedColors,
      dedupedNonBack: dedupedNonBack,
      backstitches: backstitches,
      crossStitchEquiv: crossStitchEquiv,
      backStitchEquiv: backStitchEquiv,
    );
  }
}
