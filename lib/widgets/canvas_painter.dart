import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/layer.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../providers/editor_provider.dart' show StitchViewMode;
import '../services/sprite_importer.dart';

// ─── Shared drawing primitives ────────────────────────────────────────────────
// Both CanvasStaticPainter and CanvasOverlayPainter mix this in.

mixin _DrawingMethods {
  double get cellSize;
  Color get aidaColor;
  double get scale;

  // ─── Contrast helper ────────────────────────────────────────────────────────

  double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  // ─── Thread line with highlight ─────────────────────────────────────────────

  void _drawThreadLine(Canvas canvas, Offset from, Offset to, Color color,
      {double widthFactor = 0.12, double minWidth = 1.2}) {
    final width = math.max(minWidth, cellSize * widthFactor);

    final contrast = _contrastRatio(color, aidaColor);
    if (contrast < 3.5) {
      final outlineBase =
          aidaColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      final alpha = ((3.5 - contrast.clamp(1.0, 3.5)) / 2.5) * 0.7;
      canvas.drawLine(
          from,
          to,
          Paint()
            ..color = outlineBase.withValues(alpha: alpha)
            ..strokeWidth = width * 1.8
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke);
    }

    canvas.drawLine(
        from,
        to,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return;

    final px = -dy / dist;
    final py = dx / dist;
    final offset = Offset(px, py) * (width * 0.22);

    canvas.drawLine(
        from + offset,
        to + offset,
        Paint()
          ..color = Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: 0.65)
          ..strokeWidth = width * 0.38
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
  }

  // ─── Stitch draw methods ────────────────────────────────────────────────────

  void _drawFullStitch(Canvas canvas, int x, int y, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color);
    _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color);
  }

  void _drawHalfStitch(Canvas canvas, int x, int y, bool isForward, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    if (isForward) {
      _drawThreadLine(canvas, Offset(right, top), Offset(left, bottom), color);
    } else {
      _drawThreadLine(canvas, Offset(left, top), Offset(right, bottom), color);
    }
  }

  void _drawQuarterStitch(
      Canvas canvas, int x, int y, QuadrantPosition quadrant, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final cx = left + cellSize / 2;
    final cy = top + cellSize / 2;
    final (from, to) = switch (quadrant) {
      QuadrantPosition.topLeft => (Offset(left, top), Offset(cx, cy)),
      QuadrantPosition.topRight => (Offset(right, top), Offset(cx, cy)),
      QuadrantPosition.bottomLeft => (Offset(left, bottom), Offset(cx, cy)),
      QuadrantPosition.bottomRight => (Offset(right, bottom), Offset(cx, cy)),
    };
    _drawThreadLine(canvas, from, to, color);
  }

  void _drawHalfCrossStitch(
      Canvas canvas, int x, int y, HalfOrientation half, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final midX = left + cellSize / 2;
    final midY = top + cellSize / 2;
    final (tl, tr, bl, br) = switch (half) {
      HalfOrientation.left => (
          Offset(left, top), Offset(midX, top), Offset(left, bottom), Offset(midX, bottom)),
      HalfOrientation.right => (
          Offset(midX, top), Offset(right, top), Offset(midX, bottom), Offset(right, bottom)),
      HalfOrientation.top => (
          Offset(left, top), Offset(right, top), Offset(left, midY), Offset(right, midY)),
      HalfOrientation.bottom => (
          Offset(left, midY), Offset(right, midY), Offset(left, bottom), Offset(right, bottom)),
    };
    _drawThreadLine(canvas, tl, br, color);
    _drawThreadLine(canvas, tr, bl, color);
  }

  void _drawQuarterCrossStitch(
      Canvas canvas, int x, int y, QuadrantPosition quadrant, Color color) {
    final left = x * cellSize;
    final top = y * cellSize;
    final right = left + cellSize;
    final bottom = top + cellSize;
    final midX = left + cellSize / 2;
    final midY = top + cellSize / 2;
    final (tl, tr, bl, br) = switch (quadrant) {
      QuadrantPosition.topLeft => (
          Offset(left, top), Offset(midX, top), Offset(left, midY), Offset(midX, midY)),
      QuadrantPosition.topRight => (
          Offset(midX, top), Offset(right, top), Offset(midX, midY), Offset(right, midY)),
      QuadrantPosition.bottomLeft => (
          Offset(left, midY), Offset(midX, midY), Offset(left, bottom), Offset(midX, bottom)),
      QuadrantPosition.bottomRight => (
          Offset(midX, midY), Offset(right, midY), Offset(midX, bottom), Offset(right, bottom)),
    };
    _drawThreadLine(canvas, tl, br, color);
    _drawThreadLine(canvas, tr, bl, color);
  }

  void _drawBackstitch(
      Canvas canvas, double x1, double y1, double x2, double y2, Color color) {
    _drawThreadLine(
        canvas,
        Offset(x1 * cellSize, y1 * cellSize),
        Offset(x2 * cellSize, y2 * cellSize),
        color,
        widthFactor: 0.15,
        minWidth: 1.5);
  }

  void _drawSingleStitch(Canvas canvas, Stitch stitch, Color color) {
    switch (stitch) {
      case FullStitch(:final x, :final y):
        _drawFullStitch(canvas, x, y, color);
      case HalfStitch(:final x, :final y, :final isForward):
        _drawHalfStitch(canvas, x, y, isForward, color);
      case QuarterStitch(:final x, :final y, :final quadrant):
        _drawQuarterStitch(canvas, x, y, quadrant, color);
      case HalfCrossStitch(:final x, :final y, :final half):
        _drawHalfCrossStitch(canvas, x, y, half, color);
      case QuarterCrossStitch(:final x, :final y, :final quadrant):
        _drawQuarterCrossStitch(canvas, x, y, quadrant, color);
      case BackStitch(:final x1, :final y1, :final x2, :final y2):
        _drawBackstitch(canvas, x1, y1, x2, y2, color);
    }
  }

  // ─── Backstitch preview & start indicator ───────────────────────────────────

  void _drawGridPointIndicator(Canvas canvas, Offset gridPoint) {
    canvas.drawCircle(
      Offset(gridPoint.dx * cellSize, gridPoint.dy * cellSize),
      math.max(3.0, cellSize * 0.15),
      Paint()..color = Colors.blue.shade700,
    );
  }

  void _drawBackstitchPreview(Canvas canvas, Offset start, Offset end) {
    final p = Paint()
      ..color = Colors.black54
      ..strokeWidth = math.max(1.0, cellSize * 0.1)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final startPx = Offset(start.dx * cellSize, start.dy * cellSize);
    final endPx = Offset(end.dx * cellSize, end.dy * cellSize);
    final dx = endPx.dx - startPx.dx;
    final dy = endPx.dy - startPx.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return;

    const dashLen = 6.0;
    const gapLen = 4.0;
    final ux = dx / dist;
    final uy = dy / dist;
    var d = 0.0;
    var drawing = true;
    final path = Path();
    while (d < dist) {
      final segLen =
          drawing ? math.min(dashLen, dist - d) : math.min(gapLen, dist - d);
      if (drawing) {
        path.moveTo(startPx.dx + ux * d, startPx.dy + uy * d);
        path.lineTo(startPx.dx + ux * (d + segLen), startPx.dy + uy * (d + segLen));
      }
      d += segLen;
      drawing = !drawing;
    }
    canvas.drawPath(path, p);
  }

  // ─── Ghost stitches (paste / move preview) ──────────────────────────────────

  void _drawGhostStitches(
      Canvas canvas, List<Stitch> stitches, Map<String, Thread> threadMap,
      {double opacity = 1.0}) {
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: opacity));
    for (final stitch in stitches) {
      final thread = threadMap[stitch.threadId];
      if (thread == null) continue;
      _drawSingleStitch(canvas, stitch, thread.color);
    }
    canvas.restore();
  }

  // ─── Selection rect ─────────────────────────────────────────────────────────

  void _drawSelectionRect(Canvas canvas, Rect rect) {
    final px = Rect.fromLTRB(
      rect.left * cellSize,
      rect.top * cellSize,
      rect.right * cellSize,
      rect.bottom * cellSize,
    );
    canvas.drawRect(px, Paint()..color = const Color(0x264D90FE));
    canvas.drawRect(
      px,
      Paint()
        ..color = const Color(0xFF4D90FE)
        ..strokeWidth = 1.5 / scale
        ..style = PaintingStyle.stroke,
    );
    final h = math.max(4.0, 8.0 / scale);
    final hp = Paint()
      ..color = const Color(0xFF4D90FE)
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    for (final corner in [px.topLeft, px.topRight, px.bottomLeft, px.bottomRight]) {
      final dx = corner.dx == px.left ? h : -h;
      final dy = corner.dy == px.top ? h : -h;
      canvas.drawLine(corner, Offset(corner.dx + dx, corner.dy), hp);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy), hp);
    }
  }

  // ─── Custom cursors (screen-space) ──────────────────────────────────────────

  void _drawEraserCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-math.pi / 4);
    const w = 11.0;
    const h = 18.0;
    final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-w / 2, 0, w, h), const Radius.circular(2));
    canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFFF4A0B0));
    canvas.save();
    canvas.clipRRect(bodyRect);
    canvas.drawRect(Rect.fromLTWH(-w / 2, 0, w, h * 0.25),
        Paint()..color = Colors.white.withValues(alpha: 0.55));
    canvas.restore();
    canvas.drawRRect(
        bodyRect,
        Paint()
          ..color = const Color(0xFF444444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
    canvas.restore();
  }

  void _drawPencilCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-math.pi / 4);
    const halfW = 2.5;
    final outlinePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final graphitePath = Path()
      ..moveTo(0, 0)
      ..lineTo(-1.0, 2.5)
      ..lineTo(1.0, 2.5)
      ..close();
    canvas.drawPath(graphitePath, Paint()..color = const Color(0xFF555555));
    canvas.drawPath(graphitePath, outlinePaint);
    final woodPath = Path()
      ..moveTo(-1.0, 2.5)
      ..lineTo(1.0, 2.5)
      ..lineTo(halfW, 7.0)
      ..lineTo(-halfW, 7.0)
      ..close();
    canvas.drawPath(woodPath, Paint()..color = const Color(0xFFD4A04A));
    canvas.drawPath(woodPath, outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-halfW, 7.0, halfW * 2, 12.0),
        Paint()..color = const Color(0xFFFFD700));
    canvas.drawRect(Rect.fromLTWH(-halfW, 7.0, halfW * 2, 12.0), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-halfW, 19.0, halfW * 2, 2.0),
        Paint()..color = const Color(0xFFAAAAAA));
    canvas.drawRect(Rect.fromLTWH(-halfW, 19.0, halfW * 2, 2.0), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-halfW, 21.0, halfW * 2, 3.5),
        Paint()..color = const Color(0xFFF4A0B0));
    canvas.drawRect(Rect.fromLTWH(-halfW, 21.0, halfW * 2, 3.5), outlinePaint);
    canvas.drawLine(Offset(-halfW, 7.0), Offset(halfW, 7.0), outlinePaint);
    canvas.restore();
  }

  void _drawEyedropperCursor(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-math.pi / 4);
    final outlinePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset.zero, 1.5, Paint()..color = const Color(0xFF333333));
    final rodPath = Path()
      ..moveTo(-1.0, 1.5)
      ..lineTo(1.0, 1.5)
      ..lineTo(1.5, 6.0)
      ..lineTo(-1.5, 6.0)
      ..close();
    canvas.drawPath(rodPath, Paint()..color = const Color(0xFF888888));
    canvas.drawPath(rodPath, outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-2.0, 6.0, 4.0, 1.5),
        Paint()..color = const Color(0xFF666666));
    canvas.drawRect(Rect.fromLTWH(-2.0, 6.0, 4.0, 1.5), outlinePaint);
    canvas.drawRect(Rect.fromLTWH(-2.5, 7.5, 5.0, 9.5),
        Paint()..color = const Color(0xFFDDDDDD));
    canvas.drawRect(Rect.fromLTWH(-2.5, 7.5, 5.0, 9.5), outlinePaint);
    canvas.drawCircle(
        const Offset(0, 22.0), 5.0, Paint()..color = const Color(0xFF888888));
    canvas.drawCircle(const Offset(0, 22.0), 5.0, outlinePaint);
    canvas.drawCircle(const Offset(-1.5, 20.5), 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.45));
    canvas.restore();
  }
}

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
  final StitchViewMode stitchViewMode;
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
    this.stitchViewMode = StitchViewMode.normal,
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
    // Below kNoGrid: grid lines add no information and just darken the view.
    const kNoGrid          = 1.5;

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
      _drawGrid(canvas, minCX, minCY, maxCX, maxCY);
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

  void _drawGrid(Canvas canvas, int minX, int minY, int maxX, int maxY) {
    final base = aidaColor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    final minorPaint = Paint()
      ..color = base.withValues(alpha: 0.18)
      ..strokeWidth = 0.5;
    final majorPaint = Paint()
      ..color = base.withValues(alpha: 0.38)
      ..strokeWidth = 1.0;

    final minorPath = Path();
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
        minorPath.moveTo(px, top);
        minorPath.lineTo(px, bottom);
      }
    }
    for (int y = minY; y <= maxY; y++) {
      final py = y * cellSize;
      if (y % 10 == 0) {
        majorPath.moveTo(left, py);
        majorPath.lineTo(right, py);
      } else {
        minorPath.moveTo(left, py);
        minorPath.lineTo(right, py);
      }
    }

    canvas.drawPath(minorPath, minorPaint);
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
    final cellStack = <String, List<({Color color, double opacity})>>{};
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! FullStitch) continue;
        final thread = threadMap[stitch.threadId];
        if (thread == null) continue;
        final key = '${stitch.x},${stitch.y}';
        (cellStack[key] ??= [])
            .add((color: thread.color, opacity: layer.opacity));
      }
    }

    final result = <String, Color>{};
    for (final entry in cellStack.entries) {
      final stack = entry.value;
      if (stack.length < 2) continue; // lone stitches excluded
      var blended = stack.first.color;
      for (int i = 1; i < stack.length; i++) {
        blended = Color.lerp(blended, stack[i].color, stack[i].opacity)!;
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
    for (final s in [5, 10, 20, 50, 100]) {
      if (s * effectiveCellPx >= minSpacing) return s;
    }
    return 100;
  }

  void _drawGridLabels(Canvas canvas, Size size) {
    final effectiveCellPx = cellSize * scale;
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
    if (stitchViewMode == StitchViewMode.greyed) {
      if (isCrossStitch) return _greyColor(original);
      final hasFocus = stitchFocusThreadId != null;
      if (!hasFocus || stitchFocusThreadId == threadId) return original;
      return _greyColor(original);
    }
    final hasFocus = stitchFocusThreadId != null;
    final isFocused = !hasFocus || stitchFocusThreadId == threadId;
    if (hasFocus && !isFocused) return _greyColor(original);
    if (hasFocus && isFocused) {
      if (stitchViewMode == StitchViewMode.hidden && !isCrossStitch) return null;
      return original;
    }
    return switch (stitchViewMode) {
      StitchViewMode.normal => original,
      StitchViewMode.hidden => isCrossStitch ? original : null,
      StitchViewMode.greyed => original,
    };
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
      old.stitchViewMode != stitchViewMode ||
      old.stitchFocusThreadId != stitchFocusThreadId ||
      old.referenceImage != referenceImage ||
      old.referenceOpacity != referenceOpacity ||
      old.referenceVisible != referenceVisible ||
      old.compositeThreadCache != compositeThreadCache ||
      old.paletteOverride != paletteOverride;
}

// ─── Overlay layer ────────────────────────────────────────────────────────────
// Cursor, ghost stitches, selection rect, stylus hover, backstitch preview.
// Repaints independently of the static layer — never invalidates its cache.

class CanvasOverlayPainter extends CustomPainter with _DrawingMethods {
  @override final double cellSize;
  final Offset panOffset;
  @override final double scale;
  @override final Color aidaColor;
  final Offset? backstitchStartPoint;
  final Offset? backstitchCurrentPoint;
  final bool isErasing;
  final bool isDrawCursor;
  final bool isColorPickerCursor;
  final Offset? cursorScreenPos;
  final Rect? selectionRect;
  final List<Stitch>? ghostStitches;
  final List<Thread>? ghostThreads;
  final double ghostOpacity;
  final List<Thread> patternThreads;
  final (int, int)? stylusHoverCell;
  final Color? stylusHoverColor;
  final String? activeLayerName;
  final bool stitchMode;

  CanvasOverlayPainter({
    required this.cellSize,
    required this.panOffset,
    required this.scale,
    required this.aidaColor,
    required this.patternThreads,
    this.backstitchStartPoint,
    this.backstitchCurrentPoint,
    this.isErasing = false,
    this.isDrawCursor = false,
    this.isColorPickerCursor = false,
    this.cursorScreenPos,
    this.selectionRect,
    this.ghostStitches,
    this.ghostThreads,
    this.ghostOpacity = 1.0,
    this.stylusHoverCell,
    this.stylusHoverColor,
    this.activeLayerName,
    this.stitchMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Keep overlay drawing within widget bounds too.
    canvas.clipRect(Offset.zero & size);

    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    // Backstitch start indicator + preview
    if (backstitchStartPoint != null) {
      _drawGridPointIndicator(canvas, backstitchStartPoint!);
      if (backstitchCurrentPoint != null &&
          backstitchCurrentPoint != backstitchStartPoint) {
        _drawBackstitchPreview(canvas, backstitchStartPoint!, backstitchCurrentPoint!);
      }
    }

    // Ghost stitches (paste / move preview)
    if (ghostStitches != null && ghostStitches!.isNotEmpty) {
      final threadMap = <String, Thread>{
        for (final t in patternThreads) t.dmcCode: t,
        if (ghostThreads != null) for (final t in ghostThreads!) t.dmcCode: t,
      };
      _drawGhostStitches(canvas, ghostStitches!, threadMap, opacity: ghostOpacity);
    }

    // Selection rect
    if (selectionRect != null) _drawSelectionRect(canvas, selectionRect!);

    // Stylus hover preview
    if (stylusHoverCell != null) {
      final (hx, hy) = stylusHoverCell!;
      final hColor = stylusHoverColor ?? const Color(0xFF9B30D0);
      final rect = Rect.fromLTWH(hx * cellSize, hy * cellSize, cellSize, cellSize);
      canvas.drawRect(rect, Paint()..color = hColor.withValues(alpha: 0.25));
      canvas.drawRect(
          rect,
          Paint()
            ..color = hColor.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale);
    }

    canvas.restore();

    // Custom cursors (screen-space, after restore)
    if (cursorScreenPos != null) {
      if (isErasing) _drawEraserCursor(canvas, cursorScreenPos!);
      if (isDrawCursor) _drawPencilCursor(canvas, cursorScreenPos!);
      if (isColorPickerCursor) _drawEyedropperCursor(canvas, cursorScreenPos!);
    }

    // ── Active layer chip ───────────────────────────────────────────────────
    if (!stitchMode && activeLayerName != null) {
      _drawActiveLayerChip(canvas, size, activeLayerName!);
    }
  }

  void _drawActiveLayerChip(Canvas canvas, Size size, String layerName) {
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    const textStyle = TextStyle(
      fontSize: 11,
      color: Colors.white,
      fontWeight: FontWeight.w500,
    );
    final label = 'Drawing on: $layerName';
    final tp = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    const left = 8.0;
    const bottom = 8.0;
    final chipRect = Rect.fromLTWH(
      left,
      size.height - bottom - tp.height - padding.vertical,
      tp.width + padding.horizontal,
      tp.height + padding.vertical,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
      Paint()..color = const Color(0xCC1A1A2E),
    );
    tp.paint(canvas,
        Offset(chipRect.left + padding.left, chipRect.top + padding.top));
  }

  @override
  bool shouldRepaint(CanvasOverlayPainter old) =>
      old.cellSize != cellSize ||
      old.panOffset != panOffset ||
      old.scale != scale ||
      old.aidaColor != aidaColor ||
      old.backstitchStartPoint != backstitchStartPoint ||
      old.backstitchCurrentPoint != backstitchCurrentPoint ||
      old.isErasing != isErasing ||
      old.isDrawCursor != isDrawCursor ||
      old.isColorPickerCursor != isColorPickerCursor ||
      old.cursorScreenPos != cursorScreenPos ||
      old.selectionRect != selectionRect ||
      old.ghostStitches != ghostStitches ||
      old.ghostThreads != ghostThreads ||
      old.ghostOpacity != ghostOpacity ||
      old.patternThreads != patternThreads ||
      old.stylusHoverCell != stylusHoverCell ||
      old.stylusHoverColor != stylusHoverColor ||
      old.activeLayerName != activeLayerName ||
      old.stitchMode != stitchMode;
}
