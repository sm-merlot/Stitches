import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/dmc_colors.dart';
import '../../data/symbols.dart';
import '../../models/layer.dart';
import '../../models/cell.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_item.dart';
import '../../models/page_config.dart';
import '../../models/page_layout.dart';
import '../../models/pattern.dart';
import '../../models/pattern_progress.dart';
import '../../models/progress_log.dart';
import '../../models/snippet.dart';
import '../../models/snippet_palette.dart';
import '../../models/snippet_palette_resolver.dart';
import '../../models/stitch.dart';
import '../../models/stitch_geometry.dart';
import '../../models/thread.dart';
import '../../services/editor_session_service.dart';
import '../../services/reference_image_service.dart';
import '../../services/sprite_importer.dart';
import '../../services/stitch_compositor.dart';
import '../settings_provider.dart';

part 'editor_state.dart';
part 'editor_provider_drawing.dart';
part 'editor_provider_layers.dart';
part 'editor_provider_progress.dart';
part 'editor_provider_snippets.dart';
part 'editor_provider_selection.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum DrawingTool {
  fullStitch,    // Full X stitch             [1]
  halfForward,   // Diagonal half /           [2]
  halfBackward,  // Diagonal half \           [3]
  halfCross,     // Full X in half cell       [4]
  quarterDiag,   // Diagonal quarter (auto)   [5]
  quarterCross,  // Full X in quarter cell    [6]
  backstitch,    // Backstitch line           [7]
  fill,          // Flood fill colour         [8]
  fillErase,     // Flood fill erase          [9]
}

/// Cursor mode — controls what pointer/touch interactions do.
enum DrawingMode { draw, erase, pan, colorPicker, select, paste }

enum SnippetResizeMode { clip, scale, expand }

enum SnippetTransform { flipH, flipV, rotateCW }

/// The three top-level application modes.
///
/// - [view] — read-only overview; the default when opening a file.
/// - [edit] — full pattern editor (drawing, layers, snippets, etc.).
/// - [stitch] — active stitching session (page nav, progress tracking).
enum AppMode { view, edit, stitch }


// ─── Canvas warning messages ──────────────────────────────────────────────────

const kLayerHint           = ' — are you on the right layer?';
const kWarnSelectFirst     = 'Select a region first';
const kWarnNothingToCopy   = 'Nothing to copy';
const kWarnNothingToMove   = 'Nothing to move';
const kWarnNothingToDelete = 'Nothing to delete';
const kWarnNothingToFlip   = 'Nothing to flip';
const kWarnNothingToRotate = 'Nothing to rotate';
const kWarnNothingToSave   = 'Nothing to save';


// ─── EditorNotifier ───────────────────────────────────────────────────────────

class EditorNotifier extends Notifier<EditorState>
    with DrawingMixin, LayersMixin, ProgressMixin, SnippetsMixin, SelectionMixin {

  static const int _maxUndoDepth = 200;

  @override
  EditorState build() {
    // Cancel any pending composite-refresh debounce when the notifier is
    // re-built or disposed, so the timer callback never fires against a
    // disposed Ref and tests don't see "Ref used after dispose" errors.
    ref.onDispose(() => _drawCompositeDebounce?.cancel());
    return EditorState(pattern: CrossStitchPattern.empty());
  }

  // ─── File lifecycle ─────────────────────────────────────────────────────────

  /// Load [pattern] into the editor, restoring the per-device session state
  /// from [session] if provided.
  ///
  /// When [session] is null the editor falls back to any `editor:` fields
  /// present in the pattern YAML (backwards compatibility for files saved
  /// before this change), then migrates them into [EditorSessionService] so
  /// the next open uses app data instead.
  void loadPattern(
    CrossStitchPattern pattern, {
    String? filePath,
    String? driveFileId,
    String? driveParentFolderId,
    bool compressOnSave = true,
    EditorSession? session,
  }) {
    // ── Resolve session state ────────────────────────────────────────────────
    // Files always open in View mode regardless of saved session.
    DrawingTool tool = DrawingTool.fullStitch;
    bool colourMode = false;
    String? selectedThreadId;
    String? rawActiveLayerId;
    double viewPanX = 0;
    double viewPanY = 0;
    double viewScale = 0;
    int? stitchPage = 0;

    // True when the parsed YAML contained a legacy `editor:` section that
    // is no longer written by toYamlString.  We mark the file dirty so the
    // next auto-save rewrites it cleanly without those fields.
    bool hasLegacyEditorSection = false;

    if (session != null) {
      try { tool = DrawingTool.values.byName(session.tool); } catch (_) {}
      colourMode       = session.colourMode;
      selectedThreadId = session.selectedThreadId;
      rawActiveLayerId = session.activeLayerId;
      viewPanX = session.viewPanX;
      viewPanY = session.viewPanY;
      viewScale = session.viewScale;
      stitchPage = session.stitchPage;
    } else {
      // First open after migration: read legacy YAML fields as a one-time seed.
      hasLegacyEditorSection =
          pattern.editorTool != null ||
          pattern.editorSelectedThreadId != null ||
          pattern.editorStitchMode ||
          !pattern.editorBlockMode ||
          pattern.editorActiveLayerId != null ||
          pattern.editorViewPanX != 0 ||
          pattern.editorViewPanY != 0 ||
          pattern.editorViewScale != 0;
      if (pattern.editorTool != null) {
        try { tool = DrawingTool.values.byName(pattern.editorTool!); } catch (_) {}
      }
      colourMode        = !pattern.editorBlockMode;
      selectedThreadId = pattern.editorSelectedThreadId;
      rawActiveLayerId = pattern.editorActiveLayerId;
      viewPanX = pattern.editorViewPanX;
      viewPanY = pattern.editorViewPanY;
      viewScale = pattern.editorViewScale;
    }

    stitchPage ??= 0;

    // ── Assign symbols and validate palette ──────────────────────────────────
    final withSymbols = pattern.copyWith(
        threads: _assignSymbols(pattern.threads,
            existingSymbols: pattern.compositeSymbols.values
                .where(symbolIsVisible)
                .toSet()));

    String? threadId = selectedThreadId;
    if (threadId == null || withSymbols.threadByCode(threadId) == null) {
      threadId = withSymbols.threads.isNotEmpty
          ? withSymbols.threads.values.first.dmcCode
          : null;
    }

    // Validate active layer (may have been deleted since session was saved).
    final resolvedLayerId = (rawActiveLayerId != null &&
            withSymbols.layers.any((l) => l.id == rawActiveLayerId))
        ? rawActiveLayerId
        : (withSymbols.layers.isNotEmpty ? withSymbols.layers.first.id : '');

    final prevClipboard = state.clipboard;
    final prevClipboardThreads = state.clipboardThreads;
    final prevClipboardFromSnippet = state.clipboardFromSnippet;
    final hasClipboard = prevClipboard != null && prevClipboard.isNotEmpty;

    state = EditorState(
      pattern: withSymbols,
      filePath: filePath,
      currentTool: tool,
      selectedThreadId: threadId,
      recentThreadIds: threadId != null ? [threadId] : [],
      mode: AppMode.view,
      colourMode: colourMode,
      drawingMode: DrawingMode.pan,
      clipboard: hasClipboard ? prevClipboard : null,
      clipboardThreads: hasClipboard ? prevClipboardThreads : null,
      clipboardFromSnippet: hasClipboard && prevClipboardFromSnippet,
      referenceOpacity: withSymbols.referenceOpacity,
      driveFileId: driveFileId,
      driveParentFolderId: driveParentFolderId,
      isFileOpen: true,
      activeLayerId: resolvedLayerId,
      viewPanX: viewPanX,
      viewPanY: viewPanY,
      viewScale: viewScale,
      compressOnSave: compressOnSave,
      isDirty: hasLegacyEditorSection,
      // Only restore the saved stitch page when page mode is enabled and the
      // user has already started marking progress on this pattern.
      currentPage: (withSymbols.pageConfig.enabled &&
              (withSymbols.progress.completedStitches.isNotEmpty ||
               withSymbols.progress.completedBackstitches.isNotEmpty))
          ? stitchPage
          : 0,
    );

    // Migrate legacy session fields to app data on first open.
    if (session == null) {
      final key = driveFileId != null
          ? 'drive:$driveFileId'
          : filePath != null
              ? 'local:$filePath'
              : null;
      if (key != null) {
        unawaited(EditorSessionService.save(
          key,
          EditorSession(
            tool: tool.name,
            selectedThreadId: threadId,
            colourMode: colourMode,
            activeLayerId: resolvedLayerId.isEmpty ? null : resolvedLayerId,
            viewPanX: viewPanX,
            viewPanY: viewPanY,
            viewScale: viewScale,
            stitchPage: stitchPage,
          ),
        ));
      }
    }

    refreshCompositeCache();

    // Build page layout if page mode was saved with this pattern.
    if (withSymbols.pageConfig.enabled) {
      final layout = PageLayout.compute(withSymbols.pageConfig, withSymbols);
      state = state.copyWith(pageLayout: layout, pendingFitPage: 0);
    }

    if (withSymbols.referenceImagePath != null) {
      ReferenceImageService.decodeFromPath(withSymbols.referenceImagePath!)
          .then((img) {
        if (img != null && ref.mounted) {
          state = state.copyWith(referenceImage: img);
        }
      });
    }
  }

  /// Called by AidaWidget on gesture end to persist the current view
  /// position. Does NOT mark the file dirty — view state is session-only.
  void updateViewPosition(double panX, double panY, double scale) {
    state = state.copyWith(viewPanX: panX, viewPanY: panY, viewScale: scale);
    _saveSession();
  }

  // ─── Session helpers ─────────────────────────────────────────────────────────

  String? get _sessionKey {
    if (state.driveFileId != null) return 'drive:${state.driveFileId}';
    if (state.filePath != null) return 'local:${state.filePath}';
    return null;
  }

  /// Persist the current editor session to app data (fire-and-forget).
  @override
  void _saveSession() {
    final key = _sessionKey;
    if (key == null) return;
    unawaited(EditorSessionService.save(
      key,
      EditorSession(
        tool: state.currentTool.name,
        selectedThreadId: state.selectedThreadId,
        colourMode: state.colourMode,
        activeLayerId: state.activeLayerId.isEmpty ? null : state.activeLayerId,
        viewPanX: state.viewPanX,
        viewPanY: state.viewPanY,
        viewScale: state.viewScale,
        stitchPage: state.currentPage,
      ),
    ));
  }

  /// Switch to [mode], updating drawingMode and display state accordingly.
  @override
  /// Switches to [mode]. Returns the number of orphaned completed-stitch
  /// entries pruned when entering stitch mode (cells no longer in the pattern).
  int setMode(AppMode mode) {
    int pruned = 0;
    var pattern = state.pattern;
    if (mode == AppMode.stitch) {
      final validCells = <(int, int)>{};
      final validBack = <(double, double, double, double)>{};
      for (final layer in pattern.layers) {
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) {
            validBack.add(PatternProgress.normBackstitch(
                stitch.x1, stitch.y1, stitch.x2, stitch.y2));
          } else {
            final c = EditorState.cellCoords(stitch);
            if (c != null) validCells.add(c);
          }
        }
      }
      final oldCompleted = pattern.progress.completedStitches;
      final newCompleted = oldCompleted.intersection(validCells);
      final oldBack = pattern.progress.completedBackstitches;
      final newBack = oldBack.intersection(validBack);
      pruned = (oldCompleted.length - newCompleted.length) +
               (oldBack.length - newBack.length);
      if (pruned > 0) {
        pattern = pattern.copyWith(
          progress: pattern.progress.copyWith(
            completedStitches: newCompleted,
            completedBackstitches: newBack,
          ),
        );
      }
    }
    state = state.copyWith(
      pattern: pruned > 0 ? pattern : null,
      mode: mode,
      drawingMode: switch (mode) {
        AppMode.stitch => DrawingMode.select,
        AppMode.edit   => DrawingMode.draw,
        AppMode.view   => DrawingMode.pan,
      },
      selectionRect: null,
      backstitchStartPoint: null,
      progressRegion: null,
      colourMode: mode == AppMode.stitch ? false : null,
      showCompositeThreads: mode == AppMode.stitch || state.showCompositeThreads,
      stitchCrossMode: false,
      stitchBackMode: false,
      stitchFocusThreadId: mode == AppMode.stitch ? state.stitchFocusThreadId : null,
      pendingFitPage: state.currentPage,
    );
    if (mode == AppMode.stitch) refreshCompositeCache();
    _saveSession();
    return pruned;
  }

  /// Set or clear the committed progress-marking region (stitch mode).
  void setProgressRegion(Rect? region) {
    state = state.copyWith(progressRegion: region);
  }

  void setDriveFileId(String? id) {
    state = state.copyWith(driveFileId: id, isDirty: state.isFileOpen);
  }

  void setDriveParentFolderId(String? id) {
    state = state.copyWith(driveParentFolderId: id);
  }

  void newPattern(CrossStitchPattern pattern) {
    final compress = ref.read(settingsProvider).compressNewFiles;
    final threads = _assignSymbols(pattern.threads);
    final seeded = pattern.copyWith(threads: threads);
    state = EditorState(
      pattern: seeded,
      selectedThreadId: threads.values.first.dmcCode,
      recentThreadIds: [threads.values.first.dmcCode],
      mode: AppMode.edit,
      drawingMode: DrawingMode.draw,
      isFileOpen: true,
      activeLayerId: seeded.layers.isNotEmpty ? seeded.layers.first.id : '',
      compressOnSave: compress,
    );
  }

  void toggleCompressOnSave() {
    state = state.copyWith(compressOnSave: !state.compressOnSave, isDirty: true);
  }

  void closeFile() {
    state = EditorState(pattern: CrossStitchPattern.empty());
  }

  void setFilePath(String? path) {
    state = state.copyWith(filePath: path);
  }

  void markSaved() {
    state = state.copyWith(isDirty: false);
  }

  // ─── Tool and mode ──────────────────────────────────────────────────────────

  void setTool(DrawingTool tool) {
    state = state.copyWith(currentTool: tool, backstitchStartPoint: null);
    _saveSession();
  }

  void setDrawingMode(DrawingMode mode) {
    final leavingSelection =
        state.drawingMode == DrawingMode.select || state.drawingMode == DrawingMode.paste;
    state = state.copyWith(
      drawingMode: mode,
      backstitchStartPoint: null,
      selectionRect: leavingSelection ? null : state.selectionRect,
    );
  }

  void toggleDrawingMode() {
    final newMode = state.drawingMode == DrawingMode.draw
        ? DrawingMode.erase
        : DrawingMode.draw;
    state = state.copyWith(drawingMode: newMode, backstitchStartPoint: null);
  }

  // ─── Undo / Redo ────────────────────────────────────────────────────────────

  // Delegate set by the active mode controller via [registerUndoDelegate].
  // When non-null, [undo] and [redo] route through the controller's
  // [UndoManager] before falling back to the snapshot undo stack.
  ({
    bool Function() canUndo,
    bool Function() canRedo,
    void Function() undo,
    void Function() redo,
  })? _controllerUndoDelegate;

  /// Registers [canUndo]/[canRedo]/[undo]/[redo] callbacks from the active
  /// mode controller. Call from [CanvasEditController.attachCanvas].
  void registerUndoDelegate({
    required bool Function() canUndo,
    required bool Function() canRedo,
    required void Function() undo,
    required void Function() redo,
  }) {
    _controllerUndoDelegate = (
      canUndo: canUndo,
      canRedo: canRedo,
      undo: undo,
      redo: redo,
    );
  }

  /// Removes the controller delegate. Call from [CanvasEditController.detachCanvas].
  ///
  /// Does not update state — called during [AidaWidget.dispose] when the
  /// Riverpod element may already be defunct. The [controllerCanUndo] /
  /// [controllerCanRedo] fields naturally become stale; they reset to false
  /// on the next [attachCanvas] + [registerUndoDelegate] cycle.
  void unregisterUndoDelegate() {
    _controllerUndoDelegate = null;
  }

  /// Reads [canUndo]/[canRedo] from the active delegate and updates
  /// [EditorState.controllerCanUndo] / [EditorState.controllerCanRedo].
  /// Called after each [UndoManager.execute], [UndoManager.undo], or
  /// [UndoManager.redo] so the toolbar reflects the live undo state.
  void updateControllerUndoState() {
    final d = _controllerUndoDelegate;
    state = state.copyWith(
      controllerCanUndo: d?.canUndo() ?? false,
      controllerCanRedo: d?.canRedo() ?? false,
    );
  }

  void undo() {
    // Route through the active controller's UndoManager first.
    final d = _controllerUndoDelegate;
    if (d != null && d.canUndo()) {
      d.undo();
      updateControllerUndoState();
      return;
    }
    if (state._undoStack.isEmpty) return;
    final undoStack = [...state._undoStack];
    final redoStack = [...state._redoStack];
    final (prevPattern, prevPalettes) = undoStack.removeLast();
    redoStack.add((state.pattern, state.snippetPalettes));
    // Preserve current layer UI state so undo only reverts stitch/thread data,
    // not layer visibility or lock the user toggled independently.
    final restored = _applyLayerUiState(prevPattern, state.pattern);
    state = state.copyWith(
      pattern: restored,
      snippetPalettes: prevPalettes,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: true,
      // Recompute composite so _syncRenderCache sees a changed identity and
      // rebuilds the render cache from the restored pattern. Without this,
      // the old composite is kept (sentinel pass-through) and the canvas
      // shows the pre-undo stitches until something else forces a refresh.
      compositeLayer: StitchCompositor.computeLayer(restored),
    );
  }

  void redo() {
    // Route through the active controller's UndoManager first.
    final d = _controllerUndoDelegate;
    if (d != null && d.canRedo()) {
      d.redo();
      updateControllerUndoState();
      return;
    }
    if (state._redoStack.isEmpty) return;
    final undoStack = [...state._undoStack];
    final redoStack = [...state._redoStack];
    final (nextPattern, nextPalettes) = redoStack.removeLast();
    undoStack.add((state.pattern, state.snippetPalettes));
    final restored = _applyLayerUiState(nextPattern, state.pattern);
    state = state.copyWith(
      pattern: restored,
      snippetPalettes: nextPalettes,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: true,
      compositeLayer: StitchCompositor.computeLayer(restored),
    );
  }

  /// Returns [target] with each layer's [visible] and [locked] overridden by
  /// the matching layer from [source] (matched by layer id). Layers present in
  /// [target] but absent in [source] keep their own UI state. This lets
  /// undo/redo restore stitch data while preserving any visibility/lock changes
  /// the user made independently of the undo-able operation.
  CrossStitchPattern _applyLayerUiState(
      CrossStitchPattern target, CrossStitchPattern source) {
    final sourceById = {for (final l in source.layers) l.id: l};
    return target.mapLayers((l) {
      final s = sourceById[l.id];
      if (s == null) return l;
      if (s.visible == l.visible && s.locked == l.locked) return l;
      return l.copyWith(visible: s.visible, locked: s.locked);
    });
  }

  void clearCanvasWarning() {
    state = state.copyWith(pendingCanvasWarning: null);
  }

  void clearPendingFitPage() {
    state = state.copyWith(pendingFitPage: null);
  }

  // ─── Page mode ──────────────────────────────────────────────────────────────

  /// Update page config and recompute the layout.
  void updatePageConfig(PageConfig config) {
    final newPattern = state.pattern.copyWith(pageConfig: config);
    final layout = config.enabled
        ? PageLayout.compute(config, newPattern)
        : null;
    final page = config.enabled ? state.currentPage.clamp(0, (layout!.totalPages - 1).clamp(0, 999)) : 0;
    state = state.copyWith(
      pattern: newPattern,
      pageLayout: layout,
      currentPage: page,
      pendingFitPage: config.enabled ? page : null,
      isDirty: true,
    );
  }

  /// Navigate to a specific page index.
  void navigatePage(int page) {
    final layout = state.pageLayout;
    if (layout == null) return;
    final clamped = page.clamp(0, layout.totalPages - 1);
    state = state.copyWith(currentPage: clamped, pendingFitPage: clamped);
    // Persist the current page so it is restored on next session open — but
    // only when in stitch mode with page mode active and progress started.
    final progress = state.pattern.progress;
    if (state.mode == AppMode.stitch &&
        state.pattern.pageConfig.enabled &&
        (progress.completedStitches.isNotEmpty ||
         progress.completedBackstitches.isNotEmpty)) {
      _saveSession();
    }
  }

  void navigateNextPage() {
    navigatePage(state.currentPage + 1);
  }

  void navigatePreviousPage() {
    navigatePage(state.currentPage - 1);
  }

  /// Navigate one page to the right within the same row.
  void navigatePageRight() {
    final layout = state.pageLayout;
    if (layout == null) return;
    final (col, row) = layout.pageCoords(state.currentPage);
    if (col < layout.pagesAcross - 1) {
      navigatePage(layout.pageIndex(col + 1, row));
    }
  }

  /// Navigate one page to the left within the same row.
  void navigatePageLeft() {
    final layout = state.pageLayout;
    if (layout == null) return;
    final (col, row) = layout.pageCoords(state.currentPage);
    if (col > 0) {
      navigatePage(layout.pageIndex(col - 1, row));
    }
  }

  /// Navigate one page down within the same column.
  void navigatePageDown() {
    final layout = state.pageLayout;
    if (layout == null) return;
    final (col, row) = layout.pageCoords(state.currentPage);
    if (row < layout.pagesDown - 1) {
      navigatePage(layout.pageIndex(col, row + 1));
    }
  }

  /// Navigate one page up within the same column.
  void navigatePageUp() {
    final layout = state.pageLayout;
    if (layout == null) return;
    final (col, row) = layout.pageCoords(state.currentPage);
    if (row > 0) {
      navigatePage(layout.pageIndex(col, row - 1));
    }
  }

  @override
  void warnNoSelection() {
    state = state.copyWith(
      pendingCanvasWarning: kWarnSelectFirst,
    );
  }

  // ─── Shared helpers (satisfy abstract declarations in mixins) ────────────────

  @override
  List<(CrossStitchPattern, List<SnippetPalette>)> _buildUndoStack() {
    var stack = [...state._undoStack, (state.pattern, state.snippetPalettes)];
    if (stack.length > _maxUndoDepth) {
      stack = stack.sublist(stack.length - _maxUndoDepth);
    }
    return stack;
  }

  @override
  List<Stitch> _stitchesWithAdded(List<Stitch> existing, Stitch newStitch) {
    final filtered = existing.where((s) => s != newStitch).toList();
    return [...filtered, newStitch];
  }

  @override
  CrossStitchPattern _patternWithActiveLayerStitches(
      CrossStitchPattern pattern, List<Stitch> newStitches) {
    final activeId = state.activeLayerId;
    return pattern.mapLayers((l) {
      if (l.id == activeId || (activeId.isEmpty && l == pattern.layers.first)) {
        return l.copyWith(stitches: newStitches);
      }
      return l;
    });
  }

  @override
  bool _isInBounds(Stitch s, int maxX, int maxY) {
    final coords = EditorState.cellCoords(s);
    if (coords != null) {
      return coords.$1 >= 0 && coords.$1 < maxX && coords.$2 >= 0 && coords.$2 < maxY;
    }
    final bs = s as BackStitch;
    return bs.x1 >= 0 && bs.x1 <= maxX && bs.y1 >= 0 && bs.y1 <= maxY &&
        bs.x2 >= 0 && bs.x2 <= maxX && bs.y2 >= 0 && bs.y2 <= maxY;
  }

  @override
  CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern) {
    final used = <String>{};
    for (final layer in pattern.layers) {
      for (final stitch in layer.stitches) {
        used.add(switch (stitch) {
          FullStitch(:final threadId) => threadId,
          HalfStitch(:final threadId) => threadId,
          HalfCrossStitch(:final threadId) => threadId,
          QuarterStitch(:final threadId) => threadId,
          QuarterCrossStitch(:final threadId) => threadId,
          BackStitch(:final threadId) => threadId,
        });
      }
    }
    if (pattern.threads.keys.every(used.contains)) return pattern;
    final pruned = {
      for (final e in pattern.threads.entries)
        if (used.contains(e.key)) e.key: e.value,
    };
    return pattern.copyWith(threads: pruned);
  }

  @override
  String _nextSymbol(Set<String> used) {
    for (final s in kPatternSymbols) {
      if (!used.contains(s)) return s;
    }
    return '';
  }

  @override
  Thread _resolveThreadSymbol(Thread thread, List<Thread> existingThreads) {
    final usedSymbols = {
      ...existingThreads.map((t) => t.symbol).where(symbolIsVisible),
      ...state.pattern.compositeSymbols.values.where(symbolIsVisible),
    };
    if (!symbolIsVisible(thread.symbol) || usedSymbols.contains(thread.symbol)) {
      return thread.copyWith(symbol: _nextSymbol(usedSymbols));
    }
    return thread;
  }

  @override
  String _serializeClipboard(List<Thread> threads, List<Stitch> stitches) {
    return jsonEncode({
      'stitches': {
        'version': 1,
        'threads': threads.map((t) => t.toYaml()).toList(),
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      }
    });
  }

  /// Ensures every thread has a symbol, assigning from [kPatternSymbols] for
  /// any that are missing one. [existingSymbols] pre-populates the "taken"
  /// set so composite symbols are not reused for layer threads on load.
  @visibleForTesting
  Map<String, Thread> assignSymbolsForTest(Map<String, Thread> threads,
          {Set<String> existingSymbols = const {}}) =>
      _assignSymbols(threads, existingSymbols: existingSymbols);

  Map<String, Thread> _assignSymbols(Map<String, Thread> threads,
      {Set<String> existingSymbols = const {}}) {
    final assigned = <String>{...existingSymbols};
    final result = <String, Thread>{};
    for (final t in threads.values) {
      if (symbolIsVisible(t.symbol) && !symbolIsPdfUnsupported(t.symbol)) {
        assigned.add(t.symbol);
        result[t.dmcCode] = t;
      } else {
        final s = _nextSymbol(assigned);
        if (s.isNotEmpty) assigned.add(s);
        result[t.dmcCode] = t.copyWith(symbol: s);
      }
    }
    return result;
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

