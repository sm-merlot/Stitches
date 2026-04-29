import 'dart:math' as math;
import 'package:flutter/widgets.dart' show Offset, Rect;
import '../../providers/editor/editor_provider.dart' show kLayerHint, kWarnNothingToMove;
import '../canvas/canvas_viewport.dart';

/// Handles rubber-band region selection and selection-move drag.
///
/// Owns all selection-gesture state (anchor, drag rect, move delta).
/// Writes back to [EditorNotifier] via injected callbacks so this handler is
/// unit-testable without Riverpod.
///
/// [AidaWidget] calls the appropriate method on pointer events and reads
/// [dragRect], [moveDelta], and [isMoving] to drive the overlay painter.
class SelectHandler {
  Offset? _anchor;
  bool _isMoving = false;
  bool _hasDragged = false;
  Offset? _moveStartCell;
  Offset _moveDelta = Offset.zero;
  Rect? _dragRect;

  final void Function(Rect? rect) onSetSelectionRect;
  final void Function(int dx, int dy) onMoveSelection;
  final void Function(String msg) onWarning;
  final void Function() scheduleRebuild;

  SelectHandler({
    required this.onSetSelectionRect,
    required this.onMoveSelection,
    required this.onWarning,
    required this.scheduleRebuild,
  });

  // ── Getters ──────────────────────────────────────────────────────────────────

  Offset? get anchor => _anchor;
  bool get isMoving => _isMoving;
  Offset get moveDelta => _moveDelta;
  Rect? get dragRect => _dragRect;
  bool get isActive => _anchor != null || _isMoving;

  // ── Coordinate helpers ────────────────────────────────────────────────────────

  /// Builds a selection rect from two corner cells, inclusive on both ends.
  static Rect buildSelRect(Offset a, Offset b) => Rect.fromLTRB(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        math.max(a.dx, b.dx) + 1,
        math.max(a.dy, b.dy) + 1,
      );

  /// Returns true when cell (x, y) is inside [rect].
  static bool cellInSelRect(int x, int y, Rect rect) =>
      x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;

  /// Maps [screenPos] to a cell clamped to pattern bounds.
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

  // ── Pointer events ────────────────────────────────────────────────────────────

  /// Call on pointer down in select mode (edit mode only, not stitch mode).
  void onPointerDown(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH, {
    required Rect? currentSelectionRect,
    required bool hasSelectedStitches,
    required bool canvasSelectionMode,
    required bool isOnCanvas,
  }) {
    final cell = toSelCell(screenPos, viewport, patW, patH);
    final sel = currentSelectionRect;
    if (sel != null && cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
      if (!hasSelectedStitches) {
        onWarning(kWarnNothingToMove + (canvasSelectionMode ? '' : kLayerHint));
      } else {
        _isMoving = true;
        _moveStartCell = cell;
        _moveDelta = Offset.zero;
        scheduleRebuild();
      }
    } else {
      onSetSelectionRect(null);
      if (isOnCanvas) {
        _anchor = cell;
        _isMoving = false;
        _hasDragged = false;
        scheduleRebuild();
      }
    }
  }

  /// Call on pointer move in select mode (edit mode only, not stitch mode).
  void onPointerMove(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    final cell = toSelCell(screenPos, viewport, patW, patH);
    if (_isMoving && _moveStartCell != null) {
      _moveDelta = cell - _moveStartCell!;
      scheduleRebuild();
    } else if (_anchor != null) {
      _hasDragged = true;
      _dragRect = buildSelRect(_anchor!, cell);
      scheduleRebuild();
    }
  }

  /// Call on pointer up in select mode (edit mode only, not stitch mode).
  void onPointerUp(
    Offset screenPos,
    CanvasViewport viewport,
    int patW,
    int patH,
  ) {
    if (_isMoving) {
      final dx = _moveDelta.dx.round();
      final dy = _moveDelta.dy.round();
      if (dx != 0 || dy != 0) {
        onMoveSelection(dx, dy);
      } else {
        // Single click inside selection with no movement → deselect.
        onSetSelectionRect(null);
      }
      _isMoving = false;
      _moveStartCell = null;
      _moveDelta = Offset.zero;
      scheduleRebuild();
      return;
    }
    if (_anchor != null) {
      final cell = toSelCell(screenPos, viewport, patW, patH);
      final rect = _dragRect ?? buildSelRect(_anchor!, cell);
      // Only keep selection if the user actually dragged.
      onSetSelectionRect(
          _hasDragged && rect.width >= 1 && rect.height >= 1 ? rect : null);
      _anchor = null;
      _hasDragged = false;
      _dragRect = null;
      scheduleRebuild();
    }
  }

  /// Clears all gesture state without committing (e.g. when multi-touch starts).
  void cancel() {
    _anchor = null;
    _isMoving = false;
    _hasDragged = false;
    _moveStartCell = null;
    _moveDelta = Offset.zero;
    _dragRect = null;
  }
}
