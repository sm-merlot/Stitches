import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import '../utils/canvas_callbacks.dart';
import '../utils/edit_controller.dart';
import '../utils/shortcut_router.dart';
import '../utils/stitch_controller.dart';
import '../utils/view_mode_controller.dart';
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
import 'hover_handler.dart';
import 'zoom_pan_handler.dart';

/// The canvas widget. Owns viewport state, [RenderCache], and mode controllers.
///
/// Exactly one mode controller is active at any time, determined by
/// [EditorState.mode]. Mode switches preserve viewport state.
///
/// **Controller lifecycle (caller's responsibility):**
/// 1. Construct each controller in the owning screen's `initState`.
/// 2. Push to [ShortcutRouter] before the first frame.
/// 3. [AidaWidget] calls [attachCanvas] / [detachCanvas] on mount/unmount.
/// 4. Pop from [ShortcutRouter] in the screen's `dispose`.
///
/// Step 9 will wrap this widget in `EditView`, `StitchView`, and
/// `SnippetEditView` — each owning a single controller — so callers no longer
/// need to manage three controllers directly.
class AidaWidget extends ConsumerStatefulWidget {
  /// Controller for edit mode. Owns [DrawHandler], [SelectHandler],
  /// [PasteHandler], and [HoverHandler]. Required — edit mode is always
  /// available when [AidaWidget] is used.
  final EditController editController;

  /// Controller for view mode (read-only). Owns [HoverHandler] only.
  /// Null when view mode is unavailable (e.g. snippet editor).
  final ViewModeController? viewModeController;

  /// Controller for stitch mode. Owns [ProgressHandler] and [HoverHandler].
  /// Null when stitch mode is unavailable (e.g. snippet editor).
  final StitchController? stitchController;

  const AidaWidget({
    super.key,
    required this.editController,
    required this.viewModeController,
    required this.stitchController,
  });

  @override
  ConsumerState<AidaWidget> createState() => _AidaWidgetState();
}

class _AidaWidgetState extends ConsumerState<AidaWidget>
    implements ShortcutHandler {
  static const double _baseCellSize = 20.0;

  // ── ZoomPanHandler ──────────────────────────────────────────────────────────
  // Always active regardless of mode — zoom/pan works in every mode.
  late final ZoomPanHandler _zoomPan;

  double get _scale => _zoomPan.scale;
  Offset get _panOffset => _zoomPan.panOffset;

  // ── Active controller accessors ───────────────────────────────────────────
  // Three controllers cover all modes. Exactly one is active per mode.
  // Step 9 (view widgets) will push this selection up to the caller so
  // AidaWidget receives a single already-active controller.
  EditController get _edit => widget.editController;
  ViewModeController? get _view => widget.viewModeController;
  StitchController? get _stitch => widget.stitchController;

  /// The hover handler for the currently active mode.
  HoverHandler? _activeHover(AppMode mode) => switch (mode) {
    AppMode.view   => _view?.hover,
    AppMode.edit   => _edit.hover,
    AppMode.stitch => _stitch?.hover,
  };

  // ── RenderCache ─────────────────────────────────────────────────────────────
  // Owned here (not in Riverpod state) — UI concern, not business logic.
  // Rebuilt when pattern/composite/mode changes; NOT rebuilt on pan/zoom.
  final RenderCache _renderCache = RenderCache();

  // Touch pinch-to-zoom tracking.
  final Map<int, Offset> _activePointers = {};
  // True while any gesture sequence that included ≥2 fingers is still active.
  // Single-finger actions are suppressed during this window so the residual
  // finger from a pinch never accidentally draws stitches.
  // Reset only when _activePointers becomes empty (all fingers lifted).
  bool _hadMultiTouch = false;

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

  /// Compute pan/scale so [pageIndex] fills the canvas with padding.
  /// Called when [EditorState.pendingFitPage] fires.
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

    final cb = CanvasCallbacks(
      scheduleRebuild: _scheduleRebuild,
      onWarning: _showWarning,
      getPencilPasteConfirm: () => ref.read(settingsProvider).pencilPasteConfirm,
    );
    widget.editController.attachCanvas(cb);
    widget.viewModeController?.attachCanvas(cb);
    widget.stitchController?.attachCanvas(cb);

    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
    ShortcutRouter.instance.push(this);
    _rebuildRenderCache(editorState);
  }

  @override
  void dispose() {
    _warningTimer?.cancel();
    _viewSaveTimer?.cancel();
    widget.editController.detachCanvas();
    widget.viewModeController?.detachCanvas();
    widget.stitchController?.detachCanvas();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    ShortcutRouter.instance.pop(this);
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

  @override
  bool handle(KeyEvent event) {
    // Pass modifier state to the edit controller's paste handler.
    // Returns false — modifier tracking only, not a consumed shortcut.
    _edit.updateModifiers(
      ctrl: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    return false;
  }

  void _onGlobalPointerEvent(PointerEvent event) {
    if (!mounted) return;
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return;
    }
    final state = ref.read(editorProvider);

    if (event is PointerAddedEvent) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final local = box.globalToLocal(event.position);
      final p = state.pattern;
      switch (state.mode) {
        case AppMode.view:
          _view?.onStylusAdded(local, _viewport, p.width, p.height);
        case AppMode.edit:
          _edit.onStylusAdded(local, _viewport, p.width, p.height);
        case AppMode.stitch:
          _stitch?.onStylusAdded(local, _viewport, p.width, p.height);
      }
    } else if (event is PointerRemovedEvent) {
      switch (state.mode) {
        case AppMode.view:
          _view?.onStylusRemoved();
        case AppMode.edit:
          _edit.onStylusRemoved();
        case AppMode.stitch:
          _stitch?.onStylusRemoved();
      }
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
    // Use putIfAbsent so duplicate dmcCodes in the primary palette always map
    // to the FIRST slot's secondary colour — matching resolveThread's indexWhere.
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

  bool _isNavZone(Offset screenPos, EditorState state) =>
      _stitch?.isNavZone(screenPos, _canvasSize.width, _canvasSize.height, state) ??
      false;

  void _onPointerDown(PointerDownEvent event) {
    Focus.maybeOf(context)?.requestFocus();
    _activePointers[event.pointer] = event.localPosition;
    _warnedThisGesture = false;
    _scheduleRebuild();

    final state = ref.read(editorProvider);
    _activeHover(state.mode)?.onPointerDown(event.localPosition);

    final vp = _viewport;
    final localPos = event.localPosition;

    // Apple Pencil secondary-button (double-tap) — edit mode only.
    if (event.kind == PointerDeviceKind.stylus &&
        event.buttons == kSecondaryStylusButton) {
      if (state.editMode) _edit.onPencilDoubleTap(state);
      return;
    }

    final isStylusMouse = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse;

    if (isStylusMouse) {
      switch (state.mode) {
        case AppMode.view:
          break; // pan handled by ZoomPanHandler
        case AppMode.edit:
          _edit.onPointerDown(
            localPos, event.kind, event.buttons, vp, state,
            isOnCanvas: _screenOnCanvas(localPos),
            pencilPasteConfirm: ref.read(settingsProvider).pencilPasteConfirm,
          );
        case AppMode.stitch:
          _stitch?.onPointerDown(
            localPos, event.kind, vp, state,
            isOnCanvas: _screenOnCanvas(localPos),
            isNavZone: _isNavZone(localPos, state),
          );
      }
      return;
    }

    // Touch — handle special modes before pan/pinch setup.
    if (_activePointers.length == 1 && !_hadMultiTouch) {
      switch (state.mode) {
        case AppMode.view:
          break; // pan handled by ZoomPanHandler
        case AppMode.edit:
          _edit.onPointerDown(
            localPos, event.kind, event.buttons, vp, state,
            isOnCanvas: _screenOnCanvas(localPos),
            pencilPasteConfirm: ref.read(settingsProvider).pencilPasteConfirm,
          );
        case AppMode.stitch:
          _stitch?.onPointerDown(
            localPos, event.kind, vp, state,
            isOnCanvas: _screenOnCanvas(localPos),
            isNavZone: _isNavZone(localPos, state),
          );
      }
      return;
    }

    // Multi-touch — set up pinch.
    if (_activePointers.length == 2) {
      _hadMultiTouch = true;
      _stitch?.cancelActiveGestures();
      _edit.cancelActiveGestures();
      final pts = _activePointers.values.toList();
      _zoomPan.beginPinch(pts[0], pts[1]);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    final state = ref.read(editorProvider);
    final vp = _viewport;
    final localPos = event.localPosition;

    final isStylusMouse = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse;

    if (isStylusMouse) {
      if (_isPanMode || event.buttons == kMiddleMouseButton) {
        _pan(event.delta);
        return;
      }
      switch (state.mode) {
        case AppMode.view:
          break;
        case AppMode.edit:
          _edit.onPointerMove(localPos, event.kind, event.buttons, vp, state);
        case AppMode.stitch:
          _stitch?.onPointerMove(localPos, event.kind, vp, state);
      }
      _scheduleRebuild();
      return;
    }

    // ── Touch ───────────────────────────────────────────────────────────────
    if (_activePointers.length >= 2) {
      if (!_hadMultiTouch) {
        _hadMultiTouch = true;
        _stitch?.cancelActiveGestures();
        _edit.cancelActiveGestures();
      }
      final pts = _activePointers.values.toList();
      _zoomPan.updatePinch(pts[0], pts[1]);
    } else if (_activePointers.length == 1) {
      if (_hadMultiTouch) {
        _pan(event.delta);
        return;
      }
      if (_isPanMode) {
        _pan(event.delta);
      } else {
        switch (state.mode) {
          case AppMode.view:
            break;
          case AppMode.edit:
            _edit.onPointerMove(localPos, event.kind, event.buttons, vp, state);
          case AppMode.stitch:
            _stitch?.onPointerMove(localPos, event.kind, vp, state);
        }
      }
    }

    // ── Kind-agnostic fallback (iPadOS Pencil unknown-kind events) ───────────
    if (_edit.select?.isActive == true && state.editMode) {
      _edit.onPointerMove(localPos, event.kind, event.buttons, vp, state);
    } else if (_stitch?.progress?.isActive == true && state.stitchMode) {
      _stitch!.onPointerMove(localPos, event.kind, vp, state);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final state = ref.read(editorProvider);
    final vp = _viewport;
    final localPos = event.localPosition;
    final wasSinglePointer = _activePointers.length == 1;

    _activeHover(state.mode)?.onPointerUp(event.kind);

    switch (state.mode) {
      case AppMode.view:
        break;
      case AppMode.edit:
        _edit.onPointerUp(
          localPos, event.kind, vp, state,
          wasSinglePointer: wasSinglePointer,
          hadMultiTouch: _hadMultiTouch,
          isPanMode: _isPanMode,
        );
      case AppMode.stitch:
        _stitch?.onPointerUp(localPos, vp, state);
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
    final localPos = event.localPosition;

    // We don't guard by kind because Apple Pencil hover events on iPadOS may
    // not always arrive as PointerDeviceKind.stylus through this path.
    switch (state.mode) {
      case AppMode.view:
        _view?.onPointerHover(localPos, event.kind, vp, state);
      case AppMode.edit:
        _edit.onPointerHover(localPos, event.kind, vp, state);
      case AppMode.stitch:
        _stitch?.onPointerHover(localPos, event.kind, vp, state);
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

    // Resolve ghost stitches (paste preview or move drag) before passing to
    // the overlay painter. Ghost thread colors are read from state so the
    // painter receives pre-resolved (Stitch, Color) data.
    final paste = _edit.paste;
    final select = _edit.select;
    List<Stitch>? ghostStitches;
    if (state.drawingMode == DrawingMode.paste && state.clipboard != null && paste != null) {
      final origin = paste.pasteOrigin ??
          Offset(state.pattern.width / 2.0, state.pattern.height / 2.0);
      final (dx, dy) = paste.effectiveOffset(origin, state.clipboard!, state.pattern);
      ghostStitches = paste.buildGhostStitches(dx, dy, state.clipboard!, EditorState.offsetStitch);
    } else if (select?.isMoving == true && state.selectionRect != null) {
      final dx = select!.moveDelta.dx.round();
      final dy = select.moveDelta.dy.round();
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
          onExit: (_) {
            switch (state.mode) {
              case AppMode.view:
                _view?.onHoverExit();
              case AppMode.edit:
                _edit.onHoverExit();
              case AppMode.stitch:
                _stitch?.onHoverExit();
            }
          },
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
                  // RepaintBoundary caches the GPU texture so Flutter skips
                  // re-rasterisation when only cursor/hover/ghost state changes.
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: CanvasStaticPainter(
                        pattern: state.pattern,
                        cellSize: _cellSize,
                        panOffset: _panOffset,
                        scale: _scale,
                        aidaColor: state.pattern.aidaColor,
                        renderCache: _renderCache,
                        cacheVersion: _renderCache.version,
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
                  // Layer visibility warning banner.
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
                  if ((select?.dragRect != null && select?.anchor != null) ||
                      (_stitch?.progress?.dragRect != null &&
                          _stitch?.progress?.anchor != null &&
                          _stitch?.progress?.hasDragged == true))
                    () {
                      final progress = _stitch?.progress;
                      final activeHover = _activeHover(state.mode);
                      final rect = select?.dragRect ?? progress!.dragRect!;
                      final anchor = select?.anchor ?? progress!.anchor!;
                      final anchorScreen = _viewport.canvasToScreen(
                        Offset(anchor.dx * _cellSize, anchor.dy * _cellSize),
                      );
                      final mp = activeHover?.mouseScreenPos;
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
                      backstitchCurrentPoint: _edit.draw?.backstitchHoverPoint,
                      isErasing: isErasing,
                      eraserSize: state.eraserSize,
                      fillEraseActive: state.fillEraseActive,
                      isDrawCursor: isDrawCursor,
                      isColorPickerCursor: isColorPickerCursor,
                      cursorScreenPos: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                          ? null
                          : _activeHover(state.mode)?.mouseScreenPos,
                      selectionRect: _stitch?.progress?.dragRect ??
                          state.progressRegion ??
                          select?.dragRect ??
                          state.selectionRect,
                      ghostStitches: ghostStitches,
                      ghostThreads: state.drawingMode == DrawingMode.paste
                          ? state.clipboardThreads
                          : null,
                      ghostOpacity: state.drawingMode == DrawingMode.paste
                          ? 0.55
                          : 1.0,
                      stylusHoverCell: _activeHover(state.mode)?.hoverCell,
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
          ]),
        );
      },
    );
  }

  MouseCursor _cursor(EditorState state) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return MouseCursor.defer;
    }
    return switch (state.drawingMode) {
      DrawingMode.pan         => SystemMouseCursors.grab,
      DrawingMode.erase       => SystemMouseCursors.none,
      DrawingMode.colorPicker => SystemMouseCursors.none,
      DrawingMode.draw        => SystemMouseCursors.none,
      DrawingMode.select      => SystemMouseCursors.precise,
      DrawingMode.paste       => _edit.paste?.ctrlHeld == true
          ? SystemMouseCursors.copy
          : _edit.paste?.shiftHeld == true
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
        if (hasLeft)
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Center(child: _NavArrowButton(icon: Icons.chevron_left, onTap: onLeft)),
          ),
        if (hasRight)
          Positioned(
            right: 0, top: 0, bottom: 0,
            child: Center(child: _NavArrowButton(icon: Icons.chevron_right, onTap: onRight)),
          ),
        if (hasUp)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Center(child: _NavArrowButton(icon: Icons.expand_less, horizontal: false, onTap: onUp)),
          ),
        if (hasDown)
          Positioned(
            bottom: 52, left: 0, right: 0,
            child: Center(child: _NavArrowButton(icon: Icons.expand_more, horizontal: false, onTap: onDown)),
          ),
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
