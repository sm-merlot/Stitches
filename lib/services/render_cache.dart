import 'dart:ui' show Path, Rect;
import 'package:flutter/material.dart' show Color, HSLColor, immutable;
import '../models/cell.dart';
import '../models/page/page_layout.dart';
import '../models/progress/pattern_progress.dart';
import '../models/stitch/stitch.dart';
import '../models/stitch/stitch_geometry.dart';
import 'block_shape.dart';
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

/// Maintains a pre-resolved `Map<Color, …BlockShape>` cache of stitch blocks.
///
/// Each stitch type produces a [BlockShape]: [RectShape] for axis-aligned
/// blocks (full/half-cross/quarter), [PathShape] for diagonal bands (half
/// stitch) and triangles (three-quarter stitch). The painter iterates the
/// store and calls `shape.draw(canvas, paint)` — polymorphic dispatch selects
/// `drawRect` or `drawPath` as appropriate.
///
/// ## Data structure
///
/// ```
/// store[color][cellKey]    = BlockShape
/// _cellColors[cellKey]     = {color, ...}   ← reverse index
/// ```
///
/// The inner map keyed by `cellKey` enables O(1) cell removal: look up the
/// cell's colours in [_cellColors], then call `Map.remove(key)` on each colour
/// bucket — no list scanning, no index bookkeeping.
class RenderCache {
  /// Nested store: colour → (cellKey → block shape for this cell).
  ///
  /// Exposed for read-only use by [CanvasStaticPainter]. Do not mutate.
  final Map<Color, Map<Cell, BlockShape>> store = {};

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
  /// O(changed_cells) — removes old paths for each key, recomputes from the
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

    // Build the block shape for this stitch.
    final shape = _buildBlockShape(cs.stitch, cellSize);
    if (shape == null) return;

    // Insert into store and update reverse index.
    (store[color] ??= {})[key] = shape;
    (_cellColors[key] ??= {}).add(color);
  }

  /// Builds the block-mode [BlockShape] for a stitch.
  ///
  /// - [FullStitch], [HalfCrossStitch], [QuarterStitch] → [RectShape]
  /// - [HalfStitch] → [PathShape] (thick diagonal parallelogram)
  /// - [ThreeQuarterStitch] → [PathShape] (filled triangle)
  /// - [BackStitch] → null (drawn separately by the painter)
  static BlockShape? _buildBlockShape(Stitch stitch, double cellSize) {
    return switch (stitch) {
      HalfStitch(:final x, :final y, :final isForward) =>
        PathShape(_halfStitchPath(x, y, isForward, cellSize)),
      ThreeQuarterStitch(:final x, :final y, :final quadrant) =>
        PathShape(_threeQuarterPath(x, y, quadrant, cellSize)),
      BackStitch() => null,
      _ => _rectShape(stitch, cellSize),
    };
  }

  /// [RectShape] for stitches that use standard axis-aligned block geometry.
  static RectShape? _rectShape(Stitch stitch, double cellSize) {
    final block = stitch.blockCells;
    if (block == null) return null;
    final (bl, bt, bw, bh) = block;
    return RectShape(Rect.fromLTWH(
        bl * cellSize, bt * cellSize, bw * cellSize, bh * cellSize));
  }

  /// Thick diagonal band (parallelogram) for a [HalfStitch].
  /// Stays within cell bounds. Thickness ≈ 44% of cell size.
  static Path _halfStitchPath(int x, int y, bool isForward, double cellSize) {
    final left = x * cellSize;
    final top = y * cellSize;
    final cs = cellSize;
    final t = cs * 0.22; // half-thickness of the band

    if (isForward) {
      // / diagonal: top-right → bottom-left
      return Path()
        ..moveTo(left + cs - t, top)
        ..lineTo(left + cs, top)
        ..lineTo(left + cs, top + t)
        ..lineTo(left + t, top + cs)
        ..lineTo(left, top + cs)
        ..lineTo(left, top + cs - t)
        ..close();
    } else {
      // \ diagonal: top-left → bottom-right
      return Path()
        ..moveTo(left, top)
        ..lineTo(left + t, top)
        ..lineTo(left + cs, top + cs - t)
        ..lineTo(left + cs, top + cs)
        ..lineTo(left + cs - t, top + cs)
        ..lineTo(left, top + t)
        ..close();
    }
  }

  /// Half-cell filled triangle for a [ThreeQuarterStitch].
  /// The triangle occupies the half of the cell that contains the quadrant corner.
  static Path _threeQuarterPath(
      int x, int y, QuadrantPosition quadrant, double cellSize) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;

    return switch (quadrant) {
      QuadrantPosition.topLeft => (Path()
        ..moveTo(left, top)
        ..lineTo(right, top)
        ..lineTo(left, bottom)
        ..close()),
      QuadrantPosition.topRight => (Path()
        ..moveTo(left, top)
        ..lineTo(right, top)
        ..lineTo(right, bottom)
        ..close()),
      QuadrantPosition.bottomLeft => (Path()
        ..moveTo(left, top)
        ..lineTo(left, bottom)
        ..lineTo(right, bottom)
        ..close()),
      QuadrantPosition.bottomRight => (Path()
        ..moveTo(right, top)
        ..lineTo(left, bottom)
        ..lineTo(right, bottom)
        ..close()),
    };
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

    // Back mode: all cross-stitches greyed so backstitches stand out.
    if (config.stitchBackMode) return _unfocusedGrey;

    // B&W stitch mode.
    if (config.stitchMode) {
      final xy = stitch.cellCoords;
      final isDone = xy != null && config.progress.completedStitches.contains(xy);

      if (hasFocus && !isFocused) {
        // Unfocused + done → pale version of actual colour (still recognisable).
        if (isDone) return _paleColor(baseColor);
        // Unfocused + undone → pale greyscale (symbol still drawn by painter).
        return _paleGreyscale(baseColor);
      }

      if (!isDone) {
        // Focused/no-focus undone → subtle greyscale tint.
        return _bwGreyscale(baseColor);
      }
      return baseColor;
    }

    // Focus greying (design mode): unfocused cells shown at a uniform grey.
    if (hasFocus && !isFocused) return _unfocusedGrey;

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

  /// Pale version of the actual colour — used for unfocused done stitches.
  /// Keeps hue, desaturates heavily, and pushes lightness toward white.
  static Color _paleColor(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 0.3).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.5 + 0.45).clamp(0.0, 0.95))
        .toColor();
  }

  /// Pale greyscale — used for unfocused undone stitches.
  /// Same greyscale mapping as [_bwGreyscale] but with alpha for translucency.
  static Color _paleGreyscale(Color c) {
    final l = c.computeLuminance();
    final grey = (0.72 + l * 0.22).clamp(0.0, 1.0);
    final v = (grey * 255).round();
    return Color.fromARGB(128, v, v, v);
  }
}
