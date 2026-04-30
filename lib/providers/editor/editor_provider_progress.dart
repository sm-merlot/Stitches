part of 'editor_provider.dart';

// ─── ProgressMixin ────────────────────────────────────────────────────────────
//
// Stitch progress tracking: toggle done, region mark, flood fill, page toggle.

mixin ProgressMixin on Notifier<EditorState> {
  // Abstract — implemented by EditorNotifier to route through the active
  // controller delegate. Called by [_applyProgress] when [pushUndo] is true
  // so that direct-from-UI mutations (markRegion, clearProgress) get an undo
  // entry in the controller's UndoManager. Toggle/floodFill callbacks are
  // wrapped by the controller itself and call with [pushUndo: false].
  void _pushProgressSnapshot(PatternProgress before, PatternProgress after);
  // ─── StitchOps log helpers ─────────────────────────────────────────────────

  /// Updates the pattern-level [progressLog] with today's actual cumulative
  /// count.
  ///
  /// Called from [_applyProgress] so every stitch-marking action (including
  /// frogging) is reflected in the log.  Because the log lives on the pattern
  /// (not inside [PatternProgress]), it is never rolled back by undo/redo.
  ///
  /// The entry always stores the real current count, not a high-watermark.
  /// If the count returns to the same value it was at the end of yesterday,
  /// today's entry is removed (no net change for the day).
  List<ProgressLogEntry> _updatedLog(PatternProgress newProgress) {
    final today = todayIsoDate();
    final newCount = newProgress.completedStitches.length;
    final newBackCount = newProgress.completedBackstitches.length;

    // Find the cumulative baseline at the end of yesterday: the most recent
    // log entry dated before today (log may be unsorted, so iterate all).
    ProgressLogEntry? prevEntry;
    for (final e in state.pattern.progressLog) {
      if (e.isoDate.compareTo(today) < 0) {
        if (prevEntry == null || e.isoDate.compareTo(prevEntry.isoDate) > 0) {
          prevEntry = e;
        }
      }
    }
    final prevCount = prevEntry?.stitchCount ?? 0;
    final prevBackCount = prevEntry?.backstitchCount ?? 0;

    // If today's net change is zero (count returned to yesterday's baseline),
    // remove today's entry — unless it has timer minutes, in which case keep
    // it (it still records how long the user stitched today).
    final existing = state.pattern.progressLog
        .where((e) => e.isoDate == today)
        .firstOrNull;
    if (newCount == prevCount && newBackCount == prevBackCount) {
      if (existing == null) return state.pattern.progressLog;
      if (existing.minutesSpent == 0) {
        // Purely a stitch-count entry with no net change — discard.
        return state.pattern.progressLog
            .where((e) => e.isoDate != today)
            .toList();
      }
      // Timer minutes present — keep entry, just sync the stitch counts.
      if (existing.stitchCount == newCount &&
          existing.backstitchCount == newBackCount) {
        return state.pattern.progressLog; // already in sync
      }
      return [
        ...state.pattern.progressLog.where((e) => e.isoDate != today),
        existing.copyWith(stitchCount: newCount, backstitchCount: newBackCount),
      ];
    }

    // Write the actual current count (may be lower than a previous today
    // entry if stitches were frogged since the last save).
    if (existing != null &&
        existing.stitchCount == newCount &&
        existing.backstitchCount == newBackCount) {
      return state.pattern.progressLog; // no change
    }
    final existingMinutes = existing?.minutesSpent ?? 0;
    return [
      ...state.pattern.progressLog.where((e) => e.isoDate != today),
      ProgressLogEntry(
        isoDate: today,
        stitchCount: newCount,
        backstitchCount: newBackCount,
        minutesSpent: existingMinutes,
      ),
    ];
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Toggle a single cell done/undone.
  void toggleStitchDone(int x, int y) {
    // Backstitch focus mode: cross-stitch marking blocked.
    if (state.stitchSession.backMode) return;
    // In focus mode, only interact with cells whose topmost thread matches.
    final focusId = state.stitchSession.focusThreadId;
    if (focusId != null && _topThreadAt(x, y) != focusId) return;

    final prog = state.pattern.progress;
    final cell = Cell(x, y);
    final current = prog.completedStitches;
    Set<Cell> next;
    if (current.contains(cell)) {
      next = {...current}..remove(cell);
    } else {
      // Only mark if there is actually a stitch here.
      final hasStitch = _hasCrossStitchAt(x, y);
      if (!hasStitch) return;
      // In page mode, only mark cells on the current page.
      final layout = state.stitchSession.pageLayout;
      if (layout != null) {
        final (pageCol, pageRow) = layout.pageCoords(state.stitchSession.currentPage);
        if (!layout.rawCellOnPage(x, y, pageCol, pageRow)) return;
      }
      next = {...current, cell};
    }
    final newProg = prog.copyWith(completedStitches: next);
    _applyProgress(newProg);
    _checkColourCompletion(newProg, _threadIdsAt(x, y));
    _checkPageCompletion(newProg);
  }

  /// Toggle a single backstitch done/undone.
  void toggleBackstitchDone(double x1, double y1, double x2, double y2) {
    // Cross-stitch focus mode: backstitch marking blocked.
    if (state.stitchSession.crossMode) return;
    // Focus mode guard.
    final focusId = state.stitchSession.focusThreadId;
    if (focusId != null) {
      final thread = _backstitchThreadAt(x1, y1, x2, y2);
      if (thread == null || thread != focusId) return;
    }
    // Page mode guard — backstitch must lie on the current page.
    final layout = state.stitchSession.pageLayout;
    if (layout != null) {
      final mid = ((x1 + x2) / 2, (y1 + y2) / 2);
      final (pageCol, pageRow) = layout.pageCoords(state.stitchSession.currentPage);
      if (!layout.rawCellOnPage(mid.$1.floor(), mid.$2.floor(), pageCol, pageRow)) return;
    }
    final prog = state.pattern.progress;
    final key = PatternProgress.normBackstitch(x1, y1, x2, y2);
    final current = prog.completedBackstitches;
    final next = current.contains(key)
        ? ({...current}..remove(key))
        : {...current, key};
    _applyProgress(prog.copyWith(completedBackstitches: next));
  }

  /// Mark all stitches within [region] (cell coords) as done.
  /// Does not un-mark already-completed stitches.
  /// In page mode, only stitches on the current page are affected.
  void markRegionDone(Rect region) {
    final prog = state.pattern.progress;
    final current = Set<Cell>.from(prog.completedStitches);
    final affectedThreads = <String>{};
    final layout = state.stitchSession.pageLayout;
    final (pageCol, pageRow) = layout != null ? layout.pageCoords(state.stitchSession.currentPage) : (0, 0);
    final focusId = state.stitchSession.focusThreadId;
    if (!state.stitchSession.backMode) {
    // Build topmost-thread map from compositeLayer so focus mode matches
    // single-tap behaviour, including composite/blended cells.
    final topThread = <Cell, String>{};
    final composite = state.compositeLayer;
    if (composite != null) {
      for (final e in composite.fullStitches.entries) {
        topThread[e.key] = e.value.resolvedThread.dmcCode;
      }
      for (final cs in composite.otherStitches) {
        final cell = cs.stitch.cellCoords;
        if (cell != null) topThread[cell] = cs.resolvedThread.dmcCode;
      }
    } else {
      // Fallback: raw layer scan when composite not yet available.
      for (final layer in state.pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          final coords = _crossStitchXY(stitch);
          if (coords != null) topThread[coords] = stitch.threadId;
        }
      }
    }
    for (final entry in topThread.entries) {
      final coords = entry.key;
      final threadId = entry.value;
      // In focus mode, only mark cells where the focused thread is on top.
      if (focusId != null && threadId != focusId) continue;
      final sx = coords.x;
      final sy = coords.y;
      if (sx >= region.left && sx < region.right &&
          sy >= region.top && sy < region.bottom) {
        if (layout != null && !layout.rawCellOnPage(sx, sy, pageCol, pageRow)) continue;
        current.add(coords);
        affectedThreads.add(threadId);
      }
    }
    }
    // Backstitches — include if midpoint is within region (and on current page).
    final backCurrent = Set<(double, double, double, double)>.from(
        prog.completedBackstitches);
    if (!state.stitchSession.crossMode) {
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
              !layout.rawCellOnPage(
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
    if (state.stitchSession.backMode) return;
    final prog = state.pattern.progress;
    final startIsDone = originalStartIsDone ?? prog.completedStitches.contains(Cell(x, y));

    // Build a map of cell → topmost visible thread from the composite layer.
    // This matches exactly what the user sees (including blended/composite cells).
    final topThread = <Cell, String>{};
    final composite = state.compositeLayer;
    if (composite != null) {
      for (final e in composite.fullStitches.entries) {
        topThread[e.key] = e.value.resolvedThread.dmcCode;
      }
      for (final cs in composite.otherStitches) {
        final cell = cs.stitch.cellCoords;
        if (cell != null) topThread[cell] = cs.resolvedThread.dmcCode;
      }
    } else {
      // Fallback: raw layer scan when composite is not yet available.
      for (final layer in state.pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          final coords = _crossStitchXY(stitch);
          if (coords != null) topThread[coords] = stitch.threadId;
        }
      }
    }

    // The thread that is visually on top at the starting cell.
    final threadId = topThread[Cell(x, y)];
    if (threadId == null) return;

    // In focus mode, only flood-fill if the starting cell matches the focus thread.
    final focusId = state.stitchSession.focusThreadId;
    if (focusId != null && threadId != focusId) return;

    // In page mode, constrain flood fill to the current page.
    final layout = state.stitchSession.pageLayout;
    final (pageCol, pageRow) =
        layout != null ? layout.pageCoords(state.stitchSession.currentPage) : (0, 0);

    // BFS flood fill — 8-directional (sides + diagonals).
    // Only traverse cells where the same thread is the topmost visible stitch.
    // In page mode, also restrict to cells on the current page.
    final queue = <Cell>[Cell(x, y)];
    final visited = <Cell>{};
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      if (visited.contains(cell)) continue;
      if (topThread[cell] != threadId) continue;
      if (layout != null && !layout.cellOnPage(cell.x, cell.y, pageCol, pageRow)) continue;
      visited.add(cell);
      final cx = cell.x;
      final cy = cell.y;
      for (final n in [
        Cell(cx - 1, cy - 1), Cell(cx, cy - 1), Cell(cx + 1, cy - 1),
        Cell(cx - 1, cy),                        Cell(cx + 1, cy),
        Cell(cx - 1, cy + 1), Cell(cx, cy + 1), Cell(cx + 1, cy + 1),
      ]) {
        if (!visited.contains(n) && topThread[n] == threadId) queue.add(n);
      }
    }

    if (startIsDone) {
      // Un-mark mode: remove all visited cells from completedStitches.
      final newCompleted = Set<Cell>.from(prog.completedStitches)
        ..removeAll(visited);
      if (newCompleted.length == prog.completedStitches.length) return;
      final newProg = prog.copyWith(completedStitches: newCompleted);
      _applyProgress(newProg);
      _checkPageCompletion(newProg);
    } else {
      // Mark done mode: add all visited cells to completedStitches.
      final newCompleted = Set<Cell>.from(prog.completedStitches)
        ..addAll(visited);
      if (newCompleted.length == prog.completedStitches.length) return;
      final newProg = prog.copyWith(completedStitches: newCompleted);
      _applyProgress(newProg);
      _checkColourCompletion(newProg, {threadId});
      _checkPageCompletion(newProg);
    }
  }

  /// Mark all stitches within [region] (cell coords) as NOT done.
  /// In page mode, only stitches on the current page are affected.
  void markRegionNotDone(Rect region) {
    final prog = state.pattern.progress;
    final current = Set<Cell>.from(prog.completedStitches);
    int removed = 0;
    final layout = state.stitchSession.pageLayout;
    final (pageCol, pageRow) = layout != null ? layout.pageCoords(state.stitchSession.currentPage) : (0, 0);
    final focusId = state.stitchSession.focusThreadId;
    if (!state.stitchSession.backMode) {
    // Build topThread from compositeLayer so blended cells are filtered correctly.
    final topThread = <Cell, String>{};
    final composite = state.compositeLayer;
    if (composite != null) {
      for (final e in composite.fullStitches.entries) {
        topThread[e.key] = e.value.resolvedThread.dmcCode;
      }
      for (final cs in composite.otherStitches) {
        final cell = cs.stitch.cellCoords;
        if (cell != null) topThread[cell] = cs.resolvedThread.dmcCode;
      }
    } else {
      for (final layer in state.pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          final coords = _crossStitchXY(stitch);
          if (coords != null) topThread[coords] = stitch.threadId;
        }
      }
    }
    for (final entry in topThread.entries) {
      final coords = entry.key;
      if (focusId != null && entry.value != focusId) continue;
      final sx = coords.x;
      final sy = coords.y;
      if (sx >= region.left && sx < region.right &&
          sy >= region.top && sy < region.bottom) {
        if (layout != null && !layout.rawCellOnPage(sx, sy, pageCol, pageRow)) continue;
        if (current.remove(coords)) { removed++; }
      }
    }
    }
    // Backstitches in region.
    final backCurrent = Set<(double, double, double, double)>.from(
        prog.completedBackstitches);
    if (!state.stitchSession.crossMode) {
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
              !layout.rawCellOnPage(
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

  /// Adds [minutes] to the progress log entry for [isoDate] (defaults to today).
  ///
  /// Called when the user stops the stitching timer.  Creates the entry
  /// if one doesn't exist yet, otherwise accumulates into the existing one.
  void addTimeToLog(int minutes, {String? isoDate}) {
    if (minutes <= 0) return;
    final today = isoDate ?? todayIsoDate();
    final existing = state.pattern.progressLog
        .where((e) => e.isoDate == today)
        .firstOrNull;
    final currentCount = state.pattern.progress.completedStitches.length;
    final currentBackCount = state.pattern.progress.completedBackstitches.length;
    final updated = existing != null
        ? existing.copyWith(minutesSpent: existing.minutesSpent + minutes)
        : ProgressLogEntry(
            isoDate: today,
            stitchCount: currentCount,
            backstitchCount: currentBackCount,
            minutesSpent: minutes,
          );
    final newLog = [
      ...state.pattern.progressLog.where((e) => e.isoDate != today),
      updated,
    ];
    state = state.copyWith(
      pattern: state.pattern.copyWith(progressLog: newLog),
      isDirty: true,
    );
  }

  /// Overrides [minutesSpent] for the log entry on [isoDate] to [minutes].
  ///
  /// Used by the manual time-adjustment UI in StitchOps.  If [minutes] is 0
  /// the entry's time is zeroed (other fields like stitchCount are preserved).
  /// If no entry exists for [isoDate] and [minutes] > 0 a skeleton entry is
  /// created with the current stitch counts.
  void setTimeForDate(String isoDate, int minutes) {
    final existing = state.pattern.progressLog
        .where((e) => e.isoDate == isoDate)
        .firstOrNull;
    if (existing == null && minutes <= 0) return; // nothing to do
    late final List<ProgressLogEntry> newLog;
    if (existing != null) {
      newLog = [
        ...state.pattern.progressLog.where((e) => e.isoDate != isoDate),
        existing.copyWith(minutesSpent: minutes),
      ];
    } else {
      // No log entry for this date yet — create one with current counts.
      final currentCount = state.pattern.progress.completedStitches.length;
      final currentBackCount =
          state.pattern.progress.completedBackstitches.length;
      newLog = [
        ...state.pattern.progressLog,
        ProgressLogEntry(
          isoDate: isoDate,
          stitchCount: currentCount,
          backstitchCount: currentBackCount,
          minutesSpent: minutes,
        ),
      ];
    }
    state = state.copyWith(
      pattern: state.pattern.copyWith(progressLog: newLog),
      isDirty: true,
    );
  }

  /// Clear all progress (completed stitches and pages). Undoable.
  void clearProgress() {
    if (state.pattern.progress == PatternProgress.empty) return;
    _applyProgress(PatternProgress.empty, pushUndo: true);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Applies [progress] and updates [progressLog].
  ///
  /// When [pushUndo] is true, calls [_pushProgressSnapshot] so the notifier
  /// routes the undo entry to the active controller's [UndoManager]. Use for
  /// direct-from-UI mutations (markRegion, clearProgress).
  ///
  /// Pass the default [pushUndo: false] for controller-wrapped callbacks
  /// (toggleStitchDone, toggleBackstitchDone, floodFillDone) — the controller
  /// handles undo bookkeeping via [ProgressSnapshotCommand].
  void _applyProgress(PatternProgress progress, {bool pushUndo = false}) {
    final before = state.pattern.progress;
    final updatedLog = _updatedLog(progress);
    final newPattern = state.pattern.copyWith(progress: progress, progressLog: updatedLog);
    state = state.copyWith(pattern: newPattern, isDirty: true);
    if (pushUndo) {
      _pushProgressSnapshot(before, state.pattern.progress);
    }
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
  /// Uses [compositeLayer] for O(1) lookup; falls back to raw layer scan if
  /// the composite is not yet available.
  String? _topThreadAt(int x, int y) {
    final composite = state.compositeLayer;
    if (composite != null) return composite.topThreadAt(Cell(x, y));
    // Fallback: raw layer scan (should rarely be needed in practice).
    final target = Cell(x, y);
    String? result;
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == target) result = stitch.threadId;
      }
    }
    return result;
  }

  bool _hasCrossStitchAt(int x, int y) {
    final composite = state.compositeLayer;
    if (composite != null) return composite.hasCrossStitchAt(Cell(x, y));
    // Fallback: raw layer scan.
    final target = Cell(x, y);
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == target) return true;
      }
    }
    return false;
  }

  Set<String> _threadIdsAt(int x, int y) {
    final target = Cell(x, y);
    final ids = <String>{};
    for (final layer in state.pattern.layers) {
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final coords = _crossStitchXY(stitch);
        if (coords == target) {
          ids.add(stitch.threadId);
        }
      }
    }
    return ids;
  }

  static Cell? _crossStitchXY(Stitch stitch) => switch (stitch) {
        FullStitch(:final x, :final y) => Cell(x, y),
        HalfStitch(:final x, :final y) => Cell(x, y),
        HalfCrossStitch(:final x, :final y) => Cell(x, y),
        QuarterStitch(:final x, :final y) => Cell(x, y),
        QuarterCrossStitch(:final x, :final y) => Cell(x, y),
        BackStitch() => null,
      };

  void _checkColourCompletion(PatternProgress prog, Set<String> threadIds) {
    final allStitches = state.pattern.stitches;
    for (final threadId in threadIds) {
      if (prog.isColourDone(threadId, allStitches)) {
        final thread = state.pattern.threads[threadId];
        if (thread != null) {
          state = state.copyWith(
            editSession: state.editSession.copyWith(
              pendingCanvasWarning: '${thread.dmcCode} ${thread.name} complete ✓',
            ),
          );
        }
      }
    }
  }

  void _checkPageCompletion(PatternProgress prog) {
    final layout = state.stitchSession.pageLayout;
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
            if (!layout.cellOnPage(coords.x, coords.y, pageCol, pageRow)) continue;
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
