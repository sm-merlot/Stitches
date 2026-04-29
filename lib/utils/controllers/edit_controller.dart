import 'package:flutter/gestures.dart' show PointerDeviceKind, kMiddleMouseButton;
import 'package:flutter/services.dart' hide UndoManager;
import '../../models/cell.dart';
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

/// Controller for edit (and view) mode.
///
/// Owns the keyboard shortcut handler (via [ShortcutHandler]) and the
/// canvas pointer-event handlers ([DrawHandler], [SelectHandler],
/// [PasteHandler], [HoverHandler]).
///
/// **Lifecycle:**
/// - Push to [ShortcutRouter] in the owning screen's `initState`.
/// - Call [attachCanvas] when [AidaWidget] mounts so pointer handlers
///   receive the view-level callbacks they need.
/// - Call [detachCanvas] in [AidaWidget.dispose].
/// - Pop from [ShortcutRouter] in the owning screen's `dispose`.
///
/// Only fires keyboard shortcuts when [EditorState.stitchMode] is false.
class EditController implements CanvasEditController, ShortcutHandler {
  EditController({
    required EditorNotifier notifier,
    required EditorState Function() getState,
    this.onSave,
    this.onShowShortcuts,
    this.onPdfZoomIn,
    this.onPdfZoomOut,
    this.onFlipCanvasH,
    this.onFlipCanvasV,
    this.onRotateCanvasCW,
  })  : _notifier = notifier,
        _getState = getState;

  final EditorNotifier _notifier;
  final EditorState Function() _getState;

  /// Called for Cmd/Ctrl+S.  Omit in screens that use auto-save.
  final VoidCallback? onSave;

  /// Called for Shift+? to show the shortcuts reference dialog.
  final VoidCallback? onShowShortcuts;

  /// PDF panel zoom-in (Cmd/Ctrl+=).  Null if no PDF panel is active.
  final VoidCallback? onPdfZoomIn;

  /// PDF panel zoom-out (Cmd/Ctrl+-).  Null if no PDF panel is active.
  final VoidCallback? onPdfZoomOut;

  /// Canvas-level horizontal flip (Ctrl+Shift+H with no selection/paste).
  /// Provided by the snippet editor; null in the main editor.
  final VoidCallback? onFlipCanvasH;

  /// Canvas-level vertical flip.
  final VoidCallback? onFlipCanvasV;

  /// Canvas-level 90° clockwise rotation.
  final VoidCallback? onRotateCanvasCW;

  /// Per-context undo stack.
  final UndoManager undoManager = UndoManager();

  // ── Canvas pointer handlers ────────────────────────────────────────────────
  // Null until [attachCanvas] is called.

  HoverHandler? _hover;
  DrawHandler? _draw;
  SelectHandler? _select;
  PasteHandler? _paste;

  /// Read by [AidaWidget] overlay painter.
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

  /// Wire up pointer handlers with view-level callbacks.
  /// Called by [AidaWidget.initState] after the widget is mounted.
  @override
  void attachCanvas(CanvasCallbacks cb) {
    final n = _notifier;
    // Sync toolbar can-undo/can-redo after every undo-manager state change.
    undoManager.onChange = n.updateControllerUndoState;
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
      },
      onRemoveAt: (x, y) {
        final state = _getState();
        final removed = state.activeLayer.stitches
            .where((s) => Cell.hitStitch(s, x, y))
            .toList();
        if (removed.isEmpty) return;
        undoManager.execute(
            RemoveStitchesAtCommand(notifier: n, x: x, y: y, removed: removed));
      },
      onRemoveBox: (cx, cy, size) {
        final state = _getState();
        final removed = state.activeLayer.stitches
            .where((s) => Cell.hitBox(s, cx, cy, size))
            .toList();
        if (removed.isEmpty) return;
        undoManager.execute(RemoveStitchesInBoxCommand(
            notifier: n, cx: cx, cy: cy, size: size, removed: removed));
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

  /// Release pointer handlers. Called by [AidaWidget.dispose].
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

  /// Update paste/modifier state. Called unconditionally on each key event
  /// from [AidaWidget]'s [ShortcutHandler.handle] (returns false — modifier
  /// tracking only, not a consumed shortcut).
  @override
  void updateModifiers({required bool ctrl, required bool shift}) {
    _paste?.updateModifiers(ctrl: ctrl, shift: shift);
  }

  /// Apple Pencil secondary-button (double-tap) in edit/paste mode.
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

    // Double-tap (touch, edit mode only) → undo.
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

  /// Cancel any active select/paste gestures (e.g. when multi-touch starts).
  @override
  void cancelActiveGestures() {
    _select?.cancel();
  }

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────

  @override
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final state = _getState();
    if (state.stitchMode) return false;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final key = event.logicalKey;

    // Update paste modifier state on every key event.
    updateModifiers(ctrl: ctrl || meta, shift: shift);

    // ── PDF zoom ────────────────────────────────────────────────────────────
    if ((meta || ctrl) && onPdfZoomIn != null) {
      if (key == LogicalKeyboardKey.equal) {
        onPdfZoomIn!();
        return true;
      }
      if (key == LogicalKeyboardKey.minus && onPdfZoomOut != null) {
        onPdfZoomOut!();
        return true;
      }
    }

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
      if (onSave != null && key == LogicalKeyboardKey.keyS) {
        onSave!();
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
      case LogicalKeyboardKey.slash:
        if (shift && onShowShortcuts != null) {
          onShowShortcuts!();
        } else {
          return false;
        }
      default:
        return false;
    }
    return true;
  }
}
