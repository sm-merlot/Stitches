part of 'editor_provider.dart';

// ─── EditorState ──────────────────────────────────────────────────────────────

// ignore_for_file: avoid_positional_boolean_parameters

/// Monolithic editor state shared across all modes.
///
/// Field groups:
///
/// **Shared / file lifecycle**
///   pattern, filePath, driveFileId, driveParentFolderId, isFileOpen,
///   isDirty, compressOnSave, mode, selectedThreadId, activeLayerId,
///   showCompositeThreads, compositeLayer, recentThreadIds,
///   controllerCanUndo, controllerCanRedo.
///
/// **Edit-mode session** → [editSession] ([EditSessionState])
///   currentTool, drawingMode, backstitchStartPoint, backstitchChainMode,
///   selectionRect, clipboard, clipboardThreads, clipboardFromSnippet,
///   eraserSize, fillEraseActive, canvasSelectionMode, pendingCanvasWarning,
///   referenceImage, referenceOpacity, referenceVisible, colourMode.
///
/// **Stitch-mode session** → [stitchSession] ([StitchSessionState])
///   crossMode (was stitchCrossMode), backMode (was stitchBackMode),
///   focusThreadId (was stitchFocusThreadId),
///   showPageColours (was stitchShowPageColours),
///   currentPage, pageLayout, pendingFitPage, progressRegion.
///
/// **Snippet-editor session** → [snippetEditorState] ([SnippetEditorState])
///   palettes (was snippetPalettes),
///   activePaletteIndex (was snippetActivePaletteIndex).
///
/// **View / pan position** → [viewState] ([ViewState])
///   panX (was viewPanX), panY (was viewPanY), scale (was viewScale).
///
/// **Render pipeline hint** (kept flat — AidaWidget reads it directly)
///   dirtyCellKeys.
class EditorState {
  // ── Shared / file lifecycle ───────────────────────────────────────────────
  final CrossStitchPattern pattern;
  final String? filePath;
  final String? driveFileId;
  final String? driveParentFolderId;
  final bool isFileOpen;
  final bool isDirty;
  final bool compressOnSave;
  final AppMode mode;
  final String? selectedThreadId;
  final String activeLayerId;
  final bool showCompositeThreads;
  final CompositeLayer? compositeLayer;

  /// Most-recently-used thread IDs, most recent first. Max 5. Session-only.
  final List<String> recentThreadIds;
  final bool controllerCanUndo;
  final bool controllerCanRedo;

  // ── Grouped session state ─────────────────────────────────────────────────
  final ViewState viewState;
  final StitchSessionState stitchSession;
  final EditSessionState editSession;
  final SnippetEditorState snippetEditorState;

  // ── Render pipeline hint ──────────────────────────────────────────────────
  /// [Cell] keys whose [RenderCache] entries need incremental update.
  ///
  /// Non-null when [compositeLayer] was patched incrementally (e.g. a single
  /// stitch drawn or erased). [AidaWidget._syncRenderCache] calls
  /// [RenderCache.updateCells] instead of [RenderCache.rebuild] when this is
  /// set — O(changed cells) instead of O(total stitches).
  ///
  /// Null when the composite was fully rebuilt; forces a full cache rebuild.
  /// Accumulated across successive draw events within the same frame so that
  /// multiple pointer-move events are batched into one [updateCells] call.
  /// Always null in [copyWith] unless explicitly passed — any operation that
  /// replaces the composite without knowing dirty cells must clear it.
  final Set<Cell>? dirtyCellKeys;

  /// True when the current file is in the native .stitches format (or unsaved).
  bool get isNativeFormat {
    final path = filePath;
    if (path == null) return true;
    return path.endsWith('.stitches');
  }

  const EditorState({
    required this.pattern,
    this.filePath,
    this.selectedThreadId,
    this.isDirty = false,
    this.recentThreadIds = const [],
    this.activeLayerId = '',
    this.showCompositeThreads = true,
    this.compositeLayer,
    this.mode = AppMode.view,
    this.driveFileId,
    this.driveParentFolderId,
    this.isFileOpen = false,
    this.compressOnSave = true,
    this.controllerCanUndo = false,
    this.controllerCanRedo = false,
    this.viewState = const ViewState(),
    this.stitchSession = const StitchSessionState(),
    this.editSession = const EditSessionState(),
    this.snippetEditorState = const SnippetEditorState(),
    this.dirtyCellKeys,
  });

  bool get canUndo => controllerCanUndo;
  bool get canRedo => controllerCanRedo;

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
    final rect = editSession.selectionRect;
    if (rect == null) return [];
    if (editSession.canvasSelectionMode) {
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
  static Cell? cellCoords(Stitch s) => s.cellCoords;

  static bool isStitchInRect(Stitch s, Rect rect) {
    final coords = cellCoords(s);
    if (coords != null) {
      return coords.x >= rect.left && coords.x < rect.right &&
          coords.y >= rect.top && coords.y < rect.bottom;
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
    Object? selectedThreadId = _sentinel,
    bool? isDirty,
    List<String>? recentThreadIds,
    String? activeLayerId,
    bool? showCompositeThreads,
    Object? compositeLayer = _sentinel,
    AppMode? mode,
    Object? driveFileId = _sentinel,
    Object? driveParentFolderId = _sentinel,
    bool? isFileOpen,
    bool? compressOnSave,
    bool? controllerCanUndo,
    bool? controllerCanRedo,
    ViewState? viewState,
    StitchSessionState? stitchSession,
    EditSessionState? editSession,
    SnippetEditorState? snippetEditorState,
    Set<Cell>? dirtyCellKeys,
  }) {
    return EditorState(
      pattern: pattern ?? this.pattern,
      filePath: filePath == _sentinel ? this.filePath : filePath as String?,
      selectedThreadId: selectedThreadId == _sentinel
          ? this.selectedThreadId
          : selectedThreadId as String?,
      isDirty: isDirty ?? this.isDirty,
      recentThreadIds: recentThreadIds ?? this.recentThreadIds,
      activeLayerId: activeLayerId ?? this.activeLayerId,
      showCompositeThreads: showCompositeThreads ?? this.showCompositeThreads,
      compositeLayer: compositeLayer == _sentinel
          ? this.compositeLayer
          : compositeLayer as CompositeLayer?,
      mode: mode ?? this.mode,
      driveFileId: driveFileId == _sentinel
          ? this.driveFileId
          : driveFileId as String?,
      driveParentFolderId: driveParentFolderId == _sentinel
          ? this.driveParentFolderId
          : driveParentFolderId as String?,
      isFileOpen: isFileOpen ?? this.isFileOpen,
      compressOnSave: compressOnSave ?? this.compressOnSave,
      controllerCanUndo: controllerCanUndo ?? this.controllerCanUndo,
      controllerCanRedo: controllerCanRedo ?? this.controllerCanRedo,
      viewState: viewState ?? this.viewState,
      stitchSession: stitchSession ?? this.stitchSession,
      editSession: editSession ?? this.editSession,
      snippetEditorState: snippetEditorState ?? this.snippetEditorState,
      dirtyCellKeys: dirtyCellKeys,
    );
  }

  static const _sentinel = Object();
}
