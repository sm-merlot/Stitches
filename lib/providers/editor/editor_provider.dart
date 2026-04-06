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
import '../../models/layer_blend_mode.dart';
import '../../models/layer_item.dart';
import '../../models/page_config.dart';
import '../../models/page_layout.dart';
import '../../models/pattern.dart';
import '../../models/pattern_progress.dart';
import '../../models/snippet.dart';
import '../../models/snippet_palette.dart';
import '../../models/snippet_palette_resolver.dart';
import '../../models/stitch.dart';
import '../../models/thread.dart';
import '../../services/editor_session_service.dart';
import '../../services/reference_image_service.dart';
import '../../services/sprite_importer.dart';
import '../../services/stitch_compositor.dart';
import '../settings_provider.dart';

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

// ─── EditorState ──────────────────────────────────────────────────────────────

class EditorState {
  final CrossStitchPattern pattern;
  final String? filePath;
  final DrawingTool currentTool;
  final DrawingMode drawingMode;
  final String? selectedThreadId;
  final List<(CrossStitchPattern, List<SnippetPalette>)> _undoStack;
  final List<(CrossStitchPattern, List<SnippetPalette>)> _redoStack;
  final bool isDirty;
  final Offset? backstitchStartPoint;
  /// Most-recently-used thread IDs, most recent first. Max 5. Session-only.
  final List<String> recentThreadIds;
  final Rect? selectionRect;
  final List<Stitch>? clipboard;
  final List<Thread>? clipboardThreads;
  final bool clipboardFromSnippet;
  final String activeLayerId;
  final bool showCompositeThreads;
  final CompositeResult? compositeResult;
  final AppMode mode;
  final bool blockMode;
  final bool stitchCrossMode; // Cross: hides backstitches, normal stitches shown in colour
  final bool stitchBackMode;  // Back: greys normal stitches, backstitches shown in colour
  final String? stitchFocusThreadId;
  final ui.Image? referenceImage;
  final double referenceOpacity;
  final bool referenceVisible;
  final String? driveFileId;
  final String? driveParentFolderId;
  final bool isFileOpen;
  final List<SnippetPalette> snippetPalettes;
  final int snippetActivePaletteIndex;
  /// Edge length of the eraser square (1 = single cell, 2 = 2×2, etc.).
  final int eraserSize;
  /// When true, erase mode uses flood-fill erase instead of the square eraser.
  final bool fillEraseActive;

  /// Last-known canvas view position — written on pointer-up, read on file open.
  /// Scale == 0 means no saved position (use PatternCanvas default).
  final double viewPanX;
  final double viewPanY;
  final double viewScale;
  /// When true, selection operations act on all visible layers instead of just the active layer.
  final bool canvasSelectionMode;
  /// Non-null when the notifier wants PatternCanvas to show a one-shot warning banner.
  /// PatternCanvas clears this immediately after showing it.
  final String? pendingCanvasWarning;

  /// Whether to gzip-compress this file when saving.
  /// Set from the file's detected compression on open; defaults to the app
  /// setting for new patterns. Toggled per-file via the overflow menu.
  final bool compressOnSave;

  /// Current page index (0-based) in page mode. Session-only, not persisted.
  final int currentPage;

  /// Precomputed page layout. Non-null when page mode is enabled.
  final PageLayout? pageLayout;

  /// When non-null, PatternCanvas should animate to fit this page index then
  /// clear the value via [clearPendingFitPage].
  final int? pendingFitPage;

  /// True when the current file is in the native .stitches format (or unsaved).
  bool get isNativeFormat {
    final path = filePath;
    if (path == null) return true;
    return path.endsWith('.stitches');
  }

  const EditorState({
    required this.pattern,
    this.filePath,
    this.currentTool = DrawingTool.fullStitch,
    this.drawingMode = DrawingMode.draw,
    this.selectedThreadId,
    List<(CrossStitchPattern, List<SnippetPalette>)> undoStack = const [],
    List<(CrossStitchPattern, List<SnippetPalette>)> redoStack = const [],
    this.isDirty = false,
    this.backstitchStartPoint,
    this.recentThreadIds = const [],
    this.selectionRect,
    this.clipboard,
    this.clipboardThreads,
    this.clipboardFromSnippet = false,
    this.activeLayerId = '',
    this.showCompositeThreads = true,
    this.compositeResult,
    this.mode = AppMode.view,
    this.blockMode = false,
    this.stitchCrossMode = false,
    this.stitchBackMode = false,
    this.stitchFocusThreadId,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.referenceVisible = true,
    this.driveFileId,
    this.driveParentFolderId,
    this.isFileOpen = false,
    this.snippetPalettes = const [],
    this.snippetActivePaletteIndex = 0,
    this.eraserSize = 1,
    this.fillEraseActive = false,
    this.viewPanX = 0,
    this.viewPanY = 0,
    this.viewScale = 0,
    this.canvasSelectionMode = false,
    this.pendingCanvasWarning,
    this.compressOnSave = true,
    this.currentPage = 0,
    this.pageLayout,
    this.pendingFitPage,
  })  : _undoStack = undoStack,
        _redoStack = redoStack;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// True when in stitch mode — used by existing consumers without change.
  bool get stitchMode => mode == AppMode.stitch;

  /// True when in edit mode.
  bool get editMode => mode == AppMode.edit;

  Layer get activeLayer => pattern.layers.firstWhere(
        (l) => l.id == activeLayerId,
        orElse: () => pattern.layers.first,
      );

  Iterable<Layer> get visibleLayers => pattern.layers.where((l) => l.visible);

  /// The pattern as it should be written to disk.  Editor session state
  /// (tool, mode, view position, active layer) is stored separately in
  /// EditorSessionService, not in the file.
  CrossStitchPattern get patternForSave => pattern;

  Thread? get selectedThread {
    if (selectedThreadId == null) return null;
    final inPalette = pattern.threadByCode(selectedThreadId!);
    if (inPalette != null) return inPalette;
    // Not yet in palette — look up in DMC DB for preview.
    final dmc = dmcColorByCode(selectedThreadId!);
    if (dmc == null) return null;
    return Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
  }

  List<Stitch> get selectedStitches {
    final rect = selectionRect;
    if (rect == null) return [];
    if (canvasSelectionMode) {
      return pattern.layers
          .where((l) => l.visible)
          .expand((l) => l.stitches.where((s) => isStitchInRect(s, rect)))
          .toList();
    }
    return activeLayer.stitches.where((s) => isStitchInRect(s, rect)).toList();
  }

  static (int, int)? cellCoords(Stitch s) => switch (s) {
    FullStitch(:final x, :final y) => (x, y),
    HalfStitch(:final x, :final y) => (x, y),
    HalfCrossStitch(:final x, :final y) => (x, y),
    QuarterStitch(:final x, :final y) => (x, y),
    QuarterCrossStitch(:final x, :final y) => (x, y),
    BackStitch() => null,
  };

  static bool isStitchInRect(Stitch s, Rect rect) {
    final coords = cellCoords(s);
    if (coords != null) {
      return coords.$1 >= rect.left && coords.$1 < rect.right &&
          coords.$2 >= rect.top && coords.$2 < rect.bottom;
    }
    final bs = s as BackStitch;
    return bs.x1 >= rect.left && bs.x1 <= rect.right &&
        bs.y1 >= rect.top && bs.y1 <= rect.bottom &&
        bs.x2 >= rect.left && bs.x2 <= rect.right &&
        bs.y2 >= rect.top && bs.y2 <= rect.bottom;
  }

  static Stitch offsetStitch(Stitch s, int dx, int dy) => switch (s) {
    FullStitch(:final x, :final y, :final threadId) =>
        FullStitch(x: x + dx, y: y + dy, threadId: threadId),
    HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
        HalfStitch(x: x + dx, y: y + dy, isForward: isForward, threadId: threadId),
    QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
        QuarterStitch(x: x + dx, y: y + dy, quadrant: quadrant, threadId: threadId),
    HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
        HalfCrossStitch(x: x + dx, y: y + dy, half: half, threadId: threadId),
    QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
        QuarterCrossStitch(x: x + dx, y: y + dy, quadrant: quadrant, threadId: threadId),
    BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
        BackStitch(x1: x1 + dx, y1: y1 + dy, x2: x2 + dx, y2: y2 + dy, threadId: threadId),
  };

  /// Returns a copy of [s] with its threadId replaced by [newId].
  static Stitch remapStitchThread(Stitch s, String newId) => switch (s) {
    FullStitch(:final x, :final y) =>
        FullStitch(x: x, y: y, threadId: newId),
    HalfStitch(:final x, :final y, :final isForward) =>
        HalfStitch(x: x, y: y, isForward: isForward, threadId: newId),
    QuarterStitch(:final x, :final y, :final quadrant) =>
        QuarterStitch(x: x, y: y, quadrant: quadrant, threadId: newId),
    HalfCrossStitch(:final x, :final y, :final half) =>
        HalfCrossStitch(x: x, y: y, half: half, threadId: newId),
    QuarterCrossStitch(:final x, :final y, :final quadrant) =>
        QuarterCrossStitch(x: x, y: y, quadrant: quadrant, threadId: newId),
    BackStitch(:final x1, :final y1, :final x2, :final y2) =>
        BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: newId),
  };

  EditorState copyWith({
    CrossStitchPattern? pattern,
    Object? filePath = _sentinel,
    DrawingTool? currentTool,
    DrawingMode? drawingMode,
    Object? selectedThreadId = _sentinel,
    List<(CrossStitchPattern, List<SnippetPalette>)>? undoStack,
    List<(CrossStitchPattern, List<SnippetPalette>)>? redoStack,
    bool? isDirty,
    Object? backstitchStartPoint = _sentinel,
    List<String>? recentThreadIds,
    Object? selectionRect = _sentinel,
    Object? clipboard = _sentinel,
    Object? clipboardThreads = _sentinel,
    bool? clipboardFromSnippet,
    String? activeLayerId,
    bool? showCompositeThreads,
    Object? compositeResult = _sentinel,
    AppMode? mode,
    bool? blockMode,
    bool? stitchCrossMode,
    bool? stitchBackMode,
    Object? stitchFocusThreadId = _sentinel,
    Object? referenceImage = _sentinel,
    double? referenceOpacity,
    bool? referenceVisible,
    Object? driveFileId = _sentinel,
    Object? driveParentFolderId = _sentinel,
    bool? isFileOpen,
    List<SnippetPalette>? snippetPalettes,
    int? snippetActivePaletteIndex,
    int? eraserSize,
    bool? fillEraseActive,
    double? viewPanX,
    double? viewPanY,
    double? viewScale,
    bool? canvasSelectionMode,
    Object? pendingCanvasWarning = _sentinel,
    bool? compressOnSave,
    int? currentPage,
    Object? pageLayout = _sentinel,
    Object? pendingFitPage = _sentinel,
  }) {
    return EditorState(
      pattern: pattern ?? this.pattern,
      filePath: filePath == _sentinel ? this.filePath : filePath as String?,
      currentTool: currentTool ?? this.currentTool,
      drawingMode: drawingMode ?? this.drawingMode,
      selectedThreadId: selectedThreadId == _sentinel
          ? this.selectedThreadId
          : selectedThreadId as String?,
      undoStack: undoStack ?? _undoStack,
      redoStack: redoStack ?? _redoStack,
      isDirty: isDirty ?? this.isDirty,
      backstitchStartPoint: backstitchStartPoint == _sentinel
          ? this.backstitchStartPoint
          : backstitchStartPoint as Offset?,
      recentThreadIds: recentThreadIds ?? this.recentThreadIds,
      selectionRect: selectionRect == _sentinel ? this.selectionRect : selectionRect as Rect?,
      clipboard: clipboard == _sentinel ? this.clipboard : clipboard as List<Stitch>?,
      clipboardThreads: clipboardThreads == _sentinel ? this.clipboardThreads : clipboardThreads as List<Thread>?,
      clipboardFromSnippet: clipboardFromSnippet ?? this.clipboardFromSnippet,
      activeLayerId: activeLayerId ?? this.activeLayerId,
      showCompositeThreads: showCompositeThreads ?? this.showCompositeThreads,
      compositeResult: compositeResult == _sentinel
          ? this.compositeResult
          : compositeResult as CompositeResult?,
      mode: mode ?? this.mode,
      blockMode: blockMode ?? this.blockMode,
      stitchCrossMode: stitchCrossMode ?? this.stitchCrossMode,
      stitchBackMode: stitchBackMode ?? this.stitchBackMode,
      stitchFocusThreadId: stitchFocusThreadId == _sentinel
          ? this.stitchFocusThreadId
          : stitchFocusThreadId as String?,
      referenceImage: referenceImage == _sentinel
          ? this.referenceImage
          : referenceImage as ui.Image?,
      referenceOpacity: referenceOpacity ?? this.referenceOpacity,
      referenceVisible: referenceVisible ?? this.referenceVisible,
      driveFileId: driveFileId == _sentinel
          ? this.driveFileId
          : driveFileId as String?,
      driveParentFolderId: driveParentFolderId == _sentinel
          ? this.driveParentFolderId
          : driveParentFolderId as String?,
      isFileOpen: isFileOpen ?? this.isFileOpen,
      snippetPalettes: snippetPalettes ?? this.snippetPalettes,
      snippetActivePaletteIndex: snippetActivePaletteIndex ?? this.snippetActivePaletteIndex,
      eraserSize: eraserSize ?? this.eraserSize,
      fillEraseActive: fillEraseActive ?? this.fillEraseActive,
      viewPanX: viewPanX ?? this.viewPanX,
      viewPanY: viewPanY ?? this.viewPanY,
      viewScale: viewScale ?? this.viewScale,
      canvasSelectionMode: canvasSelectionMode ?? this.canvasSelectionMode,
      pendingCanvasWarning: pendingCanvasWarning == _sentinel
          ? this.pendingCanvasWarning
          : pendingCanvasWarning as String?,
      compressOnSave: compressOnSave ?? this.compressOnSave,
      currentPage: currentPage ?? this.currentPage,
      pageLayout: pageLayout == _sentinel ? this.pageLayout : pageLayout as PageLayout?,
      pendingFitPage: pendingFitPage == _sentinel ? this.pendingFitPage : pendingFitPage as int?,
    );
  }

  static const _sentinel = Object();
}

// ─── EditorNotifier ───────────────────────────────────────────────────────────

class EditorNotifier extends Notifier<EditorState>
    with DrawingMixin, LayersMixin, ProgressMixin, SnippetsMixin, SelectionMixin {

  static const int _maxUndoDepth = 200;

  @override
  EditorState build() => EditorState(pattern: CrossStitchPattern.empty());

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
    bool blockMode = false;
    String? selectedThreadId;
    String? rawActiveLayerId;
    double viewPanX = 0;
    double viewPanY = 0;
    double viewScale = 0;

    // True when the parsed YAML contained a legacy `editor:` section that
    // is no longer written by toYamlString.  We mark the file dirty so the
    // next auto-save rewrites it cleanly without those fields.
    bool hasLegacyEditorSection = false;

    if (session != null) {
      try { tool = DrawingTool.values.byName(session.tool); } catch (_) {}
      blockMode       = session.blockMode;
      selectedThreadId = session.selectedThreadId;
      rawActiveLayerId = session.activeLayerId;
      viewPanX = session.viewPanX;
      viewPanY = session.viewPanY;
      viewScale = session.viewScale;
    } else {
      // First open after migration: read legacy YAML fields as a one-time seed.
      hasLegacyEditorSection =
          pattern.editorTool != null ||
          pattern.editorSelectedThreadId != null ||
          pattern.editorStitchMode ||
          pattern.editorBlockMode ||
          pattern.editorActiveLayerId != null ||
          pattern.editorViewPanX != 0 ||
          pattern.editorViewPanY != 0 ||
          pattern.editorViewScale != 0;
      if (pattern.editorTool != null) {
        try { tool = DrawingTool.values.byName(pattern.editorTool!); } catch (_) {}
      }
      blockMode        = pattern.editorBlockMode;
      selectedThreadId = pattern.editorSelectedThreadId;
      rawActiveLayerId = pattern.editorActiveLayerId;
      viewPanX = pattern.editorViewPanX;
      viewPanY = pattern.editorViewPanY;
      viewScale = pattern.editorViewScale;
    }

    // ── Assign symbols and validate palette ──────────────────────────────────
    final withSymbols = pattern.copyWith(
        threads: _assignSymbols(pattern.threads,
            existingSymbols: pattern.compositeSymbols.values
                .where(symbolIsVisible)
                .toSet()));

    String? threadId = selectedThreadId;
    if (threadId == null || withSymbols.threadByCode(threadId) == null) {
      threadId = withSymbols.threads.isNotEmpty
          ? withSymbols.threads.first.dmcCode
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
      blockMode: blockMode,
      drawingMode: hasClipboard ? DrawingMode.paste : DrawingMode.pan,
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
            blockMode: blockMode,
            activeLayerId: resolvedLayerId.isEmpty ? null : resolvedLayerId,
            viewPanX: viewPanX,
            viewPanY: viewPanY,
            viewScale: viewScale,
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

  /// Called by PatternCanvas on gesture end to persist the current view
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
        blockMode: state.blockMode,
        activeLayerId: state.activeLayerId.isEmpty ? null : state.activeLayerId,
        viewPanX: state.viewPanX,
        viewPanY: state.viewPanY,
        viewScale: state.viewScale,
      ),
    ));
  }

  /// Switch to [mode], updating drawingMode and display state accordingly.
  @override
  void setMode(AppMode mode) {
    state = state.copyWith(
      mode: mode,
      drawingMode: switch (mode) {
        AppMode.stitch => DrawingMode.select,
        AppMode.edit   => DrawingMode.draw,
        AppMode.view   => DrawingMode.pan,
      },
      selectionRect: null,
      backstitchStartPoint: null,
      showCompositeThreads: mode == AppMode.stitch || state.showCompositeThreads,
      stitchCrossMode: false,
      stitchBackMode: false,
      stitchFocusThreadId: mode == AppMode.stitch ? state.stitchFocusThreadId : null,
    );
    if (mode == AppMode.stitch) refreshCompositeCache();
    _saveSession();
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
      selectedThreadId: threads.first.dmcCode,
      recentThreadIds: [threads.first.dmcCode],
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

  void undo() {
    if (!state.canUndo) return;
    final undoStack = [...state._undoStack];
    final redoStack = [...state._redoStack];
    final (prevPattern, prevPalettes) = undoStack.removeLast();
    redoStack.add((state.pattern, state.snippetPalettes));
    state = state.copyWith(
      pattern: prevPattern,
      snippetPalettes: prevPalettes,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: true,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final undoStack = [...state._undoStack];
    final redoStack = [...state._redoStack];
    final (nextPattern, nextPalettes) = redoStack.removeLast();
    undoStack.add((state.pattern, state.snippetPalettes));
    state = state.copyWith(
      pattern: nextPattern,
      snippetPalettes: nextPalettes,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: true,
    );
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
    final pruned = pattern.threads.where((t) => used.contains(t.dmcCode)).toList();
    if (pruned.length == pattern.threads.length) return pattern;
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
  List<Thread> assignSymbolsForTest(List<Thread> threads,
          {Set<String> existingSymbols = const {}}) =>
      _assignSymbols(threads, existingSymbols: existingSymbols);

  List<Thread> _assignSymbols(List<Thread> threads,
      {Set<String> existingSymbols = const {}}) {
    final assigned = <String>{...existingSymbols};
    return threads.map((t) {
      if (symbolIsVisible(t.symbol) && !symbolIsPdfUnsupported(t.symbol)) {
        assigned.add(t.symbol);
        return t;
      }
      final s = _nextSymbol(assigned);
      if (s.isNotEmpty) assigned.add(s);
      return t.copyWith(symbol: s);
    }).toList();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

