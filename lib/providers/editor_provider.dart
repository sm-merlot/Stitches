import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/symbols.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../services/file_service.dart';

enum DrawingTool {
  fullStitch,    // Full X stitch             [1]
  halfForward,   // Diagonal half /           [2]
  halfBackward,  // Diagonal half \           [3]
  halfCross,     // Full X in half cell       [4]
  quarterDiag,   // Diagonal quarter (auto)   [5]
  quarterCross,  // Full X in quarter cell    [6]
  backstitch,    // Backstitch line           [7]
}

/// Cursor mode — controls what pointer/touch interactions do.
enum DrawingMode { draw, erase, pan, colorPicker, select, paste }

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

  // ── Stitch mode ───────────────────────────────────────────────────────────
  /// Whether stitch mode is active (canvas readonly, simplified toolbar).
  final bool stitchMode;
  /// How cross stitches are rendered in stitch mode.
  final StitchViewMode stitchViewMode;
  /// If set, only this thread is shown at full colour; all others are greyed.
  final String? stitchFocusThreadId;

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
    this.stitchMode = false,
    this.stitchViewMode = StitchViewMode.normal,
    this.stitchFocusThreadId,
  })  : _undoStack = undoStack,
        _redoStack = redoStack;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Thread? get selectedThread => selectedThreadId != null
      ? pattern.threadByCode(selectedThreadId!)
      : null;

  /// Stitches that fall inside the current selectionRect.
  List<Stitch> get selectedStitches {
    final rect = selectionRect;
    if (rect == null) return [];
    return pattern.stitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
  }

  /// Whether a stitch falls within [rect] (for cell stitches: whole-cell containment;
  /// for backstitches: both endpoints must be within the rect).
  static bool isStitchInRect(Stitch s, Rect rect) {
    bool cellIn(int x, int y) =>
        x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
    return switch (s) {
      FullStitch(x: final x, y: final y) => cellIn(x, y),
      HalfStitch(x: final x, y: final y) => cellIn(x, y),
      QuarterStitch(x: final x, y: final y) => cellIn(x, y),
      HalfCrossStitch(x: final x, y: final y) => cellIn(x, y),
      QuarterCrossStitch(x: final x, y: final y) => cellIn(x, y),
      BackStitch(x1: final x1, y1: final y1, x2: final x2, y2: final y2) =>
        x1 >= rect.left && x1 <= rect.right &&
        y1 >= rect.top && y1 <= rect.bottom &&
        x2 >= rect.left && x2 <= rect.right &&
        y2 >= rect.top && y2 <= rect.bottom,
    };
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
    bool? stitchMode,
    StitchViewMode? stitchViewMode,
    Object? stitchFocusThreadId = _sentinel,
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
      stitchMode: stitchMode ?? this.stitchMode,
      stitchViewMode: stitchViewMode ?? this.stitchViewMode,
      stitchFocusThreadId: stitchFocusThreadId == _sentinel
          ? this.stitchFocusThreadId
          : stitchFocusThreadId as String?,
    );
  }

  static const _sentinel = Object();
}

class EditorNotifier extends StateNotifier<EditorState> {
  static const int _maxUndoDepth = 200;

  EditorNotifier() : super(EditorState(pattern: CrossStitchPattern.empty()));

  /// DMC 310 Black — added automatically to every new pattern.
  static const _defaultBlackThread = Thread(
    dmcCode: '310',
    color: Color(0xFF000000),
    name: 'Black',
  );

  void loadPattern(CrossStitchPattern pattern, {String? filePath}) {
    // Restore saved tool, falling back to fullStitch
    DrawingTool tool = DrawingTool.fullStitch;
    if (pattern.editorTool != null) {
      try {
        tool = DrawingTool.values.byName(pattern.editorTool!);
      } catch (_) {}
    }

    // Ensure all threads have symbols (handles files saved before this feature)
    final withSymbols = pattern.copyWith(threads: _assignSymbols(pattern.threads));

    // Restore saved thread, falling back to first thread
    String? threadId = withSymbols.editorSelectedThreadId;
    if (threadId == null || withSymbols.threadByCode(threadId) == null) {
      threadId = withSymbols.threads.isNotEmpty ? withSymbols.threads.first.dmcCode : null;
    }

    state = EditorState(
      pattern: withSymbols,
      filePath: filePath,
      currentTool: tool,
      selectedThreadId: threadId,
      recentThreadIds: threadId != null ? [threadId] : [],
      stitchMode: pattern.editorStitchMode,
      drawingMode: pattern.editorStitchMode ? DrawingMode.pan : DrawingMode.draw,
    );
  }

  void newPattern(CrossStitchPattern pattern) {
    // Seed with DMC 310 Black if no threads provided, then assign symbols
    final threads = _assignSymbols(
        pattern.threads.isNotEmpty ? pattern.threads : [_defaultBlackThread]);
    final seeded = pattern.copyWith(threads: threads);

    state = EditorState(
      pattern: seeded,
      selectedThreadId: threads.first.dmcCode,
      recentThreadIds: [threads.first.dmcCode],
    );
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
    final s = state;
    if (s.filePath == null) return;
    final patternToSave = s.pattern.copyWith(
      editorSelectedThreadId: s.selectedThreadId,
      editorTool: s.currentTool.name,
      editorStitchMode: s.stitchMode,
    );
    await FileService.saveFile(patternToSave, s.filePath!);
  }

  void setStitchViewMode(StitchViewMode mode) {
    state = state.copyWith(stitchViewMode: mode);
  }

  /// Set or clear the focus thread. Pass [null] to show all threads normally.
  void setStitchFocusThread(String? threadId) {
    state = state.copyWith(stitchFocusThreadId: threadId);
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
        state.pattern.stitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) return;
    final clips = inSel
        .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
        .toList();
    final threadIds = clips.map((s) => s.threadId).toSet();
    final threads = state.pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
    await Clipboard.setData(ClipboardData(text: _serializeClipboard(threads, clips)));
    state = state.copyWith(clipboard: clips, clipboardThreads: threads);
  }

  Future<void> cutSelection() async {
    final rect = state.selectionRect;
    if (rect == null) return;
    final inSel =
        state.pattern.stitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) return;
    final clips = inSel
        .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
        .toList();
    final threadIds = clips.map((s) => s.threadId).toSet();
    final threads = state.pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
    await Clipboard.setData(ClipboardData(text: _serializeClipboard(threads, clips)));
    final remaining =
        state.pattern.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    final newPattern = state.pattern.copyWith(stitches: remaining);
    state = state.copyWith(
      pattern: newPattern,
      clipboard: clips,
      clipboardThreads: threads,
      selectionRect: null,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
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
        final usedSymbols = threads.map((t) => t.symbol).toSet();
        final resolved = usedSymbols.contains(ct.symbol)
            ? ct.copyWith(symbol: _nextSymbol(usedSymbols))
            : ct;
        threads.add(resolved);
      }
    }

    var stitches = [...state.pattern.stitches];
    for (final s in clips) {
      final placed = EditorState.offsetStitch(s, dx, dy);
      if (_isInBounds(placed, maxX, maxY)) {
        stitches = _stitchesWithAdded(stitches, placed);
      }
    }
    final newPattern = state.pattern.copyWith(stitches: stitches, threads: threads);
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
    final inSel =
        state.pattern.stitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) return;
    var remaining =
        state.pattern.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
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
    final newPattern = state.pattern.copyWith(stitches: remaining);
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
    if (!state.pattern.stitches.any((s) => EditorState.isStitchInRect(s, rect))) return;
    final remaining =
        state.pattern.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    final newPattern = state.pattern.copyWith(stitches: remaining);
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
    // Auto-assign a symbol if the thread doesn't have one
    final usedSymbols = state.pattern.threads.map((t) => t.symbol).toSet();
    final t = thread.symbol.isEmpty
        ? thread.copyWith(symbol: _nextSymbol(usedSymbols))
        : thread;
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

  void resizePattern(int newWidth, int newHeight, int anchorX, int anchorY) {
    final old = state.pattern;
    final dx = (anchorX / 2.0 * (newWidth - old.width)).round();
    final dy = (anchorY / 2.0 * (newHeight - old.height)).round();

    bool inBounds(Stitch s) => switch (s) {
      FullStitch(x: final x, y: final y) =>
        x >= 0 && x < newWidth && y >= 0 && y < newHeight,
      HalfStitch(x: final x, y: final y) =>
        x >= 0 && x < newWidth && y >= 0 && y < newHeight,
      QuarterStitch(x: final x, y: final y) =>
        x >= 0 && x < newWidth && y >= 0 && y < newHeight,
      HalfCrossStitch(x: final x, y: final y) =>
        x >= 0 && x < newWidth && y >= 0 && y < newHeight,
      QuarterCrossStitch(x: final x, y: final y) =>
        x >= 0 && x < newWidth && y >= 0 && y < newHeight,
      BackStitch(x1: final x1, y1: final y1, x2: final x2, y2: final y2) =>
        x1 >= 0 && x1 <= newWidth && y1 >= 0 && y1 <= newHeight &&
        x2 >= 0 && x2 <= newWidth && y2 >= 0 && y2 <= newHeight,
    };

    final newStitches = old.stitches
        .map((s) => EditorState.offsetStitch(s, dx, dy))
        .where(inBounds)
        .toList();

    final newPattern = old.copyWith(
      width: newWidth,
      height: newHeight,
      stitches: newStitches,
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
    final newStitches =
        state.pattern.stitches.where((s) => s.threadId != dmcCode).toList();
    final newPattern =
        state.pattern.copyWith(threads: newThreads, stitches: newStitches);
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
    final alreadyExists = state.pattern.stitches
        .any((s) => s == stitch && s.threadId == stitch.threadId);
    if (alreadyExists) return;

    final newStitches = _stitchesWithAdded(state.pattern.stitches, stitch);
    final newPattern = state.pattern.copyWith(stitches: newStitches);
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
    if (!state.pattern.stitches.any(hit)) return;

    final newStitches =
        state.pattern.stitches.where((s) => !hit(s)).toList();
    final newPattern = state.pattern.copyWith(stitches: newStitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void removeBackstitchAt(double x1, double y1, double x2, double y2) {
    final target = BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: '');
    if (!state.pattern.stitches.any((s) => s == target)) return;

    final newStitches =
        state.pattern.stitches.where((s) => s != target).toList();
    final newPattern = state.pattern.copyWith(stitches: newStitches);
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

  bool _stitchAtCell(Stitch s, int cellX, int cellY) {
    return switch (s) {
      FullStitch(x: final sx, y: final sy) => sx == cellX && sy == cellY,
      HalfStitch(x: final sx, y: final sy) => sx == cellX && sy == cellY,
      QuarterStitch(x: final sx, y: final sy) => sx == cellX && sy == cellY,
      HalfCrossStitch(x: final sx, y: final sy) => sx == cellX && sy == cellY,
      QuarterCrossStitch(x: final sx, y: final sy) =>
        sx == cellX && sy == cellY,
      BackStitch() => false,
    };
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
        'threads': threads.map((t) => t.toYaml()).toList(),
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      }
    });
  }

  (List<Thread>, List<Stitch>)? _parseClipboard(String text) {
    try {
      final root = (jsonDecode(text) as Map<String, dynamic>)['stitchx'];
      if (root == null) return null;
      final threads = (root['threads'] as List)
          .map((t) => Thread.fromYaml(t as Map))
          .toList();
      final stitches = (root['stitches'] as List)
          .map((s) => Stitch.fromYaml(s as Map))
          .toList();
      return (threads, stitches);
    } catch (_) {
      return null;
    }
  }

  bool _isInBounds(Stitch s, int maxX, int maxY) {
    bool cellOk(int x, int y) => x >= 0 && x < maxX && y >= 0 && y < maxY;
    return switch (s) {
      FullStitch(x: final x, y: final y) => cellOk(x, y),
      HalfStitch(x: final x, y: final y) => cellOk(x, y),
      QuarterStitch(x: final x, y: final y) => cellOk(x, y),
      HalfCrossStitch(x: final x, y: final y) => cellOk(x, y),
      QuarterCrossStitch(x: final x, y: final y) => cellOk(x, y),
      BackStitch(x1: final x1, y1: final y1, x2: final x2, y2: final y2) =>
        x1 >= 0 && x1 <= maxX && y1 >= 0 && y1 <= maxY &&
        x2 >= 0 && x2 <= maxX && y2 >= 0 && y2 <= maxY,
    };
  }
}

final editorProvider =
    StateNotifierProvider<EditorNotifier, EditorState>((ref) {
  return EditorNotifier();
});
