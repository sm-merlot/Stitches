import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/widgets/handlers/hover_handler.dart';
import 'test_helpers.dart';

void main() {
  group('HoverHandler', () {
    late int rebuildCount;
    late HoverHandler h;

    setUp(() {
      rebuildCount = 0;
      h = HoverHandler(scheduleRebuild: () => rebuildCount++);
    });

    test('initial state is null', () {
      expect(h.mouseScreenPos, isNull);
      expect(h.hoverCell, isNull);
    });

    test('onPointerDown sets mouseScreenPos', () {
      h.onPointerDown(const Offset(100, 200));
      expect(h.mouseScreenPos, const Offset(100, 200));
    });

    test('onPointerMove updates mouseScreenPos and hoverCell', () {
      // Screen (25, 45) → cell (1, 2) with cellSize=20, zero pan
      h.onPointerMove(const Offset(25, 45), vp, patW, patH);
      expect(h.mouseScreenPos, const Offset(25, 45));
      expect(h.hoverCell, (1, 2));
      expect(rebuildCount, 1);
    });

    test('onPointerMove clamps out-of-bounds cell to null', () {
      h.onPointerMove(const Offset(-10, -10), vp, patW, patH);
      expect(h.hoverCell, isNull);
    });

    test('onPointerHover updates hoverCell for mouse', () {
      h.onPointerHover(const Offset(60, 80), PointerDeviceKind.mouse, vp, patW, patH);
      expect(h.hoverCell, (3, 4));
    });

    test('onPointerHover ignores touch devices', () {
      h.onPointerHover(const Offset(60, 80), PointerDeviceKind.touch, vp, patW, patH);
      expect(h.hoverCell, isNull);
    });

    test('onPointerUp clears hoverCell for stylus', () {
      h.onPointerMove(const Offset(25, 45), vp, patW, patH);
      h.onPointerUp(PointerDeviceKind.stylus);
      expect(h.hoverCell, isNull);
    });

    test('onPointerUp leaves hoverCell for touch', () {
      h.onPointerMove(const Offset(25, 45), vp, patW, patH);
      h.onPointerUp(PointerDeviceKind.touch);
      expect(h.hoverCell, (1, 2));
    });

    test('onExit clears both fields', () {
      h.onPointerDown(const Offset(50, 50));
      h.onPointerMove(const Offset(50, 50), vp, patW, patH);
      h.onExit();
      expect(h.mouseScreenPos, isNull);
      expect(h.hoverCell, isNull);
    });

    test('onExit calls scheduleRebuild', () {
      rebuildCount = 0;
      h.onExit();
      expect(rebuildCount, 1);
    });

    test('onStylusAdded sets hoverCell when in bounds', () {
      h.onStylusAdded(const Offset(25, 45), vp, patW, patH);
      expect(h.hoverCell, (1, 2));
    });

    test('onStylusAdded ignores out-of-bounds', () {
      h.onStylusAdded(const Offset(-5, -5), vp, patW, patH);
      expect(h.hoverCell, isNull);
      expect(rebuildCount, 0);
    });

    test('onStylusRemoved clears hoverCell', () {
      h.onStylusAdded(const Offset(25, 45), vp, patW, patH);
      h.onStylusRemoved();
      expect(h.hoverCell, isNull);
    });
  });
}
