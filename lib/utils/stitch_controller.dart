import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' hide UndoManager;
import '../providers/editor/editor_provider.dart';
import '../widgets/canvas_viewport.dart';
import '../widgets/hover_handler.dart';
import '../widgets/page_nav_handler.dart';
import '../widgets/progress_handler.dart';
import 'canvas_callbacks.dart';
import 'shortcut_router.dart';
import 'undo_manager.dart';

/// Controller for stitch mode.
///
/// Owns the keyboard shortcut handler (via [ShortcutHandler]) and the
/// canvas pointer-event handlers ([ProgressHandler], [PageNavHandler],
/// [HoverHandler]).
///
/// **Lifecycle:**
/// - Push to [ShortcutRouter] in the owning screen's `initState`.
/// - Call [attachCanvas] when [PatternCanvas] mounts.
/// - Call [detachCanvas] in [PatternCanvas.dispose].
/// - Pop from [ShortcutRouter] in the owning screen's `dispose`.
///
/// Only fires keyboard shortcuts when [EditorState.stitchMode] is true.
/// Pattern mutation is structurally impossible: this controller composes no
/// [DrawHandler] or [PasteHandler].
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

  // ── Canvas pointer handlers ────────────────────────────────────────────────

  HoverHandler? _hover;
  ProgressHandler? _progress;
  static const _pageNav = PageNavHandler();

  /// Read by [PatternCanvas] overlay painter.
  HoverHandler? get hover => _hover;
  ProgressHandler? get progress => _progress;

  /// Wire up pointer handlers with view-level callbacks.
  void attachCanvas(CanvasCallbacks cb) {
    final n = _notifier;
    _hover = HoverHandler(scheduleRebuild: cb.scheduleRebuild);
    _progress = ProgressHandler(
      onToggleStitchDone: n.toggleStitchDone,
      onToggleBackstitchDone: n.toggleBackstitchDone,
      onFloodFillDone: n.floodFillDone,
      onSetProgressRegion: n.setProgressRegion,
      scheduleRebuild: cb.scheduleRebuild,
    );
  }

  /// Release pointer handlers. Called by [PatternCanvas.dispose].
  void detachCanvas() {
    _hover = null;
    _progress = null;
  }

  // ── Pointer event dispatch ─────────────────────────────────────────────────

  void onPointerDown(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state, {
    required bool isOnCanvas,
    required bool isNavZone,
  }) {
    if (_progress == null) return;
    final p = state.pattern;

    if (state.drawingMode == DrawingMode.select) {
      if (state.progressRegion != null) {
        _notifier.setProgressRegion(null);
        return;
      }
      if (isOnCanvas && !isNavZone) {
        _progress!.onPointerDown(localPos, vp, p.width, p.height, state);
      }
      return;
    }

    if (!isNavZone) {
      _progress!.onPointerDown(localPos, vp, p.width, p.height, state);
    }
  }

  void onPointerMove(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state,
  ) {
    if (_progress == null) return;
    final p = state.pattern;
    _hover!.onPointerMove(localPos, vp, p.width, p.height);

    if (_progress!.isActive) {
      if (kind == PointerDeviceKind.touch) {
        _progress!.onTouchMove(localPos, vp, p.width, p.height);
      } else {
        _progress!.onPointerMove(localPos, vp, p.width, p.height);
      }
    }
  }

  void onPointerUp(
    Offset localPos,
    CanvasViewport vp,
    EditorState state,
  ) {
    if (_progress == null) return;
    if (_progress!.isActive) {
      _progress!.onPointerUp(
          localPos, vp, state.pattern.width, state.pattern.height, state);
    }
  }

  void onPointerHover(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state,
  ) {
    if (_hover == null) return;
    final p = state.pattern;
    _hover!.onPointerHover(localPos, kind, vp, p.width, p.height);
  }

  void onStylusAdded(Offset localPos, CanvasViewport vp, int patW, int patH) {
    _hover?.onStylusAdded(localPos, vp, patW, patH);
  }

  void onStylusRemoved() => _hover?.onStylusRemoved();

  void onHoverExit() => _hover?.onExit();

  /// Cancel any active progress gesture (e.g. when multi-touch starts).
  void cancelActiveGestures() {
    _progress?.cancel();
  }

  /// Returns true if [screenPos] falls in a page-navigation zone.
  bool isNavZone(
    Offset screenPos,
    double canvasWidth,
    double canvasHeight,
    EditorState state,
  ) =>
      _pageNav.isNavZone(
        screenPos,
        Size(canvasWidth, canvasHeight),
        stitchMode: true,
        pageEnabled: state.pattern.pageConfig.enabled,
        hasPageLayout: state.pageLayout != null,
      );

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────

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

    // ── Single-key shortcuts ────────────────────────────────────────────────
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
