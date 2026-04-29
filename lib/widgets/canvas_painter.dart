import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/page_layout.dart';
import '../models/pattern.dart';
import '../models/pattern_progress.dart';
import '../models/stitch.dart';
import '../models/stitch_geometry.dart';
import '../models/thread.dart';
import '../data/symbols.dart';
import '../services/color_space.dart';
import '../services/render_cache.dart';
import '../services/stitch_compositor.dart';
import 'canvas_viewport.dart';

part 'canvas_painter_drawing_methods.dart';
part 'canvas_painter_overlay.dart';

// ─── Static layer ─────────────────────────────────────────────────────────────
// Background, stitches, grid, labels. Cached by RepaintBoundary.
// Only repaints when renderCache.version, pan/zoom, or display options change.

class CanvasStaticPainter extends CustomPainter with _DrawingMethods {
  final CrossStitchPattern pattern;
  @override final double cellSize;
  final Offset panOffset;
  @override final double scale;
  @override final Color aidaColor;
  final bool stitchMode;
  final bool stitchCrossMode;
  final bool stitchBackMode;
  final String? stitchFocusThreadId;
  final ui.Image? referenceImage;
  final double referenceOpacity;
  final bool referenceVisible;

  /// Pre-resolved stitch block rects, grouped by colour.
  /// Built and maintained by [AidaWidget]; painter just draws.
  final RenderCache renderCache;

  /// Snapshot of [renderCache.version] taken at build time.
  ///
  /// [RenderCache] is a mutable object shared across builds, so comparing the
  /// live [renderCache.version] in [shouldRepaint] would always yield equal
  /// values (old and new painter reference the same object). Snapshotting the
  /// version as a plain [int] at construction time gives [shouldRepaint] the
  /// before/after values it needs to detect data changes.
  final int cacheVersion;

  /// Flat composite view — used for symbol rendering and focus-region outline.
  /// Block rendering is fully handled by [renderCache].
  final CompositeLayer? compositeLayer;

  /// Page layout for page mode. When non-null (and config.enabled), only
  /// stitches belonging to [currentPage] are rendered.
  final PageLayout? pageLayout;

  /// The 0-based page index to display when [pageLayout] is non-null.
  final int currentPage;

  /// Progress data — used in stitch mode to dim completed stitch cells.
  final PatternProgress progress;

  late final Map<String, Thread> _threadMap = pattern.threads;

  /// Stitch mode is always B&W now (no block/colour toggle).
  bool get _isBWStitchMode => stitchMode;

  CanvasStaticPainter({
    required this.pattern,
    required this.cellSize,
    required this.panOffset,
    required this.scale,
    required this.aidaColor,
    required this.renderCache,
    required this.cacheVersion,
    this.stitchMode = false,
    this.stitchCrossMode = false,
    this.stitchBackMode = false,
    this.stitchFocusThreadId,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.referenceVisible = true,
    this.compositeLayer,
    this.pageLayout,
    this.currentPage = 0,
    this.progress = PatternProgress.empty,
  });

  @override
  void paint(Canvas canvas, Size size) {
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
    final effectivePx = cellSize * scale;
    const kNoBackstitch = 3.0;
    const kMajorOnly    = 14.0;
    const kNoGrid       = 6.0;

    // ── Stitch blocks — drawn from pre-resolved RenderCache ──────────────────
    // Viewport bounds in canvas/pattern space for culling.
    final minPx = minCX * cellSize;
    final minPy = minCY * cellSize;
    final maxPx = maxCX * cellSize;
    final maxPy = maxCY * cellSize;

    for (final colorEntry in renderCache.store.entries) {
      final paint = Paint()..color = colorEntry.key;
      for (final cellRects in colorEntry.value.values) {
        for (final rect in cellRects) {
          if (rect.right <= minPx || rect.left >= maxPx ||
              rect.bottom <= minPy || rect.top >= maxPy) { continue; }
          canvas.drawRect(rect, paint);
        }
      }
    }

    // ── Grid (batched paths, culled; skipped when cells are sub-pixel) ───────
    if (effectivePx >= kNoGrid) {
      _drawGrid(canvas, minCX, minCY, maxCX, maxCY,
          majorOnly: effectivePx < kMajorOnly);
    }

    // ── Backstitches (all visible layers, pre-resolved by compositor) ────────
    if (effectivePx >= kNoBackstitch) {
      final backstitches = compositeLayer?.backstitches ?? const [];
      for (final stitch in backstitches) {
        if (!stitch.isInViewport(minCX, minCY, maxCX, maxCY)) continue;
        final thread = _threadMap[stitch.threadId];
        if (thread == null) continue;
        var c = _resolveBackstitchColor(stitch.threadId, thread.color);
        if (c == null) continue;
        final isDone = stitchMode && progress.isBackstitchDone(
            stitch.x1, stitch.y1, stitch.x2, stitch.y2);
        if (stitchMode) {
          if (!isDone) {
            c = _bwGreyscale(c);
          } else if (stitchFocusThreadId != null &&
              stitchFocusThreadId != stitch.threadId) {
            c = _muteColor(c);
          }
        }
        if (_isBWStitchMode && _isBackstitchFocused(stitch)) {
          _drawBackstitchOutline(canvas, stitch);
        }
        _drawBackstitch(canvas, stitch.x1, stitch.y1, stitch.x2, stitch.y2, c);
      }
    }

    // ── Stitch symbols (B&W stitch mode only, zoomed in enough) ─────────────
    // Uses compositeLayer for the symbol-winner per cell — already deduped
    // and resolved by the compositor (one CompositeStitch per cell).
    if (effectivePx >= 8 && _isBWStitchMode) {
      final layer = compositeLayer;
      if (layer != null) {
        for (final cs in [...layer.fullStitches.values, ...layer.otherStitches]) {
          final stitch = cs.stitch;
          if (!stitch.isInViewport(minCX, minCY, maxCX, maxCY)) continue;

          final sCoords = stitch.cellCoords;
          if (sCoords != null && !_stitchOnPage(sCoords.x, sCoords.y)) continue;

          // Skip done cells in B&W mode.
          if (sCoords != null && progress.completedStitches.contains(sCoords)) continue;

          final thread = cs.resolvedThread;
          if (!symbolIsVisible(thread.symbol)) continue;

          final hasFocus = stitchFocusThreadId != null;
          final isFocused = hasFocus && thread.dmcCode == stitchFocusThreadId;
          final symbolColor = hasFocus && !isFocused
              ? const Color(0xFF999999)
              : const Color(0xFF000000);
          _drawStitchSymbolBW(canvas, stitch, thread.symbol, symbolColor);
        }
      }
    }

    // ── Focus region outline ────────────────────────────────────────────────
    if (stitchFocusThreadId != null ||
        (_isBWStitchMode && (stitchBackMode || stitchCrossMode))) {
      _drawFocusedRegionBorderIfNeeded(canvas);
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
    final isDark = aidaColor.computeLuminance() <= 0.4;
    final minorColor = isDark ? const Color(0xFF666666) : const Color(0xFFCCCCCC);
    final majorColor = isDark ? const Color(0xFF888888) : const Color(0xFF999999);
    final effectivePx = cellSize * scale;
    final minorAlpha = majorOnly ? 0.0 : (effectivePx - 14.0).clamp(0.0, 4.0) / 4.0;
    final majorAlpha = (effectivePx - 6.0).clamp(0.0, 4.0) / 4.0;
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
        majorPath.moveTo(px, top); majorPath.lineTo(px, bottom);
      } else {
        minorPath?.moveTo(px, top); minorPath?.lineTo(px, bottom);
      }
    }
    for (int y = minY; y <= maxY; y++) {
      final py = y * cellSize;
      if (y % 10 == 0) {
        majorPath.moveTo(left, py); majorPath.lineTo(right, py);
      } else {
        minorPath?.moveTo(left, py); minorPath?.lineTo(right, py);
      }
    }

    if (minorPath != null) canvas.drawPath(minorPath, minorPaint);
    canvas.drawPath(majorPath, majorPaint);
  }

  // ── Focus region outline ────────────────────────────────────────────────────

  static const Color _unfocusedGreyOpaque = Color(0xFFB8B8B8);

  void _drawFocusedRegionBorderIfNeeded(Canvas canvas) {
    final focusId = stitchFocusThreadId;

    if (!_isBWStitchMode) {
      if (focusId == null) return;
      final focusThread = _threadMap[focusId];
      if (focusThread == null) return;
      final needsOutline =
          _labDeltaE(focusThread.color, aidaColor) < 15 ||
          _labDeltaE(focusThread.color, _unfocusedGreyOpaque) < 45;
      if (!needsOutline) return;
    }

    final focusedKeys = <int>{};
    final layer = compositeLayer;
    if (layer != null && !stitchBackMode) {
      for (final cs in [...layer.fullStitches.values, ...layer.otherStitches]) {
        final coords = cs.stitch.cellCoords;
        if (coords == null) continue;
        final cx = coords.x;
        final cy = coords.y;
        final intKey = (cx << 16) | cy;
        if (focusId == null || cs.resolvedThread.dmcCode == focusId) {
          focusedKeys.add(intKey);
        }
      }
    }

    if (focusedKeys.isEmpty) return;

    final path = Path();
    for (final key in focusedKeys) {
      final cx = key >> 16;
      final cy = key & 0xFFFF;
      final l = cx * cellSize;
      final t = cy * cellSize;
      final r = l + cellSize;
      final b = t + cellSize;
      if (!focusedKeys.contains(((cx - 1) << 16) | cy)) { path.moveTo(l, t); path.lineTo(l, b); }
      if (!focusedKeys.contains(((cx + 1) << 16) | cy)) { path.moveTo(r, t); path.lineTo(r, b); }
      if (!focusedKeys.contains((cx << 16) | (cy - 1))) { path.moveTo(l, t); path.lineTo(r, t); }
      if (!focusedKeys.contains((cx << 16) | (cy + 1))) { path.moveTo(l, b); path.lineTo(r, b); }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF6B00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 / scale
        ..strokeCap = StrokeCap.square,
    );
  }

  bool _isBackstitchFocused(BackStitch stitch) {
    if (stitchBackMode) return true;
    return stitchFocusThreadId != null && stitch.threadId == stitchFocusThreadId;
  }

  static final _bwOutlinePaint = Paint()
    ..color = const Color(0xFFFF6B00)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _drawBackstitchOutline(Canvas canvas, BackStitch stitch) {
    final from = Offset(stitch.x1 * cellSize, stitch.y1 * cellSize);
    final to   = Offset(stitch.x2 * cellSize, stitch.y2 * cellSize);
    final width = math.max(1.5, cellSize * 0.15);
    _bwOutlinePaint.strokeWidth = width * 2.2;
    canvas.drawLine(from, to, _bwOutlinePaint);
  }

  // ── Grid labels ────────────────────────────────────────────────────────────

  int _labelStep(double effectiveCellPx) {
    const minSpacing = 35.0;
    final candidates =
        effectiveCellPx >= 8.0 ? [5, 10, 20, 50, 100] : [10, 20, 50, 100];
    for (final s in candidates) {
      if (s * effectiveCellPx >= minSpacing) return s;
    }
    return 100;
  }

  void _drawGridLabels(Canvas canvas, Size size) {
    final effectiveCellPx = cellSize * scale;
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

  void _drawStitchSymbolBW(Canvas canvas, Stitch stitch, String symbol, Color color) {
    final center = _symbolCenter(stitch);
    final fontSize = math.max(4.0, cellSize * 0.46);
    final tp = TextPainter(
      text: TextSpan(
          text: symbol,
          style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: FontWeight.bold,
              height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  Offset _symbolCenter(Stitch stitch) {
    return switch (stitch) {
      FullStitch(:final x, :final y)        => Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize),
      HalfStitch(:final x, :final y)        => Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize),
      QuarterStitch(:final x, :final y, :final quadrant) => _quadrantCenter(x, y, quadrant),
      HalfCrossStitch(:final x, :final y, :final half)   => _halfOrientCenter(x, y, half),
      QuarterCrossStitch(:final x, :final y, :final quadrant) => _quadrantCenter(x, y, quadrant),
      BackStitch()                           => Offset.zero,
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

  // ── Backstitch colour resolution ───────────────────────────────────────────

  /// Resolves the display colour for a backstitch, applying focus-greying and
  /// back/cross-mode filtering. Returns null to skip drawing entirely.
  Color? _resolveBackstitchColor(String threadId, Color original) {
    final hasFocus = stitchFocusThreadId != null;
    final isFocused = !hasFocus || stitchFocusThreadId == threadId;
    if (hasFocus && !isFocused) return _greyColor(original);
    if (stitchCrossMode) return null; // cross mode: hide backstitches
    return original;
  }

  static const Color _unfocusedGrey = Color(0xA0B8B8B8);
  static Color _greyColor(Color c) => _unfocusedGrey;

  static Color _muteColor(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.85 + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _bwGreyscale(Color c) {
    final l = c.computeLuminance();
    final grey = (0.72 + l * 0.22).clamp(0.0, 1.0);
    final v = (grey * 255).round();
    return Color.fromARGB(255, v, v, v);
  }

  // ── Page mode helpers ──────────────────────────────────────────────────────

  bool _stitchOnPage(int col, int row) {
    final layout = pageLayout;
    if (layout == null || !layout.config.enabled) return true;
    final (pageCol, pageRow) = layout.pageCoords(currentPage);
    return layout.cellOnPage(col, row, pageCol, pageRow);
  }

  @override
  bool shouldRepaint(CanvasStaticPainter old) =>
      // cacheVersion captures all stitch-data changes: pattern, composite,
      // mode, focus, palette, progress, page layout/index.
      old.cacheVersion != cacheVersion ||
      // Viewport changes are not routed through RenderCache.
      old.panOffset != panOffset ||
      old.scale != scale ||
      // Reference image is drawn directly by the painter and is not tracked
      // in RenderViewConfig, so version does not bump when it changes.
      old.referenceImage != referenceImage ||
      old.referenceOpacity != referenceOpacity ||
      old.referenceVisible != referenceVisible;
}
