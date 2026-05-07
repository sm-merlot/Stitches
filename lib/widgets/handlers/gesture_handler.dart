import 'dart:math' as math;
import 'package:flutter/widgets.dart' show Offset, Rect;
import '../canvas/canvas_viewport.dart';

/// Shared gesture recogniser — upstream of all selection / progress-marking
/// handlers.
///
/// Recognises three outcomes from a pointer gesture:
///   • double-tap  → [onDoubleTap](x, y)
///   • single tap  → [onTap](x, y)
///   • drag        → [onDragComplete](rect)
///
/// Double-click detection runs on every pointer-down, before tap vs drag
/// discrimination, so the caller never needs to implement it. Backstitch or
/// other pre-emptions can pass `suppressDoubleClick: true` to [pointerDown].
///
/// Callers wire callbacks and forward pointer events; [dragRect] and
/// [isActive] are read by the overlay painter.
class GestureHandler {
  // ── Gesture state ─────────────────────────────────────────────────────────────

  Offset? _anchor;
  Offset? _anchorScreen;
  bool _hasDragged = false;
  Rect? _dragRect;

  // ── Double-click state ────────────────────────────────────────────────────────

  DateTime? _lastDownTime;
  (int, int)? _lastDownCell;
  bool _pendingDoubleClick = false;

  // ── Constants ─────────────────────────────────────────────────────────────────

  /// Minimum pointer movement (screen pixels) before a stylus/mouse drag is
  /// registered, preventing jitter from triggering the drag path on a tap.
  static const double kDragThreshold = 10.0;
  static const int _kDoubleClickMs = 300;

  // ── Callbacks ─────────────────────────────────────────────────────────────────

  final void Function(int x, int y) onTap;
  final void Function(int x, int y) onDoubleTap;
  final void Function(Rect rect) onDragComplete;
  final void Function() scheduleRebuild;

  GestureHandler({
    required this.onTap,
    required this.onDoubleTap,
    required this.onDragComplete,
    required this.scheduleRebuild,
  });

  // ── Getters ───────────────────────────────────────────────────────────────────

  Offset? get anchor => _anchor;
  bool get hasDragged => _hasDragged;
  Rect? get dragRect => _dragRect;
  bool get isActive => _anchor != null;

  // ── Static geometry helpers ───────────────────────────────────────────────────

  /// Maps [screenPos] to a cell coordinate clamped to pattern bounds.
  static Offset toSelCell(
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

  /// Builds an inclusive selection rect from two corner cells.
  static Rect buildSelRect(Offset a, Offset b) => Rect.fromLTRB(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        math.max(a.dx, b.dx) + 1,
        math.max(a.dy, b.dy) + 1,
      );

  /// Returns true when cell (x, y) is inside [rect].
  static bool cellInSelRect(int x, int y, Rect rect) =>
      x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;

  // ── Pointer events ────────────────────────────────────────────────────────────

  void pointerDown(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH, {
    bool suppressDoubleClick = false,
  }) {
    if (!suppressDoubleClick) _checkDoubleClick(screenPos, viewport);
    _anchor = toSelCell(screenPos, viewport, patW, patH);
    _anchorScreen = screenPos;
    _hasDragged = false;
    _dragRect = null;
    scheduleRebuild();
  }

  /// Stylus / mouse move — uses pixel distance to detect drag onset.
  void pointerMove(Offset screenPos, CanvasViewport viewport, int patW, int patH) {
    if (_anchor == null) return;
    final cell = toSelCell(screenPos, viewport, patW, patH);
    final newRect = buildSelRect(_anchor!, cell);
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

  /// Touch move — uses rect size instead of pixel distance (touch is less precise).
  void touchMove(Offset screenPos, CanvasViewport viewport, int patW, int patH) {
    if (_anchor == null) return;
    final cell = toSelCell(screenPos, viewport, patW, patH);
    final newRect = buildSelRect(_anchor!, cell);
    if (newRect != _dragRect) {
      if (newRect.width > 1 || newRect.height > 1) _hasDragged = true;
      _dragRect = newRect;
      scheduleRebuild();
    }
  }

  void pointerUp(Offset screenPos, CanvasViewport viewport, int patW, int patH) {
    if (_anchor == null) return;
    if (_hasDragged) {
      final cell = toSelCell(screenPos, viewport, patW, patH);
      onDragComplete(_dragRect ?? buildSelRect(_anchor!, cell));
    } else if (_pendingDoubleClick) {
      onDoubleTap(_anchor!.dx.toInt(), _anchor!.dy.toInt());
      _pendingDoubleClick = false;
    } else {
      onTap(_anchor!.dx.toInt(), _anchor!.dy.toInt());
    }
    _reset();
  }

  void cancel() => _reset();

  // ── Internal ──────────────────────────────────────────────────────────────────

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
      // Reset so a triple-click doesn't fire a second double-tap.
      _lastDownTime = null;
      _lastDownCell = null;
    } else {
      _pendingDoubleClick = false;
      _lastDownTime = now;
      _lastDownCell = (cx, cy);
    }
  }

  void _reset() {
    _anchor = null;
    _anchorScreen = null;
    _hasDragged = false;
    _dragRect = null;
    scheduleRebuild();
  }
}
