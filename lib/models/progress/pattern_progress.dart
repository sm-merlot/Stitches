import 'package:flutter/foundation.dart';
import '../cell.dart';
import '../stitch/stitch.dart';
import '../stitch/stitch_geometry.dart';

@immutable
class PatternProgress {
  /// Cells the user has physically stitched. Stored as [Cell] objects.
  final Set<Cell> completedStitches;

  /// Backstitches the user has physically stitched.
  /// Stored as normalised (x1, y1, x2, y2) — the smaller endpoint is always first.
  final Set<(double, double, double, double)> completedBackstitches;

  /// Page indices (0-based) marked as fully done.
  final Set<int> completedPages;

  const PatternProgress({
    this.completedStitches = const {},
    this.completedBackstitches = const {},
    this.completedPages = const {},
  });

  static const PatternProgress empty = PatternProgress();

  bool get isEmpty =>
      completedStitches.isEmpty &&
      completedBackstitches.isEmpty &&
      completedPages.isEmpty;

  bool isStitchDone(int x, int y) => completedStitches.contains(Cell(x, y));
  bool isPageDone(int pageIndex) => completedPages.contains(pageIndex);

  bool isBackstitchDone(double x1, double y1, double x2, double y2) =>
      completedBackstitches.contains(normBackstitch(x1, y1, x2, y2));

  /// True when every non-backstitch belonging to [threadId] is in completedStitches.
  bool isColourDone(String threadId, Iterable<Stitch> allStitches) {
    bool hasAny = false;
    for (final stitch in allStitches) {
      if (stitch.threadId != threadId) continue;
      if (stitch is BackStitch) continue;
      final coords = stitchXY(stitch);
      if (coords == null) continue;
      hasAny = true;
      if (!completedStitches.contains(coords)) return false;
    }
    return hasAny;
  }

  PatternProgress copyWith({
    Set<Cell>? completedStitches,
    Set<(double, double, double, double)>? completedBackstitches,
    Set<int>? completedPages,
  }) =>
      PatternProgress(
        completedStitches: completedStitches ?? this.completedStitches,
        completedBackstitches:
            completedBackstitches ?? this.completedBackstitches,
        completedPages: completedPages ?? this.completedPages,
      );

  factory PatternProgress.fromYaml(Map yaml) {
    final stitches = <Cell>{};
    final rawStitches = yaml['completedStitches'] as List?;
    if (rawStitches != null) {
      for (final s in rawStitches) {
        final str = s.toString();
        final comma = str.indexOf(',');
        if (comma > 0) {
          final x = int.tryParse(str.substring(0, comma));
          final y = int.tryParse(str.substring(comma + 1));
          if (x != null && y != null) stitches.add(Cell(x, y));
        }
      }
    }
    final backstitches = <(double, double, double, double)>{};
    final rawBack = yaml['completedBackstitches'] as List?;
    if (rawBack != null) {
      for (final s in rawBack) {
        final parts = s.toString().split(',');
        if (parts.length == 4) {
          final x1 = double.tryParse(parts[0]);
          final y1 = double.tryParse(parts[1]);
          final x2 = double.tryParse(parts[2]);
          final y2 = double.tryParse(parts[3]);
          if (x1 != null && y1 != null && x2 != null && y2 != null) {
            backstitches.add(normBackstitch(x1, y1, x2, y2));
          }
        }
      }
    }
    final pages = <int>{};
    final rawPages = yaml['completedPages'] as List?;
    if (rawPages != null) {
      for (final p in rawPages) {
        final pi = p is int ? p : int.tryParse(p.toString());
        if (pi != null) pages.add(pi);
      }
    }
    return PatternProgress(
      completedStitches: stitches,
      completedBackstitches: backstitches,
      completedPages: pages,
    );
  }

  Map<String, dynamic> toYaml() => {
        'completedStitches':
            completedStitches.map((c) => '${c.x},${c.y}').toList(),
        if (completedBackstitches.isNotEmpty)
          'completedBackstitches': completedBackstitches
              .map((b) => '${_fmt(b.$1)},${_fmt(b.$2)},${_fmt(b.$3)},${_fmt(b.$4)}')
              .toList(),
        'completedPages': completedPages.toList()..sort(),
      };

  /// Normalise a backstitch key so the lexicographically smaller endpoint
  /// is always first — matches BackStitch's order-independent equality.
  static (double, double, double, double) normBackstitch(
      double x1, double y1, double x2, double y2) {
    if (x1 < x2 || (x1 == x2 && y1 <= y2)) {
      return (x1, y1, x2, y2);
    }
    return (x2, y2, x1, y1);
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternProgress &&
          setEquals(completedStitches, other.completedStitches) &&
          setEquals(completedBackstitches, other.completedBackstitches) &&
          setEquals(completedPages, other.completedPages);

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(
          completedStitches.map((c) => Object.hash(c.x, c.y))),
      Object.hashAllUnordered(completedBackstitches
          .map((b) => Object.hash(b.$1, b.$2, b.$3, b.$4))),
      Object.hashAllUnordered(completedPages));
}
