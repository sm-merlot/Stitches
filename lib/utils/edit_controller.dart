import 'package:flutter/services.dart' hide UndoManager;
import '../providers/editor/editor_provider.dart';
import 'shortcut_router.dart';
import 'undo_manager.dart';

/// Keyboard handler for edit mode.
///
/// Handles all pattern-editing shortcuts: draw/erase/tool selection,
/// undo/redo, copy/paste, selection transforms, save, and shortcuts dialog.
///
/// Only fires when [EditorState.stitchMode] is false — [StitchController]
/// handles the stitch-mode key set, enforcing mode isolation structurally.
///
/// Implements [ShortcutHandler] to integrate with [ShortcutRouter]:
/// push in the owning widget's `initState`, pop in `dispose`.
///
/// Owns an [UndoManager] ready for command-based undo (currently delegates
/// to [EditorNotifier.undo]; full command wiring comes in a later PR).
class EditController implements ShortcutHandler {
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

  /// Per-context undo stack.  Populated by commands once fully wired in PR8.
  final UndoManager undoManager = UndoManager();

  @override
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final state = _getState();
    // Edit shortcuts only fire in edit (or view) mode — stitch mode is owned
    // by StitchController.
    if (state.stitchMode) return false;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final key = event.logicalKey;

    // ── PDF zoom ──────────────────────────────────────────────────────────────
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

    // ── Modifier shortcuts ────────────────────────────────────────────────────
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
        // Three CW rotations = one CCW rotation.
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

    // ── Single-key shortcuts ──────────────────────────────────────────────────
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
