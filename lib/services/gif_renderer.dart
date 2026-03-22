// Shared GIF rendering logic — used by both the CLI and the Flutter GIF exporter.
//
// No Flutter imports; only the `image` package and internal Dart models.

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/stitch_plan.dart';
import 'stitch_renderer.dart';

/// Number of interpolated frames rendered per stitch segment.
/// Higher = smoother animation but larger GIF files.
const kDemoSubFrames = 6;

/// Returns an ARGB color map that uses [threadArgb] for front stitches and
/// neutral grey for all back stitches.
Map<StitchType, int> singleThreadColorMap(int threadArgb) => {
      StitchType.frontOne: threadArgb,
      StitchType.frontTwo: threadArgb,
      StitchType.backOne: 0xFF888888,
      StitchType.backTwo: 0xFF888888,
      StitchType.backThree: 0xFF888888,
      StitchType.automatic: threadArgb,
    };

/// Renders a full GIF animation and returns the encoded bytes.
///
/// Each segment is spread across [kDemoSubFrames] frames so the line appears to
/// be drawn in real time.
///
/// [cellSize] is pixels per grid cell (default 40).
/// [padding] is pixels around the pattern edges (default 20).
/// [fps] controls playback speed. At the default of 12 fps with 6 sub-frames,
///   each stitch takes ~0.5 s.
/// [colorMap] overrides the default educational-palette colours.
/// [samplingFactor] controls GIF colour-quantisation quality: 1 = best
///   (samples every pixel), 10 = default fast, higher = faster but worse.
/// [dither] controls the dithering kernel used when mapping to the 256-colour
///   palette. Defaults to [img.DitherKernel.none].
List<int> renderDemoGif({
  required PlannedAida aida,
  int fps = 12,
  double cellSize = 60,
  double padding = 20,
  Map<StitchType, int>? colorMap,
  int backgroundArgb = 0xFFFAF6F0,
  int samplingFactor = 1,
  img.DitherKernel dither = img.DitherKernel.none,
}) {
  final bounds = computeGridBounds(aida, cellSize);
  final originX = padding - bounds.left;
  final originY = padding - bounds.top;
  final canvasWidth = (bounds.width + padding * 2).ceil();
  final canvasHeight = (bounds.height + padding * 2).ceil();
  final rawSegments = resolveSegments(
    aida,
    cellSize: cellSize,
    originX: originX,
    originY: originY,
  );

  // Spread co-linear segments perpendicularly so all are visible (mirrors UI).
  final strokeW = _lineThickness(cellSize).toDouble();
  final segments = _applyLineOffsets(rawSegments, strokeW);

  final frameDelayMs = (1000 / fps).round();
  // Hold ~2 s on the finished frame before looping.
  final holdFrames = (fps * 2).round();

  img.Image? animation;

  // k = 0..segments.length * kDemoSubFrames
  //   completeCount = k ~/ kDemoSubFrames  (fully drawn segments)
  //   subProgress   = (k % kDemoSubFrames) / kDemoSubFrames  (0.0–< 1.0)
  // When subProgress == 0 the in-progress segment is not yet started (brief
  // pause between stitches — shows the completed stitch before the needle
  // moves to the next).
  final totalSubSteps = segments.length * kDemoSubFrames;

  for (var k = 0; k <= totalSubSteps; k++) {
    final completeCount = k ~/ kDemoSubFrames;
    final subProgress = (k % kDemoSubFrames) / kDemoSubFrames;

    final frame = _renderFrame(
      aida: aida,
      segments: segments,
      completeCount: completeCount,
      subProgress: subProgress,
      width: canvasWidth,
      height: canvasHeight,
      cellSize: cellSize,
      originX: originX,
      originY: originY,
      colors: colorMap ?? stitchTypeArgb,
      backgroundArgb: backgroundArgb,
    );
    frame.frameDuration = frameDelayMs;

    if (animation == null) {
      animation = frame;
    } else {
      animation.addFrame(frame);
    }
  }

  // Hold on the final frame.
  final finalFrame = animation!.frames.last.clone();
  finalFrame.frameDuration = frameDelayMs * holdFrames;
  animation.addFrame(finalFrame);

  return img.encodeGif(
    animation,
    repeat: 0,
    samplingFactor: samplingFactor,
    dither: dither,
  );
}

// ── Internal helpers ──────────────────────────────────────────────────────────

img.Image _renderFrame({
  required PlannedAida aida,
  required List<StitchSegment> segments,
  required int completeCount,
  required double subProgress,
  required int width,
  required int height,
  required double cellSize,
  required double originX,
  required double originY,
  required Map<StitchType, int> colors,
  required int backgroundArgb,
}) {
  final image = img.Image(width: width, height: height);

  // Background.
  img.fill(
    image,
    color: img.ColorRgba8(
      (backgroundArgb >> 16) & 0xFF,
      (backgroundArgb >> 8) & 0xFF,
      backgroundArgb & 0xFF,
      255,
    ),
  );

  // Grid lines for active squares.
  final gridColor = img.ColorRgba8(180, 180, 180, 255);
  for (final sqId in aida.activeSquareIds) {
    final sq = aida.squares[sqId];
    final l = (originX + (sq.x - 0.5) * cellSize).round();
    final t = (originY + (sq.y - 0.5) * cellSize).round();
    final r = (originX + (sq.x + 0.5) * cellSize).round();
    final b = (originY + (sq.y + 0.5) * cellSize).round();
    img.drawLine(image, x1: l, y1: t, x2: r, y2: t, color: gridColor);
    img.drawLine(image, x1: r, y1: t, x2: r, y2: b, color: gridColor);
    img.drawLine(image, x1: l, y1: b, x2: r, y2: b, color: gridColor);
    img.drawLine(image, x1: l, y1: t, x2: l, y2: b, color: gridColor);
  }

  // Completed stitches — backs drawn first, fronts on top (mirrors UI Z-order).
  for (var i = 0; i < completeCount && i < segments.length; i++) {
    final seg = segments[i];
    if (seg.type == StitchType.frontOne || seg.type == StitchType.frontTwo) {
      continue;
    }
    _drawSegment(image, seg, colors: colors, thick: false, cellSize: cellSize);
  }
  for (var i = 0; i < completeCount && i < segments.length; i++) {
    final seg = segments[i];
    if (seg.type != StitchType.frontOne && seg.type != StitchType.frontTwo) {
      continue;
    }
    _drawSegment(image, seg, colors: colors, thick: false, cellSize: cellSize);
  }

  // In-progress stitch: draw from start toward end at [subProgress].
  if (subProgress > 0 && completeCount < segments.length) {
    final seg = segments[completeCount];
    final argb = colors[seg.type] ?? 0xFF888888;
    final color =
        img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 255);
    final tipX = seg.x1 + (seg.x2 - seg.x1) * subProgress;
    final tipY = seg.y1 + (seg.y2 - seg.y1) * subProgress;

    final activeThickness = _activeLineThickness(cellSize);
    _drawThreadLine(
        image, seg.x1, seg.y1, tipX, tipY, color, activeThickness);

    // Needle dot at the tip: gold fill + dark outline ring.
    final needleR = (cellSize * 0.09).clamp(3.0, 7.0).round();
    img.fillCircle(
      image,
      x: tipX.round(),
      y: tipY.round(),
      radius: needleR,
      color: img.ColorRgba8(232, 192, 32, 255), // golden
    );
    img.drawCircle(
      image,
      x: tipX.round(),
      y: tipY.round(),
      radius: needleR,
      color: img.ColorRgba8(60, 40, 0, 200), // dark outline
    );
  }

  return image;
}

// Returns line thickness for completed stitches, scaled to cellSize.
int _lineThickness(double cellSize) =>
    (cellSize * 0.07).clamp(2.0, 5.0).round();

// Returns line thickness for the active (in-progress) stitch.
int _activeLineThickness(double cellSize) =>
    (cellSize * 0.11).clamp(3.0, 7.0).round();

void _drawSegment(
  img.Image image,
  StitchSegment seg, {
  required Map<StitchType, int> colors,
  required bool thick,
  required double cellSize,
}) {
  final argb = colors[seg.type] ?? 0xFF888888;
  final color =
      img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 255);
  final thickness = thick ? _activeLineThickness(cellSize) : _lineThickness(cellSize);

  if (seg.type == StitchType.backOne ||
      seg.type == StitchType.backTwo ||
      seg.type == StitchType.backThree) {
    _drawDashedLine(image, seg.x1, seg.y1, seg.x2, seg.y2, color,
        thickness: thickness, dashLen: 5.0, gapLen: 4.0);
  } else {
    _drawThreadLine(image, seg.x1, seg.y1, seg.x2, seg.y2, color, thickness);
  }
}

/// Draws a line with a perpendicular highlight stripe to simulate thread roundness.
void _drawThreadLine(
  img.Image image,
  double x1,
  double y1,
  double x2,
  double y2,
  img.ColorRgba8 color,
  int thickness,
) {
  img.drawLine(
    image,
    x1: x1.round(),
    y1: y1.round(),
    x2: x2.round(),
    y2: y2.round(),
    color: color,
    thickness: thickness,
    antialias: true,
  );

  // Highlight: lighter, thinner line offset perpendicularly (simulates a
  // rounded thread catching light from above).
  if (thickness >= 3) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > 0.001) {
      final px = -dy / dist;
      final py = dx / dist;
      final off = thickness * 0.22;
      final hr = (math.min(255.0, color.r + (255 - color.r) * 0.45)).round();
      final hg = (math.min(255.0, color.g + (255 - color.g) * 0.45)).round();
      final hb = (math.min(255.0, color.b + (255 - color.b) * 0.45)).round();
      img.drawLine(
        image,
        x1: (x1 + px * off).round(),
        y1: (y1 + py * off).round(),
        x2: (x2 + px * off).round(),
        y2: (y2 + py * off).round(),
        color: img.ColorRgba8(hr, hg, hb, 160),
        thickness: math.max(1, (thickness * 0.38).round()),
        antialias: true,
      );
    }
  }
}

/// Draws a dashed line between two pixel points.
void _drawDashedLine(
  img.Image image,
  double x1,
  double y1,
  double x2,
  double y2,
  img.Color color, {
  int thickness = 2,
  double dashLen = 8,
  double gapLen = 5,
}) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (dist < 0.001) return;
  final ux = dx / dist;
  final uy = dy / dist;
  var d = 0.0;
  var drawing = true;
  while (d < dist) {
    final segLen =
        drawing ? math.min(dashLen, dist - d) : math.min(gapLen, dist - d);
    if (drawing) {
      img.drawLine(
        image,
        x1: (x1 + ux * d).round(),
        y1: (y1 + uy * d).round(),
        x2: (x1 + ux * (d + segLen)).round(),
        y2: (y1 + uy * (d + segLen)).round(),
        color: color,
        thickness: thickness,
        antialias: true,
      );
    }
    d += segLen;
    drawing = !drawing;
  }
}

/// Canonical edge key: order-independent so A→B == B→A.
/// Coordinates are multiplied by 2 and rounded to handle half-pixel values.
String _segKey(StitchSegment seg) {
  final ax = (seg.x1 * 2).round();
  final ay = (seg.y1 * 2).round();
  final bx = (seg.x2 * 2).round();
  final by = (seg.y2 * 2).round();
  if (ax < bx || (ax == bx && ay <= by)) return '$ax,$ay,$bx,$by';
  return '$bx,$by,$ax,$ay';
}

/// Shifts co-linear segments by a small perpendicular offset each so that
/// all threads on the same line remain individually visible (mirrors UI).
List<StitchSegment> _applyLineOffsets(
    List<StitchSegment> segs, double strokeW) {
  final groups = <String, List<int>>{};
  for (var i = 0; i < segs.length; i++) {
    groups.putIfAbsent(_segKey(segs[i]), () => []).add(i);
  }

  if (groups.values.every((g) => g.length <= 1)) return segs;

  final result = List<StitchSegment>.from(segs);
  final step = strokeW * 1.6;

  for (final indices in groups.values) {
    if (indices.length <= 1) continue;
    final n = indices.length;
    final s0 = segs[indices[0]];
    final dx = s0.x2 - s0.x1;
    final dy = s0.y2 - s0.y1;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1e-6) continue;
    final perpX = -dy / dist;
    final perpY = dx / dist;

    for (var i = 0; i < n; i++) {
      final offset = (i - (n - 1) / 2.0) * step;
      final ox = perpX * offset;
      final oy = perpY * offset;
      final orig = segs[indices[i]];
      result[indices[i]] = StitchSegment(
        x1: orig.x1 + ox,
        y1: orig.y1 + oy,
        x2: orig.x2 + ox,
        y2: orig.y2 + oy,
        type: orig.type,
      );
    }
  }
  return result;
}
