part of 'editor_provider.dart';

// ─── SnippetsMixin ────────────────────────────────────────────────────────────
//
// Snippet CRUD, resize/transform, clipboard → paste, snippet palette management.

mixin SnippetsMixin on Notifier<EditorState> {

  // Abstract declarations for shared helpers defined in EditorNotifier.
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
            // BackStitch uses grid-point coords (0..width inclusive), so the
            // right/bottom boundary is <= not <.
            BackStitch(:final x1, :final y1, :final x2, :final y2) =>
              x1 <= newW && y1 <= newH && x2 <= newW && y2 <= newH,
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
      isDirty: true,
    );
  }

  /// Saves the current selection (select mode) or clipboard (paste mode) as a new snippet.
  bool saveSelectionAsSnippet(String name) {
    final List<Stitch> stitches;
    final List<Thread> threads;

    if (state.drawingMode == DrawingMode.paste) {
      stitches = state.clipboard ?? [];
      threads = state.clipboardThreads ?? [];
    } else {
      final rect = state.selectionRect;
      if (rect == null) {
        state = state.copyWith(
          pendingCanvasWarning: kWarnSelectFirst,
        );
        return false;
      }
      final List<Stitch> inSel;
      if (state.canvasSelectionMode) {
        inSel = state.pattern.layers
            .where((l) => l.visible)
            .expand((l) => l.stitches.where((s) => EditorState.isStitchInRect(s, rect)))
            .toList();
      } else {
        inSel = state.activeLayer.stitches
            .where((s) => EditorState.isStitchInRect(s, rect))
            .toList();
      }
      if (inSel.isEmpty) {
        state = state.copyWith(
          pendingCanvasWarning: kWarnNothingToSave +
              (state.canvasSelectionMode ? '' : kLayerHint),
        );
        return false;
      }
      stitches = inSel
          .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
          .toList();
      final threadIds = stitches.map((s) => s.threadId).toSet();
      threads = state.pattern.threads.values
          .where((t) => threadIds.contains(t.dmcCode))
          .toList();
    }

    if (stitches.isEmpty) return false;

    var maxX = 0, maxY = 0;
    for (final s in stitches) {
      final coords = EditorState.cellCoords(s);
      if (coords != null) {
        if (coords.x + 1 > maxX) maxX = coords.x + 1;
        if (coords.y + 1 > maxY) maxY = coords.y + 1;
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
    return true;
  }

  /// Loads a snippet into the in-memory and system clipboard, then enters paste mode.
  ///
  /// When a non-primary palette is active the stitch threadIds are remapped to
  /// use the active palette's DMC codes so the pasted stitches land with the
  /// correct colours in the destination pattern.
  Future<void> loadSnippetToClipboard(Snippet snippet) async {
    final activeIdx =
        snippet.activePaletteIndex.clamp(0, snippet.palettes.length - 1);
    final activePalette = snippet.palettes[activeIdx];

    final List<Stitch> clipStitches;
    final List<Thread> clipThreads;

    if (activeIdx == 0) {
      clipStitches = snippet.stitches;
      clipThreads = activePalette.threads;
    } else {
      clipStitches = snippet.stitches.map((s) {
        final resolved = resolveThread(snippet, s.threadId);
        return EditorState.remapStitchThread(s, resolved.dmcCode);
      }).toList();
      clipThreads = activePalette.threads;
    }

    await Clipboard.setData(
      ClipboardData(text: _serializeClipboard(clipThreads, clipStitches)),
    );
    // Auto-switch to edit mode so commitPaste() (which guards on editMode) works.
    // If the user was in view mode (e.g. just browsing), entering paste mode
    // from the snippets panel implies intent to draw.
    final targetMode = state.editMode ? state.mode : AppMode.edit;
    state = state.copyWith(
      mode: targetMode,
      drawingMode: DrawingMode.paste,
      selectionRect: null,
      clipboard: clipStitches,
      clipboardThreads: clipThreads,
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

  // ─── Snippet editor local palette state ───────────────────────────────────

  void initSnippetPalettesLocal(List<SnippetPalette> palettes, int activeIndex) {
    state = state.copyWith(
      snippetPalettes: syncPaletteSymbolsToPrimary(palettes),
      snippetActivePaletteIndex: activeIndex,
    );
  }

  /// Symbols belong to the *slot*, not the thread: every palette's slot `i`
  /// shares the symbol from the primary palette's slot `i`. This keeps the
  /// Colours list and the canvas stable when the user switches palettes —
  /// only the swatch colour changes, the symbol stays put.
  ///
  /// Slots in secondary palettes that don't exist in the primary (shouldn't
  /// happen, but be defensive) keep whatever symbol they already had.
  List<SnippetPalette> syncPaletteSymbolsToPrimary(
      List<SnippetPalette> palettes) {
    if (palettes.length < 2) return palettes;
    final primary = palettes[0].threads;
    return [
      palettes[0],
      for (var k = 1; k < palettes.length; k++)
        palettes[k].copyWith(
          threads: [
            for (var i = 0; i < palettes[k].threads.length; i++)
              i < primary.length
                  ? palettes[k].threads[i].copyWith(symbol: primary[i].symbol)
                  : palettes[k].threads[i],
          ],
        ),
    ];
  }

  void setSnippetActivePaletteLocal(int index) {
    state = state.copyWith(snippetActivePaletteIndex: index);
  }

  void addSnippetPaletteLocal(SnippetPalette palette) {
    final newPalettes =
        syncPaletteSymbolsToPrimary([...state.snippetPalettes, palette]);
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
    // Preserve the slot's existing symbol — the symbol belongs to the slot,
    // not the thread, so swapping the swatch colour must not change it.
    threads[slotIndex] = newThread.copyWith(symbol: threads[slotIndex].symbol);
    palettes[paletteIndex] = palettes[paletteIndex].copyWith(threads: threads);
    state = state.copyWith(snippetPalettes: palettes);
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
