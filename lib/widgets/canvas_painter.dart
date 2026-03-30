import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../services/sprite_importer.dart';

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
  final bool blockMode;
  final bool stitchCrossMode;
  final bool stitchBackMode;
  final String? stitchFocusThreadId;
  final ui.Image? referenceImage;
  final double referenceOpacity;
  final bool referenceVisible;
  /// Composite thread cache keyed by 'x,y' cell key. When present, the symbol
  /// and colour for blended cells are taken from this map (stable assignments)
  /// rather than from nearest-thread heuristics.
  final Map<String, Thread>? compositeThreadCache;
  /// Optional palette override for snippet editor: maps dmcCode → display Color.
  /// When set, stitch colours are replaced with the active palette's colours
  /// using positional slot mapping (palette[N][i] replaces palette[0][i]).
  final Map<String, Color>? paletteOverride;
  late final Map<String, Thread> _threadMap = {
    for (final t in pattern.threads) t.dmcCode: t,
  };

  CanvasStaticPainter({
    required this.pattern,
    required this.cellSize,
    required this.panOffset,
    required this.scale,
    required this.aidaColor,
    this.stitchMode = false,
    this.blockMode = false,
    this.stitchCrossMode = false,
    this.stitchBackMode = false,
    this.stitchFocusThreadId,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.referenceVisible = true,
    this.compositeThreadCache,
    this.paletteOverride,
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
    final visLeft   = -panOffset.dx / scale;
    final visTop    = -panOffset.dy / scale;
    final visRight  = (size.width  - panOffset.dx) / scale;
    final visBottom = (size.height - panOffset.dy) / scale;

    // Add 1-cell buffer to avoid visible seams at edges.
    final minCX = ((visLeft  / cellSize).floor() - 1).clamp(0, pattern.width);
    final minCY = ((visTop   / cellSize).floor() - 1).clamp(0, pattern.height);
    final maxCX = ((visRight / cellSize).ceil()  + 1).clamp(0, pattern.width);
    final maxCY = ((visBottom/ cellSize).ceil()  + 1).clamp(0, pattern.height);

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
    // Below kBlockThreshold: stitch shapes are sub-pixel noise — draw solid
    // colour blocks instead (1 drawRect vs 4–6 drawLine calls per stitch).
    const kBlockThreshold  = 6.0;
    // Below kNoBackstitch: backstitch lines are invisible at this zoom.
    const kNoBackstitch    = 3.0;
    // Below kMajorOnly: hide minor (per-cell) grid lines, show major (×10) only.
    const kMajorOnly       = 8.0;
    // Below kNoGrid: grid lines add no information and just darken the view.
    // 3.5 = the point where labels would thin to every-20 — hide everything instead.
    const kNoGrid          = 3.5;

    // ── Pre-compute blend map for overlapping FullStitches ──────────────────
    // Only cells where multiple visible layers have a FullStitch are included.
    // Lone stitches are NOT in the map — they render at full source color.
    final blendMap = _buildBlendMap();

    // ── Pre-compute occlusion sets for symbol rendering (Bug 2) ─────────────
    // For each layer index i, the set of cell keys covered by FullStitches in
    // any HIGHER visible layer (j > i). Symbols at those cells are skipped.
    final upperFullStitchCells = <int, Set<String>>{};
    for (int i = 0; i < pattern.layers.length; i++) {
      final covered = <String>{};
      for (int j = i + 1; j < pattern.layers.length; j++) {
        if (!pattern.layers[j].visible) continue;
        for (final s in pattern.layers[j].stitches) {
          if (s is FullStitch) covered.add('${s.x},${s.y}');
        }
      }
      upperFullStitchCells[i] = covered;
    }

    // ── Stitches — iterate layers bottom to top ──────────────────────────────
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      if (blockMode || effectivePx < kBlockThreshold) {
        _drawLayerStitchesAsBlocks(canvas, layer, blendMap, minCX, minCY, maxCX, maxCY);
      } else {
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          if (!_inCellRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
          final thread = _threadMap[stitch.threadId];
          if (thread == null) continue;
          final c = _resolveStitchColor(stitch.threadId,
              _applyPaletteOverride(stitch.threadId, thread.color),
              isCrossStitch: true);
          if (c == null) continue;
          switch (stitch) {
            case FullStitch(:final x, :final y):
              final blended = blendMap['$x,$y'];
              _drawFullStitch(canvas, x, y, blended ?? c);
            case HalfStitch(:final x, :final y, :final isForward):
              _drawHalfStitch(canvas, x, y, isForward, c);
            case QuarterStitch(:final x, :final y, :final quadrant):
              _drawQuarterStitch(canvas, x, y, quadrant, c);
            case HalfCrossStitch(:final x, :final y, :final half):
              _drawHalfCrossStitch(canvas, x, y, half, c);
            case QuarterCrossStitch(:final x, :final y, :final quadrant):
              _drawQuarterCrossStitch(canvas, x, y, quadrant, c);
            default:
              break;
          }
        }
      }
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
          final c = _resolveStitchColor(stitch.threadId,
              _applyPaletteOverride(stitch.threadId, thread.color),
              isCrossStitch: false);
          if (c != null) {
            _drawBackstitch(canvas, stitch.x1, stitch.y1, stitch.x2, stitch.y2, c);
          }
        }
      }
    }

    // ── Stitch symbols (all visible layers) ──────────────────────────────────
    // Shown when zoomed in enough (>= 8 px/cell) AND:
    //   • blockMode off  → always show (both edit and stitch mode)
    //   • blockMode on   → only in stitch mode (edit mode keeps a clean block view)
    // Symbols from lower layers are skipped when a higher layer has a FullStitch
    // at the same cell (prevents lower-layer symbols bleeding through).
    if (effectivePx >= 8 && (!blockMode || stitchMode)) {
      for (int layerIdx = 0; layerIdx < pattern.layers.length; layerIdx++) {
        final layer = pattern.layers[layerIdx];
        if (!layer.visible) continue;
        final occluded = upperFullStitchCells[layerIdx]!;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          if (!_inCellRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
          // Skip symbol if a higher visible layer has a FullStitch at this cell
          if (stitch is FullStitch && occluded.contains('${stitch.x},${stitch.y}')) continue;

          // For blended cells, use the composite cache (stable symbol
          // assignments) when available; fall back to nearest-thread lookup
          // only if the cache hasn't been built yet.
          Thread? compositeThread;
          if (stitch is FullStitch) {
            final cellKey = '${stitch.x},${stitch.y}';
            compositeThread = compositeThreadCache?[cellKey];
            if (compositeThread == null) {
              final blended = blendMap[cellKey];
              if (blended != null) compositeThread = _nearestThread(blended);
            }
          }
          final thread = compositeThread ?? _threadMap[stitch.threadId];
          if (thread == null || thread.symbol.isEmpty) continue;

          final c = _resolveStitchColor(stitch.threadId,
              _applyPaletteOverride(stitch.threadId, thread.color),
              isCrossStitch: true);
          if (c != null) _drawStitchSymbol(canvas, stitch, thread.symbol, c);
        }
      }
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
    // Scale-invariant stroke widths: always ~1px / ~1.5px on screen.
    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = minorColor
      ..strokeWidth = 1.0 / scale;
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = majorColor
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

  // ── Blend map for overlapping FullStitches across layers ──────────────────
  // For cells where multiple visible layers have a FullStitch, blends their
  // colours bottom-to-top using each layer's opacity value.
  // Lone-stitch cells are NOT included — callers fall back to source color.

  // ── Static cache for the blend map ──────────────────────────────────────────
  // The blend map is keyed by pattern object identity so it is only recomputed
  // when the pattern actually changes (stitches, opacity, visibility) — NOT on
  // every pan/zoom frame, which would make CIE Lab matching too expensive.
  static CrossStitchPattern? _blendMapPattern;
  static Map<String, Color> _blendMapCache = {};

  Map<String, Color> _buildBlendMap() {
    if (identical(_blendMapPattern, pattern)) return _blendMapCache;
    _blendMapPattern = pattern;

    final threadMap = _threadMap;
    final cellStack =
        <String, List<({Color color, double opacity, LayerBlendMode blendMode})>>{};
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! FullStitch) continue;
        final thread = threadMap[stitch.threadId];
        if (thread == null) continue;
        final key = '${stitch.x},${stitch.y}';
        (cellStack[key] ??= []).add((
          color: thread.color,
          opacity: layer.opacity,
          blendMode: layer.blendMode,
        ));
      }
    }

    final result = <String, Color>{};
    for (final entry in cellStack.entries) {
      final stack = entry.value;
      if (stack.length < 2) continue; // lone stitches excluded
      var blended = stack.first.color;
      for (int i = 1; i < stack.length; i++) {
        blended = stack[i].blendMode.apply(blended, stack[i].color, stack[i].opacity);
      }
      // Snap to nearest DMC thread so the displayed colour is always a real
      // thread colour — opacity produces discrete jumps, not a smooth gradient.
      final r = (blended.r * 255).round();
      final g = (blended.g * 255).round();
      final b = (blended.b * 255).round();
      final dmc = SpriteImporter.matchPixel(r, g, b, 255);
      result[entry.key] = dmc?.color ?? blended;
    }

    _blendMapCache = result;
    return result;
  }

  // ── Block-mode stitch rendering ────────────────────────────────────────────
  // Renders each occupied cell as a solid colour rect — used when zoomed out
  // far enough that stitch shapes are sub-pixel and too small to be meaningful.
  // Cells with multiple stitch layers use the topmost stitch's colour.

  void _drawLayerStitchesAsBlocks(Canvas canvas, Layer layer,
      Map<String, Color> blendMap,
      int minX, int minY, int maxX, int maxY) {
    final halfCell    = cellSize * 0.5;
    final quarterCell = cellSize * 0.5; // same value; named for clarity below

    // Collect (rect, color) for each visible stitch.
    // Full stitches → full cell; halves → half cell; quarters → quarter cell.
    final List<(Rect, Color)> rects = [];
    for (final stitch in layer.stitches) {
      if (stitch is BackStitch) continue;
      if (!_inCellRange(stitch, minX, minY, maxX, maxY)) continue;
      final thread = _threadMap[stitch.threadId];
      if (thread == null) continue;
      final c = _resolveStitchColor(stitch.threadId,
          _applyPaletteOverride(stitch.threadId, thread.color),
          isCrossStitch: true);
      if (c == null) continue;

      // For FullStitch, use the blended color if available (overlapping layers).
      // For all other stitch types, use the source thread color.
      Color effectiveColor = c;
      Rect? rect;
      switch (stitch) {
        case FullStitch(:final x, :final y):
          effectiveColor = blendMap['$x,$y'] ?? c;
          rect = Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);

        // HalfStitch (diagonal): isForward=true → `/` → right half of cell.
        case HalfStitch(:final x, :final y, isForward: true):
          rect = Rect.fromLTWH(x * cellSize + halfCell, y * cellSize, halfCell, cellSize);
        case HalfStitch(:final x, :final y, isForward: false):
          rect = Rect.fromLTWH(x * cellSize, y * cellSize, halfCell, cellSize);

        // HalfCrossStitch: occupies one explicit half of the cell.
        case HalfCrossStitch(:final x, :final y, half: HalfOrientation.left):
          rect = Rect.fromLTWH(x * cellSize, y * cellSize, halfCell, cellSize);
        case HalfCrossStitch(:final x, :final y, half: HalfOrientation.right):
          rect = Rect.fromLTWH(x * cellSize + halfCell, y * cellSize, halfCell, cellSize);
        case HalfCrossStitch(:final x, :final y, half: HalfOrientation.top):
          rect = Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, halfCell);
        case HalfCrossStitch(:final x, :final y, half: HalfOrientation.bottom):
          rect = Rect.fromLTWH(x * cellSize, y * cellSize + halfCell, cellSize, halfCell);

        // QuarterStitch / QuarterCrossStitch: one quarter of the cell.
        case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.topLeft):
        case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.topLeft):
          rect = Rect.fromLTWH(x * cellSize, y * cellSize, quarterCell, quarterCell);
        case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.topRight):
        case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.topRight):
          rect = Rect.fromLTWH(x * cellSize + quarterCell, y * cellSize, quarterCell, quarterCell);
        case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.bottomLeft):
        case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.bottomLeft):
          rect = Rect.fromLTWH(x * cellSize, y * cellSize + quarterCell, quarterCell, quarterCell);
        case QuarterStitch(:final x, :final y, quadrant: QuadrantPosition.bottomRight):
        case QuarterCrossStitch(:final x, :final y, quadrant: QuadrantPosition.bottomRight):
          rect = Rect.fromLTWH(x * cellSize + quarterCell, y * cellSize + quarterCell, quarterCell, quarterCell);

        default:
          rect = null;
      }
      if (rect != null) rects.add((rect, effectiveColor));
    }

    // Batch rects by colour to minimise Paint object churn.
    final Map<Color, List<Rect>> byColor = {};
    for (final (rect, color) in rects) {
      (byColor[color] ??= []).add(rect);
    }
    for (final entry in byColor.entries) {
      final paint = Paint()..color = entry.key;
      for (final rect in entry.value) {
        canvas.drawRect(rect, paint);
      }
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

  void _drawStitchSymbol(
      Canvas canvas, Stitch stitch, String symbol, Color threadColor) {
    final center = _symbolCenter(stitch);
    final fontSize = math.max(4.0, cellSize * 0.46);
    final textColor = threadColor.computeLuminance() > 0.35
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFFFFFFF);
    final tp = TextPainter(
      text: TextSpan(
          text: symbol,
          style: TextStyle(
              fontSize: fontSize,
              color: textColor,
              fontWeight: FontWeight.bold,
              height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromCenter(
        center: center, width: tp.width + 4, height: tp.height + 3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
        Paint()..color = threadColor);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
        Paint()
          ..color = textColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 / scale);
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
    if (!stitchMode) return original;

    final hasFocus = stitchFocusThreadId != null;
    final isFocused = !hasFocus || stitchFocusThreadId == threadId;

    // Focus: unfocused stitches always grey
    if (hasFocus && !isFocused) return _greyColor(original);

    // Back mode: grey normal stitches (isCrossStitch = true means non-backstitch)
    if (stitchBackMode && isCrossStitch) return _greyColor(original);

    // Cross mode: hide backstitches
    if (stitchCrossMode && !isCrossStitch) return null;

    return original;
  }

  static Color _greyColor(Color c) {
    final lum = 0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255);
    final g = lum.round().clamp(80, 210);
    return Color.fromARGB(160, g, g, g);
  }

  @override
  bool shouldRepaint(CanvasStaticPainter old) =>
      old.pattern != pattern ||
      old.cellSize != cellSize ||
      old.panOffset != panOffset ||
      old.scale != scale ||
      old.aidaColor != aidaColor ||
      old.stitchMode != stitchMode ||
      old.blockMode != blockMode ||
      old.stitchCrossMode != stitchCrossMode ||
      old.stitchBackMode != stitchBackMode ||
      old.stitchFocusThreadId != stitchFocusThreadId ||
      old.referenceImage != referenceImage ||
      old.referenceOpacity != referenceOpacity ||
      old.referenceVisible != referenceVisible ||
      old.compositeThreadCache != compositeThreadCache ||
      old.paletteOverride != paletteOverride;
}

