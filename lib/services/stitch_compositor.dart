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
///
/// Prefer [CompositeLayer] for new code — [CompositeResult] is retained for
/// backwards compatibility while callers migrate incrementally.
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

// ─── CompositeStitch ──────────────────────────────────────────────────────────

/// A single stitch with its layer-blended display colour and resolved thread.
///
/// Produced by [StitchCompositor]. [blendedColor] and [resolvedThread] are
/// already computed for this stitch — no further layer logic needed downstream.
class CompositeStitch {
  /// The original stitch (position, type, orientation).
  final Stitch stitch;

  /// Display colour after layer opacity/blend-mode compositing.
  /// For single-layer cells this equals [resolvedThread].color.
  final Color blendedColor;

  /// The nearest-DMC thread after blending. Carries the symbol for stitch mode.
  final Thread resolvedThread;

  /// True when [blendedColor] was computed by blending ≥2 visible layers.
  /// False for single-layer cells; [blendedColor] == [resolvedThread].color.
  final bool isBlended;

  const CompositeStitch({
    required this.stitch,
    required this.blendedColor,
    required this.resolvedThread,
    required this.isBlended,
  });
}

// ─── CompositeLayer ───────────────────────────────────────────────────────────

/// Flat, layer-resolved view of a [CrossStitchPattern].
///
/// Produced by [StitchCompositor]. All layer blending is resolved; rendering
/// code has no need to know about layers.
///
/// - [fullStitches] maps `'x,y'` → [CompositeStitch] (one per occupied cell).
/// - [otherStitches] contains half/quarter stitches verbatim.
/// - [backstitches] contains all visible backstitches.
class CompositeLayer {
  /// FullStitch cells keyed by `'x,y'`. One entry per cell; symbol-winner rule applied.
  final Map<String, CompositeStitch> fullStitches;

  /// Non-back, non-full stitches (half, quarter, etc.) — one per stitch verbatim.
  final List<CompositeStitch> otherStitches;

  /// All backstitches from all visible layers.
  final List<BackStitch> backstitches;

  /// Cross-stitch equivalent count per dmcCode.
  /// FullStitches → 1.0; HalfStitch/HalfCross → 0.5; Quarter/QuarterCross → 0.25.
  final Map<String, double> crossStitchEquiv;

  /// Backstitch Euclidean cell-unit length per threadId.
  final Map<String, double> backStitchEquiv;

  const CompositeLayer({
    required this.fullStitches,
    required this.otherStitches,
    required this.backstitches,
    required this.crossStitchEquiv,
    required this.backStitchEquiv,
  });

  /// Convert to [CompositeResult] for callers that have not yet migrated to
  /// the [CompositeLayer] API.
  CompositeResult toCompositeResult() {
    final compositeThreads = <String, Thread>{
      for (final e in fullStitches.entries) e.key: e.value.resolvedThread,
    };
    final blendedColors = <String, Color>{
      for (final e in fullStitches.entries)
        if (e.value.isBlended) e.key: e.value.blendedColor,
    };
    final dedupedNonBack = <Stitch>[
      ...fullStitches.values.map((c) => c.stitch),
      ...otherStitches.map((c) => c.stitch),
    ];
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

// ─── StitchCompositor ─────────────────────────────────────────────────────────

/// Computes and optionally maintains the [CompositeLayer] for a pattern.
///
/// ## Stateful (incremental) usage
///
/// Create an instance from a pattern and call update methods when the pattern
/// changes. [compositeLayer] is lazily rebuilt on the next access after any
/// invalidation. Future optimisation will narrow rebuilds to dirty cells only.
///
/// ```dart
/// final compositor = StitchCompositor(pattern);
///
/// // One stitch added at (3, 4):
/// compositor.updateCell(3, 4);
/// final layer = compositor.compositeLayer; // rebuilt incrementally
/// ```
///
/// ## Static convenience
///
/// For one-shot use (services, tests, PDF export) the static helpers remain:
///
/// ```dart
/// final result = StitchCompositor.compute(pattern);       // CompositeResult
/// final layer  = StitchCompositor.computeLayer(pattern);  // CompositeLayer
/// ```
class StitchCompositor {
  final CrossStitchPattern _pattern;
  CompositeLayer? _cached;

  StitchCompositor(CrossStitchPattern pattern) : _pattern = pattern;

  /// The current [CompositeLayer]. Lazily built on first access; invalidated
  /// by the update methods below.
  CompositeLayer get compositeLayer => _cached ??= _buildLayer(_pattern);

  /// Backwards-compatible [CompositeResult] derived from [compositeLayer].
  CompositeResult get compositeResult => compositeLayer.toCompositeResult();

  // ─── Incremental invalidation API ────────────────────────────────────────
  // Currently all methods invalidate the full cache; [compositeLayer] is
  // lazily rebuilt in full on next access.  The RenderCache migration step
  // will introduce true cell-level invalidation once the painter no longer
  // owns its own static caches.

  /// Invalidate the composite for a single changed cell (x, y).
  ///
  /// Call when exactly one stitch is added or removed at [x], [y].
  void updateCell(int x, int y) => _cached = null;

  /// Invalidate the composite for a batch of changed cells.
  ///
  /// Cells may be duplicated; deduplification is handled internally.
  /// Call after paste, move, or fill operations.
  void updateCells(List<(int, int)> cells) => _cached = null;

  /// Invalidate the composite for an entire layer.
  ///
  /// Call when layer visibility, opacity, or blend mode changes.
  void updateLayer(String layerId) => _cached = null;

  /// Invalidate and schedule a full rebuild.
  ///
  /// Call when thread colours change or the entire pattern is replaced.
  void rebuild() => _cached = null;

  // ─── Static convenience ───────────────────────────────────────────────────

  /// Compute the composite for [pattern] and return a [CompositeResult].
  ///
  /// Retained for backwards compatibility. Prefer [computeLayer] or the
  /// stateful instance API for new code.
  static CompositeResult compute(CrossStitchPattern pattern) =>
      _buildLayer(pattern).toCompositeResult();

  /// Compute the composite for [pattern] and return a [CompositeLayer].
  static CompositeLayer computeLayer(CrossStitchPattern pattern) =>
      _buildLayer(pattern);

  // ─── Core build logic ─────────────────────────────────────────────────────

  /// Single-pass composite build. O(total visible stitches).
  static CompositeLayer _buildLayer(CrossStitchPattern pattern) {
    final threadMap = <String, Thread>{
      for (final t in pattern.threads) t.dmcCode: t,
    };

    // ── Pass 1: bucket FullStitches per cell; collect everything else ────────
    final cellStack = <String,
        List<({
          FullStitch stitch,
          Color color,
          double opacity,
          LayerBlendMode blendMode,
        })>>{};
    final otherNonBackRaw = <Stitch>[];
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
          otherNonBackRaw.add(s);
        }
      }
    }

    // ── Pass 2: resolve each cell → blended colour, thread, CompositeStitch ─
    final fullStitches = <String, CompositeStitch>{};

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

      if (stack.length == 1) {
        final t = threadMap[stack.first.stitch.threadId];
        if (t == null) continue;
        fullStitches[key] = CompositeStitch(
          stitch: symbolStitch,
          blendedColor: t.color,
          resolvedThread: t,
          isBlended: false,
        );
      } else {
        // The bottom layer is always the compositing base — its own blend mode
        // is not applied (it has no layer below to blend with). Layers above it
        // are applied in order, each blending onto the accumulated result.
        var blended = stack.first.color;
        for (int i = 1; i < stack.length; i++) {
          blended = stack[i].blendMode.apply(blended, stack[i].color, stack[i].opacity);
        }

        final r = (blended.r * 255).round();
        final g = (blended.g * 255).round();
        final b = (blended.b * 255).round();
        final dmc = SpriteImporter.matchPixel(r, g, b, 255);
        final resolvedThread = dmc == null
            ? threadMap[stack.first.stitch.threadId]
            : (threadMap[dmc.code] ??
                Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name));
        if (resolvedThread == null) continue;

        fullStitches[key] = CompositeStitch(
          stitch: symbolStitch,
          blendedColor: blended,
          resolvedThread: resolvedThread,
          isBlended: true,
        );
      }
    }

    // ── Wrap other stitches ───────────────────────────────────────────────────
    final otherStitches = <CompositeStitch>[
      for (final s in otherNonBackRaw)
        if (threadMap[s.threadId] case final t?)
          CompositeStitch(
            stitch: s,
            blendedColor: t.color,
            resolvedThread: t,
            isBlended: false,
          ),
    ];

    // ── Pass 3: stitch counts from the composite view ────────────────────────
    final crossStitchEquiv = <String, double>{};
    for (final cs in fullStitches.values) {
      final dmcCode = cs.resolvedThread.dmcCode;
      crossStitchEquiv[dmcCode] = (crossStitchEquiv[dmcCode] ?? 0) + 1.0;
    }
    for (final cs in otherStitches) {
      final dmcCode = cs.resolvedThread.dmcCode;
      final v = switch (cs.stitch) {
        HalfStitch() => 0.5,
        HalfCrossStitch() => 0.5,
        QuarterStitch() => 0.25,
        QuarterCrossStitch() => 0.25,
        _ => 0.0,
      };
      if (v > 0) crossStitchEquiv[dmcCode] = (crossStitchEquiv[dmcCode] ?? 0) + v;
    }

    final backStitchEquiv = <String, double>{};
    for (final s in backstitches) {
      final len =
          math.sqrt(math.pow(s.x2 - s.x1, 2) + math.pow(s.y2 - s.y1, 2));
      backStitchEquiv[s.threadId] = (backStitchEquiv[s.threadId] ?? 0) + len;
    }

    return CompositeLayer(
      fullStitches: fullStitches,
      otherStitches: otherStitches,
      backstitches: backstitches,
      crossStitchEquiv: crossStitchEquiv,
      backStitchEquiv: backStitchEquiv,
    );
  }
}
