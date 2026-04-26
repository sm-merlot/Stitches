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
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../services/render_cache.dart';
import '../services/stitch_compositor.dart';
import 'canvas_painter.dart';
import 'canvas_viewport.dart';
import 'draw_handler.dart';
import 'hover_handler.dart';
import 'page_nav_handler.dart';
import 'paste_handler.dart';
import 'progress_handler.dart';
import 'select_handler.dart';
import 'zoom_pan_handler.dart';

class PatternCanvas extends ConsumerStatefulWidget {
  const PatternCanvas({super.key});

  @override
  ConsumerState<PatternCanvas> createState() => _PatternCanvasState();
}

class _PatternCanvasState extends ConsumerState<PatternCanvas> {
  static const double _baseCellSize = 20.0;

  // ── ZoomPanHandler ──────────────────────────────────────────────────────────
  // Owns _scale, _panOffset, and all gesture tracking state. Initialised in
  // initState once callbacks are available.
  late final ZoomPanHandler _zoomPan;

  // Getters so the rest of this class can read scale/panOffset unchanged.
  double get _scale => _zoomPan.scale;
  Offset get _panOffset => _zoomPan.panOffset;

  // ── Extracted input handlers ─────────────────────────────────────────────────
  // Each owns its own mutable state and communicates via injected callbacks.
  late final HoverHandler _hover;
  late final DrawHandler _draw;
  late final SelectHandler _select;
  late final PasteHandler _paste;
  late final ProgressHandler _progress;
  static const _pageNav = PageNavHandler();

  // ── RenderCache ─────────────────────────────────────────────────────────────
  // Owned here (not in Riverpod state) — UI concern, not business logic.
  // Rebuilt when pattern/composite/mode changes; NOT rebuilt on pan/zoom.
  final RenderCache _renderCache = RenderCache();

  // Touch pinch-to-zoom tracking
  final Map<int, Offset> _activePointers = {};
  // True while any gesture sequence that included ≥2 fingers is still active
  // (i.e. at least one finger from the pinch is still down).  Single-finger
  // draw/select/paste actions are suppressed during this window so that the
  // residual finger from a pinch never accidentally adds stitches.
  // Reset to false only when _activePointers becomes empty (all fingers up).
  bool _hadMultiTouch = false;

  // Double-tap / double-click detection (edit mode undo)
  DateTime? _lastTouchUpTime;
  Offset? _lastTouchUpPos;

  // ── Palette override cache ──────────────────────────────────────────────────
  // Rebuilt only when snippetPalettes identity or active index actually changes,
  // so the same Map instance is reused across builds and shouldRepaint works.
  List<Object> _lastPalettes = const [];
  int _lastPaletteIdx = -1;
  Map<String, Color>? _paletteOverride;

  // ── Layer visibility warning ───────────────────────────────────────────────
  String? _warningMessage;
  Timer? _warningTimer;
  // Suppresses repeat warnings within a single pointer-down → up gesture.
  bool _warnedThisGesture = false;

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

    _zoomPan.setViewport(newScale, Offset(newPanX, newPanY));
    setState(() {});
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
    // Restore saved view position from the loaded pattern (if any).
    final editorState = ref.read(editorProvider);
    final savedScale = editorState.viewScale > 0 ? editorState.viewScale : 1.0;
    final savedPan = editorState.viewScale > 0
        ? Offset(editorState.viewPanX, editorState.viewPanY)
        : const Offset(20, 20);
    _zoomPan = ZoomPanHandler(
      initialScale: savedScale,
      initialPanOffset: savedPan,
      cellSize: _cellSize,
      scheduleRebuild: _scheduleRebuild,
      save: _saveViewPosition,
      debouncedSave: _debouncedSaveViewPosition,
    );
    final n = ref.read(editorProvider.notifier);
    _hover = HoverHandler(scheduleRebuild: _scheduleRebuild);
    _draw = DrawHandler(
      onAddStitch: n.addStitch,
      onRemoveAt: n.removeStitchesAt,
      onRemoveBox: n.removeStitchesInBox,
      onFloodFill: n.floodFill,
      onPickColor: n.pickColorAtCell,
      onSetBackstitchStart: n.setBackstitchStart,
      onLayerWarning: _showWarning,
      getCtrlHeld: () => _paste.ctrlHeld,
    );
    _select = SelectHandler(
      onSetSelectionRect: n.setSelectionRect,
      onMoveSelection: n.moveSelection,
      onWarning: _showWarningBanner,
      scheduleRebuild: _scheduleRebuild,
    );
    _paste = PasteHandler(
      onCommitPaste: n.commitPaste,
      onCancelSelection: n.cancelSelection,
      scheduleRebuild: _scheduleRebuild,
    );
    _progress = ProgressHandler(
      onToggleStitchDone: n.toggleStitchDone,
      onToggleBackstitchDone: n.toggleBackstitchDone,
      onFloodFillDone: n.floodFillDone,
      onSetProgressRegion: n.setProgressRegion,
      scheduleRebuild: _scheduleRebuild,
    );
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // Seed the render cache with the initial editor state.
    _rebuildRenderCache(editorState);
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

  bool _onHardwareKey(KeyEvent event) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    _paste.updateModifiers(ctrl: ctrl, shift: shift);
    return false; // don't consume the event
  }

  void _onGlobalPointerEvent(PointerEvent event) {
    if (!mounted) return;
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return;
    }

    if (event is PointerAddedEvent) {
      // Pencil entered hover range — update hover cell from global position.
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final local = box.globalToLocal(event.position);
      final p = ref.read(editorProvider).pattern;
      _hover.onStylusAdded(local, _viewport, p.width, p.height);
    } else if (event is PointerRemovedEvent) {
      _hover.onStylusRemoved();
    }
  }

  double get _cellSize => _baseCellSize;

  // ── RenderCache maintenance ─────────────────────────────────────────────────

  // Track the last values used to build the cache so we only rebuild when
  // something relevant actually changed (not on every pan/zoom setState).
  CrossStitchPattern? _lastCachedPattern;
  CompositeLayer? _lastCachedComposite;
  RenderViewConfig? _lastCachedViewConfig;

  RenderViewConfig _buildViewConfig(EditorState state) => RenderViewConfig(
        focusThreadId: state.stitchFocusThreadId,
        stitchMode: state.stitchMode,
        stitchBackMode: state.stitchBackMode,
        stitchCrossMode: state.stitchCrossMode,
        paletteOverride: _getOrBuildPaletteOverride(state),
        progress: state.pattern.progress,
        pageLayout: state.stitchMode ? state.pageLayout : null,
        currentPage: state.currentPage,
      );

  void _rebuildRenderCache(EditorState state) {
    final config = _buildViewConfig(state);
    final layer = state.compositeLayer;
    if (layer == null) {
      _renderCache.clear();
    } else {
      _renderCache.rebuild(layer, config, _cellSize);
    }
    _lastCachedPattern = state.pattern;
    _lastCachedComposite = state.compositeLayer;
    _lastCachedViewConfig = config;
  }

  /// Rebuilds the render cache only when stitch data, composite, or view config
  /// has changed since the last call. Pan/zoom changes are ignored here.
  void _syncRenderCache(EditorState state) {
    final config = _buildViewConfig(state);
    final patternChanged = !identical(_lastCachedPattern, state.pattern);
    final compositeChanged = !identical(_lastCachedComposite, state.compositeLayer);
    final configChanged = config != _lastCachedViewConfig;

    if (!patternChanged && !compositeChanged && !configChanged) return;

    final layer = state.compositeLayer;
    if (layer == null) {
      _renderCache.clear();
    } else if (configChanged && !patternChanged && !compositeChanged) {
      // View config only (focus/mode/palette changed) — recolour without
      // recomputing geometry.
      _renderCache.rebuildViewConfig(layer, config, _cellSize);
    } else {
      _renderCache.rebuild(layer, config, _cellSize);
    }
    _lastCachedPattern = state.pattern;
    _lastCachedComposite = state.compositeLayer;
    _lastCachedViewConfig = config;
  }

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
    // Use putIfAbsent so duplicate dmcCodes in the primary palette (where two
    // strip colours matched the same DMC) always map to the FIRST slot's
    // secondary colour — matching the behaviour of resolveThread's indexWhere.
    for (var i = 0; i < primary.threads.length; i++) {
      if (i < active.threads.length) {
        map.putIfAbsent(primary.threads[i].dmcCode, () => active.threads[i].color);
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

  void _pan(Offset delta) => _zoomPan.pan(delta);

  bool _screenOnCanvas(Offset screenPos) {
    final c = _screenToCanvas(screenPos);
    final p = ref.read(editorProvider).pattern;
    return c.dx >= 0 && c.dy >= 0 &&
        c.dx < p.width * _cellSize && c.dy < p.height * _cellSize;
  }

  // ─── Pointer event handling ───────────────────────────────────────────────

  bool get _isPanMode =>
      ref.read(editorProvider).drawingMode == DrawingMode.pan;

  bool _isNavZone(Offset screenPos) {
    final s = ref.read(editorProvider);
    return _pageNav.isNavZone(
      screenPos,
      _canvasSize,
      stitchMode: s.stitchMode,
      pageEnabled: s.pattern.pageConfig.enabled,
      hasPageLayout: s.pageLayout != null,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    Focus.maybeOf(context)?.requestFocus();
    _activePointers[event.pointer] = event.localPosition;
    _hover.onPointerDown(event.localPosition);
    _warnedThisGesture = false;
    _scheduleRebuild();

    // Apple Pencil double-tap button
    if (event.kind == PointerDeviceKind.stylus &&
        event.buttons == kSecondaryStylusButton) {
      final state = ref.read(editorProvider);
      if (state.drawingMode == DrawingMode.paste) {
        _paste.commit(state.pattern, state.clipboard);
      } else if (!state.stitchMode) {
        ref.read(editorProvider.notifier).toggleDrawingMode();
      }
      return;
    }

    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      if (event.buttons == kMiddleMouseButton) return; // pan on move
      if (_isPanMode) return;

      final state = ref.read(editorProvider);
      final mode = state.drawingMode;
      final vp = _viewport;
      final p = state.pattern;

      if (mode == DrawingMode.select) {
        if (state.stitchMode) {
          // Select-drag in stitch mode marks a region done.
          if (state.progressRegion != null) {
            ref.read(editorProvider.notifier).setProgressRegion(null);
            return;
          }
          if (_screenOnCanvas(event.localPosition) && !_isNavZone(event.localPosition)) {
            _progress.onPointerDown(event.localPosition, vp, p.width, p.height, state);
          }
          return;
        }
        _select.onPointerDown(
          event.localPosition, vp, p.width, p.height,
          currentSelectionRect: state.selectionRect,
          hasSelectedStitches: state.selectedStitches.isNotEmpty,
          canvasSelectionMode: state.canvasSelectionMode,
          isOnCanvas: _screenOnCanvas(event.localPosition),
        );
        return;
      }

      if (mode == DrawingMode.paste) {
        final pencilConfirm = ref.read(settingsProvider).pencilPasteConfirm;
        if (pencilConfirm) {
          _paste.setOrigin(event.localPosition, vp);
        } else {
          _paste.commit(state.pattern, state.clipboard);
        }
        return;
      }

      if (state.stitchMode) {
        if (!_isNavZone(event.localPosition)) {
          _progress.onPointerDown(event.localPosition, vp, p.width, p.height, state);
        }
        return;
      }

      _draw.handleDrawAt(event.localPosition, state, vp);
      return;
    }

    // Touch — handle special modes before pan/pinch setup.
    // Skip if this finger is the residual from a pinch.
    if (_activePointers.length == 1 && !_hadMultiTouch) {
      final state = ref.read(editorProvider);
      final mode = state.drawingMode;
      final vp = _viewport;
      final p = state.pattern;

      if (mode == DrawingMode.select) {
        if (state.stitchMode) {
          if (state.progressRegion != null) {
            ref.read(editorProvider.notifier).setProgressRegion(null);
            return;
          }
          if (_screenOnCanvas(event.localPosition) && !_isNavZone(event.localPosition)) {
            _progress.onPointerDown(event.localPosition, vp, p.width, p.height, state);
          }
          return;
        }
        _select.onPointerDown(
          event.localPosition, vp, p.width, p.height,
          currentSelectionRect: state.selectionRect,
          hasSelectedStitches: state.selectedStitches.isNotEmpty,
          canvasSelectionMode: state.canvasSelectionMode,
          isOnCanvas: _screenOnCanvas(event.localPosition),
        );
        return;
      }

      if (mode == DrawingMode.paste) {
        final pencilConfirm = ref.read(settingsProvider).pencilPasteConfirm;
        if (pencilConfirm) {
          // Pencil-confirm mode: finger tap commits at current ghost position.
          _paste.commit(state.pattern, state.clipboard);
        } else {
          _paste.setOrigin(event.localPosition, vp);
          // Commit on pointer up to avoid double-tap undo collision.
        }
        return;
      }

      if (state.stitchMode) {
        if (!_isNavZone(event.localPosition)) {
          _progress.onPointerDown(event.localPosition, vp, p.width, p.height, state);
        }
        return;
      }
    }

    // Touch — set up pan/pinch start state.
    if (_activePointers.length == 2) {
      _hadMultiTouch = true;
      // Cancel any progress anchor set by the first finger.
      _progress.cancel();
      _select.cancel();
      final pts = _activePointers.values.toList();
      _zoomPan.beginPinch(pts[0], pts[1]);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      final state = ref.read(editorProvider);
      final vp = _viewport;
      final p = state.pattern;
      _hover.onPointerMove(event.localPosition, vp, p.width, p.height);

      if (_isPanMode || event.buttons == kMiddleMouseButton) {
        _pan(event.delta);
        return;
      }

      final mode = state.drawingMode;

      if (mode == DrawingMode.select && !state.stitchMode) {
        _select.onPointerMove(event.localPosition, vp, p.width, p.height);
        return;
      }

      if (mode == DrawingMode.paste) {
        _paste.updateOrigin(event.localPosition, vp);
        return;
      }

      if (mode == DrawingMode.colorPicker) return;

      if (state.stitchMode && _progress.isActive) {
        _progress.onPointerMove(event.localPosition, vp, p.width, p.height);
        return;
      }

      // Backstitch is click-to-click — only update hover preview.
      if (state.currentTool == DrawingTool.backstitch) {
        if (state.backstitchStartPoint != null) {
          _draw.updateBackstitchHover(event.localPosition, vp);
        }
        _scheduleRebuild();
      } else {
        _draw.handleDrawAt(event.localPosition, state, vp);
      }
      return;
    }

    // ── Touch gestures ───────────────────────────────────────────────────────
    if (_activePointers.length >= 2) {
      if (!_hadMultiTouch) {
        _hadMultiTouch = true;
        _progress.cancel();
        _select.cancel();
      }
      final pts = _activePointers.values.toList();
      _zoomPan.updatePinch(pts[0], pts[1]);
    } else if (_activePointers.length == 1) {
      if (_hadMultiTouch) {
        _pan(event.delta);
        return;
      }
      final state = ref.read(editorProvider);
      final vp = _viewport;
      final p = state.pattern;
      final mode = state.drawingMode;

      if (mode == DrawingMode.select && !state.stitchMode) {
        _select.onPointerMove(event.localPosition, vp, p.width, p.height);
      } else if (mode == DrawingMode.paste) {
        _paste.updateOrigin(event.localPosition, vp);
      } else if (_isPanMode) {
        _pan(event.delta);
      } else if (state.stitchMode && _progress.isActive) {
        _progress.onTouchMove(event.localPosition, vp, p.width, p.height);
      } else if (state.currentTool != DrawingTool.backstitch) {
        _draw.handleDrawAt(event.localPosition, state, vp);
      }
    }

    // ── Kind-agnostic fallback ───────────────────────────────────────────────
    // Apple Pencil can emit PointerMoveEvents with kind == unknown on some
    // iPadOS versions.  Update whichever handler is active.
    if (_select.isActive) {
      final state = ref.read(editorProvider);
      _select.onPointerMove(event.localPosition, _viewport, state.pattern.width, state.pattern.height);
    } else if (_progress.isActive && ref.read(editorProvider).stitchMode) {
      final state = ref.read(editorProvider);
      _progress.onPointerMove(event.localPosition, _viewport, state.pattern.width, state.pattern.height);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _draw.onPointerUp();
    final pos = event.localPosition;
    final now = DateTime.now();
    final wasSinglePointer = _activePointers.length == 1;

    _hover.onPointerUp(event.kind);

    // Touch paste — commit at current origin.
    if (event.kind == PointerDeviceKind.touch &&
        ref.read(editorProvider).drawingMode == DrawingMode.paste &&
        _paste.pasteOrigin != null) {
      final state = ref.read(editorProvider);
      _paste.commit(state.pattern, state.clipboard);
      _paste.clearOrigin();
      _activePointers.remove(event.pointer);
      return;
    }

    // Commit selection move or finalize rubber-band.
    if (_select.isActive) {
      final state = ref.read(editorProvider);
      _select.onPointerUp(pos, _viewport, state.pattern.width, state.pattern.height);
      _activePointers.remove(event.pointer);
      return;
    }

    // Finalize progress anchor (stitch mode tap / drag-to-mark).
    if (_progress.isActive) {
      final state = ref.read(editorProvider);
      _progress.onPointerUp(pos, _viewport, state.pattern.width, state.pattern.height, state);
      _activePointers.remove(event.pointer);
      return;
    }

    // Double-tap (touch, edit mode only) → undo.
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

      if (!_isPanMode) {
        final state = ref.read(editorProvider);
        _draw.handleDrawAt(pos, state, _viewport);
      }
    }

    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _zoomPan.resetPinch();
      _hadMultiTouch = false;
    }
  }

  // ─── Trackpad pinch-to-zoom (macOS) ──────────────────────────────────────

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) =>
      _zoomPan.onPointerPanZoomStart(event);

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) =>
      _zoomPan.onPointerPanZoomUpdate(event);

  void _onPointerHover(PointerHoverEvent event) {
    final state = ref.read(editorProvider);
    final vp = _viewport;
    final p = state.pattern;

    // We don't guard by kind because Apple Pencil hover events on iPadOS may not
    // always arrive as PointerDeviceKind.stylus through this path.
    _hover.onPointerHover(event.localPosition, event.kind, vp, p.width, p.height);

    if (state.drawingMode == DrawingMode.paste) {
      _paste.updateOrigin(event.localPosition, vp);
      return;
    }

    if (state.currentTool == DrawingTool.backstitch &&
        state.backstitchStartPoint != null) {
      _draw.updateBackstitchHover(event.localPosition, vp);
    }

    _scheduleRebuild();
  }

  // ─── Scroll wheel: zoom + shift-scroll pan ────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) =>
      _zoomPan.onPointerSignal(event);

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) =>
      _zoomPan.onPointerPanZoomEnd(event);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);

    // Keep the render cache in sync with pattern/composite/mode changes.
    // Pan/zoom-only changes are filtered out by identity checks inside.
    _syncRenderCache(state);

    // Show canvas warning banner triggered by the notifier (e.g. copy with no selection).
    ref.listen<EditorState>(editorProvider, (prev, next) {
      if (next.pendingCanvasWarning != null &&
          next.pendingCanvasWarning != prev?.pendingCanvasWarning) {
        _showWarningBanner(next.pendingCanvasWarning!);
        ref.read(editorProvider.notifier).clearCanvasWarning();
      }
      // When the file changes, restore the saved view position for the new file.
      if (next.filePath != prev?.filePath && next.isFileOpen) {
        if (next.viewScale > 0) {
          _zoomPan.setViewport(next.viewScale, Offset(next.viewPanX, next.viewPanY));
        } else {
          _zoomPan.setViewport(1.0, const Offset(20, 20));
        }
        setState(() {});
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

    // Compute ghost stitches for paste preview or move drag.
    List<Stitch>? ghostStitches;
    if (state.drawingMode == DrawingMode.paste && state.clipboard != null) {
      // Fall back to canvas centre so the ghost is visible even before the
      // user has moved the cursor (e.g. right after a flip/rotate).
      final origin = _paste.pasteOrigin ??
          Offset(state.pattern.width / 2.0, state.pattern.height / 2.0);
      final (dx, dy) = _paste.effectiveOffset(origin, state.clipboard!, state.pattern);
      ghostStitches = _paste.buildGhostStitches(dx, dy, state.clipboard!, EditorState.offsetStitch);
    } else if (_select.isMoving && state.selectionRect != null) {
      final dx = _select.moveDelta.dx.round();
      final dy = _select.moveDelta.dy.round();
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
        onExit: (_) => _hover.onExit(),
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
                  renderCache: _renderCache,
                  stitchMode: state.stitchMode,
                  stitchCrossMode: state.stitchCrossMode,
                  stitchBackMode: state.stitchBackMode,
                  stitchFocusThreadId: state.stitchFocusThreadId,
                  referenceImage: state.referenceImage,
                  referenceOpacity: state.referenceOpacity,
                  referenceVisible: state.referenceVisible,
                  compositeLayer: state.compositeLayer,
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
            if ((_select.dragRect != null && _select.anchor != null) ||
                (_progress.dragRect != null && _progress.anchor != null && _progress.hasDragged))
              () {
                final rect = _select.dragRect ?? _progress.dragRect!;
                final anchor = _select.anchor ?? _progress.anchor!;
                final anchorScreen = _viewport.canvasToScreen(
                  Offset(anchor.dx * _cellSize, anchor.dy * _cellSize),
                );
                final mp = _hover.mouseScreenPos;
                final dragRight = mp == null || mp.dx >= anchorScreen.dx;
                final dragDown  = mp == null || mp.dy >= anchorScreen.dy;
                return _SelectionTooltipOverlay(
                  rect: rect,
                  anchor: anchor,
                  mousePos: mp,
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
                backstitchCurrentPoint: _draw.backstitchHoverPoint,
                isErasing: isErasing,
                eraserSize: state.eraserSize,
                fillEraseActive: state.fillEraseActive,
                isDrawCursor: isDrawCursor,
                isColorPickerCursor: isColorPickerCursor,
                cursorScreenPos: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                    ? null
                    : _hover.mouseScreenPos,
                selectionRect: _progress.dragRect ?? state.progressRegion ?? _select.dragRect ?? state.selectionRect,
                ghostStitches: ghostStitches,
                ghostThreads: state.drawingMode == DrawingMode.paste
                    ? state.clipboardThreads
                    : null,
                ghostOpacity: state.drawingMode == DrawingMode.paste
                    ? 0.55
                    : 1.0,
                stylusHoverCell: _hover.hoverCell,
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
      DrawingMode.paste => _paste.ctrlHeld
          ? SystemMouseCursors.copy
          : _paste.shiftHeld
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
    const tooltipMaxWidth = 130.0;
    const tooltipHeight = 58.0;
    const gap = 14.0;

    double left, top;
    final mp = mousePos;
    if (mp != null) {
      // Place tooltip in the quadrant the user is dragging towards.
      if (dragRight) {
        left = mp.dx + gap;
      } else {
        left = mp.dx - tooltipMaxWidth - gap;
      }
      if (dragDown) {
        top = mp.dy + gap;
      } else {
        top = mp.dy - tooltipHeight - gap;
      }
      left = left.clamp(8.0, canvasSize.width - tooltipMaxWidth - 8);
      top = top.clamp(8.0, canvasSize.height - tooltipHeight - 8);
    } else {
      left = 16;
      top = 16;
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: IntrinsicWidth(
        child: Container(
          constraints: const BoxConstraints(maxWidth: tooltipMaxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                const SizedBox(height: 2),
                Text('From  ($x1, $y1)', style: const TextStyle(color: Colors.white70)),
                Text('To      ($toX, $toY)', style: const TextStyle(color: Colors.white70)),
              ],
            ),
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
