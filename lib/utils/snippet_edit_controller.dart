import 'package:flutter/gestures.dart' show PointerDeviceKind, kMiddleMouseButton;
import 'package:flutter/services.dart' hide UndoManager;
import '../models/stitch.dart';
import '../models/stitch_geometry.dart';
import '../providers/editor/editor_provider.dart';
import '../widgets/canvas_viewport.dart';
import '../widgets/draw_handler.dart';
import '../widgets/hover_handler.dart';
import '../widgets/paste_handler.dart';
import '../widgets/select_handler.dart';
import 'canvas_callbacks.dart';
import 'canvas_edit_controller.dart';
import 'command.dart';
import 'shortcut_router.dart';
import 'undo_manager.dart';

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

  // ── Cell-hit helpers ───────────────────────────────────────────────────────

  static bool _hitCell(Stitch s, int x, int y) {
    final coords = s.cellCoords;
    if (coords != null) return coords.$1 == x && coords.$2 == y;
    if (s is BackStitch) {
      bool inside(double gx, double gy) =>
          gx >= x && gx <= x + 1 && gy >= y && gy <= y + 1;
      return inside(s.x1, s.y1) || inside(s.x2, s.y2);
    }
    return false;
  }

  static bool _hitBox(Stitch s, int cx, int cy, int size) {
    final half = (size - 1) ~/ 2;
    final x0 = cx - half;
    final x1 = cx + (size - 1 - half);
    final y0 = cy - half;
    final y1 = cy + (size - 1 - half);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        if (_hitCell(s, x, y)) return true;
      }
    }
    return false;
  }

  // ── Delegate sync ──────────────────────────────────────────────────────────

  void _syncUndoState() => _notifier.updateControllerUndoState();

  @override
  void attachCanvas(CanvasCallbacks cb) {
    final n = _notifier;
    _hover = HoverHandler(scheduleRebuild: cb.scheduleRebuild);
    _paste = PasteHandler(
      onCommitPaste: n.commitPaste,
      onCancelSelection: n.cancelSelection,
      scheduleRebuild: cb.scheduleRebuild,
    );
    _draw = DrawHandler(
      onAddStitch: (stitch) {
        final state = _getState();
        final overwritten =
            state.activeLayer.stitches.where((s) => s == stitch).toList();
        undoManager.execute(
            AddStitchCommand(notifier: n, stitch: stitch, overwritten: overwritten));
        _syncUndoState();
      },
      onRemoveAt: (x, y) {
        final state = _getState();
        final removed = state.activeLayer.stitches
            .where((s) => _hitCell(s, x, y))
            .toList();
        if (removed.isEmpty) return;
        undoManager.execute(
            RemoveStitchesAtCommand(notifier: n, x: x, y: y, removed: removed));
        _syncUndoState();
      },
      onRemoveBox: (cx, cy, size) {
        final state = _getState();
        final removed = state.activeLayer.stitches
            .where((s) => _hitBox(s, cx, cy, size))
            .toList();
        if (removed.isEmpty) return;
        undoManager.execute(RemoveStitchesInBoxCommand(
            notifier: n, cx: cx, cy: cy, size: size, removed: removed));
        _syncUndoState();
      },
      onFloodFill: n.floodFill,
      onPickColor: n.pickColorAtCell,
      onSetBackstitchStart: n.setBackstitchStart,
      onLayerWarning: cb.onWarning,
      getCtrlHeld: () => _paste!.ctrlHeld,
    );
    _select = SelectHandler(
      onSetSelectionRect: n.setSelectionRect,
      onMoveSelection: n.moveSelection,
      onWarning: cb.onWarning,
      scheduleRebuild: cb.scheduleRebuild,
    );
    // Register as undo delegate so notifier.undo() routes here first.
    n.registerUndoDelegate(
      canUndo: () => undoManager.canUndo,
      canRedo: () => undoManager.canRedo,
      undo: undoManager.undo,
      redo: undoManager.redo,
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
  }

  // ── Pointer event dispatch ─────────────────────────────────────────────────

  @override
  void updateModifiers({required bool ctrl, required bool shift}) {
    _paste?.updateModifiers(ctrl: ctrl, shift: shift);
  }

  @override
  void onPencilDoubleTap(EditorState state) {
    if (state.drawingMode == DrawingMode.paste) {
      _paste?.commit(state.pattern, state.clipboard);
    } else {
      _notifier.toggleDrawingMode();
    }
  }

  @override
  void onPointerDown(
    Offset localPos,
    PointerDeviceKind kind,
    int buttons,
    CanvasViewport vp,
    EditorState state, {
    required bool isOnCanvas,
    required bool pencilPasteConfirm,
  }) {
    if (_draw == null) return;

    final isStylusMouse = kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse;
    final mode = state.drawingMode;
    final p = state.pattern;

    if (isStylusMouse) {
      if (buttons == kMiddleMouseButton) return;
      if (mode == DrawingMode.pan) return;

      if (mode == DrawingMode.select) {
        _select!.onPointerDown(
          localPos, vp, p.width, p.height,
          currentSelectionRect: state.selectionRect,
          hasSelectedStitches: state.selectedStitches.isNotEmpty,
          canvasSelectionMode: state.canvasSelectionMode,
          isOnCanvas: isOnCanvas,
        );
        return;
      }

      if (mode == DrawingMode.paste) {
        if (pencilPasteConfirm) {
          _paste!.setOrigin(localPos, vp);
        } else {
          _paste!.commit(state.pattern, state.clipboard);
        }
        return;
      }

      _draw!.handleDrawAt(localPos, state, vp);
      return;
    }

    // ── Touch ──────────────────────────────────────────────────────────────
    if (mode == DrawingMode.select) {
      _select!.onPointerDown(
        localPos, vp, p.width, p.height,
        currentSelectionRect: state.selectionRect,
        hasSelectedStitches: state.selectedStitches.isNotEmpty,
        canvasSelectionMode: state.canvasSelectionMode,
        isOnCanvas: isOnCanvas,
      );
      return;
    }

    if (mode == DrawingMode.paste) {
      if (pencilPasteConfirm) {
        _paste!.commit(state.pattern, state.clipboard);
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
    int buttons,
    CanvasViewport vp,
    EditorState state,
  ) {
    if (_draw == null) return;

    final isStylusMouse = kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse;
    final mode = state.drawingMode;
    final p = state.pattern;

    if (isStylusMouse) {
      _hover!.onPointerMove(localPos, vp, p.width, p.height);
      if (mode == DrawingMode.pan || buttons == kMiddleMouseButton) return;

      if (mode == DrawingMode.select) {
        _select!.onPointerMove(localPos, vp, p.width, p.height);
        return;
      }
      if (mode == DrawingMode.paste) {
        _paste!.updateOrigin(localPos, vp);
        return;
      }
      if (mode == DrawingMode.colorPicker) return;

      if (state.currentTool == DrawingTool.backstitch) {
        if (state.backstitchStartPoint != null) {
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
    } else if (state.currentTool != DrawingTool.backstitch) {
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

    // Touch paste — commit at current origin.
    if (kind == PointerDeviceKind.touch &&
        state.drawingMode == DrawingMode.paste &&
        _paste!.pasteOrigin != null) {
      _paste!.commit(state.pattern, state.clipboard);
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

    if (state.drawingMode == DrawingMode.paste) {
      _paste!.updateOrigin(localPos, vp);
      return;
    }

    if (state.currentTool == DrawingTool.backstitch &&
        state.backstitchStartPoint != null) {
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
        if (state.drawingMode == DrawingMode.select &&
            state.selectionRect != null) {
          _notifier.flipSelectionH();
        } else if (state.drawingMode == DrawingMode.paste) {
          _notifier.flipClipboardH();
        } else {
          onFlipCanvasH?.call();
        }
        return true;
      }
      if (shift && key == LogicalKeyboardKey.keyV) {
        if (state.drawingMode == DrawingMode.select &&
            state.selectionRect != null) {
          _notifier.flipSelectionV();
        } else if (state.drawingMode == DrawingMode.paste) {
          _notifier.flipClipboardV();
        } else {
          onFlipCanvasV?.call();
        }
        return true;
      }
      if (shift && key == LogicalKeyboardKey.bracketRight) {
        if (state.drawingMode == DrawingMode.select &&
            state.selectionRect != null) {
          _notifier.rotateSelectionCW();
        } else if (state.drawingMode == DrawingMode.paste) {
          _notifier.rotateClipboardCW();
        } else {
          onRotateCanvasCW?.call();
        }
        return true;
      }
      if (shift && key == LogicalKeyboardKey.bracketLeft) {
        if (state.drawingMode == DrawingMode.select &&
            state.selectionRect != null) {
          _notifier.rotateSelectionCW();
          _notifier.rotateSelectionCW();
          _notifier.rotateSelectionCW();
        } else if (state.drawingMode == DrawingMode.paste) {
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
        _notifier.setTool(DrawingTool.halfForward);
      case LogicalKeyboardKey.digit3:
        _notifier.setTool(DrawingTool.halfBackward);
      case LogicalKeyboardKey.digit4:
        _notifier.setTool(DrawingTool.halfCross);
      case LogicalKeyboardKey.digit5:
        _notifier.setTool(DrawingTool.quarterDiag);
      case LogicalKeyboardKey.digit6:
        _notifier.setTool(DrawingTool.quarterCross);
      case LogicalKeyboardKey.digit7:
        _notifier.setTool(DrawingTool.backstitch);
      case LogicalKeyboardKey.digit8:
        _notifier.setTool(DrawingTool.fill);
      case LogicalKeyboardKey.digit9:
        _notifier.setDrawingMode(DrawingMode.erase);
        if (!state.fillEraseActive) _notifier.toggleFillErase();
      case LogicalKeyboardKey.keyC:
        _notifier.setDrawingMode(DrawingMode.colorPicker);
      case LogicalKeyboardKey.keyS:
        _notifier.setDrawingMode(DrawingMode.select);
      case LogicalKeyboardKey.escape:
        _notifier.cancelSelection();
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _notifier.deleteSelection();
      default:
        return false;
    }
    return true;
  }
}
