import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/layer.dart';
import '../models/page_layout.dart';
import '../models/pattern.dart';
import '../models/pattern_progress.dart';
import '../models/stitch.dart';
import '../models/stitch_geometry.dart';
import '../models/thread.dart';
import '../data/symbols.dart';
import '../services/color_space.dart';
import '../services/stitch_compositor.dart';
import 'canvas_viewport.dart';

part 'canvas_painter_drawing_methods.dart';
part 'canvas_painter_overlay.dart';
// ─── Static layer ─────────────────────────────────────────────────────────────
// Background, stitches, grid, labels. Cached by RepaintBoundary.
// Only repaints when pattern data, pan/zoom, or display options change.

class CanvasStaticPainter extends CustomPainter with _DrawingMethods {
  final CrossStitchPattern pattern;
  @override final double cellSize;
  final Offset panOffset;
  @override final double scale;
  @override final Color aidaColor;
  final bool stitchMode;
  final bool colourMode;
  final bool stitchCrossMode;
  final bool stitchBackMode;
  final String? stitchFocusThreadId;
  final ui.Image? referenceImage;
  final double referenceOpacity;
  final bool referenceVisible;
  /// Composite result from StitchCompositor. When present, blended colours and
  /// symbol thread assignments are taken from this (stable, pre-computed)
  /// rather than from the painter's own independent blend map.
  final CompositeResult? compositeResult;
  /// Optional palette override for snippet editor: maps dmcCode → display Color.
  /// When set, stitch colours are replaced with the active palette's colours
  /// using positional slot mapping (palette[N][i] replaces palette[0][i]).
  final Map<String, Color>? paletteOverride;

  /// Page layout for page mode. When non-null (and config.enabled), only
  /// stitches belonging to [currentPage] are rendered.
  final PageLayout? pageLayout;

  /// The 0-based page index to display when [pageLayout] is non-null.
  final int currentPage;

  /// Progress data — used in stitch mode to dim completed stitch cells.
  final PatternProgress progress;
  late final Map<String, Thread> _threadMap = {
    for (final t in pattern.threads) t.dmcCode: t,
  };

  /// True when in B&W stitch mode (stitch mode with block mode off).
  bool get _isBWStitchMode => stitchMode && !colourMode;

  CanvasStaticPainter({
    required this.pattern,
    required this.cellSize,
    required this.panOffset,
    required this.scale,
    required this.aidaColor,
    this.stitchMode = false,
    this.colourMode = false,
    this.stitchCrossMode = false,
    this.stitchBackMode = false,
    this.stitchFocusThreadId,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.referenceVisible = true,
    this.compositeResult,
    this.paletteOverride,
    this.pageLayout,
    this.currentPage = 0,
    this.progress = PatternProgress.empty,
  });

  /// Returns [original] with the active palette's colour substituted if an
  /// override exists for [threadId].
  Color _applyPaletteOverride(String threadId, Color original) =>
      paletteOverride?[threadId] ?? original;

  /// Returns the palette thread whose colour is closest to [target] by
  /// squared RGB distance. Fast: only searches the pattern's own threads.
  Thread? _nearestThread(Color target) {
    Thread? best;
    double bestDist = double.infinity;
    for (final t in _threadMap.values) {
      final dr = t.color.r - target.r;
      final dg = t.color.g - target.g;
      final db = t.color.b - target.b;
      final dist = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        best = t;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Clip to widget bounds — prevents the translated/scaled pattern from
    // bleeding into adjacent widgets (e.g. the file-tree sidebar).
    canvas.clipRect(Offset.zero & size);

    // ── Compute visible cell range for culling ──────────────────────────────
    final viewport = CanvasViewport(
      cellSize: cellSize,
      panOffset: panOffset,
      scale: scale,
    );
    final range =
        viewport.visibleCellRange(size, pattern.width, pattern.height);
    final minCX = range.minX;
    final minCY = range.minY;
    final maxCX = range.maxX;
    final maxCY = range.maxY;

    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    final w = pattern.width  * cellSize;
    final h = pattern.height * cellSize;

    // ── Background ──────────────────────────────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = aidaColor);

    // ── Reference image overlay ─────────────────────────────────────────────
    if (referenceImage != null && referenceVisible && referenceOpacity > 0) {
      canvas.drawImageRect(
        referenceImage!,
        Rect.fromLTWH(0, 0,
            referenceImage!.width.toDouble(), referenceImage!.height.toDouble()),
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = Color.fromRGBO(255, 255, 255, referenceOpacity),
      );
    }

    // ── Zoom-level thresholds ────────────────────────────────────────────────
    // effectivePx is the on-screen size of one cell in logical pixels.
    final effectivePx = cellSize * scale;
    // Below kNoBackstitch: backstitch lines are invisible at this zoom.
    const kNoBackstitch    = 3.0;
    // Below kMajorOnly: hide minor (per-cell) grid lines, show major (×10) only.
    const kMajorOnly       = 14.0;
    // Below kNoGrid: grid lines add no information and just darken the view.
    const kNoGrid          = 6.0;

    // ── Blended-colour map from shared CompositeResult ──────────────────────
    // Only cells where multiple visible layers have a FullStitch are included.
    // Lone stitches are NOT in the map — they render at full source color.
    final blendedColors = compositeResult?.blendedColors ?? const {};

    // ── Pre-compute occlusion sets for symbol rendering ──────────────────────
    // For each layer index i, the set of cells (encoded as (x<<16)|y) covered
    // by FullStitches in any HIGHER visible layer. Cached — free during pan/zoom.
    final upperFullStitchCells = _getOcclusionSets();

    // ── Stitches — iterate layers bottom to top ──────────────────────────────
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      _drawLayerStitchesAsBlocks(canvas, layer, blendedColors, minCX, minCY, maxCX, maxCY);
    }

    // ── Grid (batched paths, culled; skipped when cells are sub-pixel) ───────
    if (effectivePx >= kNoGrid) {
      _drawGrid(canvas, minCX, minCY, maxCX, maxCY,
          majorOnly: effectivePx < kMajorOnly);
    }

    // ── Backstitches (all visible layers) ────────────────────────────────────
    if (effectivePx >= kNoBackstitch) {
      for (final layer in pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is! BackStitch) continue;
          if (!_backstichInRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
          final thread = _threadMap[stitch.threadId];
          if (thread == null) continue;
          var c = _resolveStitchColor(stitch.threadId,
              _applyPaletteOverride(stitch.threadId, thread.color),
              isCrossStitch: false);
          if (c == null) continue;
          final isDone = stitchMode && progress.isBackstitchDone(
              stitch.x1, stitch.y1, stitch.x2, stitch.y2);
          if (_isBWStitchMode && !isDone) {
            c = _bwGreyscale(c);
          } else if (isDone) {
            c = Color.lerp(c, aidaColor, 0.70)!;
          }
          // B&W stitch mode: draw an orange outline behind focused backstitches
          // so they stand out against the greyscale background.
          if (_isBWStitchMode && _isBackstitchFocused(stitch)) {
            _drawBackstitchOutline(canvas, stitch);
          }
          _drawBackstitch(canvas, stitch.x1, stitch.y1, stitch.x2, stitch.y2, c);
        }
      }
    }

    // ── Stitch symbols (all visible layers) ──────────────────────────────────
    // Shown when zoomed in enough (>= 8 px/cell) AND in B&W stitch mode.
    // Symbols from lower layers are skipped when a higher layer has a FullStitch
    // at the same cell (prevents lower-layer symbols bleeding through).
    if (effectivePx >= 8 && _isBWStitchMode) {
      for (int layerIdx = 0; layerIdx < pattern.layers.length; layerIdx++) {
        final layer = pattern.layers[layerIdx];
        if (!layer.visible) continue;
        final occluded = upperFullStitchCells[layerIdx]!;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          if (!_inCellRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
          // Skip symbol if a higher visible layer has a FullStitch at this cell
          if (stitch is FullStitch && occluded.contains((stitch.x << 16) | stitch.y)) continue;
          final sCoords = stitchXY(stitch);
          if (sCoords != null && !_stitchOnPage(sCoords.$1, sCoords.$2)) continue;

          // B&W stitch mode: skip symbols for done cells entirely.
          if (sCoords != null &&
              progress.completedStitches.contains(sCoords)) {
            continue;
          }

          // For blended cells, use the composite cache (stable symbol
          // assignments) when available; fall back to nearest-thread lookup
          // only if the cache hasn't been built yet.
          Thread? compositeThread;
          if (stitch is FullStitch) {
            final cellKey = '${stitch.x},${stitch.y}';
            compositeThread = compositeResult?.compositeThreads[cellKey];
            if (compositeThread == null) {
              final blended = blendedColors[cellKey];
              if (blended != null) compositeThread = _nearestThread(blended);
            }
          }
          final thread = compositeThread ?? _threadMap[stitch.threadId];
          if (thread == null || !symbolIsVisible(thread.symbol)) continue;

          _drawStitchSymbolBW(canvas, stitch, thread.symbol);
        }
      }
    }

    // ── Done-stitch dimming (block stitch mode only) ────────────────────────
    // In stitch+block mode (full colour), draw a semi-transparent aida overlay
    // on completed cells so done stitches appear dimmed. Skipped in B&W mode
    // where done/undone is handled by the colour itself.
    if (stitchMode && colourMode && progress.completedStitches.isNotEmpty) {
      final dimPaint = Paint()
        ..color = aidaColor.withValues(alpha: 0.70);
      for (final (cx, cy) in progress.completedStitches) {
        if (cx < minCX || cx >= maxCX || cy < minCY || cy >= maxCY) continue;
        if (!_stitchOnPage(cx, cy)) continue;
        canvas.drawRect(
          Rect.fromLTWH(cx * cellSize, cy * cellSize, cellSize, cellSize),
          dimPaint,
        );
      }
    }

    // ── Focus region outline ────────────────────────────────────────────────
    // When a thread is focused whose colour blends into the background, draw a
    // perimeter outline around all connected groups of focused cells so the
    // user can locate them in the grey fog of unfocused stitches.
    // In B&W mode any active focus (thread, cross, or back) triggers this.
    if (stitchFocusThreadId != null || (_isBWStitchMode && (stitchBackMode || stitchCrossMode))) {
      _drawFocusedRegionBorderIfNeeded(canvas, blendedColors);
    }

    // ── Pattern border ──────────────────────────────────────────────────────
    final borderBase = aidaColor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = borderBase.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale,
    );

    canvas.restore();

    // ── Grid labels (screen-space, drawn after restore) ─────────────────────
    _drawGridLabels(canvas, size);
  }

  // ── Grid with path batching + culling ──────────────────────────────────────

  void _drawGrid(Canvas canvas, int minX, int minY, int maxX, int maxY,
      {bool majorOnly = false}) {
    // Use solid opaque grays so lines are visible on both light and dark backgrounds.
    final isDark = aidaColor.computeLuminance() <= 0.4;
    final minorColor = isDark ? const Color(0xFF666666) : const Color(0xFFCCCCCC);
    final majorColor = isDark ? const Color(0xFF888888) : const Color(0xFF999999);
    // Smooth alpha fade near visibility thresholds so grid doesn't pop in/out.
    final effectivePx = cellSize * scale;
    final minorAlpha = majorOnly ? 0.0 : (effectivePx - 14.0).clamp(0.0, 4.0) / 4.0;
    final majorAlpha = (effectivePx - 6.0).clamp(0.0, 4.0) / 4.0;
    // Scale-invariant stroke widths: always ~1px / ~1.5px on screen.
    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = minorColor.withValues(alpha: minorAlpha)
      ..strokeWidth = 1.0 / scale;
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = majorColor.withValues(alpha: majorAlpha)
      ..strokeWidth = 1.5 / scale;

    final minorPath = majorOnly ? null : Path();
    final majorPath = Path();

    final top    = minY * cellSize;
    final bottom = maxY * cellSize;
    final left   = minX * cellSize;
    final right  = maxX * cellSize;

    for (int x = minX; x <= maxX; x++) {
      final px = x * cellSize;
      if (x % 10 == 0) {
        majorPath.moveTo(px, top);
        majorPath.lineTo(px, bottom);
      } else {
        minorPath?.moveTo(px, top);
        minorPath?.lineTo(px, bottom);
      }
    }
    for (int y = minY; y <= maxY; y++) {
      final py = y * cellSize;
      if (y % 10 == 0) {
        majorPath.moveTo(left, py);
        majorPath.lineTo(right, py);
      } else {
        minorPath?.moveTo(left, py);
        minorPath?.lineTo(right, py);
      }
    }

    if (minorPath != null) canvas.drawPath(minorPath, minorPaint);
    canvas.drawPath(majorPath, majorPaint);
  }

  // ── Static cache for the per-layer-index occlusion sets ──────────────────
  // Maps layer index → set of cell keys (encoded as (x<<16)|y) covered by a
  // FullStitch in any HIGHER visible layer. Rebuilt when pattern identity
  // changes; otherwise reused across every pan/zoom frame.
  static Map<int, Set<int>>? _occlusionCache;
  static CrossStitchPattern? _occlusionPatternRef;

  // ── Static cache for block-mode Color→Rects per layer ────────────────────
  // Rects are in canvas/pattern space and depend only on stitch content and
  // display mode, NOT on pan or zoom. Rebuilt only when pattern or mode changes.
  static CrossStitchPattern? _blockCachePattern;
  static String? _blockCacheFocusId;
  static bool _blockCacheStitchMode = false;
  static bool _blockCacheBackMode = false;
  static bool _blockCacheCrossMode = false;
  static Map<String, Color>? _blockCachePaletteOverride;
  static int _blockCacheProgressLen = -1;
  // Key is the Layer object itself (identity-compared via map lookup).
  static final Map<Layer, Map<Color, List<Rect>>> _blockRectsByLayer = {};

  // ── Occlusion sets: per-layer-index set of cells covered by higher layers ──
  // Keyed by (x<<16)|y integer to avoid string allocations in the hot path.
  // Cache is invalidated by pattern identity check below.
  Map<int, Set<int>> _getOcclusionSets() {
    if (_occlusionCache != null && identical(_occlusionPatternRef, pattern)) {
      return _occlusionCache!;
    }
    _occlusionPatternRef = pattern;
    final result = <int, Set<int>>{};
    for (int i = 0; i < pattern.layers.length; i++) {
      final covered = <int>{};
      for (int j = i + 1; j < pattern.layers.length; j++) {
        if (!pattern.layers[j].visible) continue;
        for (final s in pattern.layers[j].stitches) {
          if (s is FullStitch) covered.add((s.x << 16) | s.y);
        }
      }
      result[i] = covered;
    }
    _occlusionCache = result;
    return result;
  }

  // ── Focus region outline ────────────────────────────────────────────────────

  // The opaque base of the unfocused-stitch grey used to detect low-contrast
  // threads that would blend into the grey fog of dimmed stitches.
  static const Color _unfocusedGreyOpaque = Color(0xFFB8B8B8);

  /// Draws a perimeter outline around all connected groups of focused cells when
  /// the focused thread colour is too close to either the aida background or the
  /// unfocused-grey colour — either condition means even one cell is hard to
  /// spot, so ALL focused cells are outlined.
  ///
  /// Only draws edges that border a non-focused (or empty) cell, so adjacent
  /// focused cells share a single outline rather than having separate borders.
  void _drawFocusedRegionBorderIfNeeded(
      Canvas canvas, Map<String, Color> blendMap) {
    final focusId = stitchFocusThreadId;

    // Colour mode: only outline when focused colour is perceptually close
    // to aida or the unfocused-grey.
    // B&W stitch mode: always outline — greyscale can't distinguish threads.
    if (!_isBWStitchMode) {
      if (focusId == null) return;
      final focusThread = _threadMap[focusId];
      if (focusThread == null) return;
      final needsOutline =
          _labDeltaE(focusThread.color, aidaColor) < 15 ||
          _labDeltaE(focusThread.color, _unfocusedGreyOpaque) < 45;
      if (!needsOutline) return;
    }

    // Collect every focused cross-stitch cell encoded as (x<<16)|y for O(1)
    // neighbour lookup without string allocations in this hot path.
    // A cell is "focused" if _resolveStitchColor would return its original
    // colour (not grey/null): thread focus, cross mode, and back mode all
    // factor in.
    final focusedKeys = <int>{};
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        // Back mode greys out cross-stitches — they're not focused.
        if (stitchBackMode) continue;
        final (cx, cy) = switch (stitch) {
          FullStitch(:final x, :final y) => (x, y),
          HalfStitch(:final x, :final y) => (x, y),
          QuarterStitch(:final x, :final y) => (x, y),
          HalfCrossStitch(:final x, :final y) => (x, y),
          QuarterCrossStitch(:final x, :final y) => (x, y),
          BackStitch() => (-1, -1),
        };
        if (cx < 0) continue;
        final intKey = (cx << 16) | cy;

        if (focusId != null) {
          // Thread focus active: only cells matching the focused thread.
          final strKey = '$cx,$cy';
          if (blendMap.containsKey(strKey)) {
            if (compositeResult?.compositeThreads[strKey]?.dmcCode == focusId) focusedKeys.add(intKey);
          } else if (stitch.threadId == focusId) {
            focusedKeys.add(intKey);
          }
        } else {
          // No thread focus but cross mode: all cross-stitch cells are focused.
          focusedKeys.add(intKey);
        }
      }
    }

    if (focusedKeys.isEmpty) return;

    // Build a path of all cell edges that border a non-focused cell.
    // Drawing only outer edges makes adjacent cells share a single line.
    final path = Path();
    for (final key in focusedKeys) {
      final cx = key >> 16;
      final cy = key & 0xFFFF;
      final l = cx * cellSize;
      final t = cy * cellSize;
      final r = l + cellSize;
      final b = t + cellSize;

      // Left edge
      if (!focusedKeys.contains(((cx - 1) << 16) | cy)) {
        path.moveTo(l, t);
        path.lineTo(l, b);
      }
      // Right edge
      if (!focusedKeys.contains(((cx + 1) << 16) | cy)) {
        path.moveTo(r, t);
        path.lineTo(r, b);
      }
      // Top edge
      if (!focusedKeys.contains((cx << 16) | (cy - 1))) {
        path.moveTo(l, t);
        path.lineTo(r, t);
      }
      // Bottom edge
      if (!focusedKeys.contains((cx << 16) | (cy + 1))) {
        path.moveTo(l, b);
        path.lineTo(r, b);
      }
    }

    // Bright orange — stands out against both grey unfocused stitches and
    // most aida colours regardless of the focused thread's colour.
    const outlineColor = Color(0xFFFF6B00);
    canvas.drawPath(
      path,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 / scale
        ..strokeCap = StrokeCap.square,
    );
  }

  /// Whether a backstitch is considered "focused" for B&W outline purposes.
  bool _isBackstitchFocused(BackStitch stitch) {
    if (stitchBackMode) return true;
    return stitchFocusThreadId != null && stitch.threadId == stitchFocusThreadId;
  }

  static final _bwOutlinePaint = Paint()
    ..color = const Color(0xFFFF6B00)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Draws a bright orange outline behind a backstitch for B&W focus visibility.
  void _drawBackstitchOutline(Canvas canvas, BackStitch stitch) {
    final from = Offset(stitch.x1 * cellSize, stitch.y1 * cellSize);
    final to = Offset(stitch.x2 * cellSize, stitch.y2 * cellSize);
    final width = math.max(1.5, cellSize * 0.15);
    _bwOutlinePaint.strokeWidth = width * 2.2;
    canvas.drawLine(from, to, _bwOutlinePaint);
  }

  // ── Block-mode stitch rendering ────────────────────────────────────────────
  // Renders each occupied cell as a solid colour rect — used when zoomed out
  // far enough that stitch shapes are sub-pixel and too small to be meaningful.
  // Cells with multiple stitch layers use the topmost stitch's colour.

  // Returns (and caches) the Color→List<Rect> batch for [layer] in block mode.
  // Rects are in canvas/pattern space and are independent of pan/zoom, so they
  // can be reused across frames as long as the pattern and display modes are
  // unchanged.
  Map<Color, List<Rect>> _getOrBuildBlockRects(
      Layer layer, Map<String, Color> blendMap) {
    // Invalidate if pattern or any display-mode flag that affects colours changed.
    // In B&W stitch mode, progress changes affect block colours so we include
    // the completed-stitch count as a cheap invalidation proxy.
    final progressLen = (stitchMode && !colourMode)
        ? progress.completedStitches.length
        : -1;
    final modeChanged = !identical(_blockCachePattern, pattern) ||
        _blockCacheFocusId != stitchFocusThreadId ||
        _blockCacheStitchMode != stitchMode ||
        _blockCacheBackMode != stitchBackMode ||
        _blockCacheCrossMode != stitchCrossMode ||
        !identical(_blockCachePaletteOverride, paletteOverride) ||
        _blockCacheProgressLen != progressLen;
    if (modeChanged) {
      _blockRectsByLayer.clear();
      _blockCachePattern = pattern;
      _blockCacheFocusId = stitchFocusThreadId;
      _blockCacheStitchMode = stitchMode;
      _blockCacheBackMode = stitchBackMode;
      _blockCacheCrossMode = stitchCrossMode;
      _blockCachePaletteOverride = paletteOverride;
      _blockCacheProgressLen = progressLen;
    }

    final cached = _blockRectsByLayer[layer];
    if (cached != null) return cached;

    // Build rects for the entire layer (no viewport culling here — the caller
    // still culls so only visible rects reach canvas.drawRect).
    final byColor = <Color, List<Rect>>{};

    for (final stitch in layer.stitches) {
      if (stitch is BackStitch) continue;
      final thread = _threadMap[stitch.threadId];
      if (thread == null) continue;
      final c = _resolveStitchColor(stitch.threadId,
          _applyPaletteOverride(stitch.threadId, thread.color),
          isCrossStitch: true);
      if (c == null) continue;

      final rect = _stitchToBlockRect(stitch, cellSize);
      if (rect == null) continue;

      Color effectiveColor = c;
      if (stitch is FullStitch) {
        final key = '${stitch.x},${stitch.y}';
        final blended = blendMap[key];
        if (blended != null && stitchFocusThreadId != null) {
          final compositeThread = compositeResult?.compositeThreads[key];
          final isFocused = compositeThread?.dmcCode == stitchFocusThreadId;
          effectiveColor = isFocused ? blended : _greyColor(blended);
        } else {
          effectiveColor = blended ?? c;
        }
      }

      // B&W stitch mode: undone → subtle greyscale, done → full colour.
      if (stitchMode && !colourMode) {
        final xy = stitchXY(stitch);
        final isDone = xy != null && progress.completedStitches.contains(xy);
        if (!isDone) effectiveColor = _bwGreyscale(effectiveColor);
      }

      (byColor[effectiveColor] ??= []).add(rect);
    }

    _blockRectsByLayer[layer] = byColor;
    return byColor;
  }

  void _drawLayerStitchesAsBlocks(Canvas canvas, Layer layer,
      Map<String, Color> blendMap,
      int minX, int minY, int maxX, int maxY) {

    // When page mode is active, skip the block cache and filter per-stitch.
    final layout = pageLayout;
    if (layout != null && layout.config.enabled) {
      _drawLayerBlocksWithPageFilter(canvas, layer, blendMap, minX, minY, maxX, maxY);
      return;
    }

    final byColor = _getOrBuildBlockRects(layer, blendMap);

    // Viewport bounds in canvas/pattern space for culling.
    final minPx = minX * cellSize;
    final minPy = minY * cellSize;
    final maxPx = maxX * cellSize;
    final maxPy = maxY * cellSize;

    // Batch rects by colour to minimise Paint object churn.
    for (final entry in byColor.entries) {
      final paint = Paint()..color = entry.key;
      for (final rect in entry.value) {
        if (rect.right <= minPx || rect.left >= maxPx ||
            rect.bottom <= minPy || rect.top >= maxPy) { continue; }
        canvas.drawRect(rect, paint);
      }
    }
  }

  /// Block rendering with per-stitch page membership filtering.
  /// Used in place of the cached block rects when page mode is active.
  void _drawLayerBlocksWithPageFilter(Canvas canvas, Layer layer,
      Map<String, Color> blendMap,
      int minX, int minY, int maxX, int maxY) {
    final minPx = minX * cellSize;
    final minPy = minY * cellSize;
    final maxPx = maxX * cellSize;
    final maxPy = maxY * cellSize;

    for (final stitch in layer.stitches) {
      if (stitch is BackStitch) continue;
      if (!_inCellRange(stitch, minX, minY, maxX, maxY)) continue;
      final xy = stitchXY(stitch);
      if (xy == null || !_stitchOnPage(xy.$1, xy.$2)) continue;

      final thread = _threadMap[stitch.threadId];
      if (thread == null) continue;
      final c = _resolveStitchColor(stitch.threadId,
          _applyPaletteOverride(stitch.threadId, thread.color),
          isCrossStitch: true);
      if (c == null) continue;

      final rect = _stitchToBlockRect(stitch, cellSize);
      if (rect == null) continue;

      Color effectiveColor = c;
      if (stitch is FullStitch) {
        final key = '${stitch.x},${stitch.y}';
        final blended = blendMap[key];
        if (blended != null && stitchFocusThreadId != null) {
          final compositeThread = compositeResult?.compositeThreads[key];
          final isFocused = compositeThread?.dmcCode == stitchFocusThreadId;
          effectiveColor = isFocused ? blended : _greyColor(blended);
        } else {
          effectiveColor = blended ?? c;
        }
      }

      // B&W stitch mode: undone → subtle greyscale, done → full colour.
      if (stitchMode && !colourMode) {
        final isDone = progress.completedStitches.contains(xy);
        if (!isDone) effectiveColor = _bwGreyscale(effectiveColor);
      }

      if (rect.right <= minPx || rect.left >= maxPx ||
          rect.bottom <= minPy || rect.top >= maxPy) { continue; }
      canvas.drawRect(rect, Paint()..color = effectiveColor);
    }
  }

  /// Returns the block-mode rect for [stitch] in canvas/pattern space, or null
  /// if the stitch type has no block representation (e.g. [BackStitch]).
  ///
  /// Block mode renders each stitch as a solid colour rect — used at far-zoom
  /// where stitch shapes are sub-pixel.  Each fractional-stitch type fills its
  /// corresponding region of the cell (a quarter stitch fills its quadrant, a
  /// half stitch fills its half), so the four quadrants of a cell tile cleanly.
  static Rect? _stitchToBlockRect(Stitch stitch, double cellSize) {
    final halfCell = cellSize * 0.5;
    switch (stitch) {
      case FullStitch(:final x, :final y):
        return Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);

      case HalfStitch(:final x, :final y, isForward: true):
        return Rect.fromLTWH(x * cellSize + halfCell, y * cellSize, halfCell, cellSize);
      case HalfStitch(:final x, :final y, isForward: false):
        return Rect.fromLTWH(x * cellSize, y * cellSize, halfCell, cellSize);

      case HalfCrossStitch(:final x, :final y, half: HalfOrientation.left):
        return Rect.fromLTWH(x * cellSize, y * cellSize, halfCell, cellSize);
      case HalfCrossStitch(:final x, :final y, half: HalfOrientation.right):
        return Rect.fromLTWH(x * cellSize + halfCell, y * cellSize, halfCell, cellSize);
      case HalfCrossStitch(:final x, :final y, half: HalfOrientation.top):
        return Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, halfCell);
      case HalfCrossStitch(:final x, :final y, half: HalfOrientation.bottom):
        return Rect.fromLTWH(x * cellSize, y * cellSize + halfCell, cellSize, halfCell);

      case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.topLeft):
      case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.topLeft):
        return Rect.fromLTWH(x * cellSize, y * cellSize, halfCell, halfCell);
      case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.topRight):
      case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.topRight):
        return Rect.fromLTWH(x * cellSize + halfCell, y * cellSize, halfCell, halfCell);
      case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.bottomLeft):
      case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.bottomLeft):
        return Rect.fromLTWH(x * cellSize, y * cellSize + halfCell, halfCell, halfCell);
      case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.bottomRight):
      case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.bottomRight):
        return Rect.fromLTWH(x * cellSize + halfCell, y * cellSize + halfCell, halfCell, halfCell);

      case BackStitch():
        return null;
    }
  }

  // ── Viewport culling helpers ───────────────────────────────────────────────

  bool _inCellRange(Stitch stitch, int minX, int minY, int maxX, int maxY) {
    final (x, y) = switch (stitch) {
      FullStitch(:final x, :final y) => (x, y),
      HalfStitch(:final x, :final y) => (x, y),
      QuarterStitch(:final x, :final y) => (x, y),
      HalfCrossStitch(:final x, :final y) => (x, y),
      QuarterCrossStitch(:final x, :final y) => (x, y),
      BackStitch() => (-1, -1),
    };
    return x >= minX && x < maxX && y >= minY && y < maxY;
  }

  bool _backstichInRange(
      BackStitch s, int minX, int minY, int maxX, int maxY) {
    final bMinX = math.min(s.x1, s.x2);
    final bMaxX = math.max(s.x1, s.x2);
    final bMinY = math.min(s.y1, s.y2);
    final bMaxY = math.max(s.y1, s.y2);
    return bMaxX > minX && bMinX < maxX && bMaxY > minY && bMinY < maxY;
  }

  // ── Grid labels ────────────────────────────────────────────────────────────

  int _labelStep(double effectiveCellPx) {
    const minSpacing = 35.0;
    // When only the major (×10) grid is visible, snap labels to multiples of 10
    // so they land on grid lines rather than between them.
    final candidates =
        effectiveCellPx >= 8.0 ? [5, 10, 20, 50, 100] : [10, 20, 50, 100];
    for (final s in candidates) {
      if (s * effectiveCellPx >= minSpacing) return s;
    }
    return 100;
  }

  void _drawGridLabels(Canvas canvas, Size size) {
    final effectiveCellPx = cellSize * scale;
    // No labels when grid is hidden entirely.
    if (effectiveCellPx < 3.5) return;
    final step = _labelStep(effectiveCellPx);
    const fontSize = 10.0;
    const textColor = Color(0xFF666666);
    final bgColor = Colors.white.withValues(alpha: 0.82);
    const halfH = (fontSize + 4) / 2;
    const halfW = 14.0;

    final colLabelY =
        (panOffset.dy - halfH - 3).clamp(halfH + 2, size.height - halfH - 2);
    final rowLabelX =
        (panOffset.dx - halfW - 4).clamp(halfW + 2, size.width - halfW - 2);

    for (int x = step; x <= pattern.width; x += step) {
      final screenX = x * effectiveCellPx + panOffset.dx;
      if (screenX < 0 || screenX > size.width) continue;
      _drawNumberLabel(canvas, '$x', Offset(screenX, colLabelY), fontSize, textColor, bgColor);
    }
    for (int y = step; y <= pattern.height; y += step) {
      final screenY = y * effectiveCellPx + panOffset.dy;
      if (screenY < 0 || screenY > size.height) continue;
      _drawNumberLabel(canvas, '$y', Offset(rowLabelX, screenY), fontSize, textColor, bgColor);
    }
  }

  void _drawNumberLabel(Canvas canvas, String text, Offset center,
      double fontSize, Color textColor, Color bgColor) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: fontSize,
            color: textColor,
            fontWeight: FontWeight.w500,
            height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromCenter(
        center: center, width: tp.width + 6, height: tp.height + 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        Paint()..color = bgColor);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  // ── Stitch symbols ─────────────────────────────────────────────────────────

  /// B&W stitch mode: black text on the greyscale block background, no background box.
  void _drawStitchSymbolBW(Canvas canvas, Stitch stitch, String symbol) {
    final center = _symbolCenter(stitch);
    final fontSize = math.max(4.0, cellSize * 0.46);
    final tp = TextPainter(
      text: TextSpan(
          text: symbol,
          style: TextStyle(
              fontSize: fontSize,
              color: const Color(0xFF000000),
              fontWeight: FontWeight.bold,
              height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  Offset _symbolCenter(Stitch stitch) {
    return switch (stitch) {
      FullStitch(:final x, :final y) =>
        Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize),
      HalfStitch(:final x, :final y) =>
        Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize),
      QuarterStitch(:final x, :final y, :final quadrant) =>
        _quadrantCenter(x, y, quadrant),
      HalfCrossStitch(:final x, :final y, :final half) =>
        _halfOrientCenter(x, y, half),
      QuarterCrossStitch(:final x, :final y, :final quadrant) =>
        _quadrantCenter(x, y, quadrant),
      BackStitch() => Offset.zero,
    };
  }

  Offset _quadrantCenter(int x, int y, QuadrantPosition q) {
    final l = x * cellSize;
    final t = y * cellSize;
    final q4 = cellSize / 4;
    return switch (q) {
      QuadrantPosition.topLeft     => Offset(l + q4,     t + q4),
      QuadrantPosition.topRight    => Offset(l + 3 * q4, t + q4),
      QuadrantPosition.bottomLeft  => Offset(l + q4,     t + 3 * q4),
      QuadrantPosition.bottomRight => Offset(l + 3 * q4, t + 3 * q4),
    };
  }

  Offset _halfOrientCenter(int x, int y, HalfOrientation h) {
    final l = x * cellSize;
    final t = y * cellSize;
    final q4 = cellSize / 4;
    final half = cellSize / 2;
    return switch (h) {
      HalfOrientation.left   => Offset(l + q4,     t + half),
      HalfOrientation.right  => Offset(l + 3 * q4, t + half),
      HalfOrientation.top    => Offset(l + half,   t + q4),
      HalfOrientation.bottom => Offset(l + half,   t + 3 * q4),
    };
  }

  // ── Stitch mode colour resolution ──────────────────────────────────────────

  Color? _resolveStitchColor(String threadId, Color original,
      {required bool isCrossStitch}) {
    final hasFocus = stitchFocusThreadId != null;
    final isFocused = !hasFocus || stitchFocusThreadId == threadId;

    // Focus greying applies in all modes (view, stitch, edit).
    if (hasFocus && !isFocused) return _greyColor(original);

    // Back/cross mode applies in stitch and view mode (state is always false in edit mode).
    if (stitchBackMode && isCrossStitch) return _greyColor(original);
    if (stitchCrossMode && !isCrossStitch) return null;

    return original;
  }

  // A single uniform grey used for all unfocused stitches so that different
  // thread colours don't produce different grey shades (which caused streaks
  // when multiple layers each contributed their own luminance-based grey).
  static const Color _unfocusedGrey = Color(0xA0B8B8B8);
  static Color _greyColor(Color c) => _unfocusedGrey;

  /// Subtle greyscale for B&W stitch mode: maps each colour to a very light
  /// grey so that different thread colours remain distinguishable.
  /// Luminance is compressed into the 0.82–0.96 range.
  static Color _bwGreyscale(Color c) {
    final l = c.computeLuminance(); // 0.0 (dark) – 1.0 (light)
    final grey = (0.72 + l * 0.22).clamp(0.0, 1.0);
    final v = (grey * 255).round();
    return Color.fromARGB(255, v, v, v);
  }

  // ── Page mode helpers ──────────────────────────────────────────────────────

  /// Returns true if stitch at (x=col, y=row) should be drawn on the current page.
  bool _stitchOnPage(int col, int row) {
    final layout = pageLayout;
    if (layout == null || !layout.config.enabled) return true;
    final (pageCol, pageRow) = layout.pageCoords(currentPage);
    return layout.cellOnPage(col, row, pageCol, pageRow);
  }

  @override
  bool shouldRepaint(CanvasStaticPainter old) =>
      old.pattern != pattern ||
      old.cellSize != cellSize ||
      old.panOffset != panOffset ||
      old.scale != scale ||
      old.aidaColor != aidaColor ||
      old.stitchMode != stitchMode ||
      old.colourMode != colourMode ||
      old.stitchCrossMode != stitchCrossMode ||
      old.stitchBackMode != stitchBackMode ||
      old.stitchFocusThreadId != stitchFocusThreadId ||
      old.referenceImage != referenceImage ||
      old.referenceOpacity != referenceOpacity ||
      old.referenceVisible != referenceVisible ||
      old.compositeResult != compositeResult ||
      old.paletteOverride != paletteOverride ||
      old.pageLayout != pageLayout ||
      old.currentPage != currentPage ||
      old.progress != progress;
}

