import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        PointerPanZoomEndEvent,
        PointerPanZoomStartEvent,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:flutter/widgets.dart' show Offset;
import '../canvas/canvas_viewport.dart';

/// Handles all zoom and pan input — scroll wheel, trackpad pinch/pan,
/// touch two-finger pinch, and programmatic pan/zoom.
///
/// Owns the viewport state ([scale], [panOffset]) and all gesture-tracking
/// intermediaries. [AidaWidget] forwards the relevant events; after each
/// call it reads [scale] / [panOffset] to drive its build.
///
/// Callbacks ([scheduleRebuild], [save], [debouncedSave]) are injected so the
/// handler is fully unit-testable without a Flutter widget tree.
///
/// ## Touch pinch lifecycle
///
/// When the second finger goes down, call [beginPinch] with both screen
/// positions. On each move with ≥2 fingers, call [updatePinch]. When all
/// fingers lift, call [resetPinch].
class ZoomPanHandler {
  double _scale;
  Offset _panOffset;
  final double _cellSize;

  /// Called whenever scale or panOffset changes — host should schedule a
  /// widget rebuild so the new viewport is reflected on screen.
  final void Function() scheduleRebuild;

  /// Called when a gesture ends cleanly (pointer up, trackpad end). Host
  /// should persist the viewport position to the editor state.
  final void Function() save;

  /// Called when no discrete gesture-end event exists (scroll wheel).
  /// Host should debounce-save the viewport position.
  final void Function() debouncedSave;

  // ── Touch pinch tracking ────────────────────────────────────────────────────
  double _pinchStartDistance = 0.0;
  Offset _pinchStartCenter = Offset.zero;
  double _gestureStartScale = 1.0;
  Offset _gestureStartOffset = Offset.zero;

  // ── Trackpad pinch tracking (macOS PointerPanZoom events) ──────────────────
  double _trackpadStartScale = 1.0;
  Offset _trackpadStartPanOffset = Offset.zero;

  ZoomPanHandler({
    required double initialScale,
    required Offset initialPanOffset,
    required double cellSize,
    required this.scheduleRebuild,
    required this.save,
    required this.debouncedSave,
  })  : _scale = initialScale,
        _panOffset = initialPanOffset,
        _cellSize = cellSize;

  // ── Viewport accessors ──────────────────────────────────────────────────────

  double get scale => _scale;
  Offset get panOffset => _panOffset;

  /// Directly set viewport — used for external sync (initState restore,
  /// fit-to-page animation).
  void setViewport(double scale, Offset panOffset) {
    _scale = scale;
    _panOffset = panOffset;
  }

  // ── Core operations ─────────────────────────────────────────────────────────

  /// Translates the viewport by [delta] screen pixels.
  void pan(Offset delta) {
    _panOffset += delta;
    scheduleRebuild();
  }

  /// Zooms by [factor] keeping [focalPoint] (screen coords) stationary.
  void zoomAround(Offset focalPoint, double factor) {
    final next = _buildViewport().zoomedAround(focalPoint, factor);
    _panOffset = next.panOffset;
    _scale = next.scale;
    scheduleRebuild();
  }

  // ── Touch pinch ─────────────────────────────────────────────────────────────

  /// Record the initial two-finger state when the second finger touches down.
  void beginPinch(Offset p0, Offset p1) {
    _pinchStartDistance = (p0 - p1).distance;
    _pinchStartCenter = (p0 + p1) / 2;
    _gestureStartScale = _scale;
    _gestureStartOffset = _panOffset;
  }

  /// Update scale and pan as the two fingers move. No-op if no pinch is active.
  void updatePinch(Offset p0, Offset p1) {
    if (_pinchStartDistance <= 0) return;
    final currentDist = (p0 - p1).distance;
    final currentCenter = (p0 + p1) / 2;
    final newScale =
        (_gestureStartScale * currentDist / _pinchStartDistance).clamp(0.1, 20.0);
    final scaleFactor = newScale / _gestureStartScale;
    _scale = newScale;
    _panOffset = _pinchStartCenter -
        (_pinchStartCenter - _gestureStartOffset) * scaleFactor +
        (currentCenter - _pinchStartCenter);
    scheduleRebuild();
  }

  /// Reset pinch state when all fingers lift. Saves the final viewport.
  void resetPinch() {
    _pinchStartDistance = 0;
    save();
  }

  // ── Trackpad (macOS PointerPanZoom events) ──────────────────────────────────

  void onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadStartScale = _scale;
    _trackpadStartPanOffset = _panOffset;
  }

  void onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final newScale = (_trackpadStartScale * event.scale).clamp(0.1, 20.0);
    _panOffset = event.localPosition -
        (event.localPosition - _trackpadStartPanOffset) *
            (newScale / _trackpadStartScale) +
        event.pan;
    _scale = newScale;
    scheduleRebuild();
  }

  void onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    save();
  }

  // ── Scroll wheel ────────────────────────────────────────────────────────────

  /// Handles [PointerScrollEvent] — vertical mouse scroll zooms, horizontal
  /// (or mixed) trackpad scroll pans.
  ///
  /// Returns `true` if the event was consumed (it was a scroll event).
  bool onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return false;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    // Pinch-to-zoom on trackpad sends very small deltas; scroll wheel sends ±120.
    // Pure vertical mouse scroll → zoom; horizontal or mixed → pan.
    if (event.kind == PointerDeviceKind.mouse && dx == 0) {
      zoomAround(event.localPosition, dy > 0 ? 0.9 : 1.1);
    } else {
      pan(Offset(-dx, -dy));
    }
    // No discrete end event for scroll — debounce the save.
    debouncedSave();
    return true;
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  CanvasViewport _buildViewport() => CanvasViewport(
        cellSize: _cellSize,
        panOffset: _panOffset,
        scale: _scale,
      );
}
