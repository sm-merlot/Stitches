part of 'editor_provider.dart';

// ─── SelectionMixin ───────────────────────────────────────────────────────────
//
// Rubber-band selection, clipboard copy/paste, move/delete selection.

mixin SelectionMixin on Notifier<EditorState> {

  // Abstract declarations for shared helpers defined in EditorNotifier.
  void warnNoSelection();
  List<Stitch> _stitchesWithAdded(List<Stitch> existing, Stitch stitch);
  CrossStitchPattern _patternWithActiveLayerStitches(
      CrossStitchPattern p, List<Stitch> s);
  bool _isInBounds(Stitch s, int maxX, int maxY);
  CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern);
  Thread _resolveThreadSymbol(Thread thread, List<Thread> existingThreads);
  String _serializeClipboard(List<Thread> threads, List<Stitch> stitches);
  void refreshCompositeCache(); // provided by LayersMixin

  // ─── Private helpers ──────────────────────────────────────────────────────

  (List<Thread>, List<Stitch>)? _parseClipboard(String text) {
    try {
      final root = (jsonDecode(text) as Map<String, dynamic>)['stitches'];
      if (root == null) return null;
      final threads = (root['threads'] as List)
          .map((t) => Thread.fromYaml(t as Map<String, dynamic>))
          .toList();
      final stitches = (root['stitches'] as List)
          .map((s) => Stitch.fromYaml(s as Map<String, dynamic>))
          .toList();
      return (threads, stitches);
    } catch (_) {
      return null;
    }
  }

  // Appends the layer hint unless canvas-selection mode is active.
  String _layerWarn(String base) =>
      state.canvasSelectionMode ? base : base + kLayerHint;

  // ─── Selection management ─────────────────────────────────────────────────

  void setSelectionRect(Rect? rect) {
    state = state.copyWith(selectionRect: rect);
  }

  void selectAll() {
    state = state.copyWith(
      selectionRect: Rect.fromLTWH(
          0, 0, state.pattern.width.toDouble(), state.pattern.height.toDouble()),
      drawingMode: DrawingMode.select,
      backstitchStartPoint: null,
    );
  }

  Future<void> copySelection() async {
    final rect = state.selectionRect;
    if (rect == null) {
      warnNoSelection();
      return;
    }
    final List<Stitch> inSel;
    if (state.canvasSelectionMode) {
      // Use the compositor's already-deduplicated visible stitch list so the
      // copy matches exactly what is rendered on the canvas: one winner per cell
      // (topmost visible normal-blend opaque layer) plus all visible backstitches.
      // Falls back to raw layer iteration if the composite cache is stale/absent.
      final layer = state.compositeLayer;
      if (layer != null) {
        inSel = [
          ...layer.fullStitches.values.map((cs) => cs.stitch)
              .where((s) => EditorState.isStitchInRect(s, rect)),
          ...layer.otherStitches.map((cs) => cs.stitch)
              .where((s) => EditorState.isStitchInRect(s, rect)),
          ...layer.backstitches
              .where((s) => EditorState.isStitchInRect(s, rect)),
        ];
      } else {
        inSel = state.pattern.layers
            .where((l) => l.visible)
            .expand((l) => l.stitches.where((s) => EditorState.isStitchInRect(s, rect)))
            .toList();
      }
    } else {
      inSel = state.activeLayer.stitches
          .where((s) => EditorState.isStitchInRect(s, rect))
          .toList();
    }
    if (inSel.isEmpty) {
      state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToCopy));
      return;
    }
    final clips = inSel
        .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
        .toList();
    final threadIds = clips.map((s) => s.threadId).toSet();
    final threads = state.pattern.threads.values
        .where((t) => threadIds.contains(t.dmcCode))
        .toList();
    await Clipboard.setData(ClipboardData(text: _serializeClipboard(threads, clips)));
    state = state.copyWith(
      clipboard: clips,
      clipboardThreads: threads,
      drawingMode: DrawingMode.paste,
      selectionRect: null,
      clipboardFromSnippet: false,
    );
  }

  /// Reads the system clipboard and enters paste mode if valid stitches data is found.
  /// Falls back to the in-memory clipboard if the system clipboard has other content.
  Future<void> enterPasteMode() async {
    // Paste only works in edit mode.
    if (!state.editMode) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final parsed = _parseClipboard(data!.text!);
      if (parsed != null) {
        final (threads, stitches) = parsed;
        state = state.copyWith(
          clipboard: stitches,
          clipboardThreads: threads,
          drawingMode: DrawingMode.paste,
          selectionRect: null,
        );
        return;
      }
    }
    if (state.clipboard == null || state.clipboard!.isEmpty) return;
    state = state.copyWith(drawingMode: DrawingMode.paste, selectionRect: null);
  }

  /// Stamps the clipboard contents at offset [dx],[dy] from origin (0,0).
  /// Any clipboard threads not yet in the pattern are added automatically.
  void commitPaste(int dx, int dy) {
    if (!state.editMode) return;
    final clips = state.clipboard;
    if (clips == null || clips.isEmpty) return;
    final maxX = state.pattern.width;
    final maxY = state.pattern.height;

    var threads = Map<String, Thread>.from(state.pattern.threads);
    for (final ct in state.clipboardThreads ?? <Thread>[]) {
      if (!threads.containsKey(ct.dmcCode)) {
        final resolved = _resolveThreadSymbol(ct, threads.values.toList());
        threads[resolved.dmcCode] = resolved;
      }
    }

    // Collect all in-bounds placed stitches first, then do a single-pass merge.
    // Stitch equality is position-based, so the set lookup correctly evicts
    // any existing stitch at the same slot before we append the new ones.
    final placed = <Stitch>[];
    bool hasBackstitch = false;
    for (final s in clips) {
      final p = EditorState.offsetStitch(s, dx, dy);
      if (_isInBounds(p, maxX, maxY)) {
        placed.add(p);
        if (p is BackStitch) hasBackstitch = true;
      }
    }
    final replaceSet = <Stitch>{...placed};
    final stitches = [
      ...state.activeLayer.stitches.where((s) => !replaceSet.contains(s)),
      ...placed,
    ];
    final newPattern = _patternWithActiveLayerStitches(
        state.pattern.copyWith(threads: threads), stitches);

    // Incremental composite: patch only cells touched by the paste.
    final dirtyCells = <Cell>{
      for (final s in placed) ?s.cellCoords,
    };
    final oldComposite = state.compositeLayer;
    final newComposite = oldComposite != null
        ? StitchCompositor.patchCells(
            oldComposite, newPattern, dirtyCells,
            backstitchesChanged: hasBackstitch)
        : StitchCompositor.computeComposite(newPattern);

    state = state.copyWith(
      pattern: newPattern,
      compositeLayer: newComposite,
      dirtyCellKeys: dirtyCells.isEmpty ? null : dirtyCells,
      isDirty: true,
    );
    // Debounced full refresh for stitch-count equivalents.
    refreshCompositeCache();
  }

  void moveSelection(int dx, int dy) {
    final rect = state.selectionRect;
    if (rect == null) return;
    final maxX = state.pattern.width;
    final maxY = state.pattern.height;
    final newRect = Rect.fromLTWH(
      (rect.left + dx).clamp(0, maxX.toDouble()),
      (rect.top + dy).clamp(0, maxY.toDouble()),
      rect.width,
      rect.height,
    );
    if (state.canvasSelectionMode) {
      final hasAny = state.pattern.layers
          .where((l) => l.visible)
          .any((l) => l.stitches.any((s) => EditorState.isStitchInRect(s, rect)));
      if (!hasAny) {
        state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToMove));
        return;
      }
      final newPattern = state.pattern.mapLayers((layer) {
        if (!layer.visible) return layer;
        final inS = layer.stitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
        if (inS.isEmpty) return layer;
        var remaining = layer.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
        for (final s in inS) {
          final moved = EditorState.offsetStitch(s, dx, dy);
          if (_isInBounds(moved, maxX, maxY)) remaining = _stitchesWithAdded(remaining, moved);
        }
        return layer.copyWith(stitches: remaining);
      });
      state = state.copyWith(
        pattern: newPattern,
        selectionRect: newRect,
        compositeLayer: null,
        isDirty: true,
      );
      refreshCompositeCache();
      return;
    }
    final activeStitches = state.activeLayer.stitches;
    final inSel =
        activeStitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) {
      state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToMove));
      return;
    }
    var remaining =
        activeStitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    for (final s in inSel) {
      final moved = EditorState.offsetStitch(s, dx, dy);
      if (_isInBounds(moved, maxX, maxY)) {
        remaining = _stitchesWithAdded(remaining, moved);
      }
    }
    final newPattern = _patternWithActiveLayerStitches(state.pattern, remaining);
    state = state.copyWith(
      pattern: newPattern,
      selectionRect: newRect,
      compositeLayer: null,
      isDirty: true,
    );
    refreshCompositeCache();
  }

  void deleteSelection() {
    final rect = state.selectionRect;
    if (rect == null) return;
    if (state.canvasSelectionMode) {
      final hasAny = state.pattern.layers
          .where((l) => l.visible)
          .any((l) => l.stitches.any((s) => EditorState.isStitchInRect(s, rect)));
      if (!hasAny) {
        state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToDelete));
        return;
      }
      final newPattern = _pruneUnusedThreads(state.pattern.mapLayers((layer) {
        if (!layer.visible) return layer;
        return layer.copyWith(
          stitches: layer.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList(),
        );
      }));
      state = state.copyWith(
        pattern: newPattern,
        selectionRect: null,
        compositeLayer: null,
        isDirty: true,
      );
      refreshCompositeCache();
      return;
    }
    final activeStitches = state.activeLayer.stitches;
    if (!activeStitches.any((s) => EditorState.isStitchInRect(s, rect))) {
      state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToDelete));
      return;
    }
    final remaining =
        activeStitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayerStitches(state.pattern, remaining));
    state = state.copyWith(
      pattern: newPattern,
      selectionRect: null,
      compositeLayer: null,
      isDirty: true,
    );
    refreshCompositeCache();
  }

  /// Escape: if in paste mode, exit back to select; otherwise clear selection rect.
  void cancelSelection() {
    if (state.drawingMode == DrawingMode.paste) {
      state = state.copyWith(drawingMode: DrawingMode.select);
    } else {
      state = state.copyWith(selectionRect: null);
    }
  }

  // ─── Selection transform helpers ──────────────────────────────────────────

  /// Returns a stitch horizontally flipped within a bounding box at (l,t) with width w.
  static Stitch _flipStitchH(Stitch s, int l, int t, int w) => switch (s) {
    FullStitch(:final x, :final y, :final threadId) =>
      FullStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId),
    HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
      HalfStitch(x: (l + w - 1) - (x - l), y: y, isForward: !isForward, threadId: threadId),
    QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
      QuarterStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId,
        quadrant: switch (quadrant) {
          QuadrantPosition.topLeft => QuadrantPosition.topRight,
          QuadrantPosition.topRight => QuadrantPosition.topLeft,
          QuadrantPosition.bottomLeft => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
        }),
    HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
      HalfCrossStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId,
        half: switch (half) {
          HalfOrientation.left => HalfOrientation.right,
          HalfOrientation.right => HalfOrientation.left,
          HalfOrientation.top => HalfOrientation.top,
          HalfOrientation.bottom => HalfOrientation.bottom,
        }),
    QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
      QuarterCrossStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId,
        quadrant: switch (quadrant) {
          QuadrantPosition.topLeft => QuadrantPosition.topRight,
          QuadrantPosition.topRight => QuadrantPosition.topLeft,
          QuadrantPosition.bottomLeft => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
        }),
    BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
      BackStitch(
        x1: (l + w) - (x1 - l), y1: y1,
        x2: (l + w) - (x2 - l), y2: y2,
        threadId: threadId),
  };

  /// Returns a stitch vertically flipped within a bounding box at (l,t) with height h.
  static Stitch _flipStitchV(Stitch s, int l, int t, int h) => switch (s) {
    FullStitch(:final x, :final y, :final threadId) =>
      FullStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId),
    HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
      HalfStitch(x: x, y: (t + h - 1) - (y - t), isForward: !isForward, threadId: threadId),
    QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
      QuarterStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId,
        quadrant: switch (quadrant) {
          QuadrantPosition.topLeft => QuadrantPosition.bottomLeft,
          QuadrantPosition.topRight => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
          QuadrantPosition.bottomRight => QuadrantPosition.topRight,
        }),
    HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
      HalfCrossStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId,
        half: switch (half) {
          HalfOrientation.left => HalfOrientation.left,
          HalfOrientation.right => HalfOrientation.right,
          HalfOrientation.top => HalfOrientation.bottom,
          HalfOrientation.bottom => HalfOrientation.top,
        }),
    QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
      QuarterCrossStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId,
        quadrant: switch (quadrant) {
          QuadrantPosition.topLeft => QuadrantPosition.bottomLeft,
          QuadrantPosition.topRight => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
          QuadrantPosition.bottomRight => QuadrantPosition.topRight,
        }),
    BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
      BackStitch(
        x1: x1, y1: (t + h) - (y1 - t),
        x2: x2, y2: (t + h) - (y2 - t),
        threadId: threadId),
  };

  /// Returns a stitch rotated 90° CW within a bounding box at (l,t) with size w×h.
  static Stitch _rotateStitchCW(Stitch s, int l, int t, int w, int h) {
    int rx(int x, int y) => l + (h - 1 - (y - t));
    int ry(int x, int y) => t + (x - l);
    double rbsX(double x, double y) => l + (h - (y - t));
    double rbsY(double x, double y) => t + (x - l);

    return switch (s) {
      FullStitch(:final x, :final y, :final threadId) =>
        FullStitch(x: rx(x, y), y: ry(x, y), threadId: threadId),
      HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
        HalfStitch(x: rx(x, y), y: ry(x, y), isForward: !isForward, threadId: threadId),
      QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
        QuarterStitch(x: rx(x, y), y: ry(x, y), threadId: threadId,
          quadrant: switch (quadrant) {
            QuadrantPosition.topLeft => QuadrantPosition.topRight,
            QuadrantPosition.topRight => QuadrantPosition.bottomRight,
            QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
            QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
          }),
      HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
        HalfCrossStitch(x: rx(x, y), y: ry(x, y), threadId: threadId,
          half: switch (half) {
            HalfOrientation.top => HalfOrientation.right,
            HalfOrientation.right => HalfOrientation.bottom,
            HalfOrientation.bottom => HalfOrientation.left,
            HalfOrientation.left => HalfOrientation.top,
          }),
      QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
        QuarterCrossStitch(x: rx(x, y), y: ry(x, y), threadId: threadId,
          quadrant: switch (quadrant) {
            QuadrantPosition.topLeft => QuadrantPosition.topRight,
            QuadrantPosition.topRight => QuadrantPosition.bottomRight,
            QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
            QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
          }),
      BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
        BackStitch(
          x1: rbsX(x1, y1), y1: rbsY(x1, y1),
          x2: rbsX(x2, y2), y2: rbsY(x2, y2),
          threadId: threadId),
    };
  }

  // ─── Selection flip/rotate ─────────────────────────────────────────────────

  void flipSelectionH() {
    final rect = state.selectionRect;
    if (rect == null) return;
    final l = rect.left.floor();
    final t = rect.top.floor();
    final w = rect.width.round();
    bool inSel(Stitch s) => EditorState.isStitchInRect(s, rect);
    if (state.canvasSelectionMode) {
      final hasAny = state.pattern.layers
          .where((l) => l.visible)
          .any((l) => l.stitches.any((s) => EditorState.isStitchInRect(s, rect)));
      if (!hasAny) {
        state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToFlip));
        return;
      }
      state = state.copyWith(
        pattern: state.pattern.mapLayers((layer) {
          if (!layer.visible) return layer;
          return layer.copyWith(
            stitches: layer.stitches.map((s) => inSel(s) ? _flipStitchH(s, l, t, w) : s).toList(),
          );
        }),
      );
      return;
    }
    if (!state.activeLayer.stitches.any((s) => EditorState.isStitchInRect(s, rect))) {
      state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToFlip));
      return;
    }
    final newStitches = state.activeLayer.stitches
        .map((s) => inSel(s) ? _flipStitchH(s, l, t, w) : s)
        .toList();
    state = state.copyWith(
      pattern: _patternWithActiveLayerStitches(state.pattern, newStitches),
    );
  }

  void flipSelectionV() {
    final rect = state.selectionRect;
    if (rect == null) return;
    final l = rect.left.floor();
    final t = rect.top.floor();
    final h = rect.height.round();
    bool inSel(Stitch s) => EditorState.isStitchInRect(s, rect);
    if (state.canvasSelectionMode) {
      final hasAny = state.pattern.layers
          .where((layer) => layer.visible)
          .any((layer) => layer.stitches.any((s) => EditorState.isStitchInRect(s, rect)));
      if (!hasAny) {
        state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToFlip));
        return;
      }
      state = state.copyWith(
        pattern: state.pattern.mapLayers((layer) {
          if (!layer.visible) return layer;
          return layer.copyWith(
            stitches: layer.stitches.map((s) => inSel(s) ? _flipStitchV(s, l, t, h) : s).toList(),
          );
        }),
      );
      return;
    }
    if (!state.activeLayer.stitches.any((s) => EditorState.isStitchInRect(s, rect))) {
      state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToFlip));
      return;
    }
    final newStitches = state.activeLayer.stitches
        .map((s) => inSel(s) ? _flipStitchV(s, l, t, h) : s)
        .toList();
    state = state.copyWith(
      pattern: _patternWithActiveLayerStitches(state.pattern, newStitches),
    );
  }

  void rotateSelectionCW() {
    final rect = state.selectionRect;
    if (rect == null) return;
    final l = rect.left.floor();
    final t = rect.top.floor();
    final w = rect.width.round();
    final h = rect.height.round();
    bool inSel(Stitch s) => EditorState.isStitchInRect(s, rect);
    // After CW rotation the selection occupies same top-left but w↔h swap
    final newRect = Rect.fromLTWH(rect.left, rect.top, rect.height, rect.width);
    if (state.canvasSelectionMode) {
      final hasAny = state.pattern.layers
          .where((layer) => layer.visible)
          .any((layer) => layer.stitches.any((s) => EditorState.isStitchInRect(s, rect)));
      if (!hasAny) {
        state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToRotate));
        return;
      }
      state = state.copyWith(
        pattern: state.pattern.mapLayers((layer) {
          if (!layer.visible) return layer;
          return layer.copyWith(
            stitches: layer.stitches.map((s) => inSel(s) ? _rotateStitchCW(s, l, t, w, h) : s).toList(),
          );
        }),
        selectionRect: newRect,
      );
      return;
    }
    if (!state.activeLayer.stitches.any((s) => EditorState.isStitchInRect(s, rect))) {
      state = state.copyWith(pendingCanvasWarning: _layerWarn(kWarnNothingToRotate));
      return;
    }
    final newStitches = state.activeLayer.stitches
        .map((s) => inSel(s) ? _rotateStitchCW(s, l, t, w, h) : s)
        .toList();
    state = state.copyWith(
      pattern: _patternWithActiveLayerStitches(state.pattern, newStitches),
      selectionRect: newRect,
    );
  }

  // ─── Clipboard flip/rotate ─────────────────────────────────────────────────

  void flipClipboardH() {
    final clips = state.clipboard;
    if (clips == null || clips.isEmpty) return;
    final w = clips.fold(0, (m, s) {
      final c = EditorState.cellCoords(s);
      return c != null ? (c.x + 1 > m ? c.x + 1 : m) : m;
    });
    final flipped = clips.map((s) => _flipStitchH(s, 0, 0, w)).toList();
    state = state.copyWith(clipboard: flipped);
  }

  void flipClipboardV() {
    final clips = state.clipboard;
    if (clips == null || clips.isEmpty) return;
    final h = clips.fold(0, (m, s) {
      final c = EditorState.cellCoords(s);
      return c != null ? (c.y + 1 > m ? c.y + 1 : m) : m;
    });
    final flipped = clips.map((s) => _flipStitchV(s, 0, 0, h)).toList();
    state = state.copyWith(clipboard: flipped);
  }

  void rotateClipboardCW() {
    final clips = state.clipboard;
    if (clips == null || clips.isEmpty) return;
    int w = 0, h = 0;
    for (final s in clips) {
      final c = EditorState.cellCoords(s);
      if (c != null) {
        if (c.x + 1 > w) w = c.x + 1;
        if (c.y + 1 > h) h = c.y + 1;
      }
    }
    final rotated = clips.map((s) => _rotateStitchCW(s, 0, 0, w, h)).toList();
    state = state.copyWith(clipboard: rotated);
  }
}
