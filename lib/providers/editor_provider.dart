import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

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
enum DrawingMode { draw, erase, pan, colorPicker }

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
  })  : _undoStack = undoStack,
        _redoStack = redoStack;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Thread? get selectedThread => selectedThreadId != null
      ? pattern.threadByCode(selectedThreadId!)
      : null;

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
    );
  }

  static const _sentinel = Object();
}

class EditorNotifier extends StateNotifier<EditorState> {
  static const int _maxUndoDepth = 50;

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

    // Restore saved thread, falling back to first thread
    String? threadId = pattern.editorSelectedThreadId;
    if (threadId == null || pattern.threadByCode(threadId) == null) {
      threadId =
          pattern.threads.isNotEmpty ? pattern.threads.first.dmcCode : null;
    }

    state = EditorState(
      pattern: pattern,
      filePath: filePath,
      currentTool: tool,
      selectedThreadId: threadId,
      recentThreadIds: threadId != null ? [threadId] : [],
    );
  }

  void newPattern(CrossStitchPattern pattern) {
    // Seed with DMC 310 Black if no threads provided
    final threads = pattern.threads.isNotEmpty
        ? pattern.threads
        : [_defaultBlackThread];
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
    state = state.copyWith(
      drawingMode: mode,
      // Cancel in-progress backstitch when switching away from draw mode
      backstitchStartPoint: null,
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

  void setBackstitchStart(Offset? point) {
    state = state.copyWith(backstitchStartPoint: point);
  }

  void addThread(Thread thread) {
    final newThreads = [...state.pattern.threads, thread];
    final newPattern = state.pattern.copyWith(threads: newThreads);
    final recents = [
      thread.dmcCode,
      ...state.recentThreadIds.where((id) => id != thread.dmcCode),
    ].take(5).toList();
    state = state.copyWith(
      pattern: newPattern,
      selectedThreadId: thread.dmcCode,
      recentThreadIds: recents,
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

  /// Removes all cell-based stitches at [x],[y] (ignores backstitches).
  void removeStitchesAt(int x, int y) {
    // Skip if nothing to erase at this cell
    if (!state.pattern.stitches.any((s) => _stitchAtCell(s, x, y))) return;

    final newStitches =
        state.pattern.stitches.where((s) => !_stitchAtCell(s, x, y)).toList();
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
}

final editorProvider =
    StateNotifierProvider<EditorNotifier, EditorState>((ref) {
  return EditorNotifier();
});
