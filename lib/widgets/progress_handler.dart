import 'dart:math' as math;
import 'package:flutter/widgets.dart' show Offset, Rect;
import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart' show EditorState;
import 'canvas_viewport.dart';

/// Handles stitch-mode progress marking: tap-to-toggle, double-tap flood fill,
/// and drag-to-mark region.
///
/// Owns all progress-gesture state (anchor, drag rect, double-click timing)
/// and backstitch hit-test logic.  Writes back via injected callbacks —
/// no direct [EditorNotifier] access, so this handler is unit-testable
/// without Riverpod.
///
/// [PatternCanvas] calls the appropriate method on pointer events and reads
/// [dragRect] / [isActive] to drive the overlay painter.
class ProgressHandler {
  // ── Gesture state ─────────────────────────────────────────────────────────────
  Offset? _anchor;               // cell coords where the gesture started
  Offset? _anchorScreen;         // screen pixels (for drag-threshold check)
  bool _hasDragged = false;
  Rect? _dragRect;
  BackStitch? _pendingBackstitch; // backstitch hit at pointer-down; tapped on pointer-up

  // ── Double-click / double-tap detection (DOWN-to-DOWN) ────────────────────────
  DateTime? _lastDownTime;
  (int, int)? _lastDownCell;
  bool _pendingDoubleClick = false;
  bool? _wasProgressCellDone; // cell state BEFORE the last single toggle

  // ── Constants ─────────────────────────────────────────────────────────────────
  static const int _kDoubleClickMs = 500;

  /// Minimum pointer movement (screen pixels) before a drag is registered.
  static const double kDragThreshold = 10.0;

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

  ProgressHandler({
    required this.onToggleStitchDone,
    required this.onToggleBackstitchDone,
    required this.onFloodFillDone,
    required this.onSetProgressRegion,
    required this.scheduleRebuild,
  });

  // ── Getters ──────────────────────────────────────────────────────────────────

  Offset? get anchor => _anchor;
  bool get hasDragged => _hasDragged;
  Rect? get dragRect => _dragRect;
  bool get isActive => _anchor != null;

  // ── Coordinate helpers ────────────────────────────────────────────────────────

  static Offset _toSelCell(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    final c = viewport.screenToCanvas(screenPos);
    final (x, y) = viewport.canvasToCell(c);
    return Offset(
      x.clamp(0, patW - 1).toDouble(),
      y.clamp(0, patH - 1).toDouble(),
    );
  }

  static Rect _buildSelRect(Offset a, Offset b) => Rect.fromLTRB(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        math.max(a.dx, b.dx) + 1,
        math.max(a.dy, b.dy) + 1,
      );

  // ── Backstitch hit test ───────────────────────────────────────────────────────

  /// Returns the topmost visible [BackStitch] within [kBackstitchHitRadius]
  /// cell units of [screenPos], or `null` if none qualifies.
  ///
  /// Returns `null` when [state.stitchCrossMode] is active (cross-stitch focus
  /// mode suppresses backstitch taps so normal cross-stitch taps work).
  BackStitch? getBackstitchHit(
    Offset screenPos,
    CanvasViewport viewport,
    EditorState state,
  ) {
    if (state.stitchCrossMode) return null;
    final focusId = state.stitchFocusThreadId;
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

  // ── Double-click detection ────────────────────────────────────────────────────

  void _checkDoubleClick(Offset screenPos, CanvasViewport viewport) {
    final now = DateTime.now();
    final canvas = viewport.screenToCanvas(screenPos);
    final (cx, cy) = viewport.canvasToCell(canvas);
    final last = _lastDownTime;
    final lastCell = _lastDownCell;
    if (last != null &&
        lastCell != null &&
        now.difference(last).inMilliseconds < _kDoubleClickMs &&
        lastCell.$1 == cx &&
        lastCell.$2 == cy) {
      _pendingDoubleClick = true;
      // Reset so a triple-click doesn't fire a second flood fill.
      _lastDownTime = null;
      _lastDownCell = null;
    } else {
      _pendingDoubleClick = false;
      _lastDownTime = now;
      _lastDownCell = (cx, cy);
    }
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
    final cell = _toSelCell(screenPos, viewport, patW, patH);
    final bs = getBackstitchHit(screenPos, viewport, state);
    if (bs == null) _checkDoubleClick(screenPos, viewport);
    _anchor = cell;
    _anchorScreen = screenPos;
    _pendingBackstitch = bs;
    _hasDragged = false;
    _dragRect = null;
    scheduleRebuild();
  }

  /// Call on pointer move in progress-marking mode (stylus/mouse).
  ///
  /// Only registers as a drag once the pointer moves more than [kDragThreshold]
  /// screen pixels from the anchor, to prevent jitter from triggering the
  /// drag path on a tap.
  void onPointerMove(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    if (_anchor == null) return;
    final cell = _toSelCell(screenPos, viewport, patW, patH);
    final newRect = _buildSelRect(_anchor!, cell);
    if (!_hasDragged &&
        _anchorScreen != null &&
        (screenPos - _anchorScreen!).distance > kDragThreshold) {
      _hasDragged = true;
    }
    if (newRect != _dragRect) {
      _dragRect = newRect;
      scheduleRebuild();
    }
  }

  /// Call on pointer move in progress-marking mode for touch input.
  ///
  /// Touch uses rect size instead of screen-pixel distance to detect a drag,
  /// since touch events are less precise.
  void onTouchMove(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    if (_anchor == null) return;
    final cell = _toSelCell(screenPos, viewport, patW, patH);
    final newRect = _buildSelRect(_anchor!, cell);
    if (newRect != _dragRect) {
      if (newRect.width > 1 || newRect.height > 1) _hasDragged = true;
      _dragRect = newRect;
      scheduleRebuild();
    }
  }

  /// Call on pointer up in progress-marking mode (stitch mode).
  void onPointerUp(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
    EditorState state,
  ) {
    if (_anchor == null) return;
    final cell = _toSelCell(screenPos, viewport, patW, patH);
    if (_hasDragged) {
      final rect = _dragRect ?? _buildSelRect(_anchor!, cell);
      if (rect.width > 1 || rect.height > 1) {
        onSetProgressRegion(rect);
      }
    } else {
      final bs = _pendingBackstitch;
      if (bs != null) {
        // Backstitch tap — always single toggle, no flood fill.
        onToggleBackstitchDone(bs.x1, bs.y1, bs.x2, bs.y2);
      } else {
        final cx = _anchor!.dx.toInt();
        final cy = _anchor!.dy.toInt();
        if (_pendingDoubleClick) {
          onFloodFillDone(cx, cy,
              originalStartIsDone: _wasProgressCellDone, afterSingleTap: true);
          _pendingDoubleClick = false;
          _wasProgressCellDone = null;
        } else {
          _wasProgressCellDone = state.pattern.progress.completedStitches
              .contains((cx, cy));
          onToggleStitchDone(cx, cy);
        }
      }
      // Clear any committed progress region on a tap.
      onSetProgressRegion(null);
    }
    _reset();
  }

  /// Cancels all gesture state (e.g. when multi-touch starts).
  void cancel() => _reset();

  void _reset() {
    _anchor = null;
    _anchorScreen = null;
    _pendingBackstitch = null;
    _hasDragged = false;
    _dragRect = null;
    scheduleRebuild();
  }
}
