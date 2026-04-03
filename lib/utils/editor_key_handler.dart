import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/editor/editor_provider.dart';

/// Handles keyboard shortcuts common to both EditorScreen and WorkspaceScreen.
///
/// Call this from each screen's `onKeyEvent` closure. Returns
/// [KeyEventResult.handled] if the key was consumed, [KeyEventResult.ignored]
/// otherwise — allowing the caller to add screen-specific handling.
///
/// [onSave] — called for Cmd/Ctrl+S. Omit in screens that use auto-save.
/// [onShowShortcuts] — called for Shift+? to display the shortcuts dialog.
/// [onPdfZoomIn] / [onPdfZoomOut] — called for Cmd/Ctrl+= / Cmd/Ctrl+-.
KeyEventResult handleEditorKeys(
  KeyEvent event,
  EditorState state,
  EditorNotifier notifier, {
  VoidCallback? onSave,
  VoidCallback? onShowShortcuts,
  VoidCallback? onPdfZoomIn,
  VoidCallback? onPdfZoomOut,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }

  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight);
  final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
  final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
  final key = event.logicalKey;

  // ── Stitch mode ──────────────────────────────────────────────────────────
  if (state.stitchMode) {
    if (onSave != null && (meta || ctrl) && key == LogicalKeyboardKey.keyS) {
      onSave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      notifier.setDrawingMode(DrawingMode.select);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      notifier.setDrawingMode(DrawingMode.pan);
      return KeyEventResult.handled;
    }
    // Page mode navigation with arrow keys.
    if (state.pattern.pageConfig.enabled && state.pageLayout != null) {
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
        notifier.navigateNextPage();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
        notifier.navigatePreviousPage();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      if (state.selectionRect != null) {
        notifier.cancelSelection();
      } else {
        notifier.toggleStitchMode();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── PDF zoom shortcuts ────────────────────────────────────────────────────
  if ((meta || ctrl) && onPdfZoomIn != null) {
    if (key == LogicalKeyboardKey.equal) {
      onPdfZoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus && onPdfZoomOut != null) {
      onPdfZoomOut();
      return KeyEventResult.handled;
    }
  }

  // ── Modifier shortcuts ────────────────────────────────────────────────────
  if (meta || ctrl) {
    if (key == LogicalKeyboardKey.keyZ && !shift) {
      notifier.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ && shift) {
      notifier.redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      notifier.redo();
      return KeyEventResult.handled;
    }
    if (onSave != null && key == LogicalKeyboardKey.keyS) {
      onSave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      notifier.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      notifier.copySelection();
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyV) {
      notifier.enterPasteMode();
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.keyH) {
      if (state.drawingMode == DrawingMode.select &&
          state.selectionRect != null) {
        notifier.flipSelectionH();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.flipClipboardH();
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.keyV) {
      if (state.drawingMode == DrawingMode.select &&
          state.selectionRect != null) {
        notifier.flipSelectionV();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.flipClipboardV();
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.bracketRight) {
      if (state.drawingMode == DrawingMode.select &&
          state.selectionRect != null) {
        notifier.rotateSelectionCW();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.rotateClipboardCW();
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.bracketLeft) {
      // Three CW rotations = one CCW rotation.
      if (state.drawingMode == DrawingMode.select &&
          state.selectionRect != null) {
        notifier.rotateSelectionCW();
        notifier.rotateSelectionCW();
        notifier.rotateSelectionCW();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.rotateClipboardCW();
        notifier.rotateClipboardCW();
        notifier.rotateClipboardCW();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Single-key shortcuts ──────────────────────────────────────────────────
  switch (key) {
    case LogicalKeyboardKey.keyD:
      notifier.setDrawingMode(DrawingMode.draw);
    case LogicalKeyboardKey.keyE:
      notifier.setDrawingMode(DrawingMode.erase);
    case LogicalKeyboardKey.space:
      notifier.setDrawingMode(DrawingMode.pan);
    case LogicalKeyboardKey.digit1:
      notifier.setTool(DrawingTool.fullStitch);
    case LogicalKeyboardKey.digit2:
      notifier.setTool(DrawingTool.halfForward);
    case LogicalKeyboardKey.digit3:
      notifier.setTool(DrawingTool.halfBackward);
    case LogicalKeyboardKey.digit4:
      notifier.setTool(DrawingTool.halfCross);
    case LogicalKeyboardKey.digit5:
      notifier.setTool(DrawingTool.quarterDiag);
    case LogicalKeyboardKey.digit6:
      notifier.setTool(DrawingTool.quarterCross);
    case LogicalKeyboardKey.digit7:
      notifier.setTool(DrawingTool.backstitch);
    case LogicalKeyboardKey.digit8:
      notifier.setTool(DrawingTool.fill);
    case LogicalKeyboardKey.digit9:
      notifier.setDrawingMode(DrawingMode.erase);
      if (!state.fillEraseActive) notifier.toggleFillErase();
    case LogicalKeyboardKey.keyC:
      notifier.setDrawingMode(DrawingMode.colorPicker);
    case LogicalKeyboardKey.keyS:
      notifier.setDrawingMode(DrawingMode.select);
    case LogicalKeyboardKey.escape:
      notifier.cancelSelection();
    case LogicalKeyboardKey.delete:
    case LogicalKeyboardKey.backspace:
      notifier.deleteSelection();
    case LogicalKeyboardKey.slash:
      if (shift && onShowShortcuts != null) {
        onShowShortcuts();
      } else {
        return KeyEventResult.ignored;
      }
    default:
      return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}
