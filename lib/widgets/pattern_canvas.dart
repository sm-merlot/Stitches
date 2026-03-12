import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stitch.dart';
import '../providers/editor_provider.dart';
import 'canvas_painter.dart';

class PatternCanvas extends ConsumerStatefulWidget {
  const PatternCanvas({super.key});

  @override
  ConsumerState<PatternCanvas> createState() => _PatternCanvasState();
}

class _PatternCanvasState extends ConsumerState<PatternCanvas> {
  static const double _baseCellSize = 20.0;

  double _scale = 1.0;
  Offset _panOffset = const Offset(20, 20);

  // Touch pinch-to-zoom tracking
  final Map<int, Offset> _activePointers = {};
  double _gestureStartScale = 1.0;
  Offset _gestureStartOffset = Offset.zero;
  double _pinchStartDistance = 0.0;
  Offset _pinchStartCenter = Offset.zero;

  // Double-tap detection (touch only)
  DateTime? _lastTouchUpTime;
  Offset? _lastTouchUpPos;

  // Cursor/hover tracking
  Offset? _backstitchHoverPoint;
  Offset? _mouseScreenPos;

  double get _cellSize => _baseCellSize;

  Offset _screenToCanvas(Offset screen) {
    return (screen - _panOffset) / _scale;
  }

  Offset _canvasToGridPoint(Offset canvas) {
    final gx = (canvas.dx / _cellSize * 2).round() / 2.0;
    final gy = (canvas.dy / _cellSize * 2).round() / 2.0;
    return Offset(gx, gy);
  }

  (int, int) _canvasToCell(Offset canvas) {
    return (
      (canvas.dx / _cellSize).floor(),
      (canvas.dy / _cellSize).floor(),
    );
  }

  (double, double) _subCellPos(Offset canvas, int cellX, int cellY) {
    final subX = (canvas.dx / _cellSize) - cellX;
    final subY = (canvas.dy / _cellSize) - cellY;
    return (subX.clamp(0.0, 1.0), subY.clamp(0.0, 1.0));
  }

  QuadrantPosition _detectQuadrant(double subX, double subY) {
    if (subX < 0.5 && subY < 0.5) return QuadrantPosition.topLeft;
    if (subX >= 0.5 && subY < 0.5) return QuadrantPosition.topRight;
    if (subX < 0.5 && subY >= 0.5) return QuadrantPosition.bottomLeft;
    return QuadrantPosition.bottomRight;
  }

  HalfOrientation _detectHalf(double subX, double subY) {
    if ((subX - 0.5).abs() > (subY - 0.5).abs()) {
      return subX < 0.5 ? HalfOrientation.left : HalfOrientation.right;
    } else {
      return subY < 0.5 ? HalfOrientation.top : HalfOrientation.bottom;
    }
  }

  bool _inBounds(int cellX, int cellY) {
    final p = ref.read(editorProvider).pattern;
    return cellX >= 0 && cellX < p.width && cellY >= 0 && cellY < p.height;
  }

  void _pan(Offset delta) {
    setState(() => _panOffset += delta);
  }

  void _zoomAround(Offset focalPoint, double factor) {
    setState(() {
      final newScale = (_scale * factor).clamp(0.1, 20.0);
      final scaleFactor = newScale / _scale;
      _panOffset = focalPoint - (focalPoint - _panOffset) * scaleFactor;
      _scale = newScale;
    });
  }

  /// Returns the threadId of the topmost cell-based stitch at [cellX],[cellY].
  String? _threadAtCell(int cellX, int cellY) {
    final stitches = ref.read(editorProvider).pattern.stitches;
    for (final s in stitches.reversed) {
      final tid = switch (s) {
        FullStitch(x: final sx, y: final sy, threadId: final t)
            when sx == cellX && sy == cellY =>
          t,
        HalfStitch(x: final sx, y: final sy, threadId: final t)
            when sx == cellX && sy == cellY =>
          t,
        HalfCrossStitch(x: final sx, y: final sy, threadId: final t)
            when sx == cellX && sy == cellY =>
          t,
        QuarterStitch(x: final sx, y: final sy, threadId: final t)
            when sx == cellX && sy == cellY =>
          t,
        QuarterCrossStitch(x: final sx, y: final sy, threadId: final t)
            when sx == cellX && sy == cellY =>
          t,
        _ => null,
      };
      if (tid != null) return tid;
    }
    return null;
  }

  void _handleDrawAt(Offset screenPos) {
    final state = ref.read(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final canvas = _screenToCanvas(screenPos);

    if (state.drawingMode == DrawingMode.colorPicker) {
      final (cellX, cellY) = _canvasToCell(canvas);
      if (!_inBounds(cellX, cellY)) return;
      final threadId = _threadAtCell(cellX, cellY);
      if (threadId != null) {
        notifier.setSelectedThread(threadId);
        notifier.setDrawingMode(DrawingMode.draw);
      }
      return;
    }

    if (state.currentTool == DrawingTool.backstitch) {
      final gridPt = _canvasToGridPoint(canvas);
      final p = state.pattern;
      final gx = gridPt.dx;
      final gy = gridPt.dy;

      if (gx < 0 || gx > p.width || gy < 0 || gy > p.height) return;

      if (state.backstitchStartPoint == null) {
        notifier.setBackstitchStart(gridPt);
      } else {
        final start = state.backstitchStartPoint!;
        final sx = start.dx;
        final sy = start.dy;
        if (sx == gx && sy == gy) {
          notifier.setBackstitchStart(null);
        } else if (state.selectedThreadId != null) {
          if (state.drawingMode == DrawingMode.erase) {
            notifier.removeBackstitchAt(sx, sy, gx, gy);
          } else {
            notifier.addStitch(BackStitch(
              x1: sx,
              y1: sy,
              x2: gx,
              y2: gy,
              threadId: state.selectedThreadId!,
            ));
          }
          notifier.setBackstitchStart(null);
        }
      }
      return;
    }

    final (cellX, cellY) = _canvasToCell(canvas);
    if (!_inBounds(cellX, cellY)) return;

    if (state.drawingMode == DrawingMode.erase) {
      notifier.removeStitchesAt(cellX, cellY);
      return;
    }

    if (state.selectedThreadId == null) return;

    final (subX, subY) = _subCellPos(canvas, cellX, cellY);
    final stitch = _buildStitch(
        state.currentTool, cellX, cellY, state.selectedThreadId!, subX, subY);
    if (stitch != null) notifier.addStitch(stitch);
  }

  Stitch? _buildStitch(DrawingTool tool, int x, int y, String threadId,
      double subX, double subY) {
    return switch (tool) {
      DrawingTool.fullStitch => FullStitch(x: x, y: y, threadId: threadId),
      DrawingTool.halfForward =>
        HalfStitch(x: x, y: y, isForward: true, threadId: threadId),
      DrawingTool.halfBackward =>
        HalfStitch(x: x, y: y, isForward: false, threadId: threadId),
      DrawingTool.halfCross => HalfCrossStitch(
          x: x, y: y, half: _detectHalf(subX, subY), threadId: threadId),
      DrawingTool.quarterDiag => QuarterStitch(
          x: x,
          y: y,
          quadrant: _detectQuadrant(subX, subY),
          threadId: threadId),
      DrawingTool.quarterCross => QuarterCrossStitch(
          x: x,
          y: y,
          quadrant: _detectQuadrant(subX, subY),
          threadId: threadId),
      DrawingTool.backstitch => null,
    };
  }

  // ─── Pointer event handling ───────────────────────────────────────────────

  bool get _isPanMode =>
      ref.read(editorProvider).drawingMode == DrawingMode.pan;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (mounted) setState(() => _mouseScreenPos = event.localPosition);

    // Apple Pencil double-tap → toggle erase/draw
    if (event.kind == PointerDeviceKind.stylus &&
        event.buttons == kSecondaryStylusButton) {
      ref.read(editorProvider.notifier).toggleDrawingMode();
      return;
    }

    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      if (_isPanMode) return; // pointer-move will handle panning
      _handleDrawAt(event.localPosition);
      return;
    }

    // Touch — set up pan/pinch start state
    if (_activePointers.length == 1) {
      _gestureStartOffset = _panOffset;
    } else if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartCenter = (pts[0] + pts[1]) / 2;
      _gestureStartScale = _scale;
      _gestureStartOffset = _panOffset;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      if (mounted) setState(() => _mouseScreenPos = event.localPosition);

      if (_isPanMode) {
        _pan(event.delta);
        return;
      }

      if (ref.read(editorProvider).drawingMode == DrawingMode.colorPicker) return;

      _handleDrawAt(event.localPosition);

      if (ref.read(editorProvider).currentTool == DrawingTool.backstitch) {
        final canvas = _screenToCanvas(event.localPosition);
        final gp = _canvasToGridPoint(canvas);
        if (mounted) setState(() => _backstitchHoverPoint = gp);
      }
      return;
    }

    // ── Touch gestures ───────────────────────────────────────────────────────
    if (_activePointers.length == 2) {
      // Pinch to zoom + two-finger pan
      final pts = _activePointers.values.toList();
      final currentDist = (pts[0] - pts[1]).distance;
      final currentCenter = (pts[0] + pts[1]) / 2;

      if (_pinchStartDistance > 0) {
        final newScale =
            (_gestureStartScale * currentDist / _pinchStartDistance)
                .clamp(0.1, 20.0);
        final scaleFactor = newScale / _gestureStartScale;
        final newOffset = _pinchStartCenter -
            (_pinchStartCenter - _gestureStartOffset) * scaleFactor +
            (currentCenter - _pinchStartCenter);
        setState(() {
          _scale = newScale;
          _panOffset = newOffset;
        });
      }
    } else if (_activePointers.length == 1) {
      if (_isPanMode) {
        _pan(event.delta);
      } else {
        final moved = (event.localPosition -
                (_activePointers.values.firstOrNull ?? event.localPosition))
            .distance;
        if (moved > 2.0) _handleDrawAt(event.localPosition);
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final pos = event.localPosition;
    final now = DateTime.now();
    final wasSinglePointer = _activePointers.length == 1;

    // Double-tap (touch only) → undo
    if (event.kind == PointerDeviceKind.touch && wasSinglePointer) {
      final timeSinceLast = _lastTouchUpTime != null
          ? now.difference(_lastTouchUpTime!)
          : const Duration(seconds: 1);
      final nearLast = _lastTouchUpPos != null
          ? (pos - _lastTouchUpPos!).distance < 60.0
          : false;

      if (timeSinceLast < const Duration(milliseconds: 350) && nearLast) {
        ref.read(editorProvider.notifier).undo();
        _lastTouchUpTime = null;
        _lastTouchUpPos = null;
        _activePointers.remove(event.pointer);
        return;
      }

      _lastTouchUpTime = now;
      _lastTouchUpPos = pos;

      if (!_isPanMode) _handleDrawAt(pos);
    }

    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _pinchStartDistance = 0;
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (mounted) setState(() => _mouseScreenPos = event.localPosition);

    final state = ref.read(editorProvider);
    if (state.currentTool == DrawingTool.backstitch &&
        state.backstitchStartPoint != null) {
      final canvas = _screenToCanvas(event.localPosition);
      final gp = _canvasToGridPoint(canvas);
      setState(() => _backstitchHoverPoint = gp);
    }
  }

  // ─── Scroll wheel: zoom + shift-scroll pan ────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;

    // Pinch-to-zoom on trackpad sends very small deltas; scroll wheel sends ±120.
    // Use shift+scroll (or horizontal scroll) for panning, vertical for zoom.
    if (event.kind == PointerDeviceKind.mouse && dx == 0) {
      // Scroll wheel or two-finger vertical swipe on trackpad → zoom
      _zoomAround(event.localPosition, dy > 0 ? 0.9 : 1.1);
    } else {
      // Trackpad two-finger pan (horizontal or mixed)
      _pan(Offset(-dx, -dy));
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final isErasing = state.drawingMode == DrawingMode.erase;

    return MouseRegion(
      cursor: _cursor(state),
      onHover: _onPointerHover,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerSignal: _onPointerSignal,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: CanvasPainter(
            pattern: state.pattern,
            cellSize: _cellSize,
            panOffset: _panOffset,
            scale: _scale,
            backstitchStartPoint: state.backstitchStartPoint,
            backstitchCurrentPoint: _backstitchHoverPoint,
            isErasing: isErasing,
            cursorScreenPos: isErasing ? _mouseScreenPos : null,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  MouseCursor _cursor(EditorState state) {
    return switch (state.drawingMode) {
      DrawingMode.pan => SystemMouseCursors.grab,
      DrawingMode.erase => SystemMouseCursors.none,
      DrawingMode.colorPicker => SystemMouseCursors.cell,
      DrawingMode.draw => SystemMouseCursors.precise,
    };
  }
}
