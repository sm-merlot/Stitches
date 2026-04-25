import 'dart:ui' show Offset;
import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        PointerPanZoomEndEvent,
        PointerPanZoomStartEvent,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/widgets/zoom_pan_handler.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

const double _cellSize = 20.0;
const double _initScale = 1.0;
const Offset _initPan = Offset(20, 20);

ZoomPanHandler _handler({
  void Function()? onRebuild,
  void Function()? onSave,
  void Function()? onDebouncedSave,
}) =>
    ZoomPanHandler(
      initialScale: _initScale,
      initialPanOffset: _initPan,
      cellSize: _cellSize,
      scheduleRebuild: onRebuild ?? () {},
      save: onSave ?? () {},
      debouncedSave: onDebouncedSave ?? () {},
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Initial state ──────────────────────────────────────────────────────────

  test('initial scale and panOffset match constructor args', () {
    final h = _handler();
    expect(h.scale, _initScale);
    expect(h.panOffset, _initPan);
  });

  // ── setViewport ────────────────────────────────────────────────────────────

  test('setViewport updates scale and panOffset', () {
    final h = _handler();
    h.setViewport(2.0, const Offset(100, 200));
    expect(h.scale, 2.0);
    expect(h.panOffset, const Offset(100, 200));
  });

  // ── pan ────────────────────────────────────────────────────────────────────

  test('pan moves panOffset by delta', () {
    final h = _handler();
    h.pan(const Offset(10, -5));
    expect(h.panOffset, _initPan + const Offset(10, -5));
  });

  test('pan calls scheduleRebuild', () {
    int count = 0;
    final h = _handler(onRebuild: () => count++);
    h.pan(const Offset(1, 1));
    expect(count, 1);
  });

  test('pan does not call save', () {
    int count = 0;
    final h = _handler(onSave: () => count++);
    h.pan(const Offset(1, 1));
    expect(count, 0);
  });

  // ── zoomAround ────────────────────────────────────────────────────────────

  test('zoomAround with factor > 1 increases scale', () {
    final h = _handler();
    h.zoomAround(const Offset(100, 100), 1.5);
    expect(h.scale, greaterThan(1.0));
  });

  test('zoomAround with factor < 1 decreases scale', () {
    final h = _handler();
    h.zoomAround(const Offset(100, 100), 0.5);
    expect(h.scale, lessThan(1.0));
  });

  test('zoomAround keeps focal point stationary in canvas space', () {
    final h = _handler();
    // Focal point at screen (50, 50).
    const focal = Offset(50, 50);
    // Canvas coords before zoom: (focal - panOffset) / scale.
    final canvasBefore = (focal - h.panOffset) / h.scale;

    h.zoomAround(focal, 2.0);

    // Canvas coords after zoom should be the same.
    final canvasAfter = (focal - h.panOffset) / h.scale;
    expect(canvasAfter.dx, closeTo(canvasBefore.dx, 0.001));
    expect(canvasAfter.dy, closeTo(canvasBefore.dy, 0.001));
  });

  test('zoomAround clamps scale to 0.1 minimum', () {
    final h = _handler();
    for (int i = 0; i < 20; i++) {
      h.zoomAround(Offset.zero, 0.1);
    }
    expect(h.scale, greaterThanOrEqualTo(0.1));
  });

  test('zoomAround clamps scale to 20.0 maximum', () {
    final h = _handler();
    for (int i = 0; i < 20; i++) {
      h.zoomAround(Offset.zero, 10.0);
    }
    expect(h.scale, lessThanOrEqualTo(20.0));
  });

  test('zoomAround calls scheduleRebuild', () {
    int count = 0;
    final h = _handler(onRebuild: () => count++);
    h.zoomAround(const Offset(0, 0), 2.0);
    expect(count, 1);
  });

  // ── touch pinch ───────────────────────────────────────────────────────────

  test('beginPinch + updatePinch zooms toward focal point', () {
    final h = _handler();
    const p0 = Offset(40, 100);
    const p1 = Offset(160, 100);
    h.beginPinch(p0, p1); // distance = 120

    // Move fingers further apart (distance = 240 → 2× scale).
    const p0b = Offset(-20, 100);
    const p1b = Offset(220, 100);
    h.updatePinch(p0b, p1b);

    expect(h.scale, closeTo(2.0, 0.001));
  });

  test('updatePinch is no-op before beginPinch', () {
    final h = _handler();
    final scaleBefore = h.scale;
    final panBefore = h.panOffset;
    h.updatePinch(const Offset(0, 0), const Offset(100, 0));
    expect(h.scale, scaleBefore);
    expect(h.panOffset, panBefore);
  });

  test('resetPinch calls save', () {
    int saveCount = 0;
    final h = _handler(onSave: () => saveCount++);
    h.beginPinch(const Offset(0, 0), const Offset(100, 0));
    h.resetPinch();
    expect(saveCount, 1);
  });

  test('updatePinch is no-op after resetPinch', () {
    final h = _handler();
    h.beginPinch(const Offset(0, 0), const Offset(100, 0));
    h.resetPinch();
    final scaleAfterReset = h.scale;
    h.updatePinch(const Offset(0, 0), const Offset(400, 0)); // would 4× scale
    expect(h.scale, scaleAfterReset); // no change
  });

  // ── trackpad ──────────────────────────────────────────────────────────────

  test('onPointerPanZoomUpdate changes scale and panOffset', () {
    final h = _handler();
    h.onPointerPanZoomStart(const PointerPanZoomStartEvent(
      position: Offset.zero,
      timeStamp: Duration.zero,
    ));
    h.onPointerPanZoomUpdate(const PointerPanZoomUpdateEvent(
      position: Offset(100, 100),
      timeStamp: Duration.zero,
      pan: Offset.zero,
      scale: 2.0,
      rotation: 0.0,
      panDelta: Offset.zero,
    ));
    expect(h.scale, closeTo(2.0, 0.001));
  });

  test('onPointerPanZoomEnd calls save', () {
    int saveCount = 0;
    final h = _handler(onSave: () => saveCount++);
    h.onPointerPanZoomEnd(const PointerPanZoomEndEvent(
      position: Offset.zero,
      timeStamp: Duration.zero,
    ));
    expect(saveCount, 1);
  });

  // ── scroll wheel ──────────────────────────────────────────────────────────

  test('onPointerSignal: vertical mouse scroll zooms', () {
    final h = _handler();
    final scaleBefore = h.scale;
    h.onPointerSignal(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: const Offset(100, 100),
      scrollDelta: const Offset(0, 120), // scroll down → zoom out
      timeStamp: Duration.zero,
    ));
    expect(h.scale, lessThan(scaleBefore));
  });

  test('onPointerSignal: vertical mouse scroll up zooms in', () {
    final h = _handler();
    final scaleBefore = h.scale;
    h.onPointerSignal(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: const Offset(100, 100),
      scrollDelta: const Offset(0, -120), // scroll up → zoom in
      timeStamp: Duration.zero,
    ));
    expect(h.scale, greaterThan(scaleBefore));
  });

  test('onPointerSignal: horizontal trackpad scroll pans', () {
    final h = _handler();
    final panBefore = h.panOffset;
    h.onPointerSignal(PointerScrollEvent(
      kind: PointerDeviceKind.trackpad,
      position: const Offset(100, 100),
      scrollDelta: const Offset(30, 0),
      timeStamp: Duration.zero,
    ));
    // Horizontal scroll → pan (delta negated: -30 in x).
    expect(h.panOffset.dx, closeTo(panBefore.dx - 30, 0.001));
    expect(h.panOffset.dy, closeTo(panBefore.dy, 0.001));
  });

  test('onPointerSignal: returns true for scroll event', () {
    final h = _handler();
    final consumed = h.onPointerSignal(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: Offset.zero,
      scrollDelta: const Offset(0, 120),
      timeStamp: Duration.zero,
    ));
    expect(consumed, isTrue);
  });

  test('onPointerSignal: calls debouncedSave, not save', () {
    int saveCount = 0;
    int debouncedCount = 0;
    final h = _handler(
      onSave: () => saveCount++,
      onDebouncedSave: () => debouncedCount++,
    );
    h.onPointerSignal(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: Offset.zero,
      scrollDelta: const Offset(0, 120),
      timeStamp: Duration.zero,
    ));
    expect(saveCount, 0);
    expect(debouncedCount, 1);
  });
}
