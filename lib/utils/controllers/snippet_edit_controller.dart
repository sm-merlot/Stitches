import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' hide UndoManager;
import '../../models/cell.dart';
import '../../models/stitch/stitch.dart';
import '../../models/stitch/stitch_geometry.dart';
import '../../providers/editor/editor_provider.dart';
import '../../widgets/canvas/canvas_viewport.dart';
import '../../widgets/handlers/draw_handler.dart';
import '../../widgets/handlers/hover_handler.dart';
import '../../widgets/handlers/paste_handler.dart';
import '../../widgets/handlers/select_handler.dart';
import 'canvas_callbacks.dart';
import 'canvas_edit_controller.dart';
import '../commands/command.dart';
import '../commands/shortcut_router.dart';
import '../commands/undo_manager.dart';

/// Controller for snippet editing.
///
/// Structurally identical to [EditController] but scoped to a snippet canvas:
/// - No save, PDF zoom, or shortcuts-dialog callbacks (not applicable in snippet editor).
/// - Canvas-transform callbacks (flip/rotate) are snippet-specific.
/// - Stitch mode is unavailable; [handle] always processes shortcuts.
///
/// **Lifecycle:**
/// - Push to [ShortcutRouter] in [SnippetEditView.initState].
/// - Call [attachCanvas] when [AidaWidget] mounts.
/// - Call [detachCanvas] in [AidaWidget.dispose].
/// - Pop from [ShortcutRouter] in [SnippetEditView.dispose].
class SnippetEditController implements CanvasEditController, ShortcutHandler {
  SnippetEditController({
    required EditorNotifier notifier,
    required EditorState Function() getState,
    this.onFlipCanvasH,
    this.onFlipCanvasV,
    this.onRotateCanvasCW,
  })  : _notifier = notifier,
        _getState = getState;

  final EditorNotifier _notifier;
  final EditorState Function() _getState;

  /// Canvas-level horizontal flip (Ctrl+Shift+H with no selection/paste).
  final VoidCallback? onFlipCanvasH;

  /// Canvas-level vertical flip.
  final VoidCallback? onFlipCanvasV;

  /// Canvas-level 90° clockwise rotation.
  final VoidCallback? onRotateCanvasCW;

  /// Per-snippet undo stack (isolated from parent pattern undo stack).
  final UndoManager undoManager = UndoManager();

  // ── Canvas pointer handlers ────────────────────────────────────────────────

  HoverHandler? _hover;
  DrawHandler? _draw;
  SelectHandler? _select;
  PasteHandler? _paste;

  @override
  HoverHandler? get hover => _hover;
  @override
  DrawHandler? get draw => _draw;
  @override
  SelectHandler? get select => _select;
  @override
  PasteHandler? get paste => _paste;

  // ── Touch double-tap undo tracking ─────────────────────────────────────────
  DateTime? _lastTouchUpTime;
  Offset? _lastTouchUpPos;

  // ── Drag-to-paste tracking ─────────────────────────────────────────────────
  bool _dragToPasteActive = false;
  Rect? _dragMoveSourceRect;

  // ── Snapshot helper ────────────────────────────────────────────────────────

  /// Calls [action], then pushes a [PatternSnapshotCommand] if the pattern changed.
  void _withSnapshot(void Function() action) {
    final before = (_getState().pattern, _getState().snippetEditorState.palettes);
    action();
    final after = (_getState().pattern, _getState().snippetEditorState.palettes);
    if (before.$1 != after.$1 || before.$2 != after.$2) {
      undoManager.push(PatternSnapshotCommand(
          notifier: _notifier, before: before, after: after));
    }
  }

  @override
  void attachCanvas(CanvasCallbacks cb) {
    final n = _notifier;
    // Sync toolbar can-undo/can-redo after every undo-manager state change.
    undoManager.onChange = n.updateControllerUndoState;
    _hover = HoverHandler(scheduleRebuild: cb.scheduleRebuild);
    _paste = PasteHandler(
      onCommitPaste: (dx, dy) {
        final before = (_getState().pattern, _getState().snippetEditorState.palettes);
        n.commitPaste(dx, dy);
        final after = (_getState().pattern, _getState().snippetEditorState.palettes);
        if (before.$1 != after.$1) {
          undoManager.push(PatternSnapshotCommand(
              notifier: n, before: before, after: after));
        }
      },
      onCancelSelection: n.cancelSelection,
      scheduleRebuild: cb.scheduleRebuild,
    );
    _draw = DrawHandler(
      onAddStitch: (stitch) {
        final state = _getState();
        final coords = stitch.cellCoords;
        final overwritten = coords != null
            ? state.activeLayer
                .stitchesAt(coords.x, coords.y)
                .where((s) => s == stitch)
                .toList()
            : state.activeLayer.backstitches
                .where((s) => s == stitch)
                .toList();
        undoManager.execute(
            AddStitchCommand(notifier: n, stitch: stitch, overwritten: overwritten));
      },
      onRemoveAt: (x, y) {
        final state = _getState();
        final layer = state.activeLayer;
        final removed = <Stitch>[
          ...layer.stitchesAt(x, y),
          ...layer.backstitches.where((s) => Cell.hitStitch(s, x, y)),
        ];
        if (removed.isEmpty) return;
        undoManager.execute(
            RemoveStitchesAtCommand(notifier: n, x: x, y: y, removed: removed));
      },
      onRemoveBox: (cx, cy, size) {
        final state = _getState();
        final layer = state.activeLayer;
        final half = (size - 1) ~/ 2;
        final x0 = cx - half;
        final x1 = cx + (size - 1 - half);
        final y0 = cy - half;
        final y1 = cy + (size - 1 - half);
        final removed = <Stitch>[
          for (var xx = x0; xx <= x1; xx++)
            for (var yy = y0; yy <= y1; yy++)
              ...layer.stitchesAt(xx, yy),
          ...layer.backstitches.where((s) => Cell.hitBox(s, cx, cy, size)),
        ];
        if (removed.isEmpty) return;
        undoManager.execute(RemoveStitchesInBoxCommand(
            notifier: n, cx: cx, cy: cy, size: size, removed: removed));
      },
      onFloodFill: (x, y, {required bool erase}) {
        final before = (_getState().pattern, _getState().snippetEditorState.palettes);
        n.floodFill(x, y, erase: erase);
        final after = (_getState().pattern, _getState().snippetEditorState.palettes);
        if (before.$1 != after.$1) {
          undoManager.push(PatternSnapshotCommand(
              notifier: n, before: before, after: after));
        }
      },
      onPickColor: n.pickColorAtCell,
      onSetBackstitchStart: n.setBackstitchStart,
      onLayerWarning: cb.onWarning,
      getCtrlHeld: () => _paste!.ctrlHeld,
    );
    _select = SelectHandler(
      onSetSelectionRect: n.setSelectionRect,
      scheduleRebuild: cb.scheduleRebuild,
    );
    // Register as undo delegate so notifier.undo() routes here first.
    n.registerUndoDelegate(
      canUndo: () => undoManager.canUndo,
      canRedo: () => undoManager.canRedo,
      undo: undoManager.undo,
      redo: undoManager.redo,
      clear: undoManager.clear,
      pushProgressSnapshot: (before, after) {}, // no progress ops in snippet editor
    );
  }

  @override
  void detachCanvas() {
    _notifier.unregisterUndoDelegate();
    _hover = null;
    _draw = null;
    _select = null;
    _paste = null;
    _lastTouchUpTime = null;
    _lastTouchUpPos = null;
    _dragToPasteActive = false;
  }

  // ── Pointer event dispatch ─────────────────────────────────────────────────

  @override
  void updateModifiers({required bool ctrl, required bool shift}) {
    _paste?.updateModifiers(ctrl: ctrl, shift: shift);
  }

  @override
  void onPencilDoubleTap(EditorState state) {
    if (state.editSession.drawingMode == DrawingMode.paste) {
      _paste?.commit(state.pattern, state.editSession.clipboard);
    } else {
      _notifier.toggleDrawingMode();
    }
  }

  @override
  void onPointerDown(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state, {
    required bool isOnCanvas,
    required bool pencilPasteConfirm,
  }) {
    if (_draw == null) return;

    final isStylusMouse = kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse;
    final mode = state.editSession.drawingMode;
    final p = state.pattern;

    if (isStylusMouse) {
      if (mode == DrawingMode.pan) return;

      if (mode == DrawingMode.select) {
        if (_tryStartDragToPaste(localPos, vp, p.width, p.height, isOnCanvas)) return;
        _select!.onPointerDown(
          localPos, vp, p.width, p.height,
          isOnCanvas: isOnCanvas,
        );
        return;
      }

      if (mode == DrawingMode.paste) {
        if (pencilPasteConfirm) {
          _paste!.setOrigin(localPos, vp);
        } else {
          _paste!.commit(state.pattern, state.editSession.clipboard);
        }
        return;
      }

      _draw!.handleDrawAt(localPos, state, vp);
      return;
    }

    // ── Touch ──────────────────────────────────────────────────────────────
    if (mode == DrawingMode.select) {
      if (_tryStartDragToPaste(localPos, vp, p.width, p.height, isOnCanvas)) return;
      _select!.onPointerDown(
        localPos, vp, p.width, p.height,
        isOnCanvas: isOnCanvas,
      );
      return;
    }

    if (mode == DrawingMode.paste) {
      if (pencilPasteConfirm) {
        _paste!.commit(state.pattern, state.editSession.clipboard);
      } else {
        _paste!.setOrigin(localPos, vp);
      }
      return;
    }
  }

  @override
  void onPointerMove(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state,
  ) {
    if (_draw == null) return;

    final isStylusMouse = kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse;
    final mode = state.editSession.drawingMode;
    final p = state.pattern;

    if (isStylusMouse) {
      _hover!.onPointerMove(localPos, vp, p.width, p.height);
      if (mode == DrawingMode.pan) return;

      if (mode == DrawingMode.select) {
        _select!.onPointerMove(localPos, vp, p.width, p.height);
        return;
      }
      if (mode == DrawingMode.paste) {
        _paste!.updateOrigin(localPos, vp);
        return;
      }
      if (mode == DrawingMode.colorPicker) return;

      if (state.editSession.currentTool == DrawingTool.backstitch) {
        if (state.editSession.backstitchStartPoint != null) {
          _draw!.updateBackstitchHover(localPos, vp);
        }
      } else {
        _draw!.handleDrawAt(localPos, state, vp);
      }
      return;
    }

    // ── Touch ──────────────────────────────────────────────────────────────
    if (mode == DrawingMode.select) {
      _select!.onPointerMove(localPos, vp, p.width, p.height);
    } else if (mode == DrawingMode.paste) {
      _paste!.updateOrigin(localPos, vp);
    } else if (mode == DrawingMode.pan) {
      // pan handled by ZoomPanHandler in [AidaWidget]
    } else if (state.editSession.currentTool != DrawingTool.backstitch) {
      _draw!.handleDrawAt(localPos, state, vp);
    }
  }

  @override
  void onPointerUp(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state, {
    required bool wasSinglePointer,
    required bool hadMultiTouch,
    required bool isPanMode,
  }) {
    if (_draw == null) return;

    _draw!.onPointerUp();

    // Drag-to-move: commit paste and erase source region as one undo step.
    if (_dragToPasteActive) {
      _dragToPasteActive = false;
      final sourceRect = _dragMoveSourceRect;
      _dragMoveSourceRect = null;
      if (state.editSession.drawingMode == DrawingMode.paste) {
        final origin = _paste!.pasteOrigin;
        final clipboard = state.editSession.clipboard;
        if (origin != null && clipboard != null) {
          final (dx, dy) = _paste!.effectiveOffset(origin, clipboard, state.pattern);
          _withSnapshot(() {
            if (sourceRect != null) _notifier.deleteStitchesInRect(sourceRect);
            _notifier.commitPaste(dx, dy);
          });
          _paste!.clearOrigin();
          if (!_paste!.ctrlHeld) _notifier.cancelSelection();
        }
      }
      return;
    }

    // Touch paste — commit at current origin.
    if (kind == PointerDeviceKind.touch &&
        state.editSession.drawingMode == DrawingMode.paste &&
        _paste!.pasteOrigin != null) {
      _paste!.commit(state.pattern, state.editSession.clipboard);
      _paste!.clearOrigin();
      return;
    }

    // Commit selection move or finalise rubber-band.
    if (_select!.isActive) {
      _select!.onPointerUp(localPos, vp, state.pattern.width, state.pattern.height);
      return;
    }

    // Double-tap (touch) → undo.
    if (kind == PointerDeviceKind.touch &&
        wasSinglePointer &&
        !hadMultiTouch) {
      final now = DateTime.now();
      final timeSinceLast = _lastTouchUpTime != null
          ? now.difference(_lastTouchUpTime!)
          : const Duration(seconds: 1);
      final nearLast = _lastTouchUpPos != null
          ? (localPos - _lastTouchUpPos!).distance < 60.0
          : false;

      if (timeSinceLast < const Duration(milliseconds: 350) && nearLast) {
        _notifier.undo();
        _lastTouchUpTime = null;
        _lastTouchUpPos = null;
        return;
      }

      _lastTouchUpTime = now;
      _lastTouchUpPos = localPos;

      if (!isPanMode) {
        _draw!.handleDrawAt(localPos, state, vp);
      }
    }
  }

  @override
  void onPointerHover(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state,
  ) {
    if (_hover == null) return;

    final p = state.pattern;
    _hover!.onPointerHover(localPos, kind, vp, p.width, p.height);

    if (state.editSession.drawingMode == DrawingMode.paste) {
      _paste!.updateOrigin(localPos, vp);
      return;
    }

    if (state.editSession.currentTool == DrawingTool.backstitch &&
        state.editSession.backstitchStartPoint != null) {
      _draw!.updateBackstitchHover(localPos, vp);
    }
  }

  @override
  void onStylusAdded(Offset localPos, CanvasViewport vp, int patW, int patH) {
    _hover?.onStylusAdded(localPos, vp, patW, patH);
  }

  @override
  void onStylusRemoved() => _hover?.onStylusRemoved();

  @override
  void onHoverExit() => _hover?.onExit();

  @override
  void cancelActiveGestures() {
    _select?.cancel();
    _dragToPasteActive = false;
    _dragMoveSourceRect = null;
  }

  bool _tryStartDragToPaste(
    Offset localPos, CanvasViewport vp, int patW, int patH, bool isOnCanvas,
  ) {
    if (!isOnCanvas) return false;
    final selRect = _getState().editSession.selectionRect;
    if (selRect == null) return false;
    final cell = SelectHandler.toSelCell(localPos, vp, patW, patH);
    if (!SelectHandler.cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), selRect)) return false;
    if (!_notifier.copySelectionForDrag()) return false;
    _dragMoveSourceRect = selRect;
    _paste!.setOrigin(localPos, vp);
    _dragToPasteActive = true;
    return true;
  }

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────

  @override
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final state = _getState();
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final key = event.logicalKey;

    updateModifiers(ctrl: ctrl || meta, shift: shift);

    // ── Modifier shortcuts ──────────────────────────────────────────────────
    if (meta || ctrl) {
      if (key == LogicalKeyboardKey.keyZ && !shift) {
        _notifier.undo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyZ && shift) {
        _notifier.redo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _notifier.redo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _notifier.selectAll();
        return true;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _notifier.copySelection();
        return true;
      }
      if (!shift && key == LogicalKeyboardKey.keyV) {
        _notifier.enterPasteMode();
        return true;
      }
      if (shift && key == LogicalKeyboardKey.keyH) {
        if (state.editSession.drawingMode == DrawingMode.select &&
            state.editSession.selectionRect != null) {
          _withSnapshot(_notifier.flipSelectionH);
        } else if (state.editSession.drawingMode == DrawingMode.paste) {
          _notifier.flipClipboardH();
        } else {
          onFlipCanvasH?.call();
        }
        return true;
      }
      if (shift && key == LogicalKeyboardKey.keyV) {
        if (state.editSession.drawingMode == DrawingMode.select &&
            state.editSession.selectionRect != null) {
          _withSnapshot(_notifier.flipSelectionV);
        } else if (state.editSession.drawingMode == DrawingMode.paste) {
          _notifier.flipClipboardV();
        } else {
          onFlipCanvasV?.call();
        }
        return true;
      }
      if (shift && key == LogicalKeyboardKey.bracketRight) {
        if (state.editSession.drawingMode == DrawingMode.select &&
            state.editSession.selectionRect != null) {
          _withSnapshot(_notifier.rotateSelectionCW);
        } else if (state.editSession.drawingMode == DrawingMode.paste) {
          _notifier.rotateClipboardCW();
        } else {
          onRotateCanvasCW?.call();
        }
        return true;
      }
      if (shift && key == LogicalKeyboardKey.bracketLeft) {
        if (state.editSession.drawingMode == DrawingMode.select &&
            state.editSession.selectionRect != null) {
          _withSnapshot(() {
            _notifier.rotateSelectionCW();
            _notifier.rotateSelectionCW();
            _notifier.rotateSelectionCW();
          });
        } else if (state.editSession.drawingMode == DrawingMode.paste) {
          _notifier.rotateClipboardCW();
          _notifier.rotateClipboardCW();
          _notifier.rotateClipboardCW();
        } else {
          onRotateCanvasCW?.call();
          onRotateCanvasCW?.call();
          onRotateCanvasCW?.call();
        }
        return true;
      }
      return false;
    }

    // ── Single-key shortcuts ────────────────────────────────────────────────
    switch (key) {
      case LogicalKeyboardKey.keyD:
        _notifier.setDrawingMode(DrawingMode.draw);
      case LogicalKeyboardKey.keyE:
        _notifier.setDrawingMode(DrawingMode.erase);
      case LogicalKeyboardKey.space:
        _notifier.setDrawingMode(DrawingMode.pan);
      case LogicalKeyboardKey.digit1:
        _notifier.setTool(DrawingTool.fullStitch);
      case LogicalKeyboardKey.digit2:
        _notifier.setPartialSubTool(PartialSubTool.diagonalForward);
      case LogicalKeyboardKey.digit3:
        _notifier.setPartialSubTool(PartialSubTool.diagonalBackward);
      case LogicalKeyboardKey.digit4:
        _notifier.setPartialSubTool(PartialSubTool.half);
      case LogicalKeyboardKey.digit5:
        _notifier.setPartialSubTool(PartialSubTool.threeQuarter);
      case LogicalKeyboardKey.digit6:
        _notifier.setPartialSubTool(PartialSubTool.quarter);
      case LogicalKeyboardKey.digit7:
        _notifier.setTool(DrawingTool.backstitch);
      case LogicalKeyboardKey.digit8:
        _notifier.setTool(DrawingTool.fill);
      case LogicalKeyboardKey.digit9:
        _notifier.setDrawingMode(DrawingMode.erase);
        if (!state.editSession.fillEraseActive) _notifier.toggleFillErase();
      case LogicalKeyboardKey.keyC:
        _notifier.setDrawingMode(DrawingMode.colorPicker);
      case LogicalKeyboardKey.keyS:
        _notifier.setDrawingMode(DrawingMode.select);
      case LogicalKeyboardKey.escape:
        _notifier.cancelSelection();
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _withSnapshot(_notifier.deleteSelection);
      default:
        return false;
    }
    return true;
  }
}
