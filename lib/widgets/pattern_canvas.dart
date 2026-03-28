import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart';
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

  // Whether Ctrl is currently held — switches paste from single-stamp to multi-stamp.
  bool _ctrlHeld = false;

  // Whether Shift is currently held — enables edge snapping in paste mode.
  bool _shiftHeld = false;

  // ── Palette override cache ──────────────────────────────────────────────────
  // Rebuilt only when snippetPalettes identity or active index actually changes,
  // so the same Map instance is reused across builds and shouldRepaint works.
  List<Object> _lastPalettes = const [];
  int _lastPaletteIdx = -1;
  Map<String, Color>? _paletteOverride;

  // Guard to fire flood fill only once per tap (not repeatedly on drag).
  bool _fillFired = false;

  // ── Layer visibility warning ───────────────────────────────────────────────
  String? _warningMessage;
  Timer? _warningTimer;
  // Suppresses repeat warnings within a single pointer-down → up gesture.
  bool _warnedThisGesture = false;

  // ── Frame-coalesced rebuild ────────────────────────────────────────────────
  // Pointer events (pan, hover, pinch) can fire at 120 Hz. Calling setState on
  // every event saturates the UI thread and causes a backlog that freezes input
  // after gestures end. Instead, mutate fields directly and schedule at most
  // one rebuild per display frame.
  bool _rebuildScheduled = false;

  void _scheduleRebuild() {
    if (_rebuildScheduled || !mounted) return;
    _rebuildScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    _warningTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  void _showWarning(String message) {
    if (_warnedThisGesture) return;
    _warnedThisGesture = true;
    _warningTimer?.cancel();
    setState(() => _warningMessage = message);
    _warningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _warningMessage = null);
    });
  }

  /// Returns true if stitch [s] occupies cell (x, y).
  /// Uses EditorState.cellCoords for non-backstitch types; skips backstitches.
  bool _stitchAtCell(Stitch s, int x, int y) {
    final coords = EditorState.cellCoords(s);
    return coords != null && coords.$1 == x && coords.$2 == y;
  }

  /// Checks whether the current draw/erase at (cellX, cellY) would be invisible
  /// due to layer visibility issues. Shows a warning and returns if so.
  void _checkLayerWarning(EditorState state, int cellX, int cellY) {
    final activeLayer = state.activeLayer;
    final layers = state.pattern.layers;

    if (state.drawingMode == DrawingMode.erase) {
      // Warn if active layer has no stitch at this cell but other layers do.
      final activeHasStitch = activeLayer.stitches.any((s) => _stitchAtCell(s, cellX, cellY));
      if (!activeHasStitch) {
        final othersHaveStitch = layers.any((l) =>
            l.id != activeLayer.id &&
            l.visible &&
            l.stitches.any((s) => _stitchAtCell(s, cellX, cellY)));
        if (othersHaveStitch) {
          _showWarning('Nothing to erase on active layer here — check other layers');
        }
      }
    } else if (state.drawingMode == DrawingMode.draw) {
      if (!activeLayer.visible) {
        _showWarning('Active layer is hidden — drawing won\'t be visible');
        return;
      }
      // Warn if a fully-opaque layer above covers this cell with a full stitch.
      final activeIdx = layers.indexWhere((l) => l.id == activeLayer.id);
      if (activeIdx >= 0) {
        for (var i = activeIdx + 1; i < layers.length; i++) {
          final above = layers[i];
          if (!above.visible || above.opacity < 1.0) continue;
          final covered = above.stitches.any((s) => s is FullStitch && _stitchAtCell(s, cellX, cellY));
          if (covered) {
            _showWarning('"${above.name}" covers this cell — drawing won\'t be visible');
            return;
          }
        }
      }
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl != _ctrlHeld || shift != _shiftHeld) {
      setState(() {
        _ctrlHeld = ctrl;
        _shiftHeld = shift;
      });
    }
    return false; // don't consume the event
  }

  void _onGlobalPointerEvent(PointerEvent event) {
    if (!mounted) return;
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) { return; }

    if (event is PointerAddedEvent) {
      // Pencil entered hover range — try to update hover cell from global position.
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final local = box.globalToLocal(event.position);
      final c = _screenToCanvas(local);
      final cell = _canvasToCell(c);
      final p = ref.read(editorProvider).pattern;
      if (cell.$1 >= 0 && cell.$1 < p.width && cell.$2 >= 0 && cell.$2 < p.height) {
        _stylusHoverCell = cell;
        _scheduleRebuild();
      }
    } else if (event is PointerRemovedEvent) {
      // Pencil left hover range — clear cell.
      _stylusHoverCell = null;
      _scheduleRebuild();
    }
  }

  double get _cellSize => _baseCellSize;

  /// Returns a stable [Map] instance for the active snippet palette override,
  /// rebuilding it only when [state.snippetPalettes] identity or the active
  /// index changes. This lets [CanvasStaticPainter.shouldRepaint] use a simple
  /// identity comparison instead of deep equality.
  Map<String, Color>? _getOrBuildPaletteOverride(EditorState state) {
    final palettes = state.snippetPalettes;
    final idx = state.snippetActivePaletteIndex;
    if (identical(_lastPalettes, palettes) && _lastPaletteIdx == idx) {
      return _paletteOverride;
    }
    _lastPalettes = palettes;
    _lastPaletteIdx = idx;
    if (palettes.length <= 1 || idx == 0 || idx >= palettes.length) {
      return _paletteOverride = null;
    }
    final primary = palettes[0];
    final active = palettes[idx];
    final map = <String, Color>{};
    for (var i = 0; i < primary.threads.length; i++) {
      if (i < active.threads.length) {
        map[primary.threads[i].dmcCode] = active.threads[i].color;
      }
    }
    return _paletteOverride = map.isEmpty ? null : map;
  }

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
    _panOffset += delta;
    _scheduleRebuild();
  }

  void _zoomAround(Offset focalPoint, double factor) {
    final newScale = (_scale * factor).clamp(0.1, 20.0);
    final scaleFactor = newScale / _scale;
    _panOffset = focalPoint - (focalPoint - _panOffset) * scaleFactor;
    _scale = newScale;
    _scheduleRebuild();
  }

  void _handleDrawAt(Offset screenPos) {
    final state = ref.read(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final canvas = _screenToCanvas(screenPos);

    if (state.drawingMode == DrawingMode.colorPicker) {
      final (cellX, cellY) = _canvasToCell(canvas);
      if (!_inBounds(cellX, cellY)) return;
      notifier.pickColorAtCell(cellX, cellY);
      return;
    }

    // Erase mode is handled uniformly regardless of the current drawing tool.
    if (state.drawingMode == DrawingMode.erase) {
      final (cellX, cellY) = _canvasToCell(canvas);
      if (_inBounds(cellX, cellY)) _checkLayerWarning(state, cellX, cellY);
      if (state.fillEraseActive) {
        if (!_inBounds(cellX, cellY)) return;
        if (_fillFired) return;
        _fillFired = true;
        notifier.floodFill(cellX, cellY, erase: true);
      } else if (state.eraserSize > 1) {
        notifier.removeStitchesInBox(cellX, cellY, state.eraserSize);
      } else {
        if (_inBounds(cellX, cellY)) notifier.removeStitchesAt(cellX, cellY);
      }
      return;
    }

    if (state.currentTool == DrawingTool.fill) {
      final (cellX, cellY) = _canvasToCell(canvas);
      if (!_inBounds(cellX, cellY)) return;
      // Flood fill is triggered once per tap, not on drag — guard with a flag.
      if (_fillFired) return;
      _fillFired = true;
      notifier.floodFill(cellX, cellY, erase: false);
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

    _checkLayerWarning(state, cellX, cellY);

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
      DrawingTool.fill => null,
      DrawingTool.fillErase => null,
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

  /// Like [_centeredPasteOffset] but, when Shift is held, snaps clipboard edges
  /// to canvas boundaries and same-colour stitches. X and Y are snapped
  /// independently so corner placement always works correctly.
  ///
  /// Canvas-edge snapping triggers based on **cursor proximity** to the canvas
  /// edge (not clipboard-edge distance) so it works regardless of clipboard size.
  (int, int) _pasteOffset(Offset cursorCell, List<Stitch> clips) {
    final (cx, cy) = _centeredPasteOffset(cursorCell, clips);
    if (!_shiftHeld || clips.isEmpty) return (cx, cy);

    // Clipboard bounding box in stitch coords.
    var clipMinX = double.infinity, clipMaxX = double.negativeInfinity;
    var clipMinY = double.infinity, clipMaxY = double.negativeInfinity;
    for (final s in clips) {
      final (bx0, bx1, by0, by1) = _stitchBounds(s);
      if (bx0 < clipMinX) clipMinX = bx0;
      if (bx1 > clipMaxX) clipMaxX = bx1;
      if (by0 < clipMinY) clipMinY = by0;
      if (by1 > clipMaxY) clipMaxY = by1;
    }

    final state = ref.read(editorProvider);
    final w = state.pattern.width.toDouble();
    final h = state.pattern.height.toDouble();
    const edgeThreshold = 3.0;

    // Canvas-edge snapping: trigger when the clipboard EDGE would land within
    // edgeThreshold cells of the canvas edge/centre (natural centered placement,
    // before snapping).  This is more intuitive than cursor-proximity — the user
    // just drags the snippet close to the edge and it locks on.  When both left
    // and right (or top and bottom) are equidistant, left/top wins.
    final cxd = cx.toDouble();
    final cyd = cy.toDouble();
    final leftDist    = (clipMinX + cxd).abs();
    final rightDist   = (w - clipMaxX - cxd).abs();
    final topDist     = (clipMinY + cyd).abs();
    final bottomDist  = (h - clipMaxY - cyd).abs();
    final centreXDist = ((clipMinX + clipMaxX) / 2 + cxd - w / 2).abs();
    final centreYDist = ((clipMinY + clipMaxY) / 2 + cyd - h / 2).abs();

    double? snapDx, snapDy;
    if (leftDist <= edgeThreshold && leftDist <= rightDist) {
      snapDx = -clipMinX;                              // clipboard left → canvas left
    } else if (rightDist <= edgeThreshold) {
      snapDx = w - clipMaxX;                           // clipboard right → canvas right
    } else if (centreXDist <= edgeThreshold) {
      snapDx = w / 2 - (clipMinX + clipMaxX) / 2;     // clipboard centre → canvas centre
    }
    if (topDist <= edgeThreshold && topDist <= bottomDist) {
      snapDy = -clipMinY;                              // clipboard top → canvas top
    } else if (bottomDist <= edgeThreshold) {
      snapDy = h - clipMaxY;                           // clipboard bottom → canvas bottom
    } else if (centreYDist <= edgeThreshold) {
      snapDy = h / 2 - (clipMinY + clipMaxY) / 2;     // clipboard centre → canvas centre
    }

    // Same-colour stitch snapping: butt clipboard edge flush against the nearest
    // canvas stitch sharing a thread colour.  Only runs on axes not already
    // locked to a canvas edge, and uses a distance-from-placed-edge threshold.
    const stitchThreshold = 3.0;
    final clipThreadIds = clips.map((s) => s.threadId).toSet();
    if (snapDx == null || snapDy == null) {
      final xCandidates = <double>[];
      final yCandidates = <double>[];
      for (final cs in state.pattern.stitches) {
        if (!clipThreadIds.contains(cs.threadId)) continue;
        final (bx0, bx1, by0, by1) = _stitchBounds(cs);
        if (snapDx == null) {
          xCandidates.add(bx1 - clipMinX); // clipboard left butts canvas stitch right
          xCandidates.add(bx0 - clipMaxX); // clipboard right butts canvas stitch left
        }
        if (snapDy == null) {
          yCandidates.add(by1 - clipMinY); // clipboard top butts canvas stitch bottom
          yCandidates.add(by0 - clipMaxY); // clipboard bottom butts canvas stitch top
        }
      }
      double? pickNearest(List<double> candidates, double current) {
        double? best;
        double bestDist = stitchThreshold;
        for (final c in candidates) {
          final d = (c - current).abs();
          if (d <= bestDist) { bestDist = d; best = c; }
        }
        return best;
      }
      snapDx ??= pickNearest(xCandidates, cx.toDouble());
      snapDy ??= pickNearest(yCandidates, cy.toDouble());
    }

    return (
      (snapDx ?? cx.toDouble()).round(),
      (snapDy ?? cy.toDouble()).round(),
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
    _mouseScreenPos = event.localPosition;
    _warnedThisGesture = false;
    _scheduleRebuild();

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
      if (event.buttons == kMiddleMouseButton) return; // pan on move
      if (_isPanMode) return;

      final mode = ref.read(editorProvider).drawingMode;

      if (mode == DrawingMode.select) {
        final editorState = ref.read(editorProvider);
        final cell = _screenToSelCell(event.localPosition);
        final sel = editorState.selectionRect;
        final inStitchMode = editorState.stitchMode;
        if (!inStitchMode && sel != null && _cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
          setState(() {
            _isMovingSelection = true;
            _moveDragStartCell = cell;
            _moveDelta = Offset.zero;
          });
        } else {
          if (!inStitchMode) ref.read(editorProvider.notifier).setSelectionRect(null);
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
          final (dx, dy) = _pasteOffset(origin, clips);
          ref.read(editorProvider.notifier).commitPaste(dx, dy);
          if (!_ctrlHeld) ref.read(editorProvider.notifier).cancelSelection();
        }
        return;
      }

      _handleDrawAt(event.localPosition);
      return;
    }

    // Touch — handle special modes before pan/pinch setup
    if (_activePointers.length == 1) {
      final mode = ref.read(editorProvider).drawingMode;
      if (mode == DrawingMode.select) {
        final editorState = ref.read(editorProvider);
        final cell = _screenToSelCell(event.localPosition);
        final sel = editorState.selectionRect;
        final inStitchMode = editorState.stitchMode;
        if (!inStitchMode && sel != null && _cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
          setState(() {
            _isMovingSelection = true;
            _moveDragStartCell = cell;
            _moveDelta = Offset.zero;
          });
        } else {
          if (!inStitchMode) ref.read(editorProvider.notifier).setSelectionRect(null);
          setState(() {
            _selectionAnchor = cell;
            _isMovingSelection = false;
            _hasDraggedSelection = false;
          });
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final c = _screenToCanvas(event.localPosition);
        final (cx, cy) = _canvasToCell(c);
        setState(() => _pasteOrigin = Offset(cx.toDouble(), cy.toDouble()));
        // Commit on pointer up to avoid double-tap undo collision
        return;
      }
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
      _mouseScreenPos = event.localPosition;

      // Keep hover cell updated during active strokes.
      final c = _screenToCanvas(event.localPosition);
      final cell = _canvasToCell(c);
      final p = ref.read(editorProvider).pattern;
      _stylusHoverCell = (cell.$1 >= 0 && cell.$1 < p.width &&
              cell.$2 >= 0 && cell.$2 < p.height)
          ? cell
          : null;
      _scheduleRebuild();

      if (_isPanMode || event.buttons == kMiddleMouseButton) {
        _pan(event.delta);
        return;
      }

      final mode = ref.read(editorProvider).drawingMode;

      if (mode == DrawingMode.select) {
        final cell = _screenToSelCell(event.localPosition);
        if (_isMovingSelection && _moveDragStartCell != null) {
          _moveDelta = cell - _moveDragStartCell!;
          _scheduleRebuild();
        } else if (_selectionAnchor != null) {
          _hasDraggedSelection = true;
          ref.read(editorProvider.notifier).setSelectionRect(
              _buildSelRect(_selectionAnchor!, cell));
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final c = _screenToCanvas(event.localPosition);
        final (cx, cy) = _canvasToCell(c);
        _pasteOrigin = Offset(cx.toDouble(), cy.toDouble());
        _scheduleRebuild();
        return;
      }

      if (mode == DrawingMode.colorPicker) return;

      _handleDrawAt(event.localPosition);

      if (ref.read(editorProvider).currentTool == DrawingTool.backstitch) {
        final canvas = _screenToCanvas(event.localPosition);
        _backstitchHoverPoint = _canvasToGridPoint(canvas);
        _scheduleRebuild();
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
        _scale = newScale;
        _panOffset = _pinchStartCenter -
            (_pinchStartCenter - _gestureStartOffset) * scaleFactor +
            (currentCenter - _pinchStartCenter);
        _scheduleRebuild();
      }
    } else if (_activePointers.length == 1) {
      final mode = ref.read(editorProvider).drawingMode;
      if (mode == DrawingMode.select) {
        final cell = _screenToSelCell(event.localPosition);
        if (_isMovingSelection && _moveDragStartCell != null) {
          _moveDelta = cell - _moveDragStartCell!;
          _scheduleRebuild();
        } else if (_selectionAnchor != null) {
          _hasDraggedSelection = true;
          ref.read(editorProvider.notifier).setSelectionRect(
              _buildSelRect(_selectionAnchor!, cell));
        }
      } else if (mode == DrawingMode.paste) {
        final c = _screenToCanvas(event.localPosition);
        final (cx, cy) = _canvasToCell(c);
        _pasteOrigin = Offset(cx.toDouble(), cy.toDouble());
        _scheduleRebuild();
      } else if (_isPanMode) {
        _pan(event.delta);
      } else {
        _handleDrawAt(event.localPosition);
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _fillFired = false;
    final pos = event.localPosition;
    final now = DateTime.now();
    final wasSinglePointer = _activePointers.length == 1;

    // Non-touch pointer lifted — clear hover cell
    if (event.kind != PointerDeviceKind.touch) {
      _stylusHoverCell = null;
      _scheduleRebuild();
    }

    // Touch paste — commit at current origin (set in _onPointerDown / _onPointerMove)
    if (event.kind == PointerDeviceKind.touch &&
        ref.read(editorProvider).drawingMode == DrawingMode.paste &&
        _pasteOrigin != null) {
      final clips = ref.read(editorProvider).clipboard;
      if (clips != null) {
        final (dx, dy) = _pasteOffset(_pasteOrigin!, clips);
        ref.read(editorProvider.notifier).commitPaste(dx, dy);
        if (!_ctrlHeld) ref.read(editorProvider.notifier).cancelSelection();
      }
      _pasteOrigin = null;
      _scheduleRebuild();
      _activePointers.remove(event.pointer);
      return;
    }

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
      _isMovingSelection = false;
      _moveDragStartCell = null;
      _moveDelta = Offset.zero;
      _scheduleRebuild();
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
      _selectionAnchor = null;
      _hasDraggedSelection = false;
      _scheduleRebuild();
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
    final newScale = (_trackpadStartScale * event.scale).clamp(0.1, 20.0);
    _panOffset = event.localPosition -
        (event.localPosition - _trackpadStartPanOffset) *
            (newScale / _trackpadStartScale) +
        event.pan;
    _scale = newScale;
    _scheduleRebuild();
  }

  void _onPointerHover(PointerHoverEvent event) {
    _mouseScreenPos = event.localPosition;

    final state = ref.read(editorProvider);

    // Highlight the cell under any hovering pointer (stylus, mouse, or unknown).
    // We don't guard by kind because Apple Pencil hover events on iPadOS may not
    // always arrive as PointerDeviceKind.stylus through this path.
    if (event.kind != PointerDeviceKind.touch) {
      final c = _screenToCanvas(event.localPosition);
      final cell = _canvasToCell(c);
      final p = state.pattern;
      _stylusHoverCell = (cell.$1 >= 0 && cell.$1 < p.width &&
              cell.$2 >= 0 && cell.$2 < p.height)
          ? cell
          : null;
    }

    if (state.drawingMode == DrawingMode.paste) {
      final c = _screenToCanvas(event.localPosition);
      final (cx, cy) = _canvasToCell(c);
      _pasteOrigin = Offset(cx.toDouble(), cy.toDouble());
      _scheduleRebuild();
      return;
    }

    if (state.currentTool == DrawingTool.backstitch &&
        state.backstitchStartPoint != null) {
      final canvas = _screenToCanvas(event.localPosition);
      _backstitchHoverPoint = _canvasToGridPoint(canvas);
    }

    _scheduleRebuild();
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
      final (dx, dy) = _pasteOffset(_pasteOrigin!, state.clipboard!);
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
      onExit: (_) { _mouseScreenPos = null; _stylusHoverCell = null; _scheduleRebuild(); },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Static layer: stitches, grid, labels.
            // Wrapped in RepaintBoundary so Flutter caches the GPU texture and
            // skips re-rasterisation when only cursor/hover/ghost state changes.
            RepaintBoundary(
              child: CustomPaint(
                painter: CanvasStaticPainter(
                  pattern: state.pattern,
                  cellSize: _cellSize,
                  panOffset: _panOffset,
                  scale: _scale,
                  aidaColor: state.pattern.aidaColor,
                  stitchMode: state.stitchMode,
                  blockMode: state.blockMode,
                  stitchCrossMode: state.stitchCrossMode,
                  stitchBackMode: state.stitchBackMode,
                  stitchFocusThreadId: state.stitchFocusThreadId,
                  referenceImage: state.referenceImage,
                  referenceOpacity: state.referenceOpacity,
                  referenceVisible: state.referenceVisible,
                  compositeThreadCache: state.compositeThreadCache,
                  paletteOverride: _getOrBuildPaletteOverride(state),
                ),
                isComplex: true,
                size: Size.infinite,
              ),
            ),
            // Layer visibility warning banner
            if (_warningMessage != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xF0F57C00),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _warningMessage!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Overlay layer: cursor, ghost stitches, selection, hover.
            // Repaints freely without touching the cached static layer.
            CustomPaint(
              painter: CanvasOverlayPainter(
                cellSize: _cellSize,
                panOffset: _panOffset,
                scale: _scale,
                aidaColor: state.pattern.aidaColor,
                patternThreads: state.pattern.threads,
                backstitchStartPoint: state.backstitchStartPoint,
                backstitchCurrentPoint: _backstitchHoverPoint,
                isErasing: isErasing,
                eraserSize: state.eraserSize,
                fillEraseActive: state.fillEraseActive,
                isDrawCursor: isDrawCursor,
                isColorPickerCursor: isColorPickerCursor,
                cursorScreenPos: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                    ? null
                    : _mouseScreenPos,
                selectionRect: state.selectionRect,
                ghostStitches: ghostStitches,
                ghostThreads: state.drawingMode == DrawingMode.paste
                    ? state.clipboardThreads
                    : null,
                ghostOpacity: state.drawingMode == DrawingMode.paste
                    ? 0.55
                    : 1.0,
                stylusHoverCell: _stylusHoverCell,
                stylusHoverColor: state.selectedThread?.color,
                stitchMode: state.stitchMode,
              ),
              size: Size.infinite,
            ),
          ],
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
      DrawingMode.paste => _ctrlHeld
          ? SystemMouseCursors.copy
          : _shiftHeld
              ? SystemMouseCursors.move
              : SystemMouseCursors.cell,
    };
  }
}
