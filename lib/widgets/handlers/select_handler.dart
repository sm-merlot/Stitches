import 'package:flutter/widgets.dart' show Offset, Rect;
import '../canvas/canvas_viewport.dart';
import 'gesture_handler.dart';

/// Edit-mode rubber-band selection handler.
///
/// Composes [GestureHandler] for gesture recognition and wires the
/// outcomes to [onSetSelectionRect]:
///   • tap or double-tap → clear selection (null)
///   • drag             → commit new selection rect
///
/// [AidaWidget] reads [dragRect] and [isActive] for the overlay painter.
class SelectHandler {
  final void Function(Rect? rect) onSetSelectionRect;
  final void Function() scheduleRebuild;

  late final GestureHandler _gesture;

  SelectHandler({
    required this.onSetSelectionRect,
    required this.scheduleRebuild,
  }) {
    _gesture = GestureHandler(
      onTap: (x, y) => onSetSelectionRect(null),
      onDoubleTap: (x, y) => onSetSelectionRect(null),
      onDragComplete: (rect) =>
          onSetSelectionRect(rect.width >= 1 && rect.height >= 1 ? rect : null),
      scheduleRebuild: scheduleRebuild,
    );
  }

  // ── Getters (read by overlay painter and tests) ───────────────────────────────

  Offset? get anchor => _gesture.anchor;
  Rect? get dragRect => _gesture.dragRect;
  bool get isActive => _gesture.isActive;

  // ── Static geometry helpers (kept for callers / tests) ────────────────────────

  static Rect buildSelRect(Offset a, Offset b) =>
      GestureHandler.buildSelRect(a, b);

  static bool cellInSelRect(int x, int y, Rect rect) =>
      GestureHandler.cellInSelRect(x, y, rect);

  static Offset toSelCell(
          Offset screenPos, CanvasViewport viewport, int patW, int patH) =>
      GestureHandler.toSelCell(screenPos, viewport, patW, patH);

  // ── Pointer events ────────────────────────────────────────────────────────────

  void onPointerDown(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH, {
    required bool isOnCanvas,
  }) {
    onSetSelectionRect(null); // always clear before starting a new gesture
    if (isOnCanvas) _gesture.pointerDown(screenPos, viewport, patW, patH);
  }

  void onPointerMove(
          Offset screenPos, CanvasViewport viewport, int patW, int patH) =>
      _gesture.pointerMove(screenPos, viewport, patW, patH);

  void onPointerUp(
          Offset screenPos, CanvasViewport viewport, int patW, int patH) =>
      _gesture.pointerUp(screenPos, viewport, patW, patH);

  void cancel() => _gesture.cancel();
}
