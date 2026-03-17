// Shared GIF rendering logic — used by both the CLI and the Flutter GIF exporter.
//
// No Flutter imports; only the `image` package and internal Dart models.

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
List<int> renderDemoGif({
  required PlannedAida aida,
  int fps = 12,
  double cellSize = 40,
  double padding = 20,
  Map<StitchType, int>? colorMap,
  int backgroundArgb = 0xFFFAF6F0,
}) {
  final bounds = computeGridBounds(aida, cellSize);
  final originX = padding - bounds.left;
  final originY = padding - bounds.top;
  final canvasWidth = (bounds.width + padding * 2).ceil();
  final canvasHeight = (bounds.height + padding * 2).ceil();
  final segments = resolveSegments(
    aida,
    cellSize: cellSize,
    originX: originX,
    originY: originY,
  );

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

  return img.encodeGif(animation, repeat: 0);
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

  // Completed stitches.
  for (var i = 0; i < completeCount && i < segments.length; i++) {
    _drawSegment(image, segments[i], colors: colors, thick: false);
  }

  // In-progress stitch: draw from start toward end at [subProgress].
  if (subProgress > 0 && completeCount < segments.length) {
    final seg = segments[completeCount];
    final argb = colors[seg.type] ?? 0xFF888888;
    final color =
        img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 255);
    final tipX = seg.x1 + (seg.x2 - seg.x1) * subProgress;
    final tipY = seg.y1 + (seg.y2 - seg.y1) * subProgress;

    img.drawLine(
      image,
      x1: seg.x1.round(),
      y1: seg.y1.round(),
      x2: tipX.round(),
      y2: tipY.round(),
      color: color,
      thickness: 3,
      antialias: true,
    );

    // Needle dot at the tip.
    img.fillCircle(
      image,
      x: tipX.round(),
      y: tipY.round(),
      radius: (cellSize * 0.08).clamp(3, 6).round(),
      color: img.ColorRgba8(232, 192, 32, 255), // golden needle
    );
  }

  return image;
}

void _drawSegment(
  img.Image image,
  StitchSegment seg, {
  required Map<StitchType, int> colors,
  required bool thick,
}) {
  final argb = colors[seg.type] ?? 0xFF888888;
  final color =
      img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 255);
  img.drawLine(
    image,
    x1: seg.x1.round(),
    y1: seg.y1.round(),
    x2: seg.x2.round(),
    y2: seg.y2.round(),
    color: color,
    thickness: thick ? 3 : 2,
    antialias: true,
  );
}
