import 'dart:math' as math;
import 'package:flutter/widgets.dart' show Offset, Rect;
import '../../models/cell.dart';
import '../../models/stitch/stitch.dart';
import '../../providers/editor/editor_provider.dart' show EditorState;
import '../canvas/canvas_viewport.dart';
import 'gesture_handler.dart';

/// Handles stitch-mode progress marking: tap-to-toggle, double-tap flood fill,
/// and drag-to-mark region.
///
/// Composes [GestureHandler] for gesture recognition and wires the outcomes
/// to the appropriate callbacks. Backstitch hit-testing is handled here as a
/// pre-interception at pointer-down, suppressing double-click for backstitch
/// taps so the normal flood-fill path is not triggered.
///
/// Writes back via injected callbacks — no direct [EditorNotifier] access,
/// so this handler is unit-testable without Riverpod.
///
/// [AidaWidget] calls the appropriate method on pointer events and reads
/// [dragRect] / [isActive] to drive the overlay painter.
class ProgressHandler {
  // ── State ─────────────────────────────────────────────────────────────────────

  BackStitch? _pendingBackstitch; // backstitch hit at pointer-down; tapped on pointer-up
  bool? _wasProgressCellDone;    // cell state BEFORE the last single toggle
  EditorState? _lastState;       // state captured at pointer-down / pointer-up

  // ── Constants ─────────────────────────────────────────────────────────────────

  /// Hit radius in cell units for backstitch tapping.
  static const double kBackstitchHitRadius = 0.3;

  // ── Callbacks ─────────────────────────────────────────────────────────────────

  final void Function(int x, int y) onToggleStitchDone;
  final void Function(double x1, double y1, double x2, double y2)
      onToggleBackstitchDone;
  final void Function(
    int x,
    int y, {
    bool? originalStartIsDone,
    bool afterSingleTap,
  }) onFloodFillDone;
  final void Function(Rect? rect) onSetProgressRegion;
  final void Function() scheduleRebuild;

  late final GestureHandler _gesture;

  ProgressHandler({
    required this.onToggleStitchDone,
    required this.onToggleBackstitchDone,
    required this.onFloodFillDone,
    required this.onSetProgressRegion,
    required this.scheduleRebuild,
  }) {
    _gesture = GestureHandler(
      onTap: (x, y) {
        _wasProgressCellDone = _lastState?.pattern.progress.completedStitches
            .contains(Cell(x, y));
        onToggleStitchDone(x, y);
        onSetProgressRegion(null);
      },
      onDoubleTap: (x, y) {
        onFloodFillDone(x, y,
            originalStartIsDone: _wasProgressCellDone, afterSingleTap: true);
        _wasProgressCellDone = null;
        onSetProgressRegion(null);
      },
      onDragComplete: (rect) {
        if (rect.width > 1 || rect.height > 1) onSetProgressRegion(rect);
      },
      scheduleRebuild: scheduleRebuild,
    );
  }

  // ── Getters ───────────────────────────────────────────────────────────────────

  Offset? get anchor => _gesture.anchor;
  bool get hasDragged => _gesture.hasDragged;
  Rect? get dragRect => _gesture.dragRect;
  bool get isActive => _gesture.isActive;

  // ── Backstitch hit test ───────────────────────────────────────────────────────

  /// Returns the topmost visible [BackStitch] within [kBackstitchHitRadius]
  /// cell units of [screenPos], or `null` if none qualifies.
  ///
  /// Returns `null` when [state.stitchSession.crossMode] is active (cross-stitch
  /// focus mode suppresses backstitch taps so normal cross-stitch taps work).
  BackStitch? getBackstitchHit(
    Offset screenPos,
    CanvasViewport viewport,
    EditorState state,
  ) {
    if (state.stitchSession.crossMode) return null;
    final focusId = state.stitchSession.focusThreadId;
    final canvas = viewport.screenToCanvas(screenPos);
    final px = canvas.dx / viewport.cellSize;
    final py = canvas.dy / viewport.cellSize;
    BackStitch? result;
    for (final layer in state.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! BackStitch) continue;
        if (focusId != null && stitch.threadId != focusId) continue;
        // Point-to-segment distance in cell space.
        final dx = stitch.x2 - stitch.x1;
        final dy = stitch.y2 - stitch.y1;
        final lenSq = dx * dx + dy * dy;
        double dist;
        if (lenSq == 0) {
          final ex = px - stitch.x1, ey = py - stitch.y1;
          dist = math.sqrt(ex * ex + ey * ey);
        } else {
          final t =
              ((px - stitch.x1) * dx + (py - stitch.y1) * dy) / lenSq;
          final tc = t.clamp(0.0, 1.0);
          final nx = stitch.x1 + tc * dx - px;
          final ny = stitch.y1 + tc * dy - py;
          dist = math.sqrt(nx * nx + ny * ny);
        }
        if (dist < kBackstitchHitRadius) result = stitch; // last = topmost layer
      }
    }
    return result;
  }

  // ── Pointer events ────────────────────────────────────────────────────────────

  /// Call on pointer down in progress-marking mode (stitch mode).
  void onPointerDown(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
    EditorState state,
  ) {
    _lastState = state;
    final bs = getBackstitchHit(screenPos, viewport, state);
    _pendingBackstitch = bs;
    _gesture.pointerDown(screenPos, viewport, patW, patH,
        suppressDoubleClick: bs != null);
  }

  /// Call on pointer move in progress-marking mode (stylus/mouse).
  void onPointerMove(
          Offset screenPos, CanvasViewport viewport, int patW, int patH) =>
      _gesture.pointerMove(screenPos, viewport, patW, patH);

  /// Call on pointer move in progress-marking mode for touch input.
  void onTouchMove(
          Offset screenPos, CanvasViewport viewport, int patW, int patH) =>
      _gesture.touchMove(screenPos, viewport, patW, patH);

  /// Call on pointer up in progress-marking mode (stitch mode).
  void onPointerUp(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
    EditorState state,
  ) {
    if (_pendingBackstitch != null && !_gesture.hasDragged) {
      final bs = _pendingBackstitch!;
      _pendingBackstitch = null;
      onToggleBackstitchDone(bs.x1, bs.y1, bs.x2, bs.y2);
      onSetProgressRegion(null);
      _gesture.cancel();
    } else {
      _pendingBackstitch = null;
      _lastState = state;
      _gesture.pointerUp(screenPos, viewport, patW, patH);
    }
  }

  /// Cancels all gesture state (e.g. when multi-touch starts).
  void cancel() => _gesture.cancel();
}
