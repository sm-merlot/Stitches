import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/page_layout.dart';
import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/settings_provider.dart';
import 'canvas_painter.dart';
import 'canvas_viewport.dart';

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
  // True while any gesture sequence that included ≥2 fingers is still active
  // (i.e. at least one finger from the pinch is still down).  Single-finger
  // draw/select/paste actions are suppressed during this window so that the
  // residual finger from a pinch never accidentally adds stitches.
  // Reset to false only when _activePointers becomes empty (all fingers up).
  bool _hadMultiTouch = false;

  // Trackpad pinch-to-zoom (macOS PointerPanZoom events)
  double _trackpadStartScale = 1.0;
  Offset _trackpadStartPanOffset = Offset.zero;

  // Double-tap / double-click detection
  DateTime? _lastTouchUpTime;
  Offset? _lastTouchUpPos;
  // Progress double-click/double-tap flood fill detection (stitch mode).
  // Detected at pointer-DOWN time (DOWN-to-DOWN): if the second DOWN arrives
  // within _kDoubleClickMs of the previous DOWN at a nearby screen position,
  // set _pendingDoubleClick so that pointer-UP does a flood fill instead of
  // a single toggle.
  DateTime?    _lastProgressDownTime;
  (int, int)?  _lastProgressDownCell;
  bool         _pendingDoubleClick = false;
  bool?        _wasProgressCellDone; // state of the cell BEFORE the last single-click toggle
  static const int _kDoubleClickMs = 500;

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
  // Live rubber-band rect during drag — only committed to provider on pointer up.
  Rect? _dragSelectionRect;

  // Paste preview origin (grid cell coords, top-left of where clipboard will land)
  Offset? _pasteOrigin;

  // Progress tracking — stitch mode tap/drag state
  Offset? _progressAnchor;           // cell coords where drag/tap started
  Offset? _progressAnchorScreen;     // screen pixels where drag started (for jitter threshold)
  bool _hasDraggedProgress = false;  // true once pointer moved > _kProgressDragThreshold px
  Rect? _progressDragRect;           // live region during drag (reuses selection overlay)
  BackStitch? _progressBackstitch;   // backstitch hit at pointer-down; tapped if no drag
  static const double _kProgressDragThreshold = 10.0; // screen-pixel minimum drag distance
  static const double _kBackstitchHitRadius = 0.3;    // cell units

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

  // ── Ghost stitch cache ────────────────────────────────────────────────────
  // Avoids re-allocating the offset stitch list on every build when the paste
  // offset and clipboard haven't changed.
  List<Stitch>? _cachedGhostStitches;
  (int, int)? _lastGhostDxDy;
  List<Stitch>? _lastGhostClipboard;

  // ── View position persistence ──────────────────────────────────────────────
  // Debounce timer used only for scroll-wheel zoom (no discrete end event).
  // All other gestures save directly on pointer-up / trackpad-zoom-end.
  Timer? _viewSaveTimer;

  // ── Canvas size tracking (updated via LayoutBuilder) ──────────────────────
  Size _canvasSize = Size.zero;

  void _saveViewPosition() {
    ref.read(editorProvider.notifier)
        .updateViewPosition(_panOffset.dx, _panOffset.dy, _scale);
  }

  void _debouncedSaveViewPosition() {
    _viewSaveTimer?.cancel();
    _viewSaveTimer = Timer(const Duration(milliseconds: 400), _saveViewPosition);
  }

  /// Compute pan/scale so [pageIndex] fills the canvas with padding, then
  /// animate to that view. Called when [EditorState.pendingFitPage] fires.
  void _fitToPage(EditorState state, int pageIndex) {
    final layout = state.pageLayout;
    if (layout == null) return;
    final size = _canvasSize;
    if (size.isEmpty) return;

    final (pageCol, pageRow) = layout.pageCoords(pageIndex);
    final rect = layout.nominalPageRect(pageCol, pageRow);
    if (rect.isEmpty) return;

    const padding = 24.0;
    final availW = size.width - padding * 2;
    final availH = size.height - padding * 2;
    final newScale = math.min(availW / (rect.width * _cellSize),
                              availH / (rect.height * _cellSize));
    final pagePixelW = rect.width * _cellSize * newScale;
    final pagePixelH = rect.height * _cellSize * newScale;
    final newPanX = padding + (availW - pagePixelW) / 2 - rect.left * _cellSize * newScale;
    final newPanY = padding + (availH - pagePixelH) / 2 - rect.top * _cellSize * newScale;

    setState(() {
      _scale = newScale;
      _panOffset = Offset(newPanX, newPanY);
    });
    ref.read(editorProvider.notifier).updateViewPosition(newPanX, newPanY, newScale);
  }

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
    // Restore saved view position from the loaded pattern (if any).
    final editorState = ref.read(editorProvider);
    if (editorState.viewScale > 0) {
      _scale = editorState.viewScale;
      _panOffset = Offset(editorState.viewPanX, editorState.viewPanY);
    }
  }

  @override
  void dispose() {
    _warningTimer?.cancel();
    _viewSaveTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  void _showWarning(String message) {
    if (_warnedThisGesture) return;
    _warnedThisGesture = true;
    _showWarningBanner(message);
  }

  /// Shows the warning banner without the per-gesture dedup guard.
  /// Used for warnings triggered outside pointer gestures (e.g. keyboard shortcuts).
  void _showWarningBanner(String message) {
    _warningTimer?.cancel();
    setState(() => _warningMessage = message);
    _warningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _warningMessage = null);
    });
  }

  /// Shows a bottom sheet letting the user confirm marking a dragged region done.
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

  /// Builds a [CanvasViewport] snapshot from the current pan/zoom state.
  /// Cheap — `CanvasViewport` is just three doubles + an Offset.
  CanvasViewport get _viewport => CanvasViewport(
        cellSize: _cellSize,
        panOffset: _panOffset,
        scale: _scale,
      );

  Offset _screenToCanvas(Offset screen) => _viewport.screenToCanvas(screen);

  Offset _canvasToGridPoint(Offset canvas) =>
      _viewport.canvasToGridPoint(canvas);

  (int, int) _canvasToCell(Offset canvas) => _viewport.canvasToCell(canvas);

  (double, double) _subCellPos(Offset canvas, int cellX, int cellY) =>
      _viewport.subCellPos(canvas, cellX, cellY);

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

  bool _screenOnCanvas(Offset screenPos) {
    final c = _screenToCanvas(screenPos);
    final p = ref.read(editorProvider).pattern;
    return c.dx >= 0 && c.dy >= 0 &&
        c.dx < p.width * _cellSize && c.dy < p.height * _cellSize;
  }

  void _pan(Offset delta) {
    _panOffset += delta;
    _scheduleRebuild();
  }

  void _zoomAround(Offset focalPoint, double factor) {
    final next = _viewport.zoomedAround(focalPoint, factor);
    _panOffset = next.panOffset;
    _scale = next.scale;
    _scheduleRebuild();
  }

  void _handleDrawAt(Offset screenPos) {
    final state = ref.read(editorProvider);
    if (!state.editMode) return;
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
        // Clear stale hover so preview doesn't flash to the old end point.
        _backstitchHoverPoint = null;
      } else {
        final start = state.backstitchStartPoint!;
        final sx = start.dx;
        final sy = start.dy;
        if (sx == gx && sy == gy) {
          notifier.setBackstitchStart(null);
          _backstitchHoverPoint = null;
        } else if (state.selectedThreadId != null) {
          notifier.addStitch(BackStitch(
            x1: sx,
            y1: sy,
            x2: gx,
            y2: gy,
            threadId: state.selectedThreadId!,
          ));
          // Chain mode: end point becomes new start for next backstitch.
          // Activated by holding Ctrl (desktop) or chain toggle (touch).
          final chain = _ctrlHeld || state.backstitchChainMode;
          notifier.setBackstitchStart(chain ? gridPt : null);
          if (!chain) _backstitchHoverPoint = null;
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

  // ─── Progress double-click helper ─────────────────────────────────────────

  /// Call on every pointer-DOWN that would start a progress tap.
  /// Sets [_pendingDoubleClick] if this DOWN is on the same cell as the
  /// previous DOWN and within the double-click time threshold.
  void _checkProgressDoubleClick(Offset screenPos) {
    final now = DateTime.now();
    final last = _lastProgressDownTime;
    final lastCell = _lastProgressDownCell;
    final c = _screenToCanvas(screenPos);
    final (cx, cy) = _canvasToCell(c);
    if (last != null &&
        lastCell != null &&
        now.difference(last).inMilliseconds < _kDoubleClickMs &&
        lastCell.$1 == cx && lastCell.$2 == cy) {
      _pendingDoubleClick = true;
      // Reset so a triple-click doesn't fire a second flood fill.
      _lastProgressDownTime = null;
      _lastProgressDownCell = null;
    } else {
      _pendingDoubleClick = false;
      _lastProgressDownTime = now;
      _lastProgressDownCell = (cx, cy);
    }
  }

  /// Returns the topmost visible BackStitch within [_kBackstitchHitRadius] cell
  /// units of [screenPos], respecting focus mode. Null if none hit.
  BackStitch? _getBackstitchHit(Offset screenPos) {
    final s = ref.read(editorProvider);
    // Cross-stitch focus mode: backstitch hits are ignored so cross-stitch taps work normally.
    if (s.stitchCrossMode) return null;
    final focusId = s.stitchFocusThreadId;
    final canvas = _screenToCanvas(screenPos);
    final px = canvas.dx / _cellSize;
    final py = canvas.dy / _cellSize;
    BackStitch? result;
    for (final layer in s.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (stitch is! BackStitch) continue;
        if (focusId != null && stitch.threadId != focusId) continue;
        // Point-to-segment distance in cell space.
        final dx = stitch.x2 - stitch.x1, dy = stitch.y2 - stitch.y1;
        final lenSq = dx * dx + dy * dy;
        double dist;
        if (lenSq == 0) {
          final ex = px - stitch.x1, ey = py - stitch.y1;
          dist = math.sqrt(ex * ex + ey * ey);
        } else {
          final t = ((px - stitch.x1) * dx + (py - stitch.y1) * dy) / lenSq;
          final tc = t.clamp(0.0, 1.0);
          final nx = stitch.x1 + tc * dx - px;
          final ny = stitch.y1 + tc * dy - py;
          dist = math.sqrt(nx * nx + ny * ny);
        }
        if (dist < _kBackstitchHitRadius) result = stitch; // last = topmost layer
      }
    }
    return result;
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

  /// Returns true when [screenPos] is inside a nav-button hit area.
  /// Used to suppress accidental stitch operations when the user taps a nav
  /// button (which is a child of the Listener, so raw events reach us too).
  bool _isNavZone(Offset screenPos) {
    final s = ref.read(editorProvider);
    if (!s.stitchMode || !s.pattern.pageConfig.enabled || s.pageLayout == null) {
      return false;
    }
    // Nav buttons: left/right arrows (36 px wide + 4 margin each side = ~44 px)
    // up/down arrows (36 px tall + margins).  Page indicator at very bottom.
    const double edgeG = 56.0;
    const double bottomG = 100.0;
    return screenPos.dx < edgeG ||
        screenPos.dx > _canvasSize.width - edgeG ||
        screenPos.dy < edgeG ||
        screenPos.dy > _canvasSize.height - bottomG;
  }

  bool get _isPanMode =>
      ref.read(editorProvider).drawingMode == DrawingMode.pan;

  void _onPointerDown(PointerDownEvent event) {
    // Reclaim keyboard focus so shortcuts keep working after AppBar buttons,
    // dialogs, or bottom sheets have taken it away.
    Focus.maybeOf(context)?.requestFocus();
    _activePointers[event.pointer] = event.localPosition;
    _mouseScreenPos = event.localPosition;
    _warnedThisGesture = false;
    _scheduleRebuild();

    // Apple Pencil double-tap button
    if (event.kind == PointerDeviceKind.stylus &&
        event.buttons == kSecondaryStylusButton) {
      final state = ref.read(editorProvider);
      if (state.drawingMode == DrawingMode.paste) {
        // In paste mode, pencil button commits paste (same as a tap/screen button)
        final origin = _pasteOrigin;
        final clips = state.clipboard;
        if (origin != null && clips != null) {
          final (dx, dy) = _pasteOffset(origin, clips);
          ref.read(editorProvider.notifier).commitPaste(dx, dy);
          if (!_ctrlHeld) ref.read(editorProvider.notifier).cancelSelection();
        }
      } else if (!state.stitchMode) {
        // Outside paste mode: toggle erase/draw
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
        // In stitch mode, select-drag marks a region done instead of selecting.
        if (inStitchMode) {
          // If a progress region is active, clear it on tap without toggling
          // the cell underneath.
          if (editorState.progressRegion != null) {
            ref.read(editorProvider.notifier).setProgressRegion(null);
            return;
          }
          if (_screenOnCanvas(event.localPosition) && !_isNavZone(event.localPosition)) {
            final bs = _getBackstitchHit(event.localPosition);
            if (bs == null) _checkProgressDoubleClick(event.localPosition);
            setState(() {
              _progressAnchor = cell;
              _progressAnchorScreen = event.localPosition;
              _progressBackstitch = bs;
              _hasDraggedProgress = false;
              _progressDragRect = null;
            });
          }
          return;
        }
        if (sel != null && _cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
          if (editorState.selectedStitches.isEmpty) {
            _showWarningBanner(kWarnNothingToMove +
                (editorState.canvasSelectionMode ? '' : kLayerHint));
          } else {
            setState(() {
              _isMovingSelection = true;
              _moveDragStartCell = cell;
              _moveDelta = Offset.zero;
            });
          }
        } else {
          ref.read(editorProvider.notifier).setSelectionRect(null);
          if (_screenOnCanvas(event.localPosition)) {
            setState(() {
              _selectionAnchor = cell;
              _isMovingSelection = false;
              _hasDraggedSelection = false;
            });
          }
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final pencilConfirm =
            ref.read(settingsProvider).pencilPasteConfirm;
        if (pencilConfirm) {
          // Pencil-confirm mode: stylus tap positions ghost, finger confirms.
          final c = _screenToCanvas(event.localPosition);
          final (cx, cy) = _canvasToCell(c);
          setState(() => _pasteOrigin = Offset(cx.toDouble(), cy.toDouble()));
        } else {
          final origin = _pasteOrigin;
          final clips = ref.read(editorProvider).clipboard;
          if (origin != null && clips != null) {
            final (dx, dy) = _pasteOffset(origin, clips);
            ref.read(editorProvider.notifier).commitPaste(dx, dy);
            if (!_ctrlHeld) ref.read(editorProvider.notifier).cancelSelection();
          }
        }
        return;
      }

      // In stitch mode, start a progress anchor instead of drawing.
      if (ref.read(editorProvider).stitchMode) {
        if (!_isNavZone(event.localPosition)) {
          final cell = _screenToSelCell(event.localPosition);
          final bs = _getBackstitchHit(event.localPosition);
          if (bs == null) _checkProgressDoubleClick(event.localPosition);
          setState(() {
            _progressAnchor = cell;
            _progressBackstitch = bs;
            _hasDraggedProgress = false;
            _progressDragRect = null;
          });
        }
        return;
      }

      _handleDrawAt(event.localPosition);
      return;
    }

    // Touch — handle special modes before pan/pinch setup.
    // Skip drawing/select/paste setup if this finger is the residual from a
    // pinch — it should only pan until all fingers are lifted.
    if (_activePointers.length == 1 && !_hadMultiTouch) {
      final mode = ref.read(editorProvider).drawingMode;
      if (mode == DrawingMode.select) {
        final editorState = ref.read(editorProvider);
        final cell = _screenToSelCell(event.localPosition);
        final sel = editorState.selectionRect;
        final inStitchMode = editorState.stitchMode;
        // In stitch mode, select-drag marks a region done instead of selecting.
        if (inStitchMode) {
          // If a progress region is active, clear it on tap without toggling
          // the cell underneath.
          if (editorState.progressRegion != null) {
            ref.read(editorProvider.notifier).setProgressRegion(null);
            return;
          }
          if (_screenOnCanvas(event.localPosition) && !_isNavZone(event.localPosition)) {
            final bs = _getBackstitchHit(event.localPosition);
            if (bs == null) _checkProgressDoubleClick(event.localPosition);
            setState(() {
              _progressAnchor = cell;
              _progressAnchorScreen = event.localPosition;
              _progressBackstitch = bs;
              _hasDraggedProgress = false;
              _progressDragRect = null;
            });
          }
          return;
        }
        if (sel != null && _cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
          if (editorState.selectedStitches.isEmpty) {
            _showWarningBanner(kWarnNothingToMove +
                (editorState.canvasSelectionMode ? '' : kLayerHint));
          } else {
            setState(() {
              _isMovingSelection = true;
              _moveDragStartCell = cell;
              _moveDelta = Offset.zero;
            });
          }
        } else {
          ref.read(editorProvider.notifier).setSelectionRect(null);
          if (_screenOnCanvas(event.localPosition)) {
            setState(() {
              _selectionAnchor = cell;
              _isMovingSelection = false;
              _hasDraggedSelection = false;
            });
          }
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final pencilConfirm =
            ref.read(settingsProvider).pencilPasteConfirm;
        if (pencilConfirm) {
          // Pencil-confirm mode: finger tap commits at current ghost position.
          final origin = _pasteOrigin;
          final clips = ref.read(editorProvider).clipboard;
          if (origin != null && clips != null) {
            final (dx, dy) = _pasteOffset(origin, clips);
            ref.read(editorProvider.notifier).commitPaste(dx, dy);
            if (!_ctrlHeld) ref.read(editorProvider.notifier).cancelSelection();
          }
        } else {
          final c = _screenToCanvas(event.localPosition);
          final (cx, cy) = _canvasToCell(c);
          setState(() => _pasteOrigin = Offset(cx.toDouble(), cy.toDouble()));
          // Commit on pointer up to avoid double-tap undo collision
        }
        return;
      }

      // In stitch mode, start a progress anchor instead of drawing.
      if (ref.read(editorProvider).stitchMode) {
        if (!_isNavZone(event.localPosition)) {
          final cell = _screenToSelCell(event.localPosition);
          _checkProgressDoubleClick(event.localPosition);
          setState(() {
            _progressAnchor = cell;
            _hasDraggedProgress = false;
            _progressDragRect = null;
          });
        }
        return;
      }
    }

    // Touch — set up pan/pinch start state
    if (_activePointers.length == 1) {
      _gestureStartOffset = _panOffset;
    } else if (_activePointers.length == 2) {
      _hadMultiTouch = true;
      // Cancel any stitch-mode progress anchor set by the first finger so
      // a pan/pinch doesn't accidentally mark cells on pointer-up.
      _progressAnchor = null;
      _progressAnchorScreen = null;
      _progressBackstitch = null;
      _hasDraggedProgress = false;
      _progressDragRect = null;
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

      if (mode == DrawingMode.select && !ref.read(editorProvider).stitchMode) {
        final cell = _screenToSelCell(event.localPosition);
        if (_isMovingSelection && _moveDragStartCell != null) {
          _moveDelta = cell - _moveDragStartCell!;
          _scheduleRebuild();
        } else if (_selectionAnchor != null) {
          _hasDraggedSelection = true;
          _dragSelectionRect = _buildSelRect(_selectionAnchor!, cell);
          _scheduleRebuild();
        }
        return;
      }

      if (mode == DrawingMode.paste) {
        final c = _screenToCanvas(event.localPosition);
        final (cx, cy) = _canvasToCell(c);
        final newOrigin = Offset(cx.toDouble(), cy.toDouble());
        if (newOrigin == _pasteOrigin) return; // same cell — nothing to repaint
        _pasteOrigin = newOrigin;
        _scheduleRebuild();
        return;
      }

      if (mode == DrawingMode.colorPicker) return;

      // In stitch mode, update progress drag region instead of drawing.
      if (ref.read(editorProvider).stitchMode && _progressAnchor != null) {
        final cell = _screenToSelCell(event.localPosition);
        final newRect = _buildSelRect(_progressAnchor!, cell);
        // Only count as a real drag once the pointer has moved enough screen
        // pixels from the anchor — this prevents mouse jitter from triggering
        // the drag path on what is really just a click.
        if (!_hasDraggedProgress && _progressAnchorScreen != null &&
            (event.localPosition - _progressAnchorScreen!).distance > _kProgressDragThreshold) {
          _hasDraggedProgress = true;
        }
        if (newRect != _progressDragRect) {
          _progressDragRect = newRect;
          _scheduleRebuild();
        }
        return;
      }

      // Backstitch is click-to-click, not drag-to-draw — only update hover.
      if (ref.read(editorProvider).currentTool == DrawingTool.backstitch) {
        final canvas = _screenToCanvas(event.localPosition);
        _backstitchHoverPoint = _canvasToGridPoint(canvas);
        _scheduleRebuild();
      } else {
        _handleDrawAt(event.localPosition);
      }
      return;
    }

    // ── Touch gestures ───────────────────────────────────────────────────────
    if (_activePointers.length >= 2) {
      if (!_hadMultiTouch) {
        _hadMultiTouch = true;
        _progressAnchor = null;
        _progressAnchorScreen = null;
        _progressBackstitch = null;
        _hasDraggedProgress = false;
        _progressDragRect = null;
      }
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
      if (_hadMultiTouch) {
        // Residual finger from a pinch — pan only, never draw.
        _pan(event.delta);
        return;
      }
      final mode = ref.read(editorProvider).drawingMode;
      if (mode == DrawingMode.select && !ref.read(editorProvider).stitchMode) {
        final cell = _screenToSelCell(event.localPosition);
        if (_isMovingSelection && _moveDragStartCell != null) {
          _moveDelta = cell - _moveDragStartCell!;
          _scheduleRebuild();
        } else if (_selectionAnchor != null) {
          _hasDraggedSelection = true;
          _dragSelectionRect = _buildSelRect(_selectionAnchor!, cell);
          _scheduleRebuild();
        }
      } else if (mode == DrawingMode.paste) {
        final c = _screenToCanvas(event.localPosition);
        final (cx, cy) = _canvasToCell(c);
        _pasteOrigin = Offset(cx.toDouble(), cy.toDouble());
        _scheduleRebuild();
      } else if (_isPanMode) {
        _pan(event.delta);
      } else if (ref.read(editorProvider).stitchMode && _progressAnchor != null) {
        // Stitch mode: update progress drag region.
        final cell = _screenToSelCell(event.localPosition);
        final newRect = _buildSelRect(_progressAnchor!, cell);
        if (newRect != _progressDragRect) {
          if (newRect.width > 1 || newRect.height > 1) _hasDraggedProgress = true;
          _progressDragRect = newRect;
          _scheduleRebuild();
        }
      } else if (ref.read(editorProvider).currentTool != DrawingTool.backstitch) {
        // Backstitch is click-to-click, not drag-to-draw.
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
      final rect = _dragSelectionRect ?? _buildSelRect(_selectionAnchor!, cell);
      // Only keep selection if the user actually dragged; a bare click deselects
      ref.read(editorProvider.notifier).setSelectionRect(
          _hasDraggedSelection && rect.width >= 1 && rect.height >= 1 ? rect : null);
      _selectionAnchor = null;
      _hasDraggedSelection = false;
      _dragSelectionRect = null;
      _scheduleRebuild();
      _activePointers.remove(event.pointer);
      return;
    }

    // Finalize progress anchor (stitch mode tap / drag-to-mark)
    if (_progressAnchor != null) {
      final cell = _screenToSelCell(pos);
      if (_hasDraggedProgress) {
        // Drag ended: commit region to provider (shows sidebar Mark Done button).
        final rect = _progressDragRect ?? _buildSelRect(_progressAnchor!, cell);
        if (rect.width > 1 || rect.height > 1) {
          ref.read(editorProvider.notifier).setProgressRegion(rect);
        }
      } else {
        // Tap: toggle the tapped stitch/backstitch done/not-done,
        // or flood fill on double-click (cross-stitches only).
        final bs = _progressBackstitch;
        if (bs != null) {
          // Backstitch tap — always a single toggle, no flood fill.
          ref.read(editorProvider.notifier)
              .toggleBackstitchDone(bs.x1, bs.y1, bs.x2, bs.y2);
        } else {
          final cx = _progressAnchor!.dx.toInt();
          final cy = _progressAnchor!.dy.toInt();
          if (_pendingDoubleClick) {
            ref.read(editorProvider.notifier).floodFillDone(cx, cy,
                originalStartIsDone: _wasProgressCellDone,
                afterSingleTap: true);
            _pendingDoubleClick = false;
            _wasProgressCellDone = null;
          } else {
            _wasProgressCellDone = ref.read(editorProvider)
                .pattern.progress.completedStitches.contains((cx, cy));
            ref.read(editorProvider.notifier).toggleStitchDone(cx, cy);
          }
        }
        // Clear any committed progress region on a tap
        ref.read(editorProvider.notifier).setProgressRegion(null);
      }
      _progressAnchor = null;
      _progressAnchorScreen = null;
      _progressBackstitch = null;
      _hasDraggedProgress = false;
      _progressDragRect = null;
      _scheduleRebuild();
      _activePointers.remove(event.pointer);
      return;
    }

    // Double-tap (touch, edit mode only) → undo.
    // Stitch mode double-click/tap is detected in _onPointerDown via timing.
    // Skip if this finger was part of a multi-touch gesture.
    if (event.kind == PointerDeviceKind.touch && wasSinglePointer &&
        !_hadMultiTouch && !ref.read(editorProvider).stitchMode) {
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
    if (_activePointers.isEmpty) {
      _pinchStartDistance = 0;
      _hadMultiTouch = false; // all fingers up — next touch starts fresh
      _saveViewPosition();
    }
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
      final newOrigin = Offset(cx.toDouble(), cy.toDouble());
      if (newOrigin == _pasteOrigin) return; // same cell — nothing to repaint
      _pasteOrigin = newOrigin;
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
    // No discrete end event for scroll; debounce the save.
    _debouncedSaveViewPosition();
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _saveViewPosition();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);

    // Show canvas warning banner triggered by the notifier (e.g. copy with no selection).
    ref.listen<EditorState>(editorProvider, (prev, next) {
      if (next.pendingCanvasWarning != null &&
          next.pendingCanvasWarning != prev?.pendingCanvasWarning) {
        _showWarningBanner(next.pendingCanvasWarning!);
        ref.read(editorProvider.notifier).clearCanvasWarning();
      }
      // When the file changes, restore the saved view position for the new file.
      if (next.filePath != prev?.filePath && next.isFileOpen) {
        setState(() {
          if (next.viewScale > 0) {
            _scale = next.viewScale;
            _panOffset = Offset(next.viewPanX, next.viewPanY);
          } else {
            _scale = 1.0;
            _panOffset = const Offset(20, 20);
          }
        });
      }
      // Fit canvas to page when page mode navigates.
      if (next.pendingFitPage != null &&
          next.pendingFitPage != prev?.pendingFitPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Re-read current state: if pendingFitPage was cleared before this
          // frame fired (e.g. by a background Drive refresh that wants to
          // preserve the current viewport), skip the fit entirely.
          final current = ref.read(editorProvider);
          if (current.pendingFitPage == null) return;
          _fitToPage(current, current.pendingFitPage!);
          ref.read(editorProvider.notifier).clearPendingFitPage();
        });
      }
    });
    final isErasing = state.drawingMode == DrawingMode.erase;
    final isDrawCursor = state.drawingMode == DrawingMode.draw;
    final isColorPickerCursor = state.drawingMode == DrawingMode.colorPicker;

    // Compute ghost stitches for paste preview or move drag
    List<Stitch>? ghostStitches;
    if (state.drawingMode == DrawingMode.paste && state.clipboard != null) {
      // Fall back to canvas centre so the ghost is visible even before the
      // user has moved the cursor (e.g. right after a flip/rotate).
      final origin = _pasteOrigin ??
          Offset(state.pattern.width / 2.0, state.pattern.height / 2.0);
      final (dx, dy) = _pasteOffset(origin, state.clipboard!);
      // Only rebuild the offset list when the placement or clipboard changes.
      if (_lastGhostDxDy != (dx, dy) ||
          !identical(_lastGhostClipboard, state.clipboard)) {
        _lastGhostDxDy = (dx, dy);
        _lastGhostClipboard = state.clipboard;
        _cachedGhostStitches =
            state.clipboard!.map((s) => EditorState.offsetStitch(s, dx, dy)).toList();
      }
      ghostStitches = _cachedGhostStitches;
    } else if (_isMovingSelection && state.selectionRect != null) {
      final dx = _moveDelta.dx.round();
      final dy = _moveDelta.dy.round();
      ghostStitches =
          state.selectedStitches.map((s) => EditorState.offsetStitch(s, dx, dy)).toList();
    }

    final pageModeActive = state.stitchMode &&
        state.pattern.pageConfig.enabled &&
        state.pageLayout != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = constraints.biggest;
        return MouseRegion(
        cursor: _cursor(state),
        onExit: (_) { _mouseScreenPos = null; _stylusHoverCell = null; _scheduleRebuild(); },
        child: Stack(children: [
        Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
        onPointerPanZoomEnd: _onPointerPanZoomEnd,
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
                  colourMode: state.colourMode,
                  stitchCrossMode: state.stitchCrossMode,
                  stitchBackMode: state.stitchBackMode,
                  stitchFocusThreadId: state.stitchFocusThreadId,
                  referenceImage: state.referenceImage,
                  referenceOpacity: state.referenceOpacity,
                  referenceVisible: state.referenceVisible,
                  compositeResult: state.compositeResult,
                  paletteOverride: _getOrBuildPaletteOverride(state),
                  // Pages are a stitch-mode concept — don't filter in edit/view.
                  pageLayout: state.stitchMode ? state.pageLayout : null,
                  currentPage: state.currentPage,
                  progress: state.pattern.progress,
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
            // Drag selection tooltip — shows size and from/to coords while dragging.
            if ((_dragSelectionRect != null && _selectionAnchor != null) ||
                (_progressDragRect != null && _progressAnchor != null && _hasDraggedProgress))
              () {
                final rect = _dragSelectionRect ?? _progressDragRect!;
                final anchor = _selectionAnchor ?? _progressAnchor!;
                // Determine drag direction from anchor vs current end cell.
                final endX = rect.right - 1; // inclusive end col
                final endY = rect.bottom - 1;
                final dragRight = endX >= anchor.dx;
                final dragDown = endY >= anchor.dy;
                return _SelectionTooltipOverlay(
                  rect: rect,
                  anchor: anchor,
                  mousePos: _mouseScreenPos,
                  canvasSize: _canvasSize,
                  dragRight: dragRight,
                  dragDown: dragDown,
                );
              }(),
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
                selectionRect: _progressDragRect ?? state.progressRegion ?? _dragSelectionRect ?? state.selectionRect,
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
            // Page navigation chrome — inside Listener so multi-touch (pinch)
            // is always tracked. Nav-zone guard in _onPointerDown prevents
            // accidental stitch marks when tapping nav buttons.
            if (pageModeActive)
              _PageNavOverlay(
                layout: state.pageLayout!,
                currentPage: state.currentPage,
                completedPages: state.pattern.progress.completedPages,
                onLeft:  () => ref.read(editorProvider.notifier).navigatePageLeft(),
                onRight: () => ref.read(editorProvider.notifier).navigatePageRight(),
                onUp:    () => ref.read(editorProvider.notifier).navigatePageUp(),
                onDown:  () => ref.read(editorProvider.notifier).navigatePageDown(),
                onPageTap: (page) => ref.read(editorProvider.notifier).navigatePage(page),
                onPageLongPress: (page) => ref.read(editorProvider.notifier).togglePageDone(page),
              ),
          ],
        ),
      ),
        ])); // outer Stack, MouseRegion
    },
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

// ─── Selection drag tooltip ───────────────────────────────────────────────────

class _SelectionTooltipOverlay extends StatelessWidget {
  final Rect rect;
  final Offset anchor;
  final Offset? mousePos;
  final Size canvasSize;
  final bool dragRight;
  final bool dragDown;

  const _SelectionTooltipOverlay({
    required this.rect,
    required this.anchor,
    required this.mousePos,
    required this.canvasSize,
    required this.dragRight,
    required this.dragDown,
  });

  @override
  Widget build(BuildContext context) {
    final w = rect.width.toInt();
    final h = rect.height.toInt();
    final fromX = anchor.dx.toInt() + 1; // 1-based
    final fromY = anchor.dy.toInt() + 1;
    final toX = (rect.right - 1).toInt() + 1;
    final toY = (rect.bottom - 1).toInt() + 1;

    final x1 = math.min(fromX, toX);
    final y1 = math.min(fromY, toY);
    const tooltipWidth = 160.0;
    const tooltipHeight = 64.0;
    const gap = 14.0;

    double left, top;
    final mp = mousePos;
    if (mp != null) {
      // Place tooltip in the quadrant the user is dragging towards.
      if (dragRight) {
        left = mp.dx + gap;
      } else {
        left = mp.dx - tooltipWidth - gap;
      }
      if (dragDown) {
        top = mp.dy + gap;
      } else {
        top = mp.dy - tooltipHeight - gap;
      }
      left = left.clamp(8.0, canvasSize.width - tooltipWidth - 8);
      top = top.clamp(8.0, canvasSize.height - tooltipHeight - 8);
    } else {
      left = 16;
      top = 16;
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.crop_free, color: Colors.white70, size: 13),
                    const SizedBox(width: 5),
                    Text('$w × $h', style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    )),
                  ],
                ),
                const SizedBox(height: 3),
                Text('From  ($x1, $y1)', style: const TextStyle(color: Colors.white70)),
                Text('To      ($toX, $toY)', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Page navigation chrome ───────────────────────────────────────────────────

class _PageNavOverlay extends StatelessWidget {
  final PageLayout layout;
  final int currentPage;
  final Set<int> completedPages;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final void Function(int page) onPageTap;
  final void Function(int page) onPageLongPress;

  const _PageNavOverlay({
    required this.layout,
    required this.currentPage,
    required this.completedPages,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
    required this.onDown,
    required this.onPageTap,
    required this.onPageLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final total = layout.totalPages;
    final (col, row) = layout.pageCoords(currentPage);
    final hasLeft  = col > 0;
    final hasRight = col < layout.pagesAcross - 1;
    final hasUp    = row > 0;
    final hasDown  = row < layout.pagesDown - 1;
    const buttonStyle = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600);

    return Stack(
      children: [
        // Left arrow — left edge
        if (hasLeft)
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Center(child: _NavArrowButton(icon: Icons.chevron_left, onTap: onLeft)),
          ),
        // Right arrow — right edge
        if (hasRight)
          Positioned(
            right: 0, top: 0, bottom: 0,
            child: Center(child: _NavArrowButton(icon: Icons.chevron_right, onTap: onRight)),
          ),
        // Up arrow — top centre
        if (hasUp)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Center(child: _NavArrowButton(icon: Icons.expand_less, horizontal: false, onTap: onUp)),
          ),
        // Down arrow — bottom centre (above page indicator)
        if (hasDown)
          Positioned(
            bottom: 52, left: 0, right: 0,
            child: Center(child: _NavArrowButton(icon: Icons.expand_more, horizontal: false, onTap: onDown)),
          ),
        // Page indicator — bottom centre
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _showPageGrid(context),
              onLongPress: () => onPageLongPress(currentPage),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: completedPages.contains(currentPage)
                      ? Colors.green.shade700.withValues(alpha: 0.85)
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (completedPages.contains(currentPage)) ...[
                      const Icon(Icons.check, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '${currentPage + 1} / $total',
                      style: buttonStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showPageGrid(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PageGridSheet(
        layout: layout,
        currentPage: currentPage,
        completedPages: completedPages,
        onPageTap: (page) {
          Navigator.of(context).pop();
          onPageTap(page);
        },
      ),
    );
  }
}

class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  /// True for left/right arrows (tall and narrow); false for up/down (wide and short).
  final bool horizontal;

  const _NavArrowButton({
    required this.icon,
    required this.onTap,
    this.horizontal = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: horizontal ? 36 : 64,
        height: horizontal ? 64 : 36,
        margin: horizontal
            ? const EdgeInsets.symmetric(horizontal: 4)
            : const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

// ─── Page grid sheet ──────────────────────────────────────────────────────────

class _PageGridSheet extends StatelessWidget {
  final PageLayout layout;
  final int currentPage;
  final Set<int> completedPages;
  final void Function(int page) onPageTap;

  const _PageGridSheet({
    required this.layout,
    required this.currentPage,
    required this.completedPages,
    required this.onPageTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = layout.totalPages;
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Pages', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('$total total', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 88,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: total,
              itemBuilder: (context, index) {
                final isActive = index == currentPage;
                final isDone = completedPages.contains(index);
                final (col, row) = layout.pageCoords(index);
                return GestureDetector(
                  onTap: () => onPageTap(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: isDone
                          ? Colors.green.shade100
                          : isActive
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: isDone
                            ? Colors.green.shade600
                            : isActive
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                        width: isActive || isDone ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isDone)
                          Icon(Icons.check_circle, size: 18, color: Colors.green.shade700)
                        else
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isActive
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                        Text(
                          '${col + 1}×${row + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDone
                                ? Colors.green.shade700
                                : isActive
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
