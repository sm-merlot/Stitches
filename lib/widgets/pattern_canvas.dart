import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
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

  // Trackpad pinch-to-zoom (macOS PointerPanZoom events)
  double _trackpadStartScale = 1.0;
  Offset _trackpadStartPanOffset = Offset.zero;

  // Double-tap detection (touch only)
  DateTime? _lastTouchUpTime;
  Offset? _lastTouchUpPos;

  // Cursor/hover tracking
  Offset? _backstitchHoverPoint;
  Offset? _mouseScreenPos;
  (int, int)? _stylusHoverCell;

  // Selection / move state
  Offset? _selectionAnchor;      // grid cell where rubber-band drag started
  bool _isMovingSelection = false;
  bool _hasDraggedSelection = false; // true once pointer moves during a rubber-band
  Offset? _moveDragStartCell;
  Offset _moveDelta = Offset.zero;

  // Paste preview origin (grid cell coords, top-left of where clipboard will land)
  Offset? _pasteOrigin;

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

    // Erase mode is handled uniformly regardless of the current drawing tool.
    if (state.drawingMode == DrawingMode.erase) {
      final (cellX, cellY) = _canvasToCell(canvas);
      if (_inBounds(cellX, cellY)) notifier.removeStitchesAt(cellX, cellY);
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
          notifier.addStitch(BackStitch(
            x1: sx,
            y1: sy,
            x2: gx,
            y2: gy,
            threadId: state.selectedThreadId!,
          ));
          notifier.setBackstitchStart(null);
        }
      }
      return;
    }

    final (cellX, cellY) = _canvasToCell(canvas);
    if (!_inBounds(cellX, cellY)) return;

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

  // ─── Paste centering ─────────────────────────────────────────────────────

  /// Returns the (minX, maxX, minY, maxY) cell-space bounding box of a stitch.
  (double, double, double, double) _stitchBounds(Stitch s) {
    return switch (s) {
      FullStitch(:final x, :final y) =>
        (x.toDouble(), x + 1.0, y.toDouble(), y + 1.0),
      HalfStitch(:final x, :final y) =>
        (x.toDouble(), x + 1.0, y.toDouble(), y + 1.0),
      QuarterStitch(:final x, :final y) =>
        (x.toDouble(), x + 1.0, y.toDouble(), y + 1.0),
      HalfCrossStitch(:final x, :final y) =>
        (x.toDouble(), x + 1.0, y.toDouble(), y + 1.0),
      QuarterCrossStitch(:final x, :final y) =>
        (x.toDouble(), x + 1.0, y.toDouble(), y + 1.0),
      BackStitch(:final x1, :final y1, :final x2, :final y2) => (
          math.min(x1, x2), math.max(x1, x2),
          math.min(y1, y2), math.max(y1, y2),
        ),
    };
  }

  /// Computes the (dx, dy) offset so the clipboard is centered on [cursorCell].
  (int, int) _centeredPasteOffset(Offset cursorCell, List<Stitch> clips) {
    if (clips.isEmpty) return (cursorCell.dx.toInt(), cursorCell.dy.toInt());
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in clips) {
      final (bx0, bx1, by0, by1) = _stitchBounds(s);
      if (bx0 < minX) minX = bx0;
      if (bx1 > maxX) maxX = bx1;
      if (by0 < minY) minY = by0;
      if (by1 > maxY) maxY = by1;
    }
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    return (
      (cursorCell.dx + 0.5 - centerX).round(),
      (cursorCell.dy + 0.5 - centerY).round(),
    );
  }

  // ─── Selection helpers ────────────────────────────────────────────────────

  Rect _buildSelRect(Offset a, Offset b) {
    return Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx) + 1,
      math.max(a.dy, b.dy) + 1,
    );
  }

  bool _cellInSelRect(int cellX, int cellY, Rect rect) =>
      cellX >= rect.left && cellX < rect.right &&
      cellY >= rect.top && cellY < rect.bottom;

  Offset _screenToSelCell(Offset screenPos) {
    final c = _screenToCanvas(screenPos);
    final (x, y) = _canvasToCell(c);
    final p = ref.read(editorProvider).pattern;
    return Offset(x.clamp(0, p.width - 1).toDouble(), y.clamp(0, p.height - 1).toDouble());
  }

  // ─── Pointer event handling ───────────────────────────────────────────────

  bool get _isPanMode =>
      ref.read(editorProvider).drawingMode == DrawingMode.pan;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (mounted) setState(() => _mouseScreenPos = event.localPosition);

    // Stylus touching down — clear hover preview
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      if (mounted) setState(() => _stylusHoverCell = null);
    }

    // Apple Pencil double-tap → toggle erase/draw (disabled in stitch mode)
    if (event.kind == PointerDeviceKind.stylus &&
        event.buttons == kSecondaryStylusButton) {
      if (!ref.read(editorProvider).stitchMode) {
        ref.read(editorProvider.notifier).toggleDrawingMode();
      }
      return;
    }

    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      if (_isPanMode) return;

      final mode = ref.read(editorProvider).drawingMode;

      if (mode == DrawingMode.select) {
        final cell = _screenToSelCell(event.localPosition);
        final sel = ref.read(editorProvider).selectionRect;
        if (sel != null && _cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
          setState(() {
            _isMovingSelection = true;
            _moveDragStartCell = cell;
            _moveDelta = Offset.zero;
          });
        } else {
          ref.read(editorProvider.notifier).setSelectionRect(null);
          setState(() {
            _selectionAnchor = cell;
            _isMovingSelection = false;
            _hasDraggedSelection = false;
          });
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final origin = _pasteOrigin;
        final clips = ref.read(editorProvider).clipboard;
        if (origin != null && clips != null) {
          final (dx, dy) = _centeredPasteOffset(origin, clips);
          ref.read(editorProvider.notifier).commitPaste(dx, dy);
        }
        return;
      }

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

      final mode = ref.read(editorProvider).drawingMode;

      if (mode == DrawingMode.select) {
        final cell = _screenToSelCell(event.localPosition);
        if (_isMovingSelection && _moveDragStartCell != null) {
          setState(() => _moveDelta = cell - _moveDragStartCell!);
        } else if (_selectionAnchor != null) {
          setState(() => _hasDraggedSelection = true);
          ref.read(editorProvider.notifier).setSelectionRect(
              _buildSelRect(_selectionAnchor!, cell));
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final c = _screenToCanvas(event.localPosition);
        final (cx, cy) = _canvasToCell(c);
        setState(() => _pasteOrigin = Offset(cx.toDouble(), cy.toDouble()));
        return;
      }

      if (mode == DrawingMode.colorPicker) return;

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
        _handleDrawAt(event.localPosition);
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final pos = event.localPosition;
    final now = DateTime.now();
    final wasSinglePointer = _activePointers.length == 1;

    // Commit move drag
    if (_isMovingSelection) {
      final dx = _moveDelta.dx.round();
      final dy = _moveDelta.dy.round();
      if (dx != 0 || dy != 0) {
        ref.read(editorProvider.notifier).moveSelection(dx, dy);
      } else {
        // Single click inside selection with no movement → deselect
        ref.read(editorProvider.notifier).setSelectionRect(null);
      }
      setState(() {
        _isMovingSelection = false;
        _moveDragStartCell = null;
        _moveDelta = Offset.zero;
      });
      _activePointers.remove(event.pointer);
      return;
    }

    // Finalize rubber-band selection
    if (_selectionAnchor != null) {
      final cell = _screenToSelCell(pos);
      final rect = _buildSelRect(_selectionAnchor!, cell);
      // Only keep selection if the user actually dragged; a bare click deselects
      ref.read(editorProvider.notifier).setSelectionRect(
          _hasDraggedSelection && rect.width >= 1 && rect.height >= 1 ? rect : null);
      setState(() {
        _selectionAnchor = null;
        _hasDraggedSelection = false;
      });
      _activePointers.remove(event.pointer);
      return;
    }

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

  // ─── Trackpad pinch-to-zoom (macOS) ──────────────────────────────────────

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadStartScale = _scale;
    _trackpadStartPanOffset = _panOffset;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    setState(() {
      final newScale =
          (_trackpadStartScale * event.scale).clamp(0.1, 20.0);
      // Zoom around the focal point and apply cumulative pan from the gesture.
      // event.scale and event.pan are both cumulative since the gesture started.
      _panOffset = event.localPosition -
          (event.localPosition - _trackpadStartPanOffset) *
              (newScale / _trackpadStartScale) +
          event.pan;
      _scale = newScale;
    });
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (mounted) setState(() => _mouseScreenPos = event.localPosition);

    final state = ref.read(editorProvider);

    // Apple Pencil hover: highlight the cell the stylus is pointing at.
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      final c = _screenToCanvas(event.localPosition);
      final cell = _canvasToCell(c);
      final p = state.pattern;
      if (cell.$1 >= 0 && cell.$1 < p.width &&
          cell.$2 >= 0 && cell.$2 < p.height) {
        if (mounted) setState(() => _stylusHoverCell = cell);
      } else {
        if (mounted) setState(() => _stylusHoverCell = null);
      }
    }

    if (state.drawingMode == DrawingMode.paste) {
      final c = _screenToCanvas(event.localPosition);
      final (cx, cy) = _canvasToCell(c);
      if (mounted) setState(() => _pasteOrigin = Offset(cx.toDouble(), cy.toDouble()));
      return;
    }

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
    final isDrawCursor = state.drawingMode == DrawingMode.draw;
    final isColorPickerCursor = state.drawingMode == DrawingMode.colorPicker;

    // Compute ghost stitches for paste preview or move drag
    List<Stitch>? ghostStitches;
    if (state.drawingMode == DrawingMode.paste &&
        _pasteOrigin != null &&
        state.clipboard != null) {
      final (dx, dy) = _centeredPasteOffset(_pasteOrigin!, state.clipboard!);
      ghostStitches =
          state.clipboard!.map((s) => EditorState.offsetStitch(s, dx, dy)).toList();
    } else if (_isMovingSelection && state.selectionRect != null) {
      final dx = _moveDelta.dx.round();
      final dy = _moveDelta.dy.round();
      ghostStitches =
          state.selectedStitches.map((s) => EditorState.offsetStitch(s, dx, dy)).toList();
    }

    return MouseRegion(
      cursor: _cursor(state),
      onExit: (_) { if (mounted) setState(() { _mouseScreenPos = null; _stylusHoverCell = null; }); },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
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
            isDrawCursor: isDrawCursor,
            isColorPickerCursor: isColorPickerCursor,
            cursorScreenPos: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                ? null
                : _mouseScreenPos,
            aidaColor: state.pattern.aidaColor,
            selectionRect: state.selectionRect,
            ghostStitches: ghostStitches,
            ghostThreads: state.drawingMode == DrawingMode.paste
                ? state.clipboardThreads
                : null,
            stitchMode: state.stitchMode,
            stitchViewMode: state.stitchViewMode,
            stitchFocusThreadId: state.stitchFocusThreadId,
            referenceImage: state.referenceImage,
            referenceOpacity: state.referenceOpacity,
            referenceVisible: state.referenceVisible,
            stylusHoverCell: _stylusHoverCell,
            stylusHoverColor: state.selectedThread?.color,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  MouseCursor _cursor(EditorState state) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return MouseCursor.defer;
    }
    return switch (state.drawingMode) {
      DrawingMode.pan => SystemMouseCursors.grab,
      DrawingMode.erase => SystemMouseCursors.none,
      DrawingMode.colorPicker => SystemMouseCursors.none,
      DrawingMode.draw => SystemMouseCursors.none,
      DrawingMode.select => SystemMouseCursors.precise,
      DrawingMode.paste => SystemMouseCursors.precise,
    };
  }
}
