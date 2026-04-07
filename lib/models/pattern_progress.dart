/// Tracks stitching progress for a pattern — which stitches and pages
/// the user has marked as completed.
///
/// Stored under `stitching.progress` in the v2 file format.
/// Not yet wired into [CrossStitchPattern]; placeholder for Phase 4.
class PatternProgress {
  /// Grid cells the user has marked as stitched, as (x, y) pairs.
  final Set<(int, int)> completedStitches;

  /// Page indices (0-based) the user has marked as fully complete.
  final Set<int> completedPages;

  const PatternProgress({
    this.completedStitches = const <(int, int)>{},
    this.completedPages = const <int>{},
  });

  static const empty = PatternProgress();

  bool get isEmpty => completedStitches.isEmpty && completedPages.isEmpty;

  factory PatternProgress.fromYaml(Map yaml) {
    final stitches = (yaml['completedStitches'] as List? ?? []).map((e) {
      final pair = e as List;
      return (pair[0] as int, pair[1] as int);
    }).toSet();
    final pages =
        (yaml['completedPages'] as List? ?? []).map((e) => e as int).toSet();
    return PatternProgress(completedStitches: stitches, completedPages: pages);
  }

  Map<String, dynamic> toYaml() => {
        'completedStitches':
            completedStitches.map((s) => [s.$1, s.$2]).toList(),
        'completedPages': completedPages.toList(),
      };
}
