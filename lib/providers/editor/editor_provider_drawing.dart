part of 'editor_provider.dart';

// ─── DrawingMixin ─────────────────────────────────────────────────────────────
//
// Stitch drawing, thread management, tool modes, stitch mode, reference image.

mixin DrawingMixin on Notifier<EditorState> {

  // Abstract declarations for helpers defined in EditorNotifier / LayersMixin.
  List<(CrossStitchPattern, List<SnippetPalette>)> _buildUndoStack();
  List<Stitch> _stitchesWithAdded(List<Stitch> existing, Stitch stitch);
  CrossStitchPattern _patternWithActiveLayerStitches(
      CrossStitchPattern p, List<Stitch> s);
  CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern);
  String _nextSymbol(Set<String> used);
  void refreshCompositeCache(); // provided by LayersMixin

  // ─── Private helpers (unique to this mixin) ───────────────────────────────

  bool _stitchAtCell(Stitch s, int cellX, int cellY) {
    final coords = EditorState.cellCoords(s);
    return coords != null && coords.$1 == cellX && coords.$2 == cellY;
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
      for (final t in p.threads) if (t.symbol.isNotEmpty) t.symbol,
      ...p.compositeSymbols.values.where((s) => s.isNotEmpty),
    };
  }

  Future<void> _autoSaveStitchMode() async {
    if (state.filePath == null) return;
    await FileService.saveFile(state.patternForSave, state.filePath!);
  }

  // ─── Thread management ────────────────────────────────────────────────────

  void setSelectedThread(String? threadId) {
    final recents = threadId == null
        ? state.recentThreadIds
        : [
            threadId,
            ...state.recentThreadIds.where((id) => id != threadId),
          ].take(5).toList();
    state = state.copyWith(selectedThreadId: threadId, recentThreadIds: recents);
  }

  /// Picks the visually displayed (composite/blended) colour at [x],[y] and
  /// selects it, switching back to draw mode.
  void pickColorAtCell(int x, int y) {
    final s = state;
    final threadMap = <String, Thread>{
      for (final t in s.pattern.threads) t.dmcCode: t,
    };

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
        ...s.recentThreadIds.where((id) => id != threadId),
      ].take(5).toList();
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
      for (final stitch in layer.stitches) {
        if (stitch is FullStitch && stitch.x == x && stitch.y == y) {
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
        for (final stitch in layer.stitches.reversed) {
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

  void changeThreadSymbol(String dmcCode, String symbol) {
    final newThreads = state.pattern.threads
        .map((t) => t.dmcCode == dmcCode ? t.copyWith(symbol: symbol) : t)
        .toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(threads: newThreads),
      isDirty: true,
    );
  }

  void removeThread(String dmcCode) {
    final newThreads =
        state.pattern.threads.where((t) => t.dmcCode != dmcCode).toList();
    final newPattern = _patternWithAllLayersTransformed(
      state.pattern.copyWith(threads: newThreads),
      (stitches) => stitches.where((s) => s.threadId != dmcCode).toList(),
    );
    final newSelectedId = state.selectedThreadId == dmcCode
        ? (newThreads.isNotEmpty ? newThreads.first.dmcCode : null)
        : state.selectedThreadId;
    state = state.copyWith(
      pattern: newPattern,
      selectedThreadId: newSelectedId,
      isDirty: true,
    );
  }

  /// Replaces every stitch using [oldDmcCode] with [newDmcCode] and updates
  /// the thread palette. The old thread's symbol is preserved.
  void replaceThread(
      String oldDmcCode, String newDmcCode, Color newColor, String newName) {
    if (oldDmcCode == newDmcCode) return;
    final oldThread = state.pattern.threads
        .where((t) => t.dmcCode == oldDmcCode)
        .firstOrNull;
    if (oldThread == null) return;

    final newThread = Thread(
        dmcCode: newDmcCode, color: newColor, name: newName, symbol: oldThread.symbol);

    var threads = state.pattern.threads.toList();
    final oldIdx = threads.indexWhere((t) => t.dmcCode == oldDmcCode);
    final newExists = threads.any((t) => t.dmcCode == newDmcCode);
    if (newExists) {
      threads.removeAt(oldIdx);
    } else {
      threads[oldIdx] = newThread;
    }

    final remappedPattern = _patternWithAllLayersTransformed(
      state.pattern.copyWith(threads: threads),
      (stitches) => stitches
          .map((s) => s.threadId == oldDmcCode ? _withThreadId(s, newDmcCode) : s)
          .toList(),
    );

    state = state.copyWith(
      pattern: remappedPattern,
      selectedThreadId:
          state.selectedThreadId == oldDmcCode ? newDmcCode : state.selectedThreadId,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Changes the symbol displayed on a thread's swatch.
  void setThreadSymbol(String dmcCode, String symbol) {
    final threads = state.pattern.threads
        .map((t) => t.dmcCode == dmcCode ? t.copyWith(symbol: symbol) : t)
        .toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(threads: threads),
      isDirty: true,
    );
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
    final alreadyExists = state.activeLayer.stitches
        .any((s) => s == stitch && s.threadId == stitch.threadId);
    if (alreadyExists) return;

    var pattern = state.pattern;
    final threadId = stitch.threadId;
    Thread? addedThread;
    if (!pattern.threads.any((t) => t.dmcCode == threadId)) {
      final dmc = dmcColorByCode(threadId);
      if (dmc != null) {
        final usedSymbols = _allUsedSymbols(pattern);
        addedThread = Thread(
          dmcCode: dmc.code,
          color: dmc.color,
          name: dmc.name,
          symbol: _nextSymbol(usedSymbols),
        );
        pattern = pattern.copyWith(threads: [...pattern.threads, addedThread]);
      }
    }

    var snippetPalettes = state.snippetPalettes;
    if (addedThread != null && snippetPalettes.isNotEmpty) {
      snippetPalettes = snippetPalettes
          .map((p) => p.copyWith(threads: [...p.threads, addedThread!]))
          .toList();
    }

    final newStitches = _stitchesWithAdded(state.activeLayer.stitches, stitch);
    final rawPattern = _patternWithActiveLayerStitches(pattern, newStitches);
    // Prune threads whose last stitch was painted over by a different colour.
    final newPattern = _pruneUnusedThreads(rawPattern);
    state = state.copyWith(
      pattern: newPattern,
      snippetPalettes: snippetPalettes,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void removeStitchesAt(int x, int y) {
    if (state.activeLayer.locked) return;
    bool hit(Stitch s) => _stitchAtCell(s, x, y) || _backstitchInCell(s, x, y);
    if (!state.activeLayer.stitches.any(hit)) return;

    final newStitches = state.activeLayer.stitches.where((s) => !hit(s)).toList();
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayerStitches(state.pattern, newStitches));
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
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
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
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

    final layerStitches = state.activeLayer.stitches;

    String? seedThreadId;
    for (final s in layerStitches) {
      if (s is FullStitch && s.x == startX && s.y == startY) {
        seedThreadId = s.threadId;
        break;
      }
    }

    if (erase && seedThreadId == null) return;
    final fillThreadId = state.selectedThreadId;
    if (!erase && fillThreadId == null) return;
    if (!erase && seedThreadId == fillThreadId) return;

    final Map<int, String> occupied = {};
    for (final s in layerStitches) {
      if (s is FullStitch) occupied[s.x * 100000 + s.y] = s.threadId;
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

    List<Stitch> newStitches = [...layerStitches];
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
      isDirty: true,
      redoStack: [],
    );
  }

  void removeBackstitchAt(double x1, double y1, double x2, double y2) {
    final target = BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: '');
    if (!state.activeLayer.stitches.any((s) => s == target)) return;

    final newStitches =
        state.activeLayer.stitches.where((s) => s != target).toList();
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayerStitches(state.pattern, newStitches));
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void setBackstitchStart(Offset? point) {
    state = state.copyWith(backstitchStartPoint: point);
  }

  void resizePattern(int newWidth, int newHeight, int anchorX, int anchorY) {
    final old = state.pattern;
    final dx = (anchorX / 2.0 * (newWidth - old.width)).round();
    final dy = (anchorY / 2.0 * (newHeight - old.height)).round();

    bool inBounds(Stitch s) {
      final coords = EditorState.cellCoords(s);
      if (coords != null) {
        return coords.$1 >= 0 && coords.$1 < newWidth &&
            coords.$2 >= 0 && coords.$2 < newHeight;
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

  // ─── Stitch / block mode ──────────────────────────────────────────────────

  void toggleBlockMode() {
    state = state.copyWith(blockMode: !state.blockMode, isDirty: true);
  }

  void toggleCanvasSelectionMode() {
    state = state.copyWith(canvasSelectionMode: !state.canvasSelectionMode);
  }

  void toggleStitchMode() {
    final entering = !state.stitchMode;
    state = state.copyWith(
      stitchMode: entering,
      drawingMode: entering ? DrawingMode.select : DrawingMode.draw,
      selectionRect: null,
      backstitchStartPoint: null,
      showCompositeThreads: entering,
      stitchCrossMode: false,
      stitchBackMode: false,
    );
    if (entering) refreshCompositeCache();
    _autoSaveStitchMode();
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
