part of 'editor_provider.dart';

// ─── EditorState ──────────────────────────────────────────────────────────────

class EditorState {
  final CrossStitchPattern pattern;
  final String? filePath;
  final DrawingTool currentTool;
  final DrawingMode drawingMode;
  final String? selectedThreadId;
  final List<(CrossStitchPattern, List<SnippetPalette>)> _undoStack;
  final List<(CrossStitchPattern, List<SnippetPalette>)> _redoStack;
  final List<PatternProgress> _progressUndoStack;
  final List<PatternProgress> _progressRedoStack;
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
  final CompositeLayer? compositeLayer;
  final AppMode mode;
  final bool colourMode;
  final bool stitchCrossMode; // Cross: hides backstitches, normal stitches shown in colour
  final bool stitchBackMode;  // Back: greys normal stitches, backstitches shown in colour
  final String? stitchFocusThreadId;
  /// When true and page mode is active, the stitch-mode colour list shows only
  /// threads present on the current page. Defaults to false (show all colours).
  final bool stitchShowPageColours;
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
  /// When true, backstitch drawing chains: the end point of one backstitch
  /// becomes the start point of the next. Toggled via toolbar (touch) or
  /// held via Ctrl (desktop).
  final bool backstitchChainMode;

  /// Last-known canvas view position — written on pointer-up, read on file open.
  /// Scale == 0 means no saved position (use AidaWidget default).
  final double viewPanX;
  final double viewPanY;
  final double viewScale;
  /// When true, selection operations act on all visible layers instead of just the active layer.
  final bool canvasSelectionMode;
  /// Non-null when the notifier wants AidaWidget to show a one-shot warning banner.
  /// AidaWidget clears this immediately after showing it.
  final String? pendingCanvasWarning;

  /// Whether to gzip-compress this file when saving.
  /// Set from the file's detected compression on open; defaults to the app
  /// setting for new patterns. Toggled per-file via the overflow menu.
  final bool compressOnSave;

  /// Current page index (0-based) in page mode. Session-only, not persisted.
  final int currentPage;

  /// Precomputed page layout. Non-null when page mode is enabled.
  final PageLayout? pageLayout;

  /// When non-null, AidaWidget should animate to fit this page index then
  /// clear the value via [clearPendingFitPage].
  final int? pendingFitPage;

  /// The committed progress-marking region in stitch mode (cell coordinates).
  /// Set when the user finishes a drag-to-select on the canvas. Shown as a
  /// dashed overlay and drives the "Mark done / Mark not done" sidebar button.
  /// Cleared when leaving stitch mode or starting a new drag.
  final Rect? progressRegion;

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
    List<PatternProgress> progressUndoStack = const [],
    List<PatternProgress> progressRedoStack = const [],
    this.isDirty = false,
    this.backstitchStartPoint,
    this.recentThreadIds = const [],
    this.selectionRect,
    this.clipboard,
    this.clipboardThreads,
    this.clipboardFromSnippet = false,
    this.activeLayerId = '',
    this.showCompositeThreads = true,
    this.compositeLayer,
    this.mode = AppMode.view,
    this.colourMode = false,
    this.stitchCrossMode = false,
    this.stitchBackMode = false,
    this.stitchFocusThreadId,
    this.stitchShowPageColours = false,
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
    this.backstitchChainMode = false,
    this.viewPanX = 0,
    this.viewPanY = 0,
    this.viewScale = 0,
    this.canvasSelectionMode = false,
    this.pendingCanvasWarning,
    this.compressOnSave = true,
    this.currentPage = 0,
    this.pageLayout,
    this.pendingFitPage,
    this.progressRegion,
  })  : _undoStack = undoStack,
        _redoStack = redoStack,
        _progressUndoStack = progressUndoStack,
        _progressRedoStack = progressRedoStack;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get canUndoProgress => _progressUndoStack.isNotEmpty;
  bool get canRedoProgress => _progressRedoStack.isNotEmpty;

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
      // Mirror the compositor-based logic in copySelection: use the deduplicated
      // visible stitch list so the selection count and copy both reflect what
      // is actually rendered on the canvas.
      final layer = compositeLayer;
      if (layer != null) {
        return [
          ...layer.fullStitches.values.map((cs) => cs.stitch).where((s) => isStitchInRect(s, rect)),
          ...layer.otherStitches.map((cs) => cs.stitch).where((s) => isStitchInRect(s, rect)),
          ...layer.backstitches.where((s) => isStitchInRect(s, rect)),
        ];
      }
      return pattern.layers
          .where((l) => l.visible)
          .expand((l) => l.stitches.where((s) => isStitchInRect(s, rect)))
          .toList();
    }
    return activeLayer.stitches.where((s) => isStitchInRect(s, rect)).toList();
  }

  /// Prefer [Stitch.cellCoords] extension getter over this static method.
  static (int, int)? cellCoords(Stitch s) => s.cellCoords;

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
    List<PatternProgress>? progressUndoStack,
    List<PatternProgress>? progressRedoStack,
    bool? isDirty,
    Object? backstitchStartPoint = _sentinel,
    List<String>? recentThreadIds,
    Object? selectionRect = _sentinel,
    Object? clipboard = _sentinel,
    Object? clipboardThreads = _sentinel,
    bool? clipboardFromSnippet,
    String? activeLayerId,
    bool? showCompositeThreads,
    Object? compositeLayer = _sentinel,
    AppMode? mode,
    bool? colourMode,
    bool? stitchCrossMode,
    bool? stitchBackMode,
    Object? stitchFocusThreadId = _sentinel,
    bool? stitchShowPageColours,
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
    bool? backstitchChainMode,
    double? viewPanX,
    double? viewPanY,
    double? viewScale,
    bool? canvasSelectionMode,
    Object? pendingCanvasWarning = _sentinel,
    bool? compressOnSave,
    int? currentPage,
    Object? pageLayout = _sentinel,
    Object? pendingFitPage = _sentinel,
    Object? progressRegion = _sentinel,
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
      progressUndoStack: progressUndoStack ?? _progressUndoStack,
      progressRedoStack: progressRedoStack ?? _progressRedoStack,
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
      compositeLayer: compositeLayer == _sentinel
          ? this.compositeLayer
          : compositeLayer as CompositeLayer?,
      mode: mode ?? this.mode,
      colourMode: colourMode ?? this.colourMode,
      stitchCrossMode: stitchCrossMode ?? this.stitchCrossMode,
      stitchBackMode: stitchBackMode ?? this.stitchBackMode,
      stitchFocusThreadId: stitchFocusThreadId == _sentinel
          ? this.stitchFocusThreadId
          : stitchFocusThreadId as String?,
      stitchShowPageColours: stitchShowPageColours ?? this.stitchShowPageColours,
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
      backstitchChainMode: backstitchChainMode ?? this.backstitchChainMode,
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
      progressRegion: progressRegion == _sentinel ? this.progressRegion : progressRegion as Rect?,
    );
  }

  static const _sentinel = Object();
}
