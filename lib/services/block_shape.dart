import 'dart:ui' show Canvas, Paint, Path, Rect;

/// Polymorphic block shape for the render cache.
///
/// [RectShape] wraps an axis-aligned [Rect] and draws via [Canvas.drawRect]
/// (the GPU fast path for most stitches). [PathShape] wraps an arbitrary
/// [Path] (diagonal bands, triangles) and draws via [Canvas.drawPath].
///
/// [bounds] is pre-computed at construction time — viewport culling in the
/// painter uses it without per-frame recomputation.
sealed class BlockShape {
  /// Axis-aligned bounding box. Pre-computed; zero cost to access.
  Rect get bounds;

  /// Draw this shape onto [canvas] with [paint].
  void draw(Canvas canvas, Paint paint);
}

/// Axis-aligned rectangle — used by FullStitch, HalfCrossStitch, QuarterStitch.
class RectShape extends BlockShape {
  final Rect rect;
  RectShape(this.rect);

  @override
  Rect get bounds => rect;

  @override
  void draw(Canvas canvas, Paint paint) => canvas.drawRect(rect, paint);
}

/// Arbitrary path — used by HalfStitch (parallelogram), ThreeQuarterStitch (triangle).
class PathShape extends BlockShape {
  final Path path;
  final Rect _bounds;
  PathShape(this.path) : _bounds = path.getBounds();

  @override
  Rect get bounds => _bounds;

  @override
  void draw(Canvas canvas, Paint paint) => canvas.drawPath(path, paint);
}
