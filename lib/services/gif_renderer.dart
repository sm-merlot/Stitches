// Shared GIF rendering logic — used by both the CLI and the Flutter GIF exporter.
//
// No Flutter imports; only the `image` package and internal Dart models.

import 'package:image/image.dart' as img;

import '../models/stitch_plan.dart';
import 'stitch_renderer.dart';

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

/// Renders one animation frame as an [img.Image].
img.Image renderDemoFrame({
  required PlannedAida aida,
  required List<StitchSegment> segments,
  required int currentStep,
  required int width,
  required int height,
  required double cellSize,
  required double originX,
  required double originY,
  Map<StitchType, int>? colorMap,
  int backgroundArgb = 0xFFFAF6F0,
}) {
  final colors = colorMap ?? stitchTypeArgb;
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
  for (var i = 0; i < currentStep && i < segments.length; i++) {
    _drawSegment(image, segments[i], thick: false, colors: colors);
  }

  // Current stitch — highlighted.
  if (currentStep > 0 && currentStep <= segments.length) {
    _drawSegment(image, segments[currentStep - 1], thick: true, colors: colors);
  }

  return image;
}

/// Renders a full GIF animation and returns the encoded bytes.
///
/// [cellSize] is pixels per grid cell (default 40).
/// [padding] is pixels around the pattern edges (default 20).
/// [fps] controls animation speed.
/// [colorMap] overrides the default educational-palette colours.
List<int> renderDemoGif({
  required PlannedAida aida,
  int fps = 8,
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
  const holdFrames = 8;

  img.Image? animation;
  for (var step = 0; step <= segments.length; step++) {
    final frame = renderDemoFrame(
      aida: aida,
      segments: segments,
      currentStep: step,
      width: canvasWidth,
      height: canvasHeight,
      cellSize: cellSize,
      originX: originX,
      originY: originY,
      colorMap: colorMap,
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

void _drawSegment(
  img.Image image,
  StitchSegment seg, {
  required bool thick,
  required Map<StitchType, int> colors,
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
