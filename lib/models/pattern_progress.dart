import 'package:flutter/foundation.dart';
import 'stitch.dart';

@immutable
class PatternProgress {
  /// Cells the user has physically stitched. Stored as (x, y) pairs.
  final Set<(int, int)> completedStitches;

  /// Page indices (0-based) marked as fully done.
  final Set<int> completedPages;

  const PatternProgress({
    this.completedStitches = const {},
    this.completedPages = const {},
  });

  static const PatternProgress empty = PatternProgress();

  bool get isEmpty => completedStitches.isEmpty && completedPages.isEmpty;

  bool isStitchDone(int x, int y) => completedStitches.contains((x, y));
  bool isPageDone(int pageIndex) => completedPages.contains(pageIndex);

  /// True when every non-backstitch belonging to [threadId] is in completedStitches.
  bool isColourDone(String threadId, Iterable<Stitch> allStitches) {
    bool hasAny = false;
    for (final stitch in allStitches) {
      if (stitch.threadId != threadId) continue;
      if (stitch is BackStitch) continue;
      final coords = _stitchXY(stitch);
      if (coords == null) continue;
      hasAny = true;
      if (!completedStitches.contains(coords)) return false;
    }
    return hasAny;
  }

  PatternProgress copyWith({
    Set<(int, int)>? completedStitches,
    Set<int>? completedPages,
  }) =>
      PatternProgress(
        completedStitches: completedStitches ?? this.completedStitches,
        completedPages: completedPages ?? this.completedPages,
      );

  factory PatternProgress.fromYaml(Map yaml) {
    final stitches = <(int, int)>{};
    final rawStitches = yaml['completedStitches'] as List?;
    if (rawStitches != null) {
      for (final s in rawStitches) {
        final str = s.toString();
        final comma = str.indexOf(',');
        if (comma > 0) {
          final x = int.tryParse(str.substring(0, comma));
          final y = int.tryParse(str.substring(comma + 1));
          if (x != null && y != null) stitches.add((x, y));
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
    return PatternProgress(completedStitches: stitches, completedPages: pages);
  }

  Map<String, dynamic> toYaml() => {
        'completedStitches':
            completedStitches.map((c) => '${c.$1},${c.$2}').toList(),
        'completedPages': completedPages.toList()..sort(),
      };

  static (int, int)? _stitchXY(Stitch stitch) => switch (stitch) {
        FullStitch(:final x, :final y) => (x, y),
        HalfStitch(:final x, :final y) => (x, y),
        HalfCrossStitch(:final x, :final y) => (x, y),
        QuarterStitch(:final x, :final y) => (x, y),
        QuarterCrossStitch(:final x, :final y) => (x, y),
        BackStitch() => null,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternProgress &&
          setEquals(completedStitches, other.completedStitches) &&
          setEquals(completedPages, other.completedPages);

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(
          completedStitches.map((c) => Object.hash(c.$1, c.$2))),
      Object.hashAllUnordered(completedPages));
}
