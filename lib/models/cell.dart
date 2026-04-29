import '../models/stitch.dart';
import '../models/stitch_geometry.dart';

/// A grid cell at integer coordinates [x],[y].
///
/// Used as a canonical key type throughout the codebase — replacing ad-hoc
/// `(int, int)` tuples and `'$x,$y'` string keys.
///
/// Implements value equality and a stable [hashCode] so instances are safe as
/// `Map` keys and `Set` elements.
class Cell {
  final int x;
  final int y;

  const Cell(this.x, this.y);

  /// Canonical string key `'x,y'`. Matches the format used in
  /// [CompositeLayer.fullStitches] and [RenderCache] internals.
  String get key => '$x,$y';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Cell && x == other.x && y == other.y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Cell($x, $y)';

  // ── Stitch hit testing ───────────────────────────────────────────────────────

  /// Returns true when [s] occupies cell ([x],[y]).
  ///
  /// For non-backstitch types, uses [Stitch.cellCoords].
  /// For [BackStitch], matches if either endpoint lies within the cell bounds.
  static bool hitStitch(Stitch s, int x, int y) {
    final coords = s.cellCoords;
    if (coords != null) return coords.x == x && coords.y == y;
    if (s is BackStitch) {
      bool inside(double gx, double gy) =>
          gx >= x && gx <= x + 1 && gy >= y && gy <= y + 1;
      return inside(s.x1, s.y1) || inside(s.x2, s.y2);
    }
    return false;
  }

  /// Returns true when [s] occupies any cell within the [size]×[size] box
  /// centred on ([cx],[cy]).
  static bool hitBox(Stitch s, int cx, int cy, int size) {
    final half = (size - 1) ~/ 2;
    final x0 = cx - half;
    final x1 = cx + (size - 1 - half);
    final y0 = cy - half;
    final y1 = cy + (size - 1 - half);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        if (hitStitch(s, x, y)) return true;
      }
    }
    return false;
  }
}
