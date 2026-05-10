part of 'editor_provider.dart';

// ─── StitchSessionState ───────────────────────────────────────────────────────

/// Session state for stitch mode.
class StitchSessionState {
  /// Cross: hides backstitches, normal stitches shown in colour.
  final bool crossMode;

  /// Back: greys normal stitches, backstitches shown in colour.
  final bool backMode;

  /// When non-null, only the focused thread is highlighted in stitch mode.
  final String? focusThreadId;

  /// When true and page mode is active, the stitch-mode colour list shows only
  /// threads present on the current page. Defaults to true (page colours).
  final bool showPageColours;

  /// Current page index (0-based) in page mode. Session-only, not persisted.
  final int currentPage;

  /// Precomputed page layout. Non-null when page mode is enabled.
  final PageLayout? pageLayout;

  /// When non-null, AidaWidget should animate to fit this page index then
  /// clear the value via [clearPendingFitPage].
  final int? pendingFitPage;

  /// The committed progress-marking region in stitch mode (cell coordinates).
  /// Set when the user finishes a drag-to-select on the canvas. Shown as a
  /// dashed overlay and drives the "Mark done / Mark not done" sidebar button.
  /// Cleared when leaving stitch mode or starting a new drag.
  final Rect? progressRegion;

  const StitchSessionState({
    this.crossMode = false,
    this.backMode = false,
    this.focusThreadId,
    this.showPageColours = true,
    this.currentPage = 0,
    this.pageLayout,
    this.pendingFitPage,
    this.progressRegion,
  });

  static const _sentinel = Object();

  StitchSessionState copyWith({
    bool? crossMode,
    bool? backMode,
    Object? focusThreadId = _sentinel,
    bool? showPageColours,
    int? currentPage,
    Object? pageLayout = _sentinel,
    Object? pendingFitPage = _sentinel,
    Object? progressRegion = _sentinel,
  }) =>
      StitchSessionState(
        crossMode: crossMode ?? this.crossMode,
        backMode: backMode ?? this.backMode,
        focusThreadId: focusThreadId == _sentinel
            ? this.focusThreadId
            : focusThreadId as String?,
        showPageColours: showPageColours ?? this.showPageColours,
        currentPage: currentPage ?? this.currentPage,
        pageLayout:
            pageLayout == _sentinel ? this.pageLayout : pageLayout as PageLayout?,
        pendingFitPage: pendingFitPage == _sentinel
            ? this.pendingFitPage
            : pendingFitPage as int?,
        progressRegion: progressRegion == _sentinel
            ? this.progressRegion
            : progressRegion as Rect?,
      );
}
