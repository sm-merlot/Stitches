part of 'editor_provider.dart';

// ─── DrawingMixin ─────────────────────────────────────────────────────────────
//
// Stitch drawing, thread management, tool modes, stitch mode, reference image.

mixin DrawingMixin on Notifier<EditorState> {

  // Abstract declarations for helpers defined in EditorNotifier / LayersMixin.
  List<(CrossStitchPattern, List<SnippetPalette>)> _buildUndoStack();
  CrossStitchPattern _patternWithActiveLayerStitches(
      CrossStitchPattern p, List<Stitch> s);
  CrossStitchPattern _patternWithActiveLayer(
      CrossStitchPattern p, Layer newLayer);
  CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern);
  CrossStitchPattern _pruneSpecificThread(CrossStitchPattern pattern, String threadId);
  String _nextSymbol(Set<String> used);
  void refreshCompositeCache(); // provided by LayersMixin
  void _saveSession();          // provided by EditorNotifier
  void setMode(AppMode mode);   // provided by EditorNotifier
  List<SnippetPalette> syncPaletteSymbolsToPrimary(
      List<SnippetPalette> palettes); // provided by SnippetsMixin

  // Debounce timer: refreshCompositeCache is deferred during high-frequency
  // drag drawing so it doesn't run on every pointer-move event.
  Timer? _drawCompositeDebounce;

  // ─── Private helpers (unique to this mixin) ───────────────────────────────

  bool _stitchAtCell(Stitch s, int cellX, int cellY) {
    final coords = EditorState.cellCoords(s);
    return coords != null && coords.x == cellX && coords.y == cellY;
  }

  /// A backstitch is "in" a cell if either endpoint lies within its bounds.
  bool _backstitchInCell(Stitch s, int cellX, int cellY) {
    if (s is! BackStitch) return false;
    bool inside(double gx, double gy) =>
        gx >= cellX && gx <= cellX + 1 && gy >= cellY && gy <= cellY + 1;
    return inside(s.x1, s.y1) || inside(s.x2, s.y2);
  }

  CrossStitchPattern _patternWithAllLayersTransformed(
      CrossStitchPattern pattern, List<Stitch> Function(List<Stitch>) transform) {
    return pattern.mapLayers((l) => l.copyWith(stitches: transform(l.stitches)));
  }

  Set<String> _allUsedSymbols([CrossStitchPattern? pattern]) {
    final p = pattern ?? state.pattern;
    return {
      for (final t in p.threads.values) if (t.symbol.isNotEmpty) t.symbol,
      ...p.compositeSymbols.values.where((s) => s.isNotEmpty),
    };
  }

  // ─── Thread management ────────────────────────────────────────────────────

  void setSelectedThread(String? threadId) {
    final recents = threadId == null
        ? state.recentThreadIds
        : [
            threadId,
            if (state.selectedThreadId != null &&
                state.selectedThreadId != threadId)
              state.selectedThreadId!,
            ...state.recentThreadIds.where(
                (id) => id != threadId && id != state.selectedThreadId),
          ].take(10).toList();
    state = state.copyWith(selectedThreadId: threadId, recentThreadIds: recents);
    _saveSession();
  }

  /// Picks the visually displayed (composite/blended) colour at [x],[y] and
  /// selects it, switching back to draw mode.
  void pickColorAtCell(int x, int y) {
    final s = state;
    final threadMap = s.pattern.threads;

    String? stitchThreadId(Stitch stitch) => switch (stitch) {
          FullStitch(x: final sx, y: final sy, threadId: final t)
              when sx == x && sy == y =>
            t,
          HalfStitch(x: final sx, y: final sy, threadId: final t)
              when sx == x && sy == y =>
            t,
          HalfCrossStitch(x: final sx, y: final sy, threadId: final t)
              when sx == x && sy == y =>
            t,
          QuarterStitch(x: final sx, y: final sy, threadId: final t)
              when sx == x && sy == y =>
            t,
          QuarterCrossStitch(x: final sx, y: final sy, threadId: final t)
              when sx == x && sy == y =>
            t,
          _ => null,
        };

    void select(String threadId, [CrossStitchPattern? updatedPattern]) {
      final recents = [
        threadId,
        if (s.selectedThreadId != null && s.selectedThreadId != threadId)
          s.selectedThreadId!,
        ...s.recentThreadIds.where(
            (id) => id != threadId && id != s.selectedThreadId),
      ].take(10).toList();
      state = s.copyWith(
        pattern: updatedPattern ?? s.pattern,
        selectedThreadId: threadId,
        recentThreadIds: recents,
        drawingMode: DrawingMode.draw,
      );
    }

    final hits = <({Color color, double opacity, String threadId})>[];
    for (final layer in s.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitchesAt(x, y)) {
        if (stitch is FullStitch) {
          final t = threadMap[stitch.threadId];
          if (t != null) {
            hits.add((color: t.color, opacity: layer.opacity, threadId: stitch.threadId));
          }
          break;
        }
      }
    }

    if (hits.isEmpty) {
      for (final layer in s.pattern.layers.reversed) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitchesAt(x, y).reversed) {
          final tid = stitchThreadId(stitch);
          if (tid != null) { select(tid); return; }
        }
      }
      return;
    }

    if (hits.length == 1) { select(hits.first.threadId); return; }

    var blended = hits.first.color;
    for (int i = 1; i < hits.length; i++) {
      blended = Color.lerp(blended, hits[i].color, hits[i].opacity)!;
    }
    final r = (blended.r * 255).round();
    final g = (blended.g * 255).round();
    final b = (blended.b * 255).round();
    final dmc = SpriteImporter.matchPixel(r, g, b, 255);
    if (dmc == null) return;
    select(dmc.code);
  }

  void setAidaColor(Color color) {
    state = state.copyWith(
      pattern: state.pattern.copyWith(aidaColor: color),
      isDirty: true,
    );
  }

  /// Replaces every stitch using [oldDmcCode] with [newDmcCode] and updates
  /// the thread palette. The old thread's symbol is preserved.
  void replaceThread(
      String oldDmcCode, String newDmcCode, Color newColor, String newName) {
    if (oldDmcCode == newDmcCode) return;
    final oldThread = state.pattern.threads[oldDmcCode];
    if (oldThread == null) return;

    final newThread = Thread(
        dmcCode: newDmcCode, color: newColor, name: newName, symbol: oldThread.symbol);

    // Replace in-place preserving insertion order; drop old key.
    final Map<String, Thread> threads;
    if (state.pattern.threads.containsKey(newDmcCode)) {
      // Replacement already in palette — just remove the old one.
      threads = Map.from(state.pattern.threads)..remove(oldDmcCode);
    } else {
      // Substitute old → new at the same position.
      threads = {
        for (final e in state.pattern.threads.entries)
          if (e.key == oldDmcCode) newDmcCode: newThread else e.key: e.value,
      };
    }

    final remappedPattern = _patternWithAllLayersTransformed(
      state.pattern.copyWith(threads: threads),
      (stitches) => stitches
          .map((s) => s.threadId == oldDmcCode ? _withThreadId(s, newDmcCode) : s)
          .toList(),
    );

    // Mirror the primary slot change into snippetPalettes[0] so the
    // snippet editor's Colours panel (which reads from palette threads)
    // stays in sync with pattern.threads. syncPaletteSymbolsToPrimary
    // then propagates the unchanged slot symbol across all secondaries.
    var snippetPalettes = state.snippetPalettes;
    if (snippetPalettes.isNotEmpty) {
      final primary = List<Thread>.from(snippetPalettes[0].threads);
      final pIdx = primary.indexWhere((t) => t.dmcCode == oldDmcCode);
      if (pIdx != -1) {
        final pNewExists = primary.any((t) => t.dmcCode == newDmcCode);
        if (pNewExists) {
          primary.removeAt(pIdx);
        } else {
          primary[pIdx] = newThread;
        }
        snippetPalettes = syncPaletteSymbolsToPrimary([
          snippetPalettes[0].copyWith(threads: primary),
          ...snippetPalettes.skip(1),
        ]);
      }
    }

    state = state.copyWith(
      pattern: remappedPattern,
      snippetPalettes: snippetPalettes,
      selectedThreadId:
          state.selectedThreadId == oldDmcCode ? newDmcCode : state.selectedThreadId,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Replaces every stitch using [oldDmcCode] with [newDmcCode] within a
  /// single layer only. Other layers are untouched.
  /// If [oldDmcCode] is no longer used in any layer after the replacement,
  /// it is removed from the pattern thread palette.
  void replaceThreadInLayer(
      String layerId, String oldDmcCode, String newDmcCode, Color newColor, String newName) {
    if (oldDmcCode == newDmcCode) return;
    final oldThread = state.pattern.threads[oldDmcCode];
    if (oldThread == null) return;

    final mappedPattern = state.pattern.mapLayers((l) {
      if (l.id != layerId) return l;
      return l.copyWith(
        stitches: l.stitches
            .map((s) => s.threadId == oldDmcCode ? _withThreadId(s, newDmcCode) : s)
            .toList(),
      );
    });

    final threads = mappedPattern.threads.containsKey(newDmcCode)
        ? mappedPattern.threads
        : {
            ...mappedPattern.threads,
            newDmcCode: Thread(
                dmcCode: newDmcCode,
                color: newColor,
                name: newName,
                symbol: oldThread.symbol),
          };

    final pruned = _pruneUnusedThreads(mappedPattern.copyWith(threads: threads));

    state = state.copyWith(
      pattern: pruned,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Changes the symbol displayed on a thread's swatch.
  /// Clears the composite cache so the colours panel immediately reflects the
  /// updated symbol rather than serving stale Thread objects from the cache.
  void setThreadSymbol(String dmcCode, String symbol) {
    final existing = state.pattern.threads[dmcCode];
    if (existing == null) return;
    final threads = {...state.pattern.threads, dmcCode: existing.copyWith(symbol: symbol)};
    state = state.copyWith(
      pattern: state.pattern.copyWith(threads: threads),
      compositeLayer: null,
      isDirty: true,
    );
    // Rebuild immediately so composite panel doesn't fall back to layer threads.
    if (state.showCompositeThreads) refreshCompositeCache();
  }

  /// Same as [replaceThread] but operates on a snippet.
  void replaceSnippetThread(String snippetId, String oldDmcCode,
      String newDmcCode, Color newColor, String newName) {
    if (oldDmcCode == newDmcCode) return;
    final snippet =
        state.pattern.snippets.where((s) => s.id == snippetId).firstOrNull;
    if (snippet == null) return;
    final oldThread =
        snippet.threads.where((t) => t.dmcCode == oldDmcCode).firstOrNull;
    if (oldThread == null) return;

    final newThread = Thread(
        dmcCode: newDmcCode, color: newColor, name: newName, symbol: oldThread.symbol);

    final stitches = snippet.stitches
        .map((s) => s.threadId == oldDmcCode ? _withThreadId(s, newDmcCode) : s)
        .toList();

    var threads = snippet.threads.toList();
    final oldIdx = threads.indexWhere((t) => t.dmcCode == oldDmcCode);
    final newExists = threads.any((t) => t.dmcCode == newDmcCode);
    if (newExists) {
      threads.removeAt(oldIdx);
    } else {
      threads[oldIdx] = newThread;
    }

    final updated = state.pattern.snippets
        .map((s) => s.id == snippetId
            ? s.copyWith(
                palettes: [
                  s.palettes[0].copyWith(threads: threads),
                  ...s.palettes.skip(1),
                ],
                stitches: stitches,
              )
            : s)
        .toList();

    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: updated),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  // ─── Stitch drawing ───────────────────────────────────────────────────────

  void addStitch(Stitch stitch) {
    if (state.activeLayer.locked) return;
    // O(1) via _cellIndex for cell stitches; O(n) only for BackStitch (rare).
    final coords = stitch.cellCoords;
    final existingAtCell = coords != null
        ? state.activeLayer.stitchesAt(coords.x, coords.y)
        : null;

    // Early-return if exact stitch (same position + thread) already placed.
    if (existingAtCell != null) {
      if (existingAtCell.any((s) => s == stitch && s.threadId == stitch.threadId)) return;
    } else if (stitch is BackStitch) {
      if (state.activeLayer.backstitches
          .any((s) => s == stitch && s.threadId == stitch.threadId)) {
        return;
      }
    }

    var pattern = state.pattern;
    final threadId = stitch.threadId;
    Thread? addedThread;
    if (!pattern.threads.containsKey(threadId)) {
      final dmc = dmcColorByCode(threadId);
      if (dmc != null) {
        final usedSymbols = _allUsedSymbols(pattern);
        addedThread = Thread(
          dmcCode: dmc.code,
          color: dmc.color,
          name: dmc.name,
          symbol: _nextSymbol(usedSymbols),
        );
        pattern = pattern.copyWith(threads: {...pattern.threads, addedThread.dmcCode: addedThread});
      }
    }

    var snippetPalettes = state.snippetPalettes;
    if (addedThread != null && snippetPalettes.isNotEmpty) {
      snippetPalettes = snippetPalettes
          .map((p) => p.copyWith(threads: [...p.threads, addedThread!]))
          .toList();
    }

    // O(N_cells) map copy instead of O(N_stitches) list copy + index rebuild.
    // Common case: cell empty → withStitchAdded (no filter pass needed).
    // Rare case: cell occupied by same-geometry stitch → withStitchReplaced.
    final bool cellEmpty = existingAtCell == null || existingAtCell.isEmpty;
    final bool needsReplace = !cellEmpty && existingAtCell.any((s) => s == stitch);
    final newActiveLayer = needsReplace
        ? state.activeLayer.withStitchReplaced(stitch)
        : state.activeLayer.withStitchAdded(stitch);

    final rawPattern = _patternWithActiveLayer(pattern, newActiveLayer);

    // Prune only the displaced thread (if any) — not all threads.
    // Common case (empty cell): no displacement → skip O(total_stitches) scan.
    final String? displacedThread = needsReplace
        ? existingAtCell
            .where((s) => s == stitch && s.threadId != stitch.threadId)
            .map((s) => s.threadId)
            .firstOrNull
        : null;
    final newPattern = displacedThread != null
        ? _pruneSpecificThread(rawPattern, displacedThread)
        : rawPattern;

    // Incremental composite: patch only the affected cell when possible.
    // Falls back to computeLayer for backstitches (no cell coords) or when
    // no prior composite exists.
    final oldComposite = state.compositeLayer;
    final quickComposite = (oldComposite != null && coords != null)
        ? StitchCompositor.patchLayer(
            oldComposite, newPattern, coords.x, coords.y)
        : StitchCompositor.computeLayer(newPattern);

    // Accumulate dirty keys across successive draw events within the same frame
    // so a single updateCells() call covers all pointer-move events per render.
    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = coords != null
        ? <Cell>{...?prevDirty, coords}
        : null; // backstitch → force full rebuild next sync

    state = state.copyWith(
      pattern: newPattern,
      snippetPalettes: snippetPalettes,
      undoStack: _buildUndoStack(),
      compositeLayer: quickComposite,
      dirtyCellKeys: mergedDirty,
      isDirty: true,
      redoStack: [],
    );
    // Debounce full refresh so symbol management doesn't run on every drag event.
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  void removeStitchesAt(int x, int y) {
    if (state.activeLayer.locked) return;
    // O(1) for cell stitches; backstitch list only when cell is empty.
    if (state.activeLayer.stitchesAt(x, y).isEmpty &&
        !state.activeLayer.backstitches.any((s) => _backstitchInCell(s, x, y))) {
      return;
    }

    final removedAnyBackstitch =
        state.activeLayer.backstitches.any((s) => _backstitchInCell(s, x, y));
    final newActiveLayer = state.activeLayer.withCellCleared(x, y);
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayer(state.pattern, newActiveLayer));

    final oldComposite = state.compositeLayer;
    final quickComposite = oldComposite != null
        ? StitchCompositor.patchLayer(oldComposite, newPattern, x, y,
            backstitchesChanged: removedAnyBackstitch)
        : StitchCompositor.computeLayer(newPattern);

    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = <Cell>{...?prevDirty, Cell(x, y)};

    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      compositeLayer: quickComposite,
      dirtyCellKeys: mergedDirty,
      isDirty: true,
      redoStack: [],
    );
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  /// Erases all stitches in a [size]×[size] box centred on (cx, cy).
  void removeStitchesInBox(int cx, int cy, int size) {
    if (state.activeLayer.locked) return;
    final half = (size - 1) ~/ 2;
    final x0 = cx - half;
    final x1 = cx + (size - 1 - half);
    final y0 = cy - half;
    final y1 = cy + (size - 1 - half);

    bool hit(Stitch s) {
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          if (_stitchAtCell(s, x, y) || _backstitchInCell(s, x, y)) return true;
        }
      }
      return false;
    }

    if (!state.activeLayer.stitches.any(hit)) return;
    final newStitches = state.activeLayer.stitches.where((s) => !hit(s)).toList();
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayerStitches(state.pattern, newStitches));

    // Box erase may affect multiple cells — use computeLayer for correctness,
    // but pass dirtyCellKeys so _syncRenderCache calls updateCells() (O(box))
    // instead of rebuild() (O(total_stitches)).
    final dirtyKeys = <Cell>{
      for (var xx = x0; xx <= x1; xx++)
        for (var yy = y0; yy <= y1; yy++) Cell(xx, yy),
    };
    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = <Cell>{...?prevDirty, ...dirtyKeys};

    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      compositeLayer: StitchCompositor.computeLayer(newPattern),
      dirtyCellKeys: mergedDirty,
      isDirty: true,
      redoStack: [],
    );
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  // ─── Raw draw variants (no undo stack push) ──────────────────────────────
  //
  // Called by [Command.execute] and [Command.undo].  Identical to their
  // non-raw counterparts except they never touch [_undoStack] / [_redoStack].
  // The caller's [UndoManager] owns the undo history.

  void addStitchRaw(Stitch stitch) {
    if (state.activeLayer.locked) return;
    final coords = stitch.cellCoords;
    final existingAtCell = coords != null
        ? state.activeLayer.stitchesAt(coords.x, coords.y)
        : null;

    if (existingAtCell != null) {
      if (existingAtCell.any((s) => s == stitch && s.threadId == stitch.threadId)) return;
    } else if (stitch is BackStitch) {
      if (state.activeLayer.backstitches
          .any((s) => s == stitch && s.threadId == stitch.threadId)) {
        return;
      }
    }

    var pattern = state.pattern;
    final threadId = stitch.threadId;
    Thread? addedThread;
    if (!pattern.threads.containsKey(threadId)) {
      final dmc = dmcColorByCode(threadId);
      if (dmc != null) {
        final usedSymbols = _allUsedSymbols(pattern);
        addedThread = Thread(
          dmcCode: dmc.code,
          color: dmc.color,
          name: dmc.name,
          symbol: _nextSymbol(usedSymbols),
        );
        pattern = pattern.copyWith(threads: {...pattern.threads, addedThread.dmcCode: addedThread});
      }
    }

    var snippetPalettes = state.snippetPalettes;
    if (addedThread != null && snippetPalettes.isNotEmpty) {
      snippetPalettes = snippetPalettes
          .map((p) => p.copyWith(threads: [...p.threads, addedThread!]))
          .toList();
    }

    final bool cellEmpty = existingAtCell == null || existingAtCell.isEmpty;
    final bool needsReplace = !cellEmpty && existingAtCell.any((s) => s == stitch);
    final newActiveLayer = needsReplace
        ? state.activeLayer.withStitchReplaced(stitch)
        : state.activeLayer.withStitchAdded(stitch);

    final rawPattern = _patternWithActiveLayer(pattern, newActiveLayer);
    final String? displacedThread = needsReplace
        ? existingAtCell
            .where((s) => s == stitch && s.threadId != stitch.threadId)
            .map((s) => s.threadId)
            .firstOrNull
        : null;
    final newPattern = displacedThread != null
        ? _pruneSpecificThread(rawPattern, displacedThread)
        : rawPattern;

    final oldComposite = state.compositeLayer;
    final quickComposite = (oldComposite != null && coords != null)
        ? StitchCompositor.patchLayer(oldComposite, newPattern, coords.x, coords.y)
        : StitchCompositor.computeLayer(newPattern);

    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = coords != null
        ? <Cell>{...?prevDirty, coords}
        : null;

    state = state.copyWith(
      pattern: newPattern,
      snippetPalettes: snippetPalettes,
      compositeLayer: quickComposite,
      dirtyCellKeys: mergedDirty,
      isDirty: true,
    );
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  void removeStitchRaw(Stitch stitch) {
    if (state.activeLayer.locked) return;
    final newActiveLayer = state.activeLayer.withStitchRemoved(stitch);
    if (identical(newActiveLayer, state.activeLayer)) return;
    final coords = stitch.cellCoords;
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayer(state.pattern, newActiveLayer));

    final oldComposite = state.compositeLayer;
    final quickComposite = (oldComposite != null && coords != null)
        ? StitchCompositor.patchLayer(oldComposite, newPattern, coords.x, coords.y,
            backstitchesChanged: stitch is BackStitch)
        : StitchCompositor.computeLayer(newPattern);

    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = coords != null
        ? <Cell>{...?prevDirty, coords}
        : null;

    state = state.copyWith(
      pattern: newPattern,
      compositeLayer: quickComposite,
      dirtyCellKeys: mergedDirty,
      isDirty: true,
    );
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  void removeStitchesAtRaw(int x, int y) {
    if (state.activeLayer.locked) return;
    if (state.activeLayer.stitchesAt(x, y).isEmpty &&
        !state.activeLayer.backstitches.any((s) => _backstitchInCell(s, x, y))) {
      return;
    }

    final removedAnyBackstitch =
        state.activeLayer.backstitches.any((s) => _backstitchInCell(s, x, y));
    final newActiveLayer = state.activeLayer.withCellCleared(x, y);
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayer(state.pattern, newActiveLayer));

    final oldComposite = state.compositeLayer;
    final quickComposite = oldComposite != null
        ? StitchCompositor.patchLayer(oldComposite, newPattern, x, y,
            backstitchesChanged: removedAnyBackstitch)
        : StitchCompositor.computeLayer(newPattern);

    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = <Cell>{...?prevDirty, Cell(x, y)};

    state = state.copyWith(
      pattern: newPattern,
      compositeLayer: quickComposite,
      dirtyCellKeys: mergedDirty,
      isDirty: true,
    );
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  void removeStitchesInBoxRaw(int cx, int cy, int size) {
    if (state.activeLayer.locked) return;
    final half = (size - 1) ~/ 2;
    final x0 = cx - half;
    final x1 = cx + (size - 1 - half);
    final y0 = cy - half;
    final y1 = cy + (size - 1 - half);

    bool hit(Stitch s) {
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          if (_stitchAtCell(s, x, y) || _backstitchInCell(s, x, y)) return true;
        }
      }
      return false;
    }

    if (!state.activeLayer.stitches.any(hit)) return;
    final newStitches = state.activeLayer.stitches.where((s) => !hit(s)).toList();
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayerStitches(state.pattern, newStitches));

    final dirtyKeys = <Cell>{
      for (var xx = x0; xx <= x1; xx++)
        for (var yy = y0; yy <= y1; yy++) Cell(xx, yy),
    };
    final prevDirty = state.dirtyCellKeys;
    final mergedDirty = <Cell>{...?prevDirty, ...dirtyKeys};

    state = state.copyWith(
      pattern: newPattern,
      compositeLayer: StitchCompositor.computeLayer(newPattern),
      dirtyCellKeys: mergedDirty,
      isDirty: true,
    );
    _drawCompositeDebounce?.cancel();
    _drawCompositeDebounce =
        Timer(const Duration(milliseconds: 80), refreshCompositeCache);
  }

  void setEraserSize(int size) {
    // Selecting a size deselects fill erase — they're mutually exclusive.
    state = state.copyWith(eraserSize: size.clamp(1, 10), fillEraseActive: false);
  }

  void toggleFillErase() {
    // Toggling fill erase on deselects any size selection, and vice versa.
    state = state.copyWith(fillEraseActive: !state.fillEraseActive);
  }

  /// 8-connected flood fill. [erase] == false fills empty/same-colour cells;
  /// [erase] == true removes connected FullStitches sharing the same threadId.
  void floodFill(int startX, int startY, {required bool erase}) {
    final p = state.pattern;
    if (startX < 0 || startX >= p.width || startY < 0 || startY >= p.height) return;

    // O(1) seed lookup via cell index.
    final seedStitch = state.activeLayer
        .stitchesAt(startX, startY)
        .whereType<FullStitch>()
        .firstOrNull;
    final String? seedThreadId = seedStitch?.threadId;

    if (erase && seedThreadId == null) return;
    final fillThreadId = state.selectedThreadId;
    if (!erase && fillThreadId == null) return;
    if (!erase && seedThreadId == fillThreadId) return;

    // Build occupied map directly from the cell index — avoids stitches getter.
    final Map<int, String> occupied = {};
    for (final entry in state.activeLayer.stitchesByCell.entries) {
      for (final s in entry.value) {
        if (s is FullStitch) occupied[s.x * 100000 + s.y] = s.threadId;
      }
    }

    int key(int x, int y) => x * 100000 + y;
    bool matches(int x, int y) => occupied[key(x, y)] == seedThreadId;

    final visited = <int>{};
    final queue = <(int, int)>[(startX, startY)];
    visited.add(key(startX, startY));
    final toChange = <(int, int)>[];

    while (queue.isNotEmpty) {
      final (cx, cy) = queue.removeAt(0);
      toChange.add((cx, cy));
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || nx >= p.width || ny < 0 || ny >= p.height) continue;
          final k = key(nx, ny);
          if (visited.contains(k)) continue;
          visited.add(k);
          if (matches(nx, ny)) queue.add((nx, ny));
        }
      }
    }

    if (toChange.isEmpty) return;

    List<Stitch> newStitches = [...state.activeLayer.stitches];
    if (erase) {
      final removeKeys = toChange.map((c) => key(c.$1, c.$2)).toSet();
      newStitches = newStitches.where((s) {
        if (s is! FullStitch) return true;
        return !removeKeys.contains(key(s.x, s.y));
      }).toList();
    } else {
      final changeKeys = toChange.map((c) => key(c.$1, c.$2)).toSet();
      newStitches = newStitches.where((s) {
        if (s is! FullStitch) return true;
        return !changeKeys.contains(key(s.x, s.y));
      }).toList();
      for (final (cx, cy) in toChange) {
        newStitches.add(FullStitch(x: cx, y: cy, threadId: fillThreadId!));
      }
    }

    final newPattern = _patternWithActiveLayerStitches(p, newStitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      compositeLayer: null,
      isDirty: true,
      redoStack: [],
    );
    refreshCompositeCache();
  }

  void removeBackstitchAt(double x1, double y1, double x2, double y2) {
    final target = BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: '');
    if (!state.activeLayer.backstitches.any((s) => s == target)) return;

    final newActiveLayer = state.activeLayer.withStitchRemoved(target);
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayer(state.pattern, newActiveLayer));
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      compositeLayer: null,
      isDirty: true,
      redoStack: [],
    );
    refreshCompositeCache();
  }

  void setBackstitchStart(Offset? point) {
    state = state.copyWith(backstitchStartPoint: point);
  }

  void toggleBackstitchChainMode() {
    state = state.copyWith(backstitchChainMode: !state.backstitchChainMode);
  }

  void resizePattern(int newWidth, int newHeight, int anchorX, int anchorY) {
    final old = state.pattern;
    final dx = (anchorX / 2.0 * (newWidth - old.width)).round();
    final dy = (anchorY / 2.0 * (newHeight - old.height)).round();

    bool inBounds(Stitch s) {
      final coords = EditorState.cellCoords(s);
      if (coords != null) {
        return coords.x >= 0 && coords.x < newWidth &&
            coords.y >= 0 && coords.y < newHeight;
      }
      final bs = s as BackStitch;
      return bs.x1 >= 0 && bs.x1 <= newWidth && bs.y1 >= 0 && bs.y1 <= newHeight &&
          bs.x2 >= 0 && bs.x2 <= newWidth && bs.y2 >= 0 && bs.y2 <= newHeight;
    }

    final newPattern = _pruneUnusedThreads(_patternWithAllLayersTransformed(
      old.copyWith(width: newWidth, height: newHeight),
      (stitches) => stitches
          .map((s) => EditorState.offsetStitch(s, dx, dy))
          .where(inBounds)
          .toList(),
    ));

    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      redoStack: [],
      isDirty: true,
    );
  }

  /// Resizes the current pattern using snippet resize semantics (clip / scale /
  /// expand). Used by the snippet editor's in-AppBar resize button.
  void resizeEditorPatternAsSnippet(
      int newW, int newH, SnippetResizeMode mode) {
    final old = state.pattern;
    final oldW = old.width;
    final oldH = old.height;

    final newStitches = switch (mode) {
      SnippetResizeMode.clip => old.stitches.where((s) {
          return switch (s) {
            FullStitch(:final x, :final y) => x < newW && y < newH,
            HalfStitch(:final x, :final y) => x < newW && y < newH,
            QuarterStitch(:final x, :final y) => x < newW && y < newH,
            HalfCrossStitch(:final x, :final y) => x < newW && y < newH,
            QuarterCrossStitch(:final x, :final y) => x < newW && y < newH,
            // BackStitch uses grid-point coords (0..width inclusive), so the
            // right/bottom boundary is <= not <.
            BackStitch(:final x1, :final y1, :final x2, :final y2) =>
              x1 <= newW && y1 <= newH && x2 <= newW && y2 <= newH,
          };
        }).toList(),
      SnippetResizeMode.scale => old.stitches.map((s) {
          int sx(int x) => (x / oldW * newW).round().clamp(0, newW - 1);
          int sy(int y) => (y / oldH * newH).round().clamp(0, newH - 1);
          double sdx(double x) =>
              (x / oldW * newW).clamp(0.0, newW.toDouble());
          double sdy(double y) =>
              (y / oldH * newH).clamp(0.0, newH.toDouble());
          return switch (s) {
            FullStitch(:final x, :final y, :final threadId) =>
              FullStitch(x: sx(x), y: sy(y), threadId: threadId),
            HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
              HalfStitch(
                  x: sx(x), y: sy(y), isForward: isForward, threadId: threadId),
            QuarterStitch(
              :final x,
              :final y,
              :final quadrant,
              :final threadId
            ) =>
              QuarterStitch(
                  x: sx(x), y: sy(y), quadrant: quadrant, threadId: threadId),
            HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
              HalfCrossStitch(
                  x: sx(x), y: sy(y), half: half, threadId: threadId),
            QuarterCrossStitch(
              :final x,
              :final y,
              :final quadrant,
              :final threadId
            ) =>
              QuarterCrossStitch(
                  x: sx(x), y: sy(y), quadrant: quadrant, threadId: threadId),
            BackStitch(
              :final x1,
              :final y1,
              :final x2,
              :final y2,
              :final threadId
            ) =>
              BackStitch(
                  x1: sdx(x1),
                  y1: sdy(y1),
                  x2: sdx(x2),
                  y2: sdy(y2),
                  threadId: threadId),
          };
        }).toList(),
      SnippetResizeMode.expand => old.stitches,
    };

    state = state.copyWith(
      pattern: _patternWithAllLayersTransformed(
        old.copyWith(width: newW, height: newH),
        (_) => newStitches,
      ),
      undoStack: _buildUndoStack(),
      redoStack: [],
      isDirty: true,
    );
  }

  // ─── Colour mode (stitch mode: B&W vs colour) ──────────────────────────────

  void toggleColourMode() {
    state = state.copyWith(colourMode: !state.colourMode);
    _saveSession();
  }

  void toggleCanvasSelectionMode() {
    state = state.copyWith(canvasSelectionMode: !state.canvasSelectionMode);
  }

  void toggleStitchMode() {
    setMode(state.stitchMode ? AppMode.view : AppMode.stitch);
  }

  /// Cross: hides backstitches. Activating clears Back.
  void setStitchCrossMode(bool active) {
    state = state.copyWith(
      stitchCrossMode: active,
      stitchBackMode: active ? false : state.stitchBackMode,
    );
  }

  /// Back: greys normal stitches. Activating clears Cross.
  void setStitchBackMode(bool active) {
    state = state.copyWith(
      stitchBackMode: active,
      stitchCrossMode: active ? false : state.stitchCrossMode,
    );
  }

  void setStitchFocusThread(String? threadId) {
    state = state.copyWith(stitchFocusThreadId: threadId);
  }

  void setStitchShowPageColours(bool value) {
    state = state.copyWith(stitchShowPageColours: value);
  }

  // ─── Reference image ─────────────────────────────────────────────────────

  Future<void> pickReferenceImage() async {
    final result = await ReferenceImageService.pickAndDecode();
    if (result == null) return;
    final (path, image) = result;
    state = state.copyWith(
      pattern: state.pattern.copyWith(
        referenceImagePath: path,
        referenceOpacity: state.referenceOpacity,
      ),
      referenceImage: image,
      referenceVisible: true,
      isDirty: true,
    );
  }

  void clearReferenceImage() {
    state = state.copyWith(
      pattern: state.pattern.copyWith(referenceImagePath: null),
      referenceImage: null,
      isDirty: true,
    );
  }

  void setReferenceOpacity(double opacity) {
    state = state.copyWith(
      pattern: state.pattern.copyWith(referenceOpacity: opacity),
      referenceOpacity: opacity,
      isDirty: true,
    );
  }

  void toggleReferenceVisible() {
    state = state.copyWith(referenceVisible: !state.referenceVisible);
  }

  // ─── Whole-canvas flip/rotate (snippet editor C3) ─────────────────────────

  void flipCanvasH() {
    final w = state.pattern.width;
    final newPattern = _patternWithAllLayersTransformed(
      state.pattern,
      (stitches) => stitches
          .map((s) => SelectionMixin._flipStitchH(s, 0, 0, w))
          .toList(),
    );
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
    );
  }

  void flipCanvasV() {
    final h = state.pattern.height;
    final newPattern = _patternWithAllLayersTransformed(
      state.pattern,
      (stitches) => stitches
          .map((s) => SelectionMixin._flipStitchV(s, 0, 0, h))
          .toList(),
    );
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
    );
  }

  void rotateCanvasCW() {
    final w = state.pattern.width;
    final h = state.pattern.height;
    final newPattern = _patternWithAllLayersTransformed(
      state.pattern,
      (stitches) => stitches
          .map((s) => SelectionMixin._rotateStitchCW(s, 0, 0, w, h))
          .toList(),
    ).copyWith(width: h, height: w); // swap canvas dimensions
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
    );
  }

  // ─── Pattern metadata ─────────────────────────────────────────────────────

  void updatePatternMetadata({
    String? name,
    String? designer,
    String? description,
    String? difficulty,
    String? estimatedHours,
    String? copyright,
    List<({int aidaCount, int strands})>? materialsSuggestions,
  }) {
    state = state.copyWith(
      pattern: state.pattern.copyWith(
        name: name ?? state.pattern.name,
        designer: designer,
        description: description,
        difficulty: difficulty,
        estimatedHours: estimatedHours,
        copyright: copyright,
        materialsSuggestions:
            materialsSuggestions ?? state.pattern.materialsSuggestions,
      ),
      isDirty: true,
    );
  }
}

// ─── _withThreadId ────────────────────────────────────────────────────────────
// Library-level helper (no state dependency) used by DrawingMixin methods.

Stitch _withThreadId(Stitch s, String id) => switch (s) {
  FullStitch(:final x, :final y) =>
      FullStitch(x: x, y: y, threadId: id),
  HalfStitch(:final x, :final y, :final isForward) =>
      HalfStitch(x: x, y: y, isForward: isForward, threadId: id),
  QuarterStitch(:final x, :final y, :final quadrant) =>
      QuarterStitch(x: x, y: y, quadrant: quadrant, threadId: id),
  HalfCrossStitch(:final x, :final y, :final half) =>
      HalfCrossStitch(x: x, y: y, half: half, threadId: id),
  QuarterCrossStitch(:final x, :final y, :final quadrant) =>
      QuarterCrossStitch(x: x, y: y, quadrant: quadrant, threadId: id),
  BackStitch(:final x1, :final y1, :final x2, :final y2) =>
      BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: id),
};
