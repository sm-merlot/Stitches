import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' show Offset;
import 'canvas_viewport.dart';

/// Tracks mouse/stylus screen position and hover cell.
///
/// [AidaWidget] forwards the relevant pointer events; after each call it
/// reads [mouseScreenPos] and [hoverCell] to drive the overlay painter.
///
/// No domain logic lives here — this handler is a pure coordinate tracker.
class HoverHandler {
  Offset? _mouseScreenPos;
  (int, int)? _hoverCell;

  final void Function() scheduleRebuild;

  HoverHandler({required this.scheduleRebuild});

  Offset? get mouseScreenPos => _mouseScreenPos;
  (int, int)? get hoverCell => _hoverCell;

  // ── Internal ────────────────────────────────────────────────────────────────

  (int, int)? _toCell(
    Offset localPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    final canvas = viewport.screenToCanvas(localPos);
    final cell = viewport.canvasToCell(canvas);
    return (cell.$1 >= 0 && cell.$1 < patW && cell.$2 >= 0 && cell.$2 < patH)
        ? cell
        : null;
  }

  // ── Events ──────────────────────────────────────────────────────────────────

  /// Call on [PointerDownEvent].  Updates mouse screen position only.
  void onPointerDown(Offset localPos) {
    _mouseScreenPos = localPos;
  }

  /// Call on [PointerMoveEvent] for stylus/mouse devices.
  void onPointerMove(
    Offset localPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    _mouseScreenPos = localPos;
    _hoverCell = _toCell(localPos, viewport, patW, patH);
    scheduleRebuild();
  }

  /// Call on [PointerUpEvent].  Clears hover cell for non-touch devices.
  void onPointerUp(PointerDeviceKind kind) {
    if (kind != PointerDeviceKind.touch) {
      _hoverCell = null;
      scheduleRebuild();
    }
  }

  /// Call on [PointerHoverEvent].
  void onPointerHover(
    Offset localPos,
    PointerDeviceKind kind,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    _mouseScreenPos = localPos;
    if (kind != PointerDeviceKind.touch) {
      _hoverCell = _toCell(localPos, viewport, patW, patH);
    }
    scheduleRebuild();
  }

  /// Call when [MouseRegion.onExit] fires.
  void onExit() {
    _mouseScreenPos = null;
    _hoverCell = null;
    scheduleRebuild();
  }

  /// Call from the global stylus pointer route when a pencil enters hover range.
  void onStylusAdded(
    Offset localPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    final cell = _toCell(localPos, viewport, patW, patH);
    if (cell != null) {
      _hoverCell = cell;
      scheduleRebuild();
    }
  }

  /// Call from the global stylus pointer route when a pencil leaves hover range.
  void onStylusRemoved() {
    _hoverCell = null;
    scheduleRebuild();
  }
}
