part of 'editor_provider.dart';

// ─── ProgressMixin ────────────────────────────────────────────────────────────
//
// Stitch progress tracking: toggle done, region mark, flood fill, page toggle.

mixin ProgressMixin on Notifier<EditorState> {

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Toggle a single cell done/undone.
  void toggleStitchDone(int x, int y) {
    // Backstitch focus mode: cross-stitch marking blocked.
    if (state.stitchBackMode) return;
    // In focus mode, only interact with cells whose topmost thread matches.
    final focusId = state.stitchFocusThreadId;
    if (focusId != null && _topThreadAt(x, y) != focusId) return;

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
      // In page mode, only mark cells on the current page.
      final layout = state.pageLayout;
      if (layout != null) {
        final (pageCol, pageRow) = layout.pageCoords(state.currentPage);
        if (!layout.cellOnPage(x, y, pageCol, pageRow)) return;
      }
      next = {...current, cell};
    }
    final newProg = prog.copyWith(completedStitches: next);
    _applyProgress(newProg, pushUndo: true);
    _checkColourCompletion(newProg, _threadIdsAt(x, y));
    _checkPageCompletion(newProg);
  }

  /// Toggle a single backstitch done/undone.
  void toggleBackstitchDone(double x1, double y1, double x2, double y2) {
    // Cross-stitch focus mode: backstitch marking blocked.
    if (state.stitchCrossMode) return;
    // Focus mode guard.
    final focusId = state.stitchFocusThreadId;
    if (focusId != null) {
      final thread = _backstitchThreadAt(x1, y1, x2, y2);
      if (thread == null || thread != focusId) return;
    }
    // Page mode guard — backstitch must lie on the current page.
    final layout = state.pageLayout;
    if (layout != null) {
      final mid = ((x1 + x2) / 2, (y1 + y2) / 2);
      final (pageCol, pageRow) = layout.pageCoords(state.currentPage);
      if (!layout.cellOnPage(mid.$1.floor(), mid.$2.floor(), pageCol, pageRow)) return;
    }
    final prog = state.pattern.progress;
    final key = PatternProgress.normBackstitch(x1, y1, x2, y2);
    final current = prog.completedBackstitches;
    final next = current.contains(key)
        ? ({...current}..remove(key))
        : {...current, key};
    _applyProgress(prog.copyWith(completedBackstitches: next), pushUndo: true);
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
    final focusId = state.stitchFocusThreadId;
    if (!state.stitchBackMode) {
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        if (focusId != null && stitch.threadId != focusId) continue;
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
    }
    // Backstitches — include if midpoint is within region (and on current page).
    final backCurrent = Set<(double, double, double, double)>.from(
        prog.completedBackstitches);
    if (!state.stitchCrossMode) {
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! BackStitch) continue;
        if (focusId != null && stitch.threadId != focusId) continue;
        final midX = (stitch.x1 + stitch.x2) / 2;
        final midY = (stitch.y1 + stitch.y2) / 2;
        if (midX >= region.left && midX < region.right &&
            midY >= region.top && midY < region.bottom) {
          if (layout != null &&
              !layout.cellOnPage(
                  midX.floor(), midY.floor(), pageCol, pageRow)) { continue; }
          backCurrent.add(PatternProgress.normBackstitch(
              stitch.x1, stitch.y1, stitch.x2, stitch.y2));
        }
      }
    }
    }
    if (current.length == prog.completedStitches.length &&
        backCurrent.length == prog.completedBackstitches.length) { return; }
    final newProg = prog.copyWith(
        completedStitches: current, completedBackstitches: backCurrent);
    _applyProgress(newProg, pushUndo: true);
    _checkColourCompletion(newProg, affectedThreads);
    _checkPageCompletion(newProg);
  }

  /// Flood-fill: mark all orthogonally connected stitches of the same thread
  /// starting from (x, y) as done — or as NOT done if the starting cell is
  /// already done. This makes double-click bidirectional:
  /// - tap a done cell: flood fill un-marks the connected region
  /// - tap an undone cell: flood fill marks the connected region done
  ///
  /// [originalStartIsDone] overrides the current cell state for direction
  /// detection. Pass this when the cell may have been toggled by a single-click
  /// immediately before this flood fill (e.g., on double-click).
  /// [afterSingleTap] — when true, flood fill follows a single-tap toggle on
  /// the same cell (double-click). The single-tap already pushed an undo entry,
  /// so flood fill squashes into it rather than adding a second entry.
  void floodFillDone(int x, int y,
      {bool? originalStartIsDone, bool afterSingleTap = false}) {
    // Backstitch focus mode: flood fill only applies to cross-stitches.
    if (state.stitchBackMode) return;
    final prog = state.pattern.progress;
    final startIsDone = originalStartIsDone ?? prog.completedStitches.contains((x, y));

    // Build a map of cell → topmost visible thread by iterating layers in
    // render order (later layers paint on top, so last write wins).
    // This matches exactly what the user sees on the composite canvas.
    final topThread = <(int, int), String>{};
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords != null) topThread[coords] = stitch.threadId;
      }
    }

    // The thread that is visually on top at the starting cell.
    final threadId = topThread[(x, y)];
    if (threadId == null) return;

    // In focus mode, only flood-fill if the starting cell matches the focus thread.
    final focusId = state.stitchFocusThreadId;
    if (focusId != null && threadId != focusId) return;

    // In page mode, constrain flood fill to the current page.
    final layout = state.pageLayout;
    final (pageCol, pageRow) =
        layout != null ? layout.pageCoords(state.currentPage) : (0, 0);

    // BFS flood fill — 8-directional (sides + diagonals).
    // Only traverse cells where the same thread is the topmost visible stitch.
    // In page mode, also restrict to cells on the current page.
    final queue = <(int, int)>[(x, y)];
    final visited = <(int, int)>{};
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      if (visited.contains(cell)) continue;
      if (topThread[cell] != threadId) continue;
      if (layout != null && !layout.cellOnPage(cell.$1, cell.$2, pageCol, pageRow)) continue;
      visited.add(cell);
      final (cx, cy) = cell;
      for (final n in [
        (cx - 1, cy - 1), (cx, cy - 1), (cx + 1, cy - 1),
        (cx - 1, cy),                   (cx + 1, cy),
        (cx - 1, cy + 1), (cx, cy + 1), (cx + 1, cy + 1),
      ]) {
        if (!visited.contains(n) && topThread[n] == threadId) queue.add(n);
      }
    }

    if (startIsDone) {
      // Un-mark mode: remove all visited cells from completedStitches.
      final newCompleted = Set<(int, int)>.from(prog.completedStitches)
        ..removeAll(visited);
      if (newCompleted.length == prog.completedStitches.length) return;
      final newProg = prog.copyWith(completedStitches: newCompleted);
      _applyProgress(newProg, pushUndo: !afterSingleTap, squashPrev: afterSingleTap);
      _checkPageCompletion(newProg);
    } else {
      // Mark done mode: add all visited cells to completedStitches.
      final newCompleted = Set<(int, int)>.from(prog.completedStitches)
        ..addAll(visited);
      if (newCompleted.length == prog.completedStitches.length) return;
      final newProg = prog.copyWith(completedStitches: newCompleted);
      _applyProgress(newProg, pushUndo: !afterSingleTap, squashPrev: afterSingleTap);
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
    final focusId = state.stitchFocusThreadId;
    if (!state.stitchBackMode) {
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        if (focusId != null && stitch.threadId != focusId) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == null) continue;
        final (sx, sy) = coords;
        if (sx >= region.left && sx < region.right &&
            sy >= region.top && sy < region.bottom) {
          if (layout != null && !layout.cellOnPage(sx, sy, pageCol, pageRow)) continue;
          if (current.remove((sx, sy))) { removed++; }
        }
      }
    }
    }
    // Backstitches in region.
    final backCurrent = Set<(double, double, double, double)>.from(
        prog.completedBackstitches);
    if (!state.stitchCrossMode) {
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! BackStitch) continue;
        if (focusId != null && stitch.threadId != focusId) continue;
        final midX = (stitch.x1 + stitch.x2) / 2;
        final midY = (stitch.y1 + stitch.y2) / 2;
        if (midX >= region.left && midX < region.right &&
            midY >= region.top && midY < region.bottom) {
          if (layout != null &&
              !layout.cellOnPage(
                  midX.floor(), midY.floor(), pageCol, pageRow)) { continue; }
          if (backCurrent.remove(PatternProgress.normBackstitch(
              stitch.x1, stitch.y1, stitch.x2, stitch.y2))) { removed++; }
        }
      }
    }
    }
    if (removed == 0) return;
    final newProg = prog.copyWith(
        completedStitches: current, completedBackstitches: backCurrent);
    _applyProgress(newProg, pushUndo: true);
    _checkPageCompletion(newProg);
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

  /// Clear all progress (completed stitches and pages). Undoable.
  void clearProgress() {
    if (state.pattern.progress == PatternProgress.empty) return;
    _applyProgress(PatternProgress.empty, pushUndo: true);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  static const int _maxProgressUndoDepth = 100;

  /// [pushUndo] — push current progress onto the undo stack before applying.
  /// [squashPrev] — replace the previous undo entry rather than adding a new
  ///   one. Used by flood fill when it immediately follows a single-tap toggle
  ///   so the two operations appear as one undo step.
  void _applyProgress(PatternProgress progress,
      {required bool pushUndo, bool squashPrev = false}) {
    final newPattern = state.pattern.copyWith(progress: progress);
    if (pushUndo) {
      final newUndoStack = [
        ...state._progressUndoStack,
        state.pattern.progress,
      ];
      if (newUndoStack.length > _maxProgressUndoDepth) {
        newUndoStack.removeAt(0);
      }
      state = state.copyWith(
        pattern: newPattern,
        progressUndoStack: newUndoStack,
        progressRedoStack: [],
        isDirty: true,
      );
    } else if (squashPrev) {
      // The last undo entry already has the pre-single-tap state — just apply
      // the new progress without adding another entry.
      state = state.copyWith(
        pattern: newPattern,
        progressRedoStack: [],
        isDirty: true,
      );
    } else {
      state = state.copyWith(
        pattern: newPattern,
        isDirty: true,
      );
    }
  }

  void undoProgress() {
    if (!state.canUndoProgress) return;
    final stack = List<PatternProgress>.from(state._progressUndoStack);
    final prev = stack.removeLast();
    final redoStack = [...state._progressRedoStack, state.pattern.progress];
    state = state.copyWith(
      pattern: state.pattern.copyWith(progress: prev),
      progressUndoStack: stack,
      progressRedoStack: redoStack,
      isDirty: true,
    );
  }

  void redoProgress() {
    if (!state.canRedoProgress) return;
    final stack = List<PatternProgress>.from(state._progressRedoStack);
    final next = stack.removeLast();
    final undoStack = [...state._progressUndoStack, state.pattern.progress];
    state = state.copyWith(
      pattern: state.pattern.copyWith(progress: next),
      progressUndoStack: undoStack,
      progressRedoStack: stack,
      isDirty: true,
    );
  }

  /// Returns the threadId of the backstitch with the given endpoints, or null
  /// if no visible backstitch matches. Order-independent (matches BackStitch equality).
  String? _backstitchThreadAt(double x1, double y1, double x2, double y2) {
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! BackStitch) continue;
        if ((stitch.x1 == x1 && stitch.y1 == y1 &&
                stitch.x2 == x2 && stitch.y2 == y2) ||
            (stitch.x1 == x2 && stitch.y1 == y2 &&
                stitch.x2 == x1 && stitch.y2 == y1)) {
          return stitch.threadId;
        }
      }
    }
    return null;
  }

  /// Returns the threadId of the topmost visible non-backstitch at (x, y),
  /// matching what the user sees on the composite canvas. Null if no stitch.
  String? _topThreadAt(int x, int y) {
    String? result;
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords != null && coords.$1 == x && coords.$2 == y) {
          result = stitch.threadId; // last write wins = topmost layer
        }
      }
    }
    return result;
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
      final wasComplete = pages.contains(p);
      final (pageCol, pageRow) = layout.pageCoords(p);
      bool allDone = true;
      bool hasAny = false;
      for (final layer in state.pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) {
            final midX = (stitch.x1 + stitch.x2) / 2;
            final midY = (stitch.y1 + stitch.y2) / 2;
            if (!layout.cellOnPage(midX.floor(), midY.floor(), pageCol, pageRow)) continue;
            hasAny = true;
            final key = PatternProgress.normBackstitch(
                stitch.x1, stitch.y1, stitch.x2, stitch.y2);
            if (!prog.completedBackstitches.contains(key)) { allDone = false; break; }
          } else {
            final coords = _crossStitchXY(stitch);
            if (coords == null) continue;
            if (!layout.cellOnPage(coords.$1, coords.$2, pageCol, pageRow)) continue;
            hasAny = true;
            if (!prog.completedStitches.contains(coords)) { allDone = false; break; }
          }
        }
        if (!allDone) break;
      }
      final nowComplete = hasAny && allDone;
      if (nowComplete && !wasComplete) { pages.add(p); changed = true; }
      else if (!nowComplete && wasComplete) { pages.remove(p); changed = true; }
    }
    if (changed) {
      final newProg = prog.copyWith(completedPages: pages);
      state = state.copyWith(
        pattern: state.pattern.copyWith(progress: newProg),
      );
    }
  }
}
