import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/symbols.dart';
import '../models/layer.dart';
import '../models/pattern.dart';
import '../models/snippet.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../services/file_service.dart';
import '../services/reference_image_service.dart';

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

/// Controls how stitches are rendered in stitch mode.
enum StitchViewMode {
  /// Stitches shown at full colour (default).
  normal,
  /// Cross stitches are hidden; only backstitches visible.
  hidden,
  /// Cross stitches rendered in greyscale.
  greyed,
}

class EditorState {
  final CrossStitchPattern pattern;
  final String? filePath;
  final DrawingTool currentTool;
  final DrawingMode drawingMode;
  final String? selectedThreadId;
  final List<CrossStitchPattern> _undoStack;
  final List<CrossStitchPattern> _redoStack;
  final bool isDirty;
  final Offset? backstitchStartPoint;
  /// Most-recently-used thread IDs, most recent first. Max 5. Session-only.
  final List<String> recentThreadIds;
  final Rect? selectionRect;
  final List<Stitch>? clipboard;
  /// Thread data for stitches on the clipboard — needed when pasting across patterns.
  final List<Thread>? clipboardThreads;
  /// True when the clipboard was loaded from a snippet (not a canvas selection).
  final bool clipboardFromSnippet;

  // ── Layers ────────────────────────────────────────────────────────────────
  /// The layer that drawing operations target.
  final String activeLayerId;
  /// When true, the toolbar palette shows composite (blended) threads for all
  /// visible layers. When false, shows only the active layer's threads.
  final bool showCompositeThreads;
  /// Lazily computed composite thread map: cell key '${x},${y}' → nearest DMC
  /// Thread after blending all visible layers. Null means cache is stale.
  final Map<String, Thread>? compositeThreadCache;

  // ── Stitch mode ───────────────────────────────────────────────────────────
  /// Whether stitch mode is active (canvas readonly, simplified toolbar).
  final bool stitchMode;
  /// Whether block mode is active (stitches rendered as solid colour rects).
  final bool blockMode;
  /// How cross stitches are rendered in stitch mode.
  final StitchViewMode stitchViewMode;
  /// If set, only this thread is shown at full colour; all others are greyed.
  final String? stitchFocusThreadId;

  // ── Reference image overlay ───────────────────────────────────────────────
  /// Decoded reference image for rendering (not part of undo stack).
  final ui.Image? referenceImage;
  /// Opacity of the overlay (0.0–1.0).
  final double referenceOpacity;
  /// Whether the overlay is currently visible.
  final bool referenceVisible;

  // ── Google Drive ──────────────────────────────────────────────────────────
  /// Drive file ID if the current pattern is backed by Google Drive.
  final String? driveFileId;
  /// Drive folder ID where the file lives (needed for upload).
  final String? driveParentFolderId;

  // ── File open state ───────────────────────────────────────────────────────
  /// True once a file has been loaded or created. False on initial workspace
  /// open and after the open file is deleted.
  final bool isFileOpen;

  /// True when the current file is in the native .stitchx format (or unsaved).
  /// False when an imported foreign-format file (.oxs etc.) is open.
  bool get isNativeFormat {
    final path = filePath;
    if (path == null) return true; // unsaved → will save as .stitchx
    return path.endsWith('.stitchx');
  }

  const EditorState({
    required this.pattern,
    this.filePath,
    this.currentTool = DrawingTool.fullStitch,
    this.drawingMode = DrawingMode.draw,
    this.selectedThreadId,
    List<CrossStitchPattern> undoStack = const [],
    List<CrossStitchPattern> redoStack = const [],
    this.isDirty = false,
    this.backstitchStartPoint,
    this.recentThreadIds = const [],
    this.selectionRect,
    this.clipboard,
    this.clipboardThreads,
    this.clipboardFromSnippet = false,
    this.activeLayerId = '',
    this.showCompositeThreads = false,
    this.compositeThreadCache,
    this.stitchMode = false,
    this.blockMode = false,
    this.stitchViewMode = StitchViewMode.normal,
    this.stitchFocusThreadId,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.referenceVisible = true,
    this.driveFileId,
    this.driveParentFolderId,
    this.isFileOpen = false,
  })  : _undoStack = undoStack,
        _redoStack = redoStack;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// The layer currently targeted by drawing operations.
  /// Falls back to first layer if activeLayerId is not found.
  Layer get activeLayer {
    return pattern.layers.firstWhere(
      (l) => l.id == activeLayerId,
      orElse: () => pattern.layers.first,
    );
  }

  /// All layers that have visibility enabled.
  Iterable<Layer> get visibleLayers => pattern.layers.where((l) => l.visible);

  /// Pattern with current editor state embedded, ready to be written to disk.
  CrossStitchPattern get patternForSave => pattern.copyWith(
        editorSelectedThreadId: selectedThreadId,
        editorTool: currentTool.name,
        editorStitchMode: stitchMode,
        editorActiveLayerId: activeLayerId.isEmpty ? null : activeLayerId,
      );

  Thread? get selectedThread => selectedThreadId != null
      ? pattern.threadByCode(selectedThreadId!)
      : null;

  /// Stitches in the current selectionRect, scoped to the active layer.
  List<Stitch> get selectedStitches {
    final rect = selectionRect;
    if (rect == null) return [];
    return activeLayer.stitches
        .where((s) => EditorState.isStitchInRect(s, rect))
        .toList();
  }

  /// Returns the (x, y) cell for cell-based stitches; null for BackStitch.
  static (int, int)? cellCoords(Stitch s) => switch (s) {
    FullStitch(x: final x, y: final y) => (x, y),
    HalfStitch(x: final x, y: final y) => (x, y),
    QuarterStitch(x: final x, y: final y) => (x, y),
    HalfCrossStitch(x: final x, y: final y) => (x, y),
    QuarterCrossStitch(x: final x, y: final y) => (x, y),
    BackStitch() => null,
  };

  /// Whether a stitch falls within [rect] (for cell stitches: whole-cell containment;
  /// for backstitches: both endpoints must be within the rect).
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

  /// Creates a new stitch with coordinates shifted by [dx],[dy].
  /// Cell-based stitches use integer offsets; BackStitch uses double offsets.
  static Stitch offsetStitch(Stitch s, int dx, int dy) {
    return switch (s) {
      FullStitch(x: final x, y: final y, threadId: final t) =>
        FullStitch(x: x + dx, y: y + dy, threadId: t),
      HalfStitch(x: final x, y: final y, isForward: final f, threadId: final t) =>
        HalfStitch(x: x + dx, y: y + dy, isForward: f, threadId: t),
      QuarterStitch(x: final x, y: final y, quadrant: final q, threadId: final t) =>
        QuarterStitch(x: x + dx, y: y + dy, quadrant: q, threadId: t),
      HalfCrossStitch(x: final x, y: final y, half: final h, threadId: final t) =>
        HalfCrossStitch(x: x + dx, y: y + dy, half: h, threadId: t),
      QuarterCrossStitch(x: final x, y: final y, quadrant: final q, threadId: final t) =>
        QuarterCrossStitch(x: x + dx, y: y + dy, quadrant: q, threadId: t),
      BackStitch(x1: final x1, y1: final y1, x2: final x2, y2: final y2, threadId: final t) =>
        BackStitch(x1: x1 + dx, y1: y1 + dy, x2: x2 + dx, y2: y2 + dy, threadId: t),
    };
  }

  EditorState copyWith({
    CrossStitchPattern? pattern,
    Object? filePath = _sentinel,
    DrawingTool? currentTool,
    DrawingMode? drawingMode,
    Object? selectedThreadId = _sentinel,
    List<CrossStitchPattern>? undoStack,
    List<CrossStitchPattern>? redoStack,
    bool? isDirty,
    Object? backstitchStartPoint = _sentinel,
    List<String>? recentThreadIds,
    Object? selectionRect = _sentinel,
    Object? clipboard = _sentinel,
    Object? clipboardThreads = _sentinel,
    bool? clipboardFromSnippet,
    String? activeLayerId,
    bool? showCompositeThreads,
    Object? compositeThreadCache = _sentinel,
    bool? stitchMode,
    bool? blockMode,
    StitchViewMode? stitchViewMode,
    Object? stitchFocusThreadId = _sentinel,
    Object? referenceImage = _sentinel,
    double? referenceOpacity,
    bool? referenceVisible,
    Object? driveFileId = _sentinel,
    Object? driveParentFolderId = _sentinel,
    bool? isFileOpen,
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
      compositeThreadCache: compositeThreadCache == _sentinel
          ? this.compositeThreadCache
          : compositeThreadCache as Map<String, Thread>?,
      stitchMode: stitchMode ?? this.stitchMode,
      blockMode: blockMode ?? this.blockMode,
      stitchViewMode: stitchViewMode ?? this.stitchViewMode,
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
    );
  }

  static const _sentinel = Object();
}

class EditorNotifier extends Notifier<EditorState> {
  // When the stack exceeds this depth, the oldest entries are dropped.
  static const int _maxUndoDepth = 200;

  @override
  EditorState build() => EditorState(pattern: CrossStitchPattern.empty());

  void loadPattern(
    CrossStitchPattern pattern, {
    String? filePath,
    String? driveFileId,
    String? driveParentFolderId,
  }) {
    // Restore saved tool, falling back to fullStitch
    DrawingTool tool = DrawingTool.fullStitch;
    if (pattern.editorTool != null) {
      try {
        tool = DrawingTool.values.byName(pattern.editorTool!);
      } catch (_) {
        // Unknown tool name from an older file format — fall back to fullStitch.
      }
    }

    // Ensure all threads have symbols (handles files saved before this feature)
    final withSymbols = pattern.copyWith(threads: _assignSymbols(pattern.threads));

    // Restore saved thread, falling back to first thread
    String? threadId = withSymbols.editorSelectedThreadId;
    if (threadId == null || withSymbols.threadByCode(threadId) == null) {
      threadId = withSymbols.threads.isNotEmpty ? withSymbols.threads.first.dmcCode : null;
    }

    // Preserve clipboard across pattern switches so users can paste into a
    // different pattern without re-copying. If there was an active clipboard,
    // the new pattern opens directly in paste mode.
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
      stitchMode: pattern.editorStitchMode,
      drawingMode: hasClipboard
          ? DrawingMode.paste
          : (pattern.editorStitchMode ? DrawingMode.pan : DrawingMode.draw),
      clipboard: hasClipboard ? prevClipboard : null,
      clipboardThreads: hasClipboard ? prevClipboardThreads : null,
      clipboardFromSnippet: hasClipboard && prevClipboardFromSnippet,
      referenceOpacity: withSymbols.referenceOpacity,
      driveFileId: driveFileId,
      driveParentFolderId: driveParentFolderId,
      isFileOpen: true,
      activeLayerId: withSymbols.editorActiveLayerId ??
          (withSymbols.layers.isNotEmpty ? withSymbols.layers.first.id : ''),
    );

    // Decode reference image asynchronously after state is set.
    if (withSymbols.referenceImagePath != null) {
      ReferenceImageService.decodeFromPath(withSymbols.referenceImagePath!)
          .then((img) {
        if (img != null && ref.mounted) {
          state = state.copyWith(referenceImage: img);
        }
      });
    }
  }

  void setDriveFileId(String? id) {
    // Mark dirty so the auto-save listener uploads the current state to Drive.
    state = state.copyWith(driveFileId: id, isDirty: state.isFileOpen);
  }

  void setDriveParentFolderId(String? id) {
    state = state.copyWith(driveParentFolderId: id);
  }

  void newPattern(CrossStitchPattern pattern) {
    final threads = _assignSymbols(pattern.threads);
    final seeded = pattern.copyWith(threads: threads);

    state = EditorState(
      pattern: seeded,
      selectedThreadId: threads.first.dmcCode,
      recentThreadIds: [threads.first.dmcCode],
      isFileOpen: true,
      activeLayerId: seeded.layers.isNotEmpty ? seeded.layers.first.id : '',
    );
  }

  /// Resets to no-file-open state (e.g. after the open file is deleted).
  void closeFile() {
    state = EditorState(pattern: CrossStitchPattern.empty());
  }

  void setFilePath(String? path) {
    state = state.copyWith(filePath: path);
  }

  void markSaved() {
    state = state.copyWith(isDirty: false);
  }

  void setTool(DrawingTool tool) {
    state = state.copyWith(
      currentTool: tool,
      backstitchStartPoint: null,
    );
  }

  void setDrawingMode(DrawingMode mode) {
    final leavingSelection =
        state.drawingMode == DrawingMode.select || state.drawingMode == DrawingMode.paste;
    state = state.copyWith(
      drawingMode: mode,
      backstitchStartPoint: null,
      // Clear selection rect and paste mode when leaving select/paste modes
      selectionRect: leavingSelection ? null : state.selectionRect,
    );
  }

  void toggleDrawingMode() {
    final newMode = state.drawingMode == DrawingMode.draw
        ? DrawingMode.erase
        : DrawingMode.draw;
    state = state.copyWith(drawingMode: newMode, backstitchStartPoint: null);
  }

  void setSelectedThread(String? threadId) {
    final recents = threadId == null
        ? state.recentThreadIds
        : [
            threadId,
            ...state.recentThreadIds.where((id) => id != threadId),
          ].take(5).toList();
    state = state.copyWith(selectedThreadId: threadId, recentThreadIds: recents);
  }

  void setAidaColor(Color color) {
    state = state.copyWith(
      pattern: state.pattern.copyWith(aidaColor: color),
      isDirty: true,
    );
  }

  // ─── Stitch mode ──────────────────────────────────────────────────────────

  /// Toggle block mode on/off (stitches drawn as solid colour rects).
  void toggleBlockMode() {
    state = state.copyWith(blockMode: !state.blockMode);
  }

  /// Toggle stitch mode on/off. Entering stitch mode switches to pan.
  /// Auto-saves the new value to the file immediately if a file path is set.
  void toggleStitchMode() {
    final entering = !state.stitchMode;
    state = state.copyWith(
      stitchMode: entering,
      drawingMode: entering ? DrawingMode.pan : DrawingMode.draw,
      selectionRect: null,
      backstitchStartPoint: null,
    );
    _autoSaveStitchMode();
  }

  /// Writes only the editor metadata (including stitchMode) to the file
  /// without touching isDirty — the pattern content hasn't changed.
  Future<void> _autoSaveStitchMode() async {
    if (state.filePath == null) return;
    await FileService.saveFile(state.patternForSave, state.filePath!);
  }

  void setStitchViewMode(StitchViewMode mode) {
    state = state.copyWith(stitchViewMode: mode);
  }

  /// Set or clear the focus thread. Pass [null] to show all threads normally.
  void setStitchFocusThread(String? threadId) {
    state = state.copyWith(stitchFocusThreadId: threadId);
  }

  // ─── Reference image overlay ──────────────────────────────────────────────

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

  // ─── Selection ────────────────────────────────────────────────────────────

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
    if (rect == null) return;
    final inSel =
        state.activeLayer.stitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) return;
    final clips = inSel
        .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
        .toList();
    final threadIds = clips.map((s) => s.threadId).toSet();
    final threads = state.pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
    await Clipboard.setData(ClipboardData(text: _serializeClipboard(threads, clips)));
    state = state.copyWith(
      clipboard: clips,
      clipboardThreads: threads,
      drawingMode: DrawingMode.paste,
      selectionRect: null,
      clipboardFromSnippet: false,
    );
  }

  /// Reads the system clipboard and enters paste mode if valid stitchx data is found.
  /// Falls back to the in-memory clipboard if the system clipboard has other content.
  Future<void> enterPasteMode() async {
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
    // Fall back to in-memory clipboard (e.g. if system clipboard was overwritten)
    if (state.clipboard == null || state.clipboard!.isEmpty) return;
    state = state.copyWith(
      drawingMode: DrawingMode.paste,
      selectionRect: null,
    );
  }

  /// Stamps the clipboard contents at offset [dx],[dy] from origin (0,0).
  /// Any clipboard threads not yet in the pattern are added automatically.
  void commitPaste(int dx, int dy) {
    final clips = state.clipboard;
    if (clips == null || clips.isEmpty) return;
    final maxX = state.pattern.width;
    final maxY = state.pattern.height;

    // Add any clipboard threads not already in the pattern, resolving symbol conflicts
    var threads = [...state.pattern.threads];
    for (final ct in state.clipboardThreads ?? <Thread>[]) {
      if (!threads.any((t) => t.dmcCode == ct.dmcCode)) {
        threads.add(_resolveThreadSymbol(ct, threads));
      }
    }

    var stitches = [...state.activeLayer.stitches];
    for (final s in clips) {
      final placed = EditorState.offsetStitch(s, dx, dy);
      if (!_isInBounds(placed, maxX, maxY)) continue;
      stitches = _stitchesWithAdded(stitches, placed);
    }
    final newPattern = _patternWithActiveLayerStitches(
        state.pattern.copyWith(threads: threads), stitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Moves the selected stitches by [dx],[dy] cells. Updates selectionRect too.
  void moveSelection(int dx, int dy) {
    final rect = state.selectionRect;
    if (rect == null) return;
    final maxX = state.pattern.width;
    final maxY = state.pattern.height;
    final activeStitches = state.activeLayer.stitches;
    final inSel =
        activeStitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) return;
    var remaining =
        activeStitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    for (final s in inSel) {
      final moved = EditorState.offsetStitch(s, dx, dy);
      if (_isInBounds(moved, maxX, maxY)) {
        remaining = _stitchesWithAdded(remaining, moved);
      }
    }
    final newRect = Rect.fromLTWH(
      (rect.left + dx).clamp(0, maxX.toDouble()),
      (rect.top + dy).clamp(0, maxY.toDouble()),
      rect.width,
      rect.height,
    );
    final newPattern = _patternWithActiveLayerStitches(state.pattern, remaining);
    state = state.copyWith(
      pattern: newPattern,
      selectionRect: newRect,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void deleteSelection() {
    final rect = state.selectionRect;
    if (rect == null) return;
    final activeStitches = state.activeLayer.stitches;
    if (!activeStitches.any((s) => EditorState.isStitchInRect(s, rect))) return;
    final remaining =
        activeStitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    final newPattern = _patternWithActiveLayerStitches(state.pattern, remaining);
    state = state.copyWith(
      pattern: newPattern,
      selectionRect: null,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Escape: if in paste mode, exit back to select; otherwise clear selection rect.
  void cancelSelection() {
    if (state.drawingMode == DrawingMode.paste) {
      state = state.copyWith(drawingMode: DrawingMode.select);
    } else {
      state = state.copyWith(selectionRect: null);
    }
  }

  void setBackstitchStart(Offset? point) {
    state = state.copyWith(backstitchStartPoint: point);
  }

  void addThread(Thread thread) {
    final t = _resolveThreadSymbol(thread, state.pattern.threads);
    final newThreads = [...state.pattern.threads, t];
    final newPattern = state.pattern.copyWith(threads: newThreads);
    final recents = [
      t.dmcCode,
      ...state.recentThreadIds.where((id) => id != t.dmcCode),
    ].take(5).toList();
    state = state.copyWith(
      pattern: newPattern,
      selectedThreadId: t.dmcCode,
      recentThreadIds: recents,
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

  /// Replaces every stitch using [oldDmcCode] with [newDmcCode], and updates
  /// the thread entry in the palette. The old thread's symbol is preserved.
  /// Pushes an undo step.
  void replaceThread(String oldDmcCode, String newDmcCode, Color newColor, String newName) {
    if (oldDmcCode == newDmcCode) return;
    final oldThread = state.pattern.threads
        .where((t) => t.dmcCode == oldDmcCode)
        .firstOrNull;
    if (oldThread == null) return;

    final newThread = Thread(
      dmcCode: newDmcCode,
      color: newColor,
      name: newName,
      symbol: oldThread.symbol,
    );

    // Replace or merge threads.
    var threads = state.pattern.threads.toList();
    final oldIdx = threads.indexWhere((t) => t.dmcCode == oldDmcCode);
    final newExists = threads.any((t) => t.dmcCode == newDmcCode);
    if (newExists) {
      threads.removeAt(oldIdx);
    } else {
      threads[oldIdx] = newThread;
    }

    // Remap stitches across all layers.
    final remappedPattern = _patternWithAllLayersTransformed(
      state.pattern.copyWith(threads: threads),
      (stitches) => stitches
          .map((s) => s.threadId == oldDmcCode ? _withThreadId(s, newDmcCode) : s)
          .toList(),
    );

    state = state.copyWith(
      pattern: remappedPattern,
      selectedThreadId: state.selectedThreadId == oldDmcCode ? newDmcCode : state.selectedThreadId,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Same as [replaceThread] but operates on a snippet (used in snippet editor).
  void replaceSnippetThread(String snippetId, String oldDmcCode, String newDmcCode, Color newColor, String newName) {
    if (oldDmcCode == newDmcCode) return;
    final snippet = state.pattern.snippets
        .where((s) => s.id == snippetId)
        .firstOrNull;
    if (snippet == null) return;

    final oldThread = snippet.threads
        .where((t) => t.dmcCode == oldDmcCode)
        .firstOrNull;
    if (oldThread == null) return;

    final newThread = Thread(
      dmcCode: newDmcCode,
      color: newColor,
      name: newName,
      symbol: oldThread.symbol,
    );

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
            ? s.copyWith(threads: threads, stitches: stitches)
            : s)
        .toList();

    state = state.copyWith(
      pattern: state.pattern.copyWith(snippets: updated),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
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

    final newPattern = _patternWithAllLayersTransformed(
      old.copyWith(width: newWidth, height: newHeight),
      (stitches) => stitches
          .map((s) => EditorState.offsetStitch(s, dx, dy))
          .where(inBounds)
          .toList(),
    );

    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      redoStack: [],
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

  void addStitch(Stitch stitch) {
    // Skip if identical stitch (same position AND same thread) already exists
    final alreadyExists = state.activeLayer.stitches
        .any((s) => s == stitch && s.threadId == stitch.threadId);
    if (alreadyExists) return;

    final newStitches = _stitchesWithAdded(state.activeLayer.stitches, stitch);
    final newPattern = _patternWithActiveLayerStitches(state.pattern, newStitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Removes all stitches at [x],[y]: cell-based stitches and any backstitch
  /// with at least one endpoint inside the cell boundaries.
  void removeStitchesAt(int x, int y) {
    bool hit(Stitch s) => _stitchAtCell(s, x, y) || _backstitchInCell(s, x, y);
    if (!state.activeLayer.stitches.any(hit)) return;

    final newStitches =
        state.activeLayer.stitches.where((s) => !hit(s)).toList();
    final newPattern = _patternWithActiveLayerStitches(state.pattern, newStitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// 8-connected flood fill.
  ///
  /// [erase] == false: fill connected cells that have the same colour as
  /// (x,y) (or are empty if (x,y) is empty) with [FullStitch]es of the
  /// current thread.
  ///
  /// [erase] == true: remove all FullStitches connected (8-way) to (x,y)
  /// that share the same threadId.
  void floodFill(int startX, int startY, {required bool erase}) {
    final p = state.pattern;
    if (startX < 0 || startX >= p.width || startY < 0 || startY >= p.height) return;

    final layerStitches = state.activeLayer.stitches;

    // Determine the "seed" colour (null = empty cell).
    String? seedThreadId;
    for (final s in layerStitches) {
      if (s is FullStitch && s.x == startX && s.y == startY) {
        seedThreadId = s.threadId;
        break;
      }
    }

    if (erase && seedThreadId == null) return; // nothing to erase

    // For fill: we need a selected thread.
    final fillThreadId = state.selectedThreadId;
    if (!erase && fillThreadId == null) return;

    // If filling and the cell already has the target colour, nothing to do.
    if (!erase && seedThreadId == fillThreadId) return;

    // Build a fast lookup set of occupied cells (FullStitch only).
    // key = x * 100000 + y
    final Map<int, String> occupied = {};
    for (final s in layerStitches) {
      if (s is FullStitch) occupied[s.x * 100000 + s.y] = s.threadId;
    }

    int key(int x, int y) => x * 100000 + y;

    bool matches(int x, int y) {
      final t = occupied[key(x, y)];
      return t == seedThreadId;
    }

    // BFS
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
      // Remove existing FullStitches at target cells, then add new ones.
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
    final newPattern = _patternWithActiveLayerStitches(state.pattern, newStitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void undo() {
    if (!state.canUndo) return;
    final undoStack = [...state._undoStack];
    final redoStack = [...state._redoStack];
    final previous = undoStack.removeLast();
    redoStack.add(state.pattern);
    state = state.copyWith(
      pattern: previous,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: true,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final undoStack = [...state._undoStack];
    final redoStack = [...state._redoStack];
    final next = redoStack.removeLast();
    undoStack.add(state.pattern);
    state = state.copyWith(
      pattern: next,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: true,
    );
  }

  static Stitch _withThreadId(Stitch s, String id) => switch (s) {
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

  List<CrossStitchPattern> _buildUndoStack() {
    var stack = [...state._undoStack, state.pattern];
    if (stack.length > _maxUndoDepth) {
      stack = stack.sublist(stack.length - _maxUndoDepth);
    }
    return stack;
  }

  List<Stitch> _stitchesWithAdded(List<Stitch> existing, Stitch newStitch) {
    // Remove any conflicting stitch at the same position/type, then add
    final filtered = existing.where((s) => s != newStitch).toList();
    return [...filtered, newStitch];
  }

  /// Returns a new [CrossStitchPattern] with [newStitches] applied to the active layer.
  CrossStitchPattern _patternWithActiveLayerStitches(
      CrossStitchPattern pattern, List<Stitch> newStitches) {
    final activeId = state.activeLayerId;
    final newLayers = pattern.layers.map((l) {
      if (l.id == activeId || (activeId.isEmpty && l == pattern.layers.first)) {
        return l.copyWith(stitches: newStitches);
      }
      return l;
    }).toList();
    return pattern.copyWith(layers: newLayers);
  }

  /// Returns a new [CrossStitchPattern] with [transform] applied to each layer's stitches.
  CrossStitchPattern _patternWithAllLayersTransformed(
      CrossStitchPattern pattern, List<Stitch> Function(List<Stitch>) transform) {
    final newLayers = pattern.layers
        .map((l) => l.copyWith(stitches: transform(l.stitches)))
        .toList();
    return pattern.copyWith(layers: newLayers);
  }

  bool _stitchAtCell(Stitch s, int cellX, int cellY) {
    final coords = EditorState.cellCoords(s);
    return coords != null && coords.$1 == cellX && coords.$2 == cellY;
  }

  /// A backstitch is "in" a cell if either endpoint lies within its bounds
  /// (inclusive, so border-shared endpoints are caught by both adjacent cells).
  bool _backstitchInCell(Stitch s, int cellX, int cellY) {
    if (s is! BackStitch) return false;
    bool inside(double gx, double gy) =>
        gx >= cellX && gx <= cellX + 1 && gy >= cellY && gy <= cellY + 1;
    return inside(s.x1, s.y1) || inside(s.x2, s.y2);
  }

  // ─── Symbol assignment ────────────────────────────────────────────────────

  /// Returns the first symbol from [kPatternSymbols] not already in [used], or '' if exhausted.
  String _nextSymbol(Set<String> used) {
    for (final s in kPatternSymbols) {
      if (!used.contains(s)) return s;
    }
    return '';
  }

  /// Returns [thread] with a symbol assigned if its current symbol is empty or
  /// already used by a thread in [existingThreads].
  Thread _resolveThreadSymbol(Thread thread, List<Thread> existingThreads) {
    final usedSymbols = existingThreads.map((t) => t.symbol).toSet();
    if (thread.symbol.isEmpty || usedSymbols.contains(thread.symbol)) {
      return thread.copyWith(symbol: _nextSymbol(usedSymbols));
    }
    return thread;
  }

  /// Ensures every thread in [threads] has a symbol, assigning from [kPatternSymbols]
  /// in order for any that are missing one.  Already-assigned symbols are preserved.
  List<Thread> _assignSymbols(List<Thread> threads) {
    final assigned = <String>{};
    return threads.map((t) {
      if (t.symbol.isNotEmpty) {
        assigned.add(t.symbol);
        return t;
      }
      final s = _nextSymbol(assigned);
      if (s.isNotEmpty) assigned.add(s);
      return t.copyWith(symbol: s);
    }).toList();
  }

  // ─── System clipboard serialisation ───────────────────────────────────────

  String _serializeClipboard(List<Thread> threads, List<Stitch> stitches) {
    return jsonEncode({
      'stitchx': {
        'version': 1,
        'threads': threads.map((t) => t.toYaml()).toList(),
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      }
    });
  }

  (List<Thread>, List<Stitch>)? _parseClipboard(String text) {
    try {
      final root = (jsonDecode(text) as Map<String, dynamic>)['stitchx'];
      if (root == null) return null;
      // 'version' field reserved for future format migrations; currently unused.
      final threads = (root['threads'] as List)
          .map((t) => Thread.fromYaml(t as Map<String, dynamic>))
          .toList();
      final stitches = (root['stitches'] as List)
          .map((s) => Stitch.fromYaml(s as Map<String, dynamic>))
          .toList();
      return (threads, stitches);
    } catch (_) {
      // Invalid or non-stitchx clipboard content — fall back to in-memory clipboard.
      return null;
    }
  }

  bool _isInBounds(Stitch s, int maxX, int maxY) {
    final coords = EditorState.cellCoords(s);
    if (coords != null) {
      return coords.$1 >= 0 && coords.$1 < maxX && coords.$2 >= 0 && coords.$2 < maxY;
    }
    final bs = s as BackStitch;
    return bs.x1 >= 0 && bs.x1 <= maxX && bs.y1 >= 0 && bs.y1 <= maxY &&
        bs.x2 >= 0 && bs.x2 <= maxX && bs.y2 >= 0 && bs.y2 <= maxY;
  }

  // ─── Snippets ─────────────────────────────────────────────────────────────

  void addSnippet(Snippet snippet) {
    state = state.copyWith(
      pattern: state.pattern.copyWith(
        snippets: [...state.pattern.snippets, snippet],
      ),
      isDirty: true,
    );
  }

  void updateSnippet(Snippet snippet) {
    final updated = state.pattern.snippets
        .map((s) => s.id == snippet.id ? snippet : s)
        .toList();
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
    final updated = state.pattern.snippets.map((s) => s.id == id ? resized : s).toList();
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

    // ── per-transform orientation maps ─────────────────────────────────────

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

    // CW 90°: TL→TR→BR→BL→TL, top→right→bottom→left→top
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

    // ── stitch transformers ─────────────────────────────────────────────────

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
    final updated = state.pattern.snippets.map((s) => s.id == id ? transformed : s).toList();
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

    // Derive bounding dimensions from the normalised stitch coords.
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

    // Return to select mode after saving (exits paste mode if active).
    if (state.drawingMode == DrawingMode.paste) {
      cancelSelection();
    }
  }

  /// Loads a snippet's stitches into the in-memory and system clipboard, then enters paste mode.
  Future<void> loadSnippetToClipboard(Snippet snippet) async {
    await Clipboard.setData(
      ClipboardData(text: _serializeClipboard(snippet.threads, snippet.stitches)),
    );
    state = state.copyWith(
      clipboard: snippet.stitches,
      clipboardThreads: snippet.threads,
      drawingMode: DrawingMode.paste,
      selectionRect: null,
      clipboardFromSnippet: true,
    );
  }
}

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);
