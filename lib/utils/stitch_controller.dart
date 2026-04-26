import 'package:flutter/services.dart' hide UndoManager;
import '../providers/editor/editor_provider.dart';
import 'shortcut_router.dart';
import 'undo_manager.dart';

/// Keyboard handler for stitch mode.
///
/// Handles progress undo/redo, mode-switch keys (S, Space), page navigation
/// arrow keys, and Escape.  Does NOT handle Copy, Paste, Delete, or tool
/// selection — those are edit-mode-only intents owned by [EditController].
///
/// Only fires when [EditorState.stitchMode] is true.
///
/// Implements [ShortcutHandler] to integrate with [ShortcutRouter]:
/// push in the owning widget's `initState`, pop in `dispose`.
///
/// Owns an [UndoManager] scoped to progress marks only, separate from the
/// pattern-edit undo stack in [EditController].
class StitchController implements ShortcutHandler {
  StitchController({
    required EditorNotifier notifier,
    required EditorState Function() getState,
    this.onSave,
  })  : _notifier = notifier,
        _getState = getState;

  final EditorNotifier _notifier;
  final EditorState Function() _getState;

  /// Called for Cmd/Ctrl+S in stitch mode.
  final VoidCallback? onSave;

  /// Undo stack scoped to progress marks only.
  final UndoManager undoManager = UndoManager();

  @override
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final state = _getState();
    if (!state.stitchMode) return false;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final key = event.logicalKey;

    if (meta || ctrl) {
      if (onSave != null && key == LogicalKeyboardKey.keyS) {
        onSave!();
        return true;
      }
      if (key == LogicalKeyboardKey.keyZ && !shift) {
        _notifier.undoProgress();
        return true;
      }
      if (key == LogicalKeyboardKey.keyZ && shift) {
        _notifier.redoProgress();
        return true;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _notifier.redoProgress();
        return true;
      }
      return false;
    }

    // ── Single-key shortcuts ──────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.keyS) {
      _notifier.setDrawingMode(DrawingMode.select);
      return true;
    }
    if (key == LogicalKeyboardKey.space) {
      _notifier.setDrawingMode(DrawingMode.pan);
      return true;
    }

    // Page-mode arrow navigation.
    if (state.pattern.pageConfig.enabled && state.pageLayout != null) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _notifier.navigatePageRight();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _notifier.navigatePageLeft();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _notifier.navigatePageDown();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _notifier.navigatePageUp();
        return true;
      }
    }

    if (key == LogicalKeyboardKey.escape) {
      if (state.selectionRect != null) {
        _notifier.cancelSelection();
      } else {
        _notifier.toggleStitchMode();
      }
      return true;
    }

    return false;
  }
}
