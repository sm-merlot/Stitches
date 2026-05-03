import 'package:flutter/widgets.dart' show Offset;
import '../../models/stitch/stitch.dart';
import '../../providers/editor/editor_provider.dart'
    show DrawingMode, DrawingTool, EditorState, PartialSubTool;
import '../canvas/canvas_viewport.dart';

/// Handles all stitch-drawing and erasing interactions (draw mode).
///
/// Owns the backstitch hover point and flood-fill guard state.
/// Writes back via injected callbacks — no direct [EditorNotifier] access,
/// so this handler is unit-testable without Riverpod.
///
/// [AidaWidget] calls [handleDrawAt] on pointer down and move;
/// it reads [backstitchHoverPoint] to drive the backstitch preview line.
class DrawHandler {
  bool _fillFired = false;
  Offset? _backstitchHoverPoint;

  // ── Callbacks ─────────────────────────────────────────────────────────────────
  final void Function(Stitch) onAddStitch;
  final void Function(int x, int y) onRemoveAt;
  final void Function(int x, int y, int size) onRemoveBox;
  final void Function(int x, int y, {required bool erase}) onFloodFill;
  final void Function(int x, int y) onPickColor;
  final void Function(Offset? point) onSetBackstitchStart;
  final void Function(String msg) onLayerWarning;
  final bool Function() getCtrlHeld;

  DrawHandler({
    required this.onAddStitch,
    required this.onRemoveAt,
    required this.onRemoveBox,
    required this.onFloodFill,
    required this.onPickColor,
    required this.onSetBackstitchStart,
    required this.onLayerWarning,
    required this.getCtrlHeld,
  });

  // ── Getters ──────────────────────────────────────────────────────────────────

  Offset? get backstitchHoverPoint => _backstitchHoverPoint;

  // ── Pointer events ────────────────────────────────────────────────────────────

  /// Call on pointer up.  Resets the per-tap flood-fill guard.
  void onPointerUp() {
    _fillFired = false;
  }

  /// Update the backstitch hover point on [PointerHoverEvent] or move.
  ///
  /// Should only be called when the backstitch tool is active and a start
  /// point has been placed (i.e. there is something to preview).
  void updateBackstitchHover(Offset screenPos, CanvasViewport viewport) {
    final canvas = viewport.screenToCanvas(screenPos);
    _backstitchHoverPoint = viewport.canvasToGridPoint(canvas);
  }

  void clearBackstitchHover() {
    _backstitchHoverPoint = null;
  }

  // ── Draw at ───────────────────────────────────────────────────────────────────

  /// Applies the active drawing tool at [screenPos].
  ///
  /// Must only be called in edit mode; callers should guard on
  /// [EditorState.editMode] and [EditorState.drawingMode] == [DrawingMode.draw]
  /// or [DrawingMode.erase].
  void handleDrawAt(
    Offset screenPos,
    EditorState state,
    CanvasViewport viewport,
  ) {
    if (!state.editMode) return;
    final canvas = viewport.screenToCanvas(screenPos);

    if (state.editSession.drawingMode == DrawingMode.colorPicker) {
      final (cellX, cellY) = viewport.canvasToCell(canvas);
      if (_inBounds(cellX, cellY, state)) onPickColor(cellX, cellY);
      return;
    }

    if (state.editSession.drawingMode == DrawingMode.erase) {
      final (cellX, cellY) = viewport.canvasToCell(canvas);
      if (_inBounds(cellX, cellY, state)) {
        _checkLayerWarning(state, cellX, cellY);
      }
      if (state.editSession.fillEraseActive) {
        if (!_inBounds(cellX, cellY, state)) return;
        if (_fillFired) return;
        _fillFired = true;
        onFloodFill(cellX, cellY, erase: true);
      } else if (state.editSession.eraserSize > 1) {
        onRemoveBox(cellX, cellY, state.editSession.eraserSize);
      } else {
        if (_inBounds(cellX, cellY, state)) onRemoveAt(cellX, cellY);
      }
      return;
    }

    if (state.editSession.currentTool == DrawingTool.fill) {
      final (cellX, cellY) = viewport.canvasToCell(canvas);
      if (!_inBounds(cellX, cellY, state)) return;
      if (_fillFired) return;
      _fillFired = true;
      onFloodFill(cellX, cellY, erase: false);
      return;
    }

    if (state.editSession.currentTool == DrawingTool.backstitch) {
      _handleBackstitch(canvas, state, viewport);
      return;
    }

    final (cellX, cellY) = viewport.canvasToCell(canvas);
    if (!_inBounds(cellX, cellY, state)) return;
    if (state.selectedThreadId == null) return;

    _checkLayerWarning(state, cellX, cellY);

    final (subX, subY) = viewport.subCellPos(canvas, cellX, cellY);
    final stitch = _buildStitch(
        state.editSession.currentTool, state.editSession.partialSubTool,
        cellX, cellY, state.selectedThreadId!, subX, subY);
    if (stitch != null) onAddStitch(stitch);
  }

  // ── Private ───────────────────────────────────────────────────────────────────

  bool _inBounds(int cellX, int cellY, EditorState state) =>
      cellX >= 0 &&
      cellX < state.pattern.width &&
      cellY >= 0 &&
      cellY < state.pattern.height;

  void _handleBackstitch(
    Offset canvas,
    EditorState state,
    CanvasViewport viewport,
  ) {
    final gridPt = viewport.canvasToGridPoint(canvas);
    final p = state.pattern;
    final gx = gridPt.dx;
    final gy = gridPt.dy;

    if (gx < 0 || gx > p.width || gy < 0 || gy > p.height) return;

    if (state.editSession.backstitchStartPoint == null) {
      onSetBackstitchStart(gridPt);
      _backstitchHoverPoint = null;
    } else {
      final start = state.editSession.backstitchStartPoint!;
      final sx = start.dx, sy = start.dy;
      if (sx == gx && sy == gy) {
        onSetBackstitchStart(null);
        _backstitchHoverPoint = null;
      } else if (state.selectedThreadId != null) {
        onAddStitch(BackStitch(
          x1: sx,
          y1: sy,
          x2: gx,
          y2: gy,
          threadId: state.selectedThreadId!,
        ));
        // Chain mode: end point becomes new start for the next backstitch.
        final chain = getCtrlHeld() || state.editSession.backstitchChainMode;
        onSetBackstitchStart(chain ? gridPt : null);
        if (!chain) _backstitchHoverPoint = null;
      }
    }
  }

  Stitch? _buildStitch(
    DrawingTool tool,
    PartialSubTool subTool,
    int x,
    int y,
    String threadId,
    double subX,
    double subY,
  ) =>
      switch (tool) {
        DrawingTool.fullStitch =>
          FullStitch(x: x, y: y, threadId: threadId),
        DrawingTool.partial => switch (subTool) {
          PartialSubTool.diagonalForward =>
            HalfStitch(x: x, y: y, isForward: true, threadId: threadId),
          PartialSubTool.diagonalBackward =>
            HalfStitch(x: x, y: y, isForward: false, threadId: threadId),
          PartialSubTool.half => HalfCrossStitch(
              x: x,
              y: y,
              half: _detectHalf(subX, subY),
              threadId: threadId,
            ),
          PartialSubTool.threeQuarter => ThreeQuarterStitch(
              x: x,
              y: y,
              quadrant: _detectQuadrant(subX, subY),
              isForward: true,
              threadId: threadId,
            ),
          PartialSubTool.quarter => QuarterStitch(
              x: x,
              y: y,
              quadrant: _detectQuadrant(subX, subY),
              threadId: threadId,
            ),
        },
        DrawingTool.backstitch => null,
        DrawingTool.fill => null,
        DrawingTool.fillErase => null,
      };

  static QuadrantPosition _detectQuadrant(double subX, double subY) {
    if (subX < 0.5 && subY < 0.5) return QuadrantPosition.topLeft;
    if (subX >= 0.5 && subY < 0.5) return QuadrantPosition.topRight;
    if (subX < 0.5 && subY >= 0.5) return QuadrantPosition.bottomLeft;
    return QuadrantPosition.bottomRight;
  }

  static HalfOrientation _detectHalf(double subX, double subY) {
    if ((subX - 0.5).abs() > (subY - 0.5).abs()) {
      return subX < 0.5 ? HalfOrientation.left : HalfOrientation.right;
    } else {
      return subY < 0.5 ? HalfOrientation.top : HalfOrientation.bottom;
    }
  }

  /// Warns if the draw/erase at (cellX, cellY) will be invisible due to
  /// layer visibility issues.
  void _checkLayerWarning(EditorState state, int cellX, int cellY) {
    final activeLayer = state.activeLayer;
    final layers = state.pattern.layers;

    if (state.editSession.drawingMode == DrawingMode.erase) {
      final activeHasStitch = activeLayer.stitchesAt(cellX, cellY).isNotEmpty;
      if (!activeHasStitch) {
        final othersHaveStitch = layers.any((l) =>
            l.id != activeLayer.id &&
            l.visible &&
            l.stitchesAt(cellX, cellY).isNotEmpty);
        if (othersHaveStitch) {
          onLayerWarning(
              'Nothing to erase on active layer here — check other layers');
        }
      }
    } else if (state.editSession.drawingMode == DrawingMode.draw) {
      if (!activeLayer.visible) {
        onLayerWarning('Active layer is hidden — drawing won\'t be visible');
        return;
      }
      final activeIdx =
          layers.indexWhere((l) => l.id == activeLayer.id);
      if (activeIdx >= 0) {
        for (var i = activeIdx + 1; i < layers.length; i++) {
          final above = layers[i];
          if (!above.visible || above.opacity < 1.0) continue;
          final covered = above.stitchesAt(cellX, cellY)
              .any((s) => s is FullStitch);
          if (covered) {
            onLayerWarning(
                '"${above.name}" covers this cell — drawing won\'t be visible');
            return;
          }
        }
      }
    }
  }

}
