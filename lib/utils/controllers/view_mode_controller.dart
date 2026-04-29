import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' hide UndoManager;
import '../../providers/editor/editor_provider.dart';
import '../../widgets/canvas/canvas_viewport.dart';
import '../../widgets/handlers/hover_handler.dart';
import 'canvas_callbacks.dart';
import '../commands/shortcut_router.dart';

/// Controller for view mode (read-only).
///
/// Owns only [HoverHandler] — no [DrawHandler], [SelectHandler], or
/// [PasteHandler]. Pattern mutation is structurally impossible.
///
/// **Lifecycle:**
/// - Push to [ShortcutRouter] in the owning screen's `initState`.
/// - Call [attachCanvas] when [AidaWidget] mounts.
/// - Call [detachCanvas] in [AidaWidget.dispose].
/// - Pop from [ShortcutRouter] in the owning screen's `dispose`.
class ViewModeController implements ShortcutHandler {
  ViewModeController({
    required EditorState Function() getState,
  }) : _getState = getState;

  // ignore: unused_field
  final EditorState Function() _getState;

  // ── Canvas pointer handlers ────────────────────────────────────────────────

  HoverHandler? _hover;

  HoverHandler? get hover => _hover;

  void attachCanvas(CanvasCallbacks cb) {
    _hover = HoverHandler(scheduleRebuild: cb.scheduleRebuild);
  }

  void detachCanvas() {
    _hover = null;
  }

  // ── Pointer event dispatch ─────────────────────────────────────────────────

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

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────

  @override
  bool handle(KeyEvent event) => false; // view mode: no keyboard shortcuts
}
