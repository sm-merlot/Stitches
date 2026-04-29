import 'dart:ui' show Rect;
import 'package:flutter/material.dart' show Color, HSLColor, immutable;
import '../models/cell.dart';
import '../models/page/page_layout.dart';
import '../models/progress/pattern_progress.dart';
import '../models/stitch/stitch.dart';
import '../models/stitch/stitch_geometry.dart';
import 'stitch_compositor.dart';

// ─── RenderViewConfig ─────────────────────────────────────────────────────────

/// Immutable snapshot of view-mode settings that affect how stitch blocks are
/// coloured. Passed to [RenderCache] at build/update time.
///
/// A change to any field here triggers [RenderCache.rebuildViewConfig]; stitch
/// content changes trigger [RenderCache.rebuild], [RenderCache.updateCells],
/// or [RenderCache.clearCells].
@immutable
class RenderViewConfig {
  final String? focusThreadId;
  final bool stitchMode;      // true = B&W stitch-mode palette
  final bool stitchBackMode;  // grey cross-stitches; backstitches full colour
  final bool stitchCrossMode; // cross-stitches full colour; backstitches handled elsewhere
  final Map<String, Color>? paletteOverride;
  final PatternProgress progress;
  final PageLayout? pageLayout;
  final int currentPage;

  const RenderViewConfig({
    this.focusThreadId,
    this.stitchMode = false,
    this.stitchBackMode = false,
    this.stitchCrossMode = false,
    this.paletteOverride,
    this.progress = PatternProgress.empty,
    this.pageLayout,
    this.currentPage = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderViewConfig &&
          focusThreadId == other.focusThreadId &&
          stitchMode == other.stitchMode &&
          stitchBackMode == other.stitchBackMode &&
          stitchCrossMode == other.stitchCrossMode &&
          identical(paletteOverride, other.paletteOverride) &&
          progress == other.progress &&
          pageLayout == other.pageLayout &&
          currentPage == other.currentPage;

  @override
  int get hashCode => Object.hash(focusThreadId, stitchMode, stitchBackMode,
      stitchCrossMode, paletteOverride, progress, pageLayout, currentPage);
}

// ─── RenderCache ─────────────────────────────────────────────────────────────

/// Maintains a pre-resolved `Map<Color, …Rect>` cache of stitch block rects.
///
/// ## Data structure
///
/// ```
/// _store[color][cellKey] = [rect, ...]
/// _cellColors[cellKey]   = {color, ...}   ← reverse index
/// ```
///
/// The inner map keyed by `cellKey` enables O(1) cell removal: look up the
/// cell's colours in [_cellColors], then call `Map.remove(key)` on each colour
/// bucket — no list scanning, no index bookkeeping.
///
/// ## Usage
///
/// ```dart
/// // No composite yet (empty pattern):
/// _renderCache.clear();
///
/// // Full rebuild after pattern or thread changes:
/// _renderCache.rebuild(compositeLayer, config, cellSize);
///
/// // View-config-only change (mode/focus/palette):
/// _renderCache.rebuildViewConfig(compositeLayer, config, cellSize);
///
/// // Cells erased (no stitches remain there):
/// _renderCache.clearCells({Cell(3, 7)});
///
/// // Single-cell update after one stitch is drawn:
/// _renderCache.updateCells({Cell(3, 7)}, compositeLayer, config, cellSize);
///
/// // In painter:
/// for (final colorEntry in renderCache.store.entries) {
///   final paint = Paint()..color = colorEntry.key;
///   for (final rects in colorEntry.value.values) {
///     for (final rect in rects) canvas.drawRect(rect, paint);
///   }
/// }
/// ```
class RenderCache {
  /// Nested store: colour → (cellKey → rects for this cell).
  ///
  /// Exposed for read-only use by [CanvasStaticPainter]. Do not mutate.
  final Map<Color, Map<Cell, List<Rect>>> store = {};

  /// Reverse index: cell → set of colours contributed by this cell.
  final Map<Cell, Set<Color>> _cellColors = {};

  int _version = 0;

  /// Monotonically increasing counter. Bumped on every mutating call.
  /// [CanvasStaticPainter.shouldRepaint] checks this instead of comparing
  /// full pattern objects.
  int get version => _version;

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Clears the entire cache. Use when the pattern has no visible stitches.
  void clear() {
    store.clear();
    _cellColors.clear();
    _version++;
  }

  /// Full rebuild from the current composite + view config.
  ///
  /// Call when stitch content, thread colours, or layer structure changes.
  void rebuild(
    CompositeLayer compositeLayer,
    RenderViewConfig config,
    double cellSize,
  ) {
    store.clear();
    _cellColors.clear();
    _rebuildFrom(compositeLayer, config, cellSize);
    _version++;
  }

  /// Recolour-only rebuild: stitch geometry unchanged, view config changed.
  ///
  /// Call on focus/mode/palette changes. Semantically equivalent to [rebuild]
  /// today; separated so future optimisation can skip geometry recomputation.
  void rebuildViewConfig(
    CompositeLayer compositeLayer,
    RenderViewConfig config,
    double cellSize,
  ) =>
      rebuild(compositeLayer, config, cellSize);

  /// Removes [keys] from the cache without re-inserting. Use when cells are
  /// known to be empty in the new composite (e.g. stitch erased).
  void clearCells(Set<Cell> keys) {
    for (final key in keys) {
      _removeCell(key);
    }
    _version++;
  }

  /// Incremental update for a set of changed cells.
  ///
  /// O(changed_cells) — removes old rects for each key, recomputes from the
  /// new composite, and re-inserts. Version is bumped once for the whole batch.
  void updateCells(
    Set<Cell> keys,
    CompositeLayer compositeLayer,
    RenderViewConfig config,
    double cellSize,
  ) {
    for (final key in keys) {
      _removeCell(key);
    }
    // Re-add full stitches in the dirty set — O(1) lookup per key.
    for (final key in keys) {
      final cs = compositeLayer.fullStitches[key];
      if (cs != null) _addCompositeStitch(key, cs, config, cellSize);
    }
    // Re-add other stitches (half/quarter) whose cell is in the dirty set.
    for (final cs in compositeLayer.otherStitches) {
      final coords = cs.stitch.cellCoords;
      if (coords == null) continue;
      final key = coords;
      if (!keys.contains(key)) continue;
      _addCompositeStitch(key, cs, config, cellSize);
    }
    _version++;
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  void _rebuildFrom(
    CompositeLayer compositeLayer,
    RenderViewConfig config,
    double cellSize,
  ) {
    for (final entry in compositeLayer.fullStitches.entries) {
      _addCompositeStitch(entry.key, entry.value, config, cellSize);
    }
    for (final cs in compositeLayer.otherStitches) {
      final coords = cs.stitch.cellCoords;
      if (coords == null) continue;
      final key = coords;
      _addCompositeStitch(key, cs, config, cellSize);
    }
  }

  void _addCompositeStitch(
    Cell key,
    CompositeStitch cs,
    RenderViewConfig config,
    double cellSize,
  ) {
    // Page filter.
    if (!_stitchOnPage(cs.stitch, config)) return;

    // Resolve colour: blended (multi-layer) takes precedence over palette override.
    final baseColor = cs.isBlended
        ? cs.blendedColor
        : (config.paletteOverride?[cs.stitch.threadId] ?? cs.blendedColor);

    final color = _resolveColor(
      baseColor: baseColor,
      effectiveDmcCode: cs.resolvedThread.dmcCode,
      stitch: cs.stitch,
      config: config,
    );
    if (color == null) return;

    // Compute block rect.
    final block = cs.stitch.blockCells;
    if (block == null) return;
    final (bl, bt, bw, bh) = block;
    final rect = Rect.fromLTWH(
        bl * cellSize, bt * cellSize, bw * cellSize, bh * cellSize);

    // Insert into store and update reverse index.
    (store[color] ??= {})[key] = [rect];
    (_cellColors[key] ??= {}).add(color);
  }

  void _removeCell(Cell key) {
    final colors = _cellColors.remove(key);
    if (colors == null) return;
    for (final color in colors) {
      final batch = store[color];
      if (batch == null) continue;
      batch.remove(key);
      if (batch.isEmpty) store.remove(color);
    }
  }

  // ─── Colour resolution ───────────────────────────────────────────────────

  /// Resolves the final display colour for a non-back stitch block.
  ///
  /// Returns `null` to skip drawing (e.g. back-mode cross stitches aren't
  /// completely hidden — they're greyed — so null is not used there; reserved
  /// for future filter-only modes).
  Color? _resolveColor({
    required Color baseColor,
    required String effectiveDmcCode,
    required Stitch stitch,
    required RenderViewConfig config,
  }) {
    final focusId = config.focusThreadId;
    final hasFocus = focusId != null;
    final isFocused = !hasFocus || effectiveDmcCode == focusId;

    // Focus greying: unfocused cells shown at a uniform grey.
    if (hasFocus && !isFocused) return _unfocusedGrey;

    // Back mode: all cross-stitches greyed so backstitches stand out.
    if (config.stitchBackMode) return _unfocusedGrey;

    // B&W stitch mode.
    if (config.stitchMode) {
      final xy = stitch.cellCoords;
      final isDone = xy != null && config.progress.completedStitches.contains(xy);
      if (!isDone) {
        // Undone → subtle greyscale tint, distinguishable but clearly not done.
        return _bwGreyscale(baseColor);
      }
      // Done + non-focused → muted colour so completed work doesn't overshadow focus.
      if (hasFocus && !isFocused) return _muteColor(baseColor); // unreachable (caught above)
      return baseColor;
    }

    return baseColor;
  }

  // ─── Page filter ─────────────────────────────────────────────────────────

  static bool _stitchOnPage(Stitch stitch, RenderViewConfig config) {
    final layout = config.pageLayout;
    if (layout == null || !layout.config.enabled) return true;
    final coords = stitch.cellCoords;
    if (coords == null) return false;
    final (pageCol, pageRow) = layout.pageCoords(config.currentPage);
    return layout.cellOnPage(coords.x, coords.y, pageCol, pageRow);
  }

  // ─── Colour helpers (mirrors painter originals, moved here) ──────────────

  /// Uniform grey for all unfocused/greyed stitches — avoids per-thread shade
  /// variation that caused streaks when multiple layers blended together.
  static const Color _unfocusedGrey = Color(0xA0B8B8B8);

  /// Maps a colour to a subtle greyscale used for undone stitches in B&W mode.
  /// Luminance compressed to 0.72–0.94 so different threads remain distinguishable.
  static Color _bwGreyscale(Color c) {
    final l = c.computeLuminance();
    final grey = (0.72 + l * 0.22).clamp(0.0, 1.0);
    final v = (grey * 255).round();
    return Color.fromARGB(255, v, v, v);
  }

  /// Slightly desaturates + lightens a colour for done-but-non-focused stitches
  /// so they remain identifiable without overpowering the focus highlight.
  static Color _muteColor(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.85 + 0.10).clamp(0.0, 1.0))
        .toColor();
  }
}
