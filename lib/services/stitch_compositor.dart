import 'dart:math' as math;
import 'package:flutter/material.dart' show Color;
import '../models/cell.dart';
import '../models/layer/layer.dart';
import '../models/layer/layer_blend_mode.dart';
import '../models/pattern.dart';
import '../models/stitch/stitch.dart';
import '../models/stitch/stitch_geometry.dart';
import '../models/thread.dart';
import 'sprite_importer.dart';

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
/// - [fullStitches] maps [Cell] → [CompositeStitch] (one per occupied cell).
/// - [otherStitches] contains half/quarter stitches verbatim.
/// - [backstitches] contains all visible backstitches.
class CompositeLayer {
  /// FullStitch cells keyed by [Cell]. One entry per cell; symbol-winner rule applied.
  final Map<Cell, CompositeStitch> fullStitches;

  /// Non-back, non-full stitches (half, quarter, etc.) — one per stitch verbatim.
  final List<CompositeStitch> otherStitches;

  /// All backstitches from all visible layers.
  final List<BackStitch> backstitches;

  /// Cross-stitch equivalent count per dmcCode.
  /// FullStitches → 1.0; HalfStitch/HalfCross → 0.5; Quarter/QuarterCross → 0.25.
  final Map<String, double> crossStitchEquiv;

  /// Backstitch Euclidean cell-unit length per threadId.
  final Map<String, double> backStitchEquiv;

  /// Monotonically increasing version counter.
  ///
  /// Bumped by [StitchCompositor.patchLayer] and [patchAffectedLayer] when the
  /// composite is mutated in-place. [_syncRenderCache] in [AidaWidget] uses
  /// this instead of `identical()` to detect changes.
  int version;

  CompositeLayer({
    required this.fullStitches,
    required this.otherStitches,
    required this.backstitches,
    required this.crossStitchEquiv,
    required this.backStitchEquiv,
    this.version = 0,
  });

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
/// For one-shot use (services, tests, PDF export):
///
/// ```dart
/// final layer = StitchCompositor.computeLayer(pattern);  // CompositeLayer
/// ```
class StitchCompositor {
  final CrossStitchPattern _pattern;
  CompositeLayer? _cached;

  StitchCompositor(CrossStitchPattern pattern) : _pattern = pattern;

  /// The current [CompositeLayer]. Lazily built on first access; invalidated
  /// by the update methods below.
  CompositeLayer get compositeLayer => _cached ??= _buildLayer(_pattern);

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

  /// Compute the composite for [pattern] and return a [CompositeLayer].
  static CompositeLayer computeLayer(CrossStitchPattern pattern) =>
      _buildLayer(pattern);

  /// Incrementally patches [old] by recomputing only the cell at ([x], [y]).
  ///
  /// Uses [Layer.stitchesAt] (O(1) via lazy cell index) to collect contributions
  /// at ([x], [y]) from each visible layer, then copies [old.fullStitches] and
  /// updates just that key. All other cells carry over unchanged.
  /// Complexity: O(visible_layers × stitches_at_cell) — effectively O(1) for
  /// sparse patterns.
  ///
  /// Pass [backstitchesChanged] = true when a [BackStitch] touching cell ([x],[y])
  /// was added or removed; triggers a full backstitch list rescan. For ordinary
  /// cross/half/quarter stitch draws this is always false.
  ///
  /// Stitch-count equivalents ([CompositeLayer.crossStitchEquiv],
  /// [CompositeLayer.backStitchEquiv]) are carried from [old] — they will be
  /// corrected by the next debounced [refreshCompositeCache] call (80 ms).
  static CompositeLayer patchLayer(
    CompositeLayer old,
    CrossStitchPattern newPattern,
    int x,
    int y, {
    bool backstitchesChanged = false,
  }) {
    // Mutate in-place + bump version — avoids O(N_cells) Map.from copy.
    // Safe because the old CompositeLayer is discarded (callers always pass
    // the result to state.copyWith which replaces the previous reference).
    final newOtherAtCell = <CompositeStitch>[];
    _resolveCell(old.fullStitches, newOtherAtCell, newPattern, x, y);

    // Patch otherStitches: drop old entries at (x, y), append new ones.
    old.otherStitches.removeWhere((cs) {
      final coords = cs.stitch.cellCoords;
      return coords != null && coords.x == x && coords.y == y;
    });
    old.otherStitches.addAll(newOtherAtCell);

    // Rebuild backstitches only when one was added or removed.
    if (backstitchesChanged) {
      old.backstitches
        ..clear()
        ..addAll([
          for (final layer in newPattern.layers)
            if (layer.visible) ...layer.backstitches,
        ]);
    }

    old.version++;
    return old;
  }

  // ─── Affected-layer patch ──────────────────────────────────────────────────

  /// Patches [old] by recomputing only cells that [changedLayer] touches.
  ///
  /// Use when a single layer's visibility, opacity, or blend mode changes.
  /// Cells not touched by [changedLayer] carry over from [old] unchanged.
  ///
  /// Copies [old.fullStitches] ONCE then updates all affected cells in-place —
  /// O(cells_in_layer × avg_layers_per_cell + total_composite_cells).
  /// Far cheaper than [computeLayer] (O(total_stitches)) for sparse changes,
  /// and avoids the O(N × M) trap of calling [patchLayer] N times (each
  /// of which would copy the full map).
  static CompositeLayer patchAffectedLayer(
    CompositeLayer old,
    CrossStitchPattern newPattern,
    Layer changedLayer,
  ) {
    // Collect unique cell positions and backstitch presence from primary storage.
    final affectedCells = changedLayer.stitchesByCell.keys.toSet();
    final hasBackstitches = changedLayer.backstitches.isNotEmpty;

    if (affectedCells.isEmpty && !hasBackstitches) return old;

    // Copy fullStitches map ONCE, then update all affected cells in-place.
    final newFullStitches = Map<Cell, CompositeStitch>.from(old.fullStitches);
    final newOtherContributions = <CompositeStitch>[];

    for (final cell in affectedCells) {
      _resolveCell(newFullStitches, newOtherContributions, newPattern, cell.x, cell.y);
    }

    // Patch otherStitches: strip old entries for all affected cells, append new.
    final newOtherStitches = <CompositeStitch>[
      ...old.otherStitches.where((cs) {
        final coords = cs.stitch.cellCoords;
        return coords == null || !affectedCells.contains(coords);
      }),
      ...newOtherContributions,
    ];

    // Rebuild backstitch list when the changed layer contributes backstitches.
    final newBackstitches = hasBackstitches
        ? <BackStitch>[
            for (final layer in newPattern.layers)
              if (layer.visible) ...layer.backstitches,
          ]
        : old.backstitches;

    return CompositeLayer(
      fullStitches: newFullStitches,
      otherStitches: newOtherStitches,
      backstitches: newBackstitches,
      crossStitchEquiv: old.crossStitchEquiv,
      backStitchEquiv: old.backStitchEquiv,
    );
  }

  // ─── Shared cell resolver ─────────────────────────────────────────────────

  /// Resolves the composite for cell ([x], [y]) across all visible layers of
  /// [pattern] and writes the result into [target].
  ///
  /// If the cell has no stitches in any visible layer the key is removed from
  /// [target]. Non-full, non-back stitches are appended to [otherAcc].
  static void _resolveCell(
    Map<Cell, CompositeStitch> target,
    List<CompositeStitch> otherAcc,
    CrossStitchPattern pattern,
    int x,
    int y,
  ) {
    final threadMap = pattern.threads;
    final key = Cell(x, y);

    // Collect contributions from every visible layer at this cell.
    final stack = <({
      FullStitch stitch,
      Color color,
      double opacity,
      LayerBlendMode blendMode,
    })>[];
    final otherAtCell = <Stitch>[];

    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final s in layer.stitchesAt(x, y)) {
        // stitchesAt never returns BackStitch (no cellCoords → not indexed).
        if (s is FullStitch) {
          final thread = threadMap[s.threadId];
          if (thread == null) continue;
          stack.add((
            stitch: s,
            color: thread.color,
            opacity: layer.opacity,
            blendMode: layer.blendMode,
          ));
        } else {
          otherAtCell.add(s);
        }
      }
    }

    // Remove cell if nothing visible there any more.
    if (stack.isEmpty && otherAtCell.isEmpty) {
      target.remove(key);
      return;
    }

    // Resolve FullStitch composite.
    if (stack.isNotEmpty) {
      final top = stack.last;
      final symbolStitch =
          (top.blendMode == LayerBlendMode.normal && top.opacity >= 0.99)
              ? top.stitch
              : stack.first.stitch;

      if (stack.length == 1) {
        final t = threadMap[stack.first.stitch.threadId];
        if (t != null) {
          target[key] = CompositeStitch(
            stitch: symbolStitch,
            blendedColor: t.color,
            resolvedThread: t,
            isBlended: false,
          );
        }
      } else {
        var blended = stack.first.color;
        for (int i = 1; i < stack.length; i++) {
          blended =
              stack[i].blendMode.apply(blended, stack[i].color, stack[i].opacity);
        }
        final r = (blended.r * 255).round();
        final g = (blended.g * 255).round();
        final b = (blended.b * 255).round();
        final dmc = SpriteImporter.matchPixel(r, g, b, 255);
        final resolvedThread = dmc == null
            ? threadMap[stack.first.stitch.threadId]
            : (threadMap[dmc.code] ??
                Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name));
        if (resolvedThread != null) {
          target[key] = CompositeStitch(
            stitch: symbolStitch,
            blendedColor: blended,
            resolvedThread: resolvedThread,
            isBlended: true,
          );
        }
      }
    } else {
      target.remove(key);
    }

    // Accumulate non-full stitches.
    for (final s in otherAtCell) {
      if (threadMap[s.threadId] case final t?) {
        otherAcc.add(CompositeStitch(
          stitch: s,
          blendedColor: t.color,
          resolvedThread: t,
          isBlended: false,
        ));
      }
    }
  }

  // ─── Core build logic ─────────────────────────────────────────────────────

  /// Single-pass composite build. O(total visible stitches).
  static CompositeLayer _buildLayer(CrossStitchPattern pattern) {
    final threadMap = pattern.threads;

    // ── Pass 1: bucket FullStitches per cell; collect everything else ────────
    final cellStack = <Cell,
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
      // Iterate primary storage directly to avoid the O(N) stitches getter.
      for (final bs in layer.backstitches) {
        backstitches.add(bs);
      }
      for (final entry in layer.stitchesByCell.entries) {
        for (final s in entry.value) {
          if (s is FullStitch) {
            final thread = threadMap[s.threadId];
            if (thread == null) continue;
            (cellStack[Cell(s.x, s.y)] ??= []).add((
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
    }

    // ── Pass 2: resolve each cell → blended colour, thread, CompositeStitch ─
    final fullStitches = <Cell, CompositeStitch>{};

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
