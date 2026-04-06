part of 'editor_provider.dart';

// ─── ProgressMixin ────────────────────────────────────────────────────────────
//
// Stitch progress tracking: toggle done, region mark, flood fill, page toggle.

mixin ProgressMixin on Notifier<EditorState> {

  List<(CrossStitchPattern, List<SnippetPalette>)> _buildUndoStack();

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Toggle a single cell done/undone.
  void toggleStitchDone(int x, int y) {
    final prog = state.pattern.progress;
    final cell = (x, y);
    final current = prog.completedStitches;
    Set<(int, int)> next;
    if (current.contains(cell)) {
      next = {...current}..remove(cell);
    } else {
      // Only mark if there is actually a stitch here.
      final hasStitch = _hasCrossStitchAt(x, y);
      if (!hasStitch) return;
      next = {...current, cell};
    }
    final newProg = prog.copyWith(completedStitches: next);
    _applyProgress(newProg, pushUndo: true);
    _checkColourCompletion(newProg, _threadIdsAt(x, y));
    _checkPageCompletion(newProg);
  }

  /// Mark all stitches within [region] (cell coords) as done.
  /// Does not un-mark already-completed stitches.
  /// In page mode, only stitches on the current page are affected.
  void markRegionDone(Rect region) {
    final prog = state.pattern.progress;
    final current = Set<(int, int)>.from(prog.completedStitches);
    final affectedThreads = <String>{};
    final layout = state.pageLayout;
    final (pageCol, pageRow) = layout != null ? layout.pageCoords(state.currentPage) : (0, 0);
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == null) continue;
        final (sx, sy) = coords;
        if (sx >= region.left && sx < region.right &&
            sy >= region.top && sy < region.bottom) {
          if (layout != null && !layout.cellOnPage(sx, sy, pageCol, pageRow)) continue;
          current.add((sx, sy));
          affectedThreads.add(stitch.threadId);
        }
      }
    }
    if (current.length == prog.completedStitches.length) return;
    final newProg = prog.copyWith(completedStitches: current);
    _applyProgress(newProg, pushUndo: true);
    _checkColourCompletion(newProg, affectedThreads);
    _checkPageCompletion(newProg);
  }

  /// Flood-fill: mark all orthogonally connected stitches of the same thread
  /// starting from (x, y) as done — or as NOT done if the starting cell is
  /// already done. This makes double-click bidirectional:
  /// - tap a done cell: flood fill un-marks the connected region
  /// - tap an undone cell: flood fill marks the connected region done
  void floodFillDone(int x, int y) {
    final prog = state.pattern.progress;
    final startIsDone = prog.completedStitches.contains((x, y));

    // Find the thread at this cell.
    String? threadId;
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == null) continue;
        if (coords.$1 == x && coords.$2 == y) {
          threadId = stitch.threadId;
          break;
        }
      }
      if (threadId != null) break;
    }
    if (threadId == null) return;

    // Build cell → threadId lookup for all visible non-back stitches.
    final cellThread = <(int, int), String>{};
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords != null) cellThread[coords] = stitch.threadId;
      }
    }

    // BFS flood fill — orthogonal, same thread only.
    final queue = <(int, int)>[(x, y)];
    final visited = <(int, int)>{};
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      if (visited.contains(cell)) continue;
      visited.add(cell);
      if (cellThread[cell] != threadId) continue;
      final (cx, cy) = cell;
      for (final n in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]) {
        if (!visited.contains(n) && cellThread.containsKey(n)) queue.add(n);
      }
    }

    if (startIsDone) {
      // Un-mark mode: remove all visited cells from completedStitches.
      final newCompleted = Set<(int, int)>.from(prog.completedStitches)
        ..removeAll(visited);
      if (newCompleted.length == prog.completedStitches.length) return;
      _applyProgress(prog.copyWith(completedStitches: newCompleted), pushUndo: true);
    } else {
      // Mark done mode: add all visited cells to completedStitches.
      final newCompleted = Set<(int, int)>.from(prog.completedStitches)
        ..addAll(visited);
      if (newCompleted.length == prog.completedStitches.length) return;
      final newProg = prog.copyWith(completedStitches: newCompleted);
      _applyProgress(newProg, pushUndo: true);
      _checkColourCompletion(newProg, {threadId});
      _checkPageCompletion(newProg);
    }
  }

  /// Mark all stitches within [region] (cell coords) as NOT done.
  /// In page mode, only stitches on the current page are affected.
  void markRegionNotDone(Rect region) {
    final prog = state.pattern.progress;
    final current = Set<(int, int)>.from(prog.completedStitches);
    int removed = 0;
    final layout = state.pageLayout;
    final (pageCol, pageRow) = layout != null ? layout.pageCoords(state.currentPage) : (0, 0);
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == null) continue;
        final (sx, sy) = coords;
        if (sx >= region.left && sx < region.right &&
            sy >= region.top && sy < region.bottom) {
          if (layout != null && !layout.cellOnPage(sx, sy, pageCol, pageRow)) continue;
          if (current.remove((sx, sy))) removed++;
        }
      }
    }
    if (removed == 0) return;
    _applyProgress(prog.copyWith(completedStitches: current), pushUndo: true);
  }

  /// Manually toggle a page's done state.
  void togglePageDone(int pageIndex) {
    final prog = state.pattern.progress;
    final pages = Set<int>.from(prog.completedPages);
    if (pages.contains(pageIndex)) {
      pages.remove(pageIndex);
    } else {
      pages.add(pageIndex);
    }
    _applyProgress(prog.copyWith(completedPages: pages), pushUndo: false);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  void _applyProgress(PatternProgress progress, {required bool pushUndo}) {
    final newPattern = state.pattern.copyWith(progress: progress);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: pushUndo ? _buildUndoStack() : null,
      redoStack: pushUndo ? [] : null,
      isDirty: true,
    );
  }

  bool _hasCrossStitchAt(int x, int y) {
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords != null && coords.$1 == x && coords.$2 == y) return true;
      }
    }
    return false;
  }

  Set<String> _threadIdsAt(int x, int y) {
    final ids = <String>{};
    for (final layer in state.pattern.layers) {
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords != null && coords.$1 == x && coords.$2 == y) {
          ids.add(stitch.threadId);
        }
      }
    }
    return ids;
  }

  static (int, int)? _crossStitchXY(Stitch stitch) => switch (stitch) {
        FullStitch(:final x, :final y) => (x, y),
        HalfStitch(:final x, :final y) => (x, y),
        HalfCrossStitch(:final x, :final y) => (x, y),
        QuarterStitch(:final x, :final y) => (x, y),
        QuarterCrossStitch(:final x, :final y) => (x, y),
        BackStitch() => null,
      };

  void _checkColourCompletion(PatternProgress prog, Set<String> threadIds) {
    final allStitches = state.pattern.stitches;
    for (final threadId in threadIds) {
      if (prog.isColourDone(threadId, allStitches)) {
        final thread = state.pattern.threads.where((t) => t.dmcCode == threadId).firstOrNull;
        if (thread != null) {
          state = state.copyWith(
            pendingCanvasWarning: '${thread.dmcCode} ${thread.name} complete ✓',
          );
        }
      }
    }
  }

  void _checkPageCompletion(PatternProgress prog) {
    final layout = state.pageLayout;
    if (layout == null) return;
    final pages = Set<int>.from(prog.completedPages);
    bool changed = false;
    for (int p = 0; p < layout.totalPages; p++) {
      if (pages.contains(p)) continue;
      // Check all stitches on this page.
      final (pageCol, pageRow) = layout.pageCoords(p);
      bool allDone = true;
      bool hasAny = false;
      for (final layer in state.pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          final coords = _crossStitchXY(stitch);
          if (coords == null) continue;
          if (!layout.cellOnPage(coords.$1, coords.$2, pageCol, pageRow)) continue;
          hasAny = true;
          if (!prog.completedStitches.contains(coords)) { allDone = false; break; }
        }
        if (!allDone) break;
      }
      if (hasAny && allDone) { pages.add(p); changed = true; }
    }
    if (changed) {
      final newProg = prog.copyWith(completedPages: pages);
      state = state.copyWith(
        pattern: state.pattern.copyWith(progress: newProg),
      );
    }
  }
}
