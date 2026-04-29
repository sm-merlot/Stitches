import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/widgets/handlers/select_handler.dart';
import '../test_helpers.dart';

void main() {
  group('SelectHandler', () {
    late List<Rect?> setRectCalls;
    late List<(int, int)> moveCalls;
    late List<String> warnCalls;
    late int rebuildCount;
    late SelectHandler h;

    setUp(() {
      setRectCalls = [];
      moveCalls = [];
      warnCalls = [];
      rebuildCount = 0;
      h = SelectHandler(
        onSetSelectionRect: (r) => setRectCalls.add(r),
        onMoveSelection: (dx, dy) => moveCalls.add((dx, dy)),
        onWarning: (m) => warnCalls.add(m),
        scheduleRebuild: () => rebuildCount++,
      );
    });

    // ── static helpers ────────────────────────────────────────────────────────

    test('buildSelRect includes both corners', () {
      final r = SelectHandler.buildSelRect(const Offset(2, 3), const Offset(5, 7));
      expect(r.left, 2);
      expect(r.top, 3);
      expect(r.right, 6);   // 5+1
      expect(r.bottom, 8);  // 7+1
    });

    test('buildSelRect handles reversed corners', () {
      final r = SelectHandler.buildSelRect(const Offset(5, 7), const Offset(2, 3));
      expect(r.left, 2);
      expect(r.top, 3);
    });

    test('cellInSelRect includes boundary', () {
      final r = Rect.fromLTRB(2, 3, 6, 8);
      expect(SelectHandler.cellInSelRect(2, 3, r), isTrue);
      expect(SelectHandler.cellInSelRect(5, 7, r), isTrue);
      expect(SelectHandler.cellInSelRect(6, 8, r), isFalse); // right/bottom exclusive
    });

    test('toSelCell maps screen position to clamped cell', () {
      final cell = SelectHandler.toSelCell(const Offset(25, 45), vp, patW, patH);
      expect(cell.dx, 1);
      expect(cell.dy, 2);
    });

    test('toSelCell clamps negative coords to 0', () {
      final cell = SelectHandler.toSelCell(const Offset(-100, -100), vp, patW, patH);
      expect(cell.dx, 0);
      expect(cell.dy, 0);
    });

    test('toSelCell clamps large coords to pattern edge', () {
      final cell = SelectHandler.toSelCell(const Offset(10000, 10000), vp, patW, patH);
      expect(cell.dx, patW - 1);
      expect(cell.dy, patH - 1);
    });

    // ── initial state ─────────────────────────────────────────────────────────

    test('initial state', () {
      expect(h.isActive, isFalse);
      expect(h.isMoving, isFalse);
      expect(h.anchor, isNull);
      expect(h.dragRect, isNull);
    });

    // ── pointer down ──────────────────────────────────────────────────────────

    test('onPointerDown outside selection starts rubber-band', () {
      h.onPointerDown(
        const Offset(25, 45), vp, patW, patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      expect(h.anchor, isNotNull);
      expect(h.isMoving, isFalse);
      expect(setRectCalls, [null]); // clears existing selection
    });

    test('onPointerDown not on canvas does nothing', () {
      h.onPointerDown(
        const Offset(25, 45), vp, patW, patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: false,
      );
      expect(h.anchor, isNull);
    });

    test('onPointerDown inside selection with stitches starts move', () {
      final sel = Rect.fromLTRB(0, 0, 5, 5);
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH, // cell (1,1) inside sel
        currentSelectionRect: sel,
        hasSelectedStitches: true,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      expect(h.isMoving, isTrue);
    });

    test('onPointerDown inside selection without stitches warns', () {
      final sel = Rect.fromLTRB(0, 0, 5, 5);
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH,
        currentSelectionRect: sel,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      expect(warnCalls, isNotEmpty);
    });

    // ── pointer move ──────────────────────────────────────────────────────────

    test('onPointerMove updates dragRect', () {
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerMove(const Offset(65, 65), vp, patW, patH);
      expect(h.dragRect, isNotNull);
      expect(h.dragRect!.width, greaterThan(1));
    });

    // ── pointer up ────────────────────────────────────────────────────────────

    test('onPointerUp after drag commits non-null rect', () {
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerMove(const Offset(65, 65), vp, patW, patH);
      h.onPointerUp(const Offset(65, 65), vp, patW, patH);
      expect(setRectCalls.last, isNotNull);
      expect(h.anchor, isNull);
    });

    test('onPointerUp without drag commits null (bare click deselects)', () {
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerUp(const Offset(25, 25), vp, patW, patH);
      expect(setRectCalls.last, isNull);
    });

    test('onPointerUp after move commits movement delta', () {
      final sel = Rect.fromLTRB(0, 0, 5, 5);
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH, // cell (1,1)
        currentSelectionRect: sel,
        hasSelectedStitches: true,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerMove(const Offset(65, 25), vp, patW, patH); // cell (3,1) → Δx=2
      h.onPointerUp(const Offset(65, 25), vp, patW, patH);
      expect(moveCalls, [(2, 0)]);
    });

    // ── cancel ────────────────────────────────────────────────────────────────

    test('cancel clears all state', () {
      h.onPointerDown(
        const Offset(25, 25), vp, patW, patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.cancel();
      expect(h.isActive, isFalse);
      expect(h.anchor, isNull);
      expect(h.dragRect, isNull);
    });
  });
}
