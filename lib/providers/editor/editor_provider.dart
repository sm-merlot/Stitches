import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/dmc_colors.dart';
import '../../data/symbols.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_item.dart';
import '../../models/pattern.dart';
import '../../models/snippet.dart';
import '../../models/snippet_palette.dart';
import '../../models/snippet_palette_resolver.dart';
import '../../models/stitch.dart';
import '../../models/thread.dart';
import '../../services/file_service.dart';
import '../../services/reference_image_service.dart';
import '../../services/sprite_importer.dart';

part 'editor_provider_drawing.dart';
part 'editor_provider_layers.dart';
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
  final Map<String, Thread>? compositeThreadCache;
  final bool stitchMode;
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
  /// When true, selection operations act on all visible layers instead of just the active layer.
  final bool canvasSelectionMode;
  /// Non-null when the notifier wants PatternCanvas to show a one-shot warning banner.
  /// PatternCanvas clears this immediately after showing it.
  final String? pendingCanvasWarning;

  /// True when the current file is in the native .stitchx format (or unsaved).
  bool get isNativeFormat {
    final path = filePath;
    if (path == null) return true;
    return path.endsWith('.stitchx');
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
    this.compositeThreadCache,
    this.stitchMode = false,
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
    this.canvasSelectionMode = false,
    this.pendingCanvasWarning,
  })  : _undoStack = undoStack,
        _redoStack = redoStack;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Layer get activeLayer => pattern.layers.firstWhere(
        (l) => l.id == activeLayerId,
        orElse: () => pattern.layers.first,
      );

  Iterable<Layer> get visibleLayers => pattern.layers.where((l) => l.visible);

  CrossStitchPattern get patternForSave => pattern.copyWith(
    editorTool: currentTool.name,
    editorSelectedThreadId: selectedThreadId,
    editorStitchMode: stitchMode,
    editorActiveLayerId: activeLayerId.isEmpty ? null : activeLayerId,
    editorBlockMode: blockMode,
  );

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
    Object? compositeThreadCache = _sentinel,
    bool? stitchMode,
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
    bool? canvasSelectionMode,
    Object? pendingCanvasWarning = _sentinel,
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
      canvasSelectionMode: canvasSelectionMode ?? this.canvasSelectionMode,
      pendingCanvasWarning: pendingCanvasWarning == _sentinel
          ? this.pendingCanvasWarning
          : pendingCanvasWarning as String?,
    );
  }

  static const _sentinel = Object();
}

// ─── EditorNotifier ───────────────────────────────────────────────────────────

class EditorNotifier extends Notifier<EditorState>
    with DrawingMixin, LayersMixin, SnippetsMixin, SelectionMixin {

  static const int _maxUndoDepth = 200;

  @override
  EditorState build() => EditorState(pattern: CrossStitchPattern.empty());

  // ─── File lifecycle ─────────────────────────────────────────────────────────

  void loadPattern(
    CrossStitchPattern pattern, {
    String? filePath,
    String? driveFileId,
    String? driveParentFolderId,
  }) {
    DrawingTool tool = DrawingTool.fullStitch;
    if (pattern.editorTool != null) {
      try {
        tool = DrawingTool.values.byName(pattern.editorTool!);
      } catch (_) {}
    }

    final withSymbols = pattern.copyWith(threads: _assignSymbols(pattern.threads));

    String? threadId = withSymbols.editorSelectedThreadId;
    if (threadId == null || withSymbols.threadByCode(threadId) == null) {
      threadId = withSymbols.threads.isNotEmpty ? withSymbols.threads.first.dmcCode : null;
    }

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
      blockMode: pattern.editorBlockMode,
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
      ...existingThreads.map((t) => t.symbol).where((s) => s.isNotEmpty),
      ...state.pattern.compositeSymbols.values.where((s) => s.isNotEmpty),
    };
    if (thread.symbol.isEmpty || usedSymbols.contains(thread.symbol)) {
      return thread.copyWith(symbol: _nextSymbol(usedSymbols));
    }
    return thread;
  }

  @override
  String _serializeClipboard(List<Thread> threads, List<Stitch> stitches) {
    return jsonEncode({
      'stitchx': {
        'version': 1,
        'threads': threads.map((t) => t.toYaml()).toList(),
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      }
    });
  }

  /// Ensures every thread has a symbol, assigning from [kPatternSymbols] for any missing.
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
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

// ─── computeCompositeThreads ──────────────────────────────────────────────────

/// Computes composite threads for each cell with stitches in multiple visible
/// layers. Single-layer cells use their source thread directly.
/// Returns a map from 'x,y' cell key to the composite [Thread].
Map<String, Thread> computeCompositeThreads(CrossStitchPattern pattern) {
  final cellLayers = <String, List<({Layer layer, FullStitch stitch})>>{};
  for (final layer in pattern.layers) {
    if (!layer.visible) continue;
    for (final stitch in layer.stitches) {
      if (stitch is! FullStitch) continue;
      final key = '${stitch.x},${stitch.y}';
      (cellLayers[key] ??= []).add((layer: layer, stitch: stitch));
    }
  }

  final threadMap = <String, Thread>{
    for (final t in pattern.threads) t.dmcCode: t,
  };

  final result = <String, Thread>{};

  for (final entry in cellLayers.entries) {
    final hits = entry.value;
    if (hits.isEmpty) continue;

    if (hits.length == 1) {
      final t = threadMap[hits.first.stitch.threadId];
      if (t != null) result[entry.key] = t;
      continue;
    }

    var blended = threadMap[hits.first.stitch.threadId]?.color;
    if (blended == null) continue;

    for (int i = 1; i < hits.length; i++) {
      final hit = hits[i];
      final layerColor = threadMap[hit.stitch.threadId]?.color;
      if (layerColor == null) continue;
      blended = hit.layer.blendMode.apply(blended!, layerColor, hit.layer.opacity);
    }

    if (blended == null) continue;
    final r = (blended.r * 255).round();
    final g = (blended.g * 255).round();
    final b = (blended.b * 255).round();
    final dmc = SpriteImporter.matchPixel(r, g, b, 255);
    if (dmc != null) {
      result[entry.key] = Thread(
        dmcCode: dmc.code,
        color: dmc.color,
        name: dmc.name,
      );
    }
  }

  return result;
}
