import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show Offset;
import '../../providers/editor/editor_provider.dart';
import '../../widgets/canvas/canvas_viewport.dart';
import '../../widgets/handlers/draw_handler.dart';
import '../../widgets/handlers/hover_handler.dart';
import '../../widgets/handlers/paste_handler.dart';
import '../../widgets/handlers/select_handler.dart';
import 'canvas_callbacks.dart';

/// Abstract interface shared by [EditController] and [SnippetEditController].
///
/// [AidaWidget] depends on this type, not on the concrete controllers.
/// This allows snippet editing to use its own controller class without any
/// common base implementation, while keeping the widget layer type-safe.
abstract class CanvasEditController {
  HoverHandler? get hover;
  DrawHandler? get draw;
  SelectHandler? get select;
  PasteHandler? get paste;

  void attachCanvas(CanvasCallbacks cb);
  void detachCanvas();

  void updateModifiers({required bool ctrl, required bool shift});
  void cancelActiveGestures();

  void onPencilDoubleTap(EditorState state);

  void onPointerDown(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state, {
    required bool isOnCanvas,
    required bool pencilPasteConfirm,
  });

  void onPointerMove(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state,
  );

  void onPointerUp(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state, {
    required bool wasSinglePointer,
    required bool hadMultiTouch,
    required bool isPanMode,
  });

  void onPointerHover(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport vp,
    EditorState state,
  );

  void onStylusAdded(Offset localPos, CanvasViewport vp, int patW, int patH);
  void onStylusRemoved();
  void onHoverExit();
}
