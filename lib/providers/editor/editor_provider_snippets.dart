part of 'editor_provider.dart';

// ─── SnippetsMixin ────────────────────────────────────────────────────────────
//
// Snippet CRUD, resize/transform, clipboard → paste, snippet palette management.

mixin SnippetsMixin on Notifier<EditorState> {

  // Abstract declarations for shared helpers defined in EditorNotifier.
  List<(CrossStitchPattern, List<SnippetPalette>)> _buildUndoStack();
  String _serializeClipboard(List<Thread> threads, List<Stitch> stitches);

  // cancelSelection is provided by SelectionMixin (mixed in on EditorNotifier).
  void cancelSelection();

  // ─── Snippet CRUD ─────────────────────────────────────────────────────────

  void addSnippet(Snippet snippet) {
    state = state.copyWith(
      pattern: state.pattern.copyWith(
        snippets: [...state.pattern.snippets, snippet],
      ),
      isDirty: true,
    );
  }

  void updateSnippet(Snippet snippet) {
    final updated =
        state.pattern.snippets.map((s) => s.id == snippet.id ? snippet : s).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: updated),
      isDirty: true,
    );
  }

  void deleteSnippet(String id) {
    final updated = state.pattern.snippets.where((s) => s.id != id).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: updated),
      isDirty: true,
    );
  }

  void resizeSnippet(String id, int newW, int newH, SnippetResizeMode mode) {
    final snippet = state.pattern.snippets.firstWhere((s) => s.id == id);
    final oldW = snippet.width;
    final oldH = snippet.height;

    List<Stitch> newStitches;
    switch (mode) {
      case SnippetResizeMode.clip:
        newStitches = snippet.stitches.where((s) {
          return switch (s) {
            FullStitch(:final x, :final y) => x < newW && y < newH,
            HalfStitch(:final x, :final y) => x < newW && y < newH,
            QuarterStitch(:final x, :final y) => x < newW && y < newH,
            HalfCrossStitch(:final x, :final y) => x < newW && y < newH,
            QuarterCrossStitch(:final x, :final y) => x < newW && y < newH,
            BackStitch(:final x1, :final y1, :final x2, :final y2) =>
              x1 < newW && y1 < newH && x2 < newW && y2 < newH,
          };
        }).toList();
      case SnippetResizeMode.scale:
        newStitches = snippet.stitches.map((s) {
          int sx(int x) => (x / oldW * newW).round().clamp(0, newW - 1);
          int sy(int y) => (y / oldH * newH).round().clamp(0, newH - 1);
          double sdx(double x) => (x / oldW * newW).clamp(0.0, newW.toDouble());
          double sdy(double y) => (y / oldH * newH).clamp(0.0, newH.toDouble());
          return switch (s) {
            FullStitch(:final x, :final y, :final threadId) =>
              FullStitch(x: sx(x), y: sy(y), threadId: threadId),
            HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
              HalfStitch(x: sx(x), y: sy(y), isForward: isForward, threadId: threadId),
            QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
              QuarterStitch(x: sx(x), y: sy(y), quadrant: quadrant, threadId: threadId),
            HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
              HalfCrossStitch(x: sx(x), y: sy(y), half: half, threadId: threadId),
            QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
              QuarterCrossStitch(x: sx(x), y: sy(y), quadrant: quadrant, threadId: threadId),
            BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
              BackStitch(x1: sdx(x1), y1: sdy(y1), x2: sdx(x2), y2: sdy(y2), threadId: threadId),
          };
        }).toList();
      case SnippetResizeMode.expand:
        newStitches = snippet.stitches;
    }

    final resized = snippet.copyWith(width: newW, height: newH, stitches: newStitches);
    final updated =
        state.pattern.snippets.map((s) => s.id == id ? resized : s).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: updated),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void transformSnippet(String id, SnippetTransform transform) {
    final snippet = state.pattern.snippets.firstWhere((s) => s.id == id);
    final w = snippet.width;
    final h = snippet.height;

    QuadrantPosition flipHQuad(QuadrantPosition q) => switch (q) {
          QuadrantPosition.topLeft    => QuadrantPosition.topRight,
          QuadrantPosition.topRight   => QuadrantPosition.topLeft,
          QuadrantPosition.bottomLeft => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
        };
    HalfOrientation flipHHalf(HalfOrientation o) => switch (o) {
          HalfOrientation.left   => HalfOrientation.right,
          HalfOrientation.right  => HalfOrientation.left,
          HalfOrientation.top    => HalfOrientation.top,
          HalfOrientation.bottom => HalfOrientation.bottom,
        };
    QuadrantPosition flipVQuad(QuadrantPosition q) => switch (q) {
          QuadrantPosition.topLeft    => QuadrantPosition.bottomLeft,
          QuadrantPosition.topRight   => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
          QuadrantPosition.bottomRight => QuadrantPosition.topRight,
        };
    HalfOrientation flipVHalf(HalfOrientation o) => switch (o) {
          HalfOrientation.top    => HalfOrientation.bottom,
          HalfOrientation.bottom => HalfOrientation.top,
          HalfOrientation.left   => HalfOrientation.left,
          HalfOrientation.right  => HalfOrientation.right,
        };
    QuadrantPosition cwQuad(QuadrantPosition q) => switch (q) {
          QuadrantPosition.topLeft    => QuadrantPosition.topRight,
          QuadrantPosition.topRight   => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
          QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
        };
    HalfOrientation cwHalf(HalfOrientation o) => switch (o) {
          HalfOrientation.top    => HalfOrientation.right,
          HalfOrientation.right  => HalfOrientation.bottom,
          HalfOrientation.bottom => HalfOrientation.left,
          HalfOrientation.left   => HalfOrientation.top,
        };

    Stitch applyFlipH(Stitch s) => switch (s) {
          FullStitch(:final x, :final y, :final threadId) =>
            FullStitch(x: w - 1 - x, y: y, threadId: threadId),
          HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
            HalfStitch(x: w - 1 - x, y: y, isForward: !isForward, threadId: threadId),
          QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
            QuarterStitch(x: w - 1 - x, y: y, quadrant: flipHQuad(quadrant), threadId: threadId),
          HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
            HalfCrossStitch(x: w - 1 - x, y: y, half: flipHHalf(half), threadId: threadId),
          QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
            QuarterCrossStitch(x: w - 1 - x, y: y, quadrant: flipHQuad(quadrant), threadId: threadId),
          BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
            BackStitch(x1: w - x1, y1: y1, x2: w - x2, y2: y2, threadId: threadId),
        };

    Stitch applyFlipV(Stitch s) => switch (s) {
          FullStitch(:final x, :final y, :final threadId) =>
            FullStitch(x: x, y: h - 1 - y, threadId: threadId),
          HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
            HalfStitch(x: x, y: h - 1 - y, isForward: !isForward, threadId: threadId),
          QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
            QuarterStitch(x: x, y: h - 1 - y, quadrant: flipVQuad(quadrant), threadId: threadId),
          HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
            HalfCrossStitch(x: x, y: h - 1 - y, half: flipVHalf(half), threadId: threadId),
          QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
            QuarterCrossStitch(x: x, y: h - 1 - y, quadrant: flipVQuad(quadrant), threadId: threadId),
          BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
            BackStitch(x1: x1, y1: h - y1, x2: x2, y2: h - y2, threadId: threadId),
        };

    // CW 90°: cell (x,y) → (h-1-y, x); BackStitch grid point (x,y) → (h-y, x)
    Stitch applyRotateCW(Stitch s) => switch (s) {
          FullStitch(:final x, :final y, :final threadId) =>
            FullStitch(x: h - 1 - y, y: x, threadId: threadId),
          HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
            HalfStitch(x: h - 1 - y, y: x, isForward: !isForward, threadId: threadId),
          QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
            QuarterStitch(x: h - 1 - y, y: x, quadrant: cwQuad(quadrant), threadId: threadId),
          HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
            HalfCrossStitch(x: h - 1 - y, y: x, half: cwHalf(half), threadId: threadId),
          QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
            QuarterCrossStitch(x: h - 1 - y, y: x, quadrant: cwQuad(quadrant), threadId: threadId),
          BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
            BackStitch(x1: h - y1, y1: x1, x2: h - y2, y2: x2, threadId: threadId),
        };

    final (newW, newH, newStitches) = switch (transform) {
      SnippetTransform.flipH    => (w, h, snippet.stitches.map(applyFlipH).toList()),
      SnippetTransform.flipV    => (w, h, snippet.stitches.map(applyFlipV).toList()),
      SnippetTransform.rotateCW => (h, w, snippet.stitches.map(applyRotateCW).toList()),
    };

    final transformed = snippet.copyWith(width: newW, height: newH, stitches: newStitches);
    final updated =
        state.pattern.snippets.map((s) => s.id == id ? transformed : s).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: updated),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Saves the current selection (select mode) or clipboard (paste mode) as a new snippet.
  void saveSelectionAsSnippet(String name) {
    final List<Stitch> stitches;
    final List<Thread> threads;

    if (state.drawingMode == DrawingMode.paste) {
      stitches = state.clipboard ?? [];
      threads = state.clipboardThreads ?? [];
    } else {
      final rect = state.selectionRect;
      if (rect == null) return;
      final inSel = state.activeLayer.stitches
          .where((s) => EditorState.isStitchInRect(s, rect))
          .toList();
      if (inSel.isEmpty) return;
      stitches = inSel
          .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
          .toList();
      final threadIds = stitches.map((s) => s.threadId).toSet();
      threads = state.pattern.threads
          .where((t) => threadIds.contains(t.dmcCode))
          .toList();
    }

    if (stitches.isEmpty) return;

    var maxX = 0, maxY = 0;
    for (final s in stitches) {
      final coords = EditorState.cellCoords(s);
      if (coords != null) {
        if (coords.$1 + 1 > maxX) maxX = coords.$1 + 1;
        if (coords.$2 + 1 > maxY) maxY = coords.$2 + 1;
      }
    }

    addSnippet(Snippet.create(
      name: name,
      width: maxX,
      height: maxY,
      threads: threads,
      stitches: stitches,
    ));

    if (state.drawingMode == DrawingMode.paste) {
      cancelSelection();
    }
  }

  /// Loads a snippet into the in-memory and system clipboard, then enters paste mode.
  Future<void> loadSnippetToClipboard(Snippet snippet) async {
    await Clipboard.setData(
      ClipboardData(
          text: _serializeClipboard(snippet.threads, snippet.stitches)),
    );
    state = state.copyWith(
      clipboard: snippet.stitches,
      clipboardThreads: snippet.threads,
      drawingMode: DrawingMode.paste,
      selectionRect: null,
      clipboardFromSnippet: true,
    );
  }

  // ─── Snippet palette (stored in pattern) ─────────────────────────────────

  void setSnippetActivePalette(String snippetId, int index) {
    final snippets = state.pattern.snippets.map((s) {
      if (s.id != snippetId) return s;
      return s.copyWith(activePaletteIndex: index.clamp(0, s.palettes.length - 1));
    }).toList();
    state = state.copyWith(
        pattern: state.pattern.copyWith(snippets: snippets), isDirty: true);
  }

  void addSnippetPalette(String snippetId, SnippetPalette palette) {
    final snippets = state.pattern.snippets.map((s) {
      if (s.id != snippetId) return s;
      final newPalettes = [...s.palettes, palette];
      return s.copyWith(palettes: newPalettes, activePaletteIndex: newPalettes.length - 1);
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: snippets),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void deleteSnippetPalette(String snippetId, String paletteId) {
    final snippets = state.pattern.snippets.map((s) {
      if (s.id != snippetId || s.palettes.length <= 1) return s;
      final newPalettes = s.palettes.where((p) => p.id != paletteId).toList();
      return s.copyWith(
          palettes: newPalettes,
          activePaletteIndex: s.activePaletteIndex.clamp(0, newPalettes.length - 1));
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: snippets),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void renameSnippetPalette(String snippetId, String paletteId, String name) {
    final snippets = state.pattern.snippets.map((s) {
      if (s.id != snippetId) return s;
      final newPalettes =
          s.palettes.map((p) => p.id != paletteId ? p : p.copyWith(name: name)).toList();
      return s.copyWith(palettes: newPalettes);
    }).toList();
    state = state.copyWith(
        pattern: state.pattern.copyWith(snippets: snippets), isDirty: true);
  }

  void reorderSnippetPalette(String snippetId, int oldIndex, int newIndex) {
    final snippets = state.pattern.snippets.map((s) {
      if (s.id != snippetId) return s;
      final palettes = [...s.palettes];
      if (oldIndex < 0 || oldIndex >= palettes.length) return s;
      final palette = palettes.removeAt(oldIndex);
      final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
      palettes.insert(insertIdx.clamp(0, palettes.length), palette);
      int newActive = s.activePaletteIndex;
      if (s.activePaletteIndex == oldIndex) {
        newActive = insertIdx.clamp(0, palettes.length - 1);
      }
      return s.copyWith(palettes: palettes, activePaletteIndex: newActive);
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: snippets),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  // ─── Snippet editor local palette state ───────────────────────────────────

  void initSnippetPalettesLocal(List<SnippetPalette> palettes, int activeIndex) {
    state = state.copyWith(
      snippetPalettes: palettes,
      snippetActivePaletteIndex: activeIndex,
    );
  }

  void setSnippetActivePaletteLocal(int index) {
    state = state.copyWith(snippetActivePaletteIndex: index);
  }

  void addSnippetPaletteLocal(SnippetPalette palette) {
    final newPalettes = [...state.snippetPalettes, palette];
    state = state.copyWith(
      snippetPalettes: newPalettes,
      snippetActivePaletteIndex: newPalettes.length - 1,
    );
  }

  void deleteSnippetPaletteLocal(String paletteId) {
    if (state.snippetPalettes.length <= 1) return;
    final newPalettes =
        state.snippetPalettes.where((p) => p.id != paletteId).toList();
    final newActive =
        state.snippetActivePaletteIndex.clamp(0, newPalettes.length - 1);
    state = state.copyWith(
        snippetPalettes: newPalettes, snippetActivePaletteIndex: newActive);
  }

  void renameSnippetPaletteLocal(String paletteId, String name) {
    final newPalettes = state.snippetPalettes
        .map((p) => p.id == paletteId ? p.copyWith(name: name) : p)
        .toList();
    state = state.copyWith(snippetPalettes: newPalettes);
  }

  void setSnippetPaletteThreadColor(
      int paletteIndex, int slotIndex, Thread newThread) {
    final palettes = List<SnippetPalette>.from(state.snippetPalettes);
    if (paletteIndex < 0 || paletteIndex >= palettes.length) return;
    final threads = List<Thread>.from(palettes[paletteIndex].threads);
    if (slotIndex < 0 || slotIndex >= threads.length) return;
    threads[slotIndex] = newThread;
    palettes[paletteIndex] = palettes[paletteIndex].copyWith(threads: threads);
    // Non-zero palettes don't modify the pattern; push a palette-only undo entry.
    if (paletteIndex > 0) {
      state = state.copyWith(
        snippetPalettes: palettes,
        undoStack: _buildUndoStack(),
        redoStack: [],
      );
    } else {
      state = state.copyWith(snippetPalettes: palettes);
    }
  }

  void deleteSnippetPaletteByIndex(int index) {
    final palettes = List<SnippetPalette>.from(state.snippetPalettes);
    if (palettes.length <= 1 || index < 0 || index >= palettes.length) return;
    palettes.removeAt(index);
    final activeIdx = state.snippetActivePaletteIndex;
    state = state.copyWith(
      snippetPalettes: palettes,
      snippetActivePaletteIndex:
          activeIdx >= palettes.length ? palettes.length - 1 : activeIdx,
    );
  }

  void renameSnippetPaletteByIndex(int index, String name) {
    final palettes = List<SnippetPalette>.from(state.snippetPalettes);
    if (index < 0 || index >= palettes.length) return;
    palettes[index] = palettes[index].copyWith(name: name);
    state = state.copyWith(snippetPalettes: palettes);
  }

  void reorderSnippetPaletteLocal(int oldIndex, int newIndex) {
    final palettes = [...state.snippetPalettes];
    if (oldIndex < 0 || oldIndex >= palettes.length) return;
    final palette = palettes.removeAt(oldIndex);
    final insertIdx =
        (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, palettes.length);
    palettes.insert(insertIdx, palette);
    int newActive = state.snippetActivePaletteIndex;
    if (state.snippetActivePaletteIndex == oldIndex) {
      newActive = insertIdx.clamp(0, palettes.length - 1);
    }
    state = state.copyWith(
        snippetPalettes: palettes, snippetActivePaletteIndex: newActive);
  }
}
