import 'package:flutter/material.dart' show Colors;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' show Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/widgets/canvas_viewport.dart';
import 'package:stitches/widgets/hover_handler.dart';
import 'package:stitches/widgets/page_nav_handler.dart';
import 'package:stitches/widgets/paste_handler.dart';
import 'package:stitches/widgets/select_handler.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _cellSize = 20.0;
const _vp = CanvasViewport(cellSize: _cellSize, panOffset: Offset.zero, scale: 1.0);
const _patW = 50;
const _patH = 50;

// ─── HoverHandler ─────────────────────────────────────────────────────────────

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
      // Cell at screen (25, 45) with cellSize 20 and zero pan → cell (1, 2)
      h.onPointerMove(const Offset(25, 45), _vp, _patW, _patH);
      expect(h.mouseScreenPos, const Offset(25, 45));
      expect(h.hoverCell, (1, 2));
      expect(rebuildCount, 1);
    });

    test('onPointerMove clamps out-of-bounds cell to null', () {
      // Screen (-10, -10) is outside the pattern.
      h.onPointerMove(const Offset(-10, -10), _vp, _patW, _patH);
      expect(h.hoverCell, isNull);
    });

    test('onPointerHover updates hoverCell for non-touch', () {
      h.onPointerHover(
        const Offset(60, 80),
        PointerDeviceKind.mouse,
        _vp,
        _patW,
        _patH,
      );
      expect(h.hoverCell, (3, 4));
    });

    test('onPointerHover ignores touch devices', () {
      h.onPointerHover(
        const Offset(60, 80),
        PointerDeviceKind.touch,
        _vp,
        _patW,
        _patH,
      );
      expect(h.hoverCell, isNull);
    });

    test('onPointerUp clears hoverCell for stylus', () {
      h.onPointerMove(const Offset(25, 45), _vp, _patW, _patH);
      h.onPointerUp(PointerDeviceKind.stylus);
      expect(h.hoverCell, isNull);
    });

    test('onPointerUp leaves hoverCell for touch', () {
      h.onPointerMove(const Offset(25, 45), _vp, _patW, _patH);
      // Hover cell is set via onPointerMove regardless of device kind.
      h.onPointerUp(PointerDeviceKind.touch);
      // onPointerUp for touch does not clear hoverCell.
      expect(h.hoverCell, (1, 2));
    });

    test('onExit clears both fields', () {
      h.onPointerDown(const Offset(50, 50));
      h.onPointerMove(const Offset(50, 50), _vp, _patW, _patH);
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
      h.onStylusAdded(const Offset(25, 45), _vp, _patW, _patH);
      expect(h.hoverCell, (1, 2));
    });

    test('onStylusAdded ignores out-of-bounds', () {
      h.onStylusAdded(const Offset(-5, -5), _vp, _patW, _patH);
      expect(h.hoverCell, isNull);
      expect(rebuildCount, 0); // no rebuild for out-of-bounds
    });

    test('onStylusRemoved clears hoverCell', () {
      h.onStylusAdded(const Offset(25, 45), _vp, _patW, _patH);
      h.onStylusRemoved();
      expect(h.hoverCell, isNull);
    });
  });

  // ─── PageNavHandler ────────────────────────────────────────────────────────

  group('PageNavHandler', () {
    const h = PageNavHandler();
    const size = Size(400, 600);

    test('returns false when stitchMode is false', () {
      expect(
        h.isNavZone(
          const Offset(10, 10),
          size,
          stitchMode: false,
          pageEnabled: true,
          hasPageLayout: true,
        ),
        isFalse,
      );
    });

    test('returns false when pageEnabled is false', () {
      expect(
        h.isNavZone(
          const Offset(10, 10),
          size,
          stitchMode: true,
          pageEnabled: false,
          hasPageLayout: true,
        ),
        isFalse,
      );
    });

    test('returns false when hasPageLayout is false', () {
      expect(
        h.isNavZone(
          const Offset(10, 10),
          size,
          stitchMode: true,
          pageEnabled: true,
          hasPageLayout: false,
        ),
        isFalse,
      );
    });

    test('left edge hit', () {
      expect(
        h.isNavZone(
          const Offset(10, 300),
          size,
          stitchMode: true,
          pageEnabled: true,
          hasPageLayout: true,
        ),
        isTrue,
      );
    });

    test('right edge hit', () {
      expect(
        h.isNavZone(
          Offset(size.width - 10, 300),
          size,
          stitchMode: true,
          pageEnabled: true,
          hasPageLayout: true,
        ),
        isTrue,
      );
    });

    test('top edge hit', () {
      expect(
        h.isNavZone(
          const Offset(200, 10),
          size,
          stitchMode: true,
          pageEnabled: true,
          hasPageLayout: true,
        ),
        isTrue,
      );
    });

    test('bottom guard hit', () {
      expect(
        h.isNavZone(
          Offset(200, size.height - 10),
          size,
          stitchMode: true,
          pageEnabled: true,
          hasPageLayout: true,
        ),
        isTrue,
      );
    });

    test('centre of canvas is not a nav zone', () {
      expect(
        h.isNavZone(
          Offset(size.width / 2, size.height / 2),
          size,
          stitchMode: true,
          pageEnabled: true,
          hasPageLayout: true,
        ),
        isFalse,
      );
    });
  });

  // ─── SelectHandler ─────────────────────────────────────────────────────────

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

    test('initial state', () {
      expect(h.isActive, isFalse);
      expect(h.isMoving, isFalse);
      expect(h.anchor, isNull);
      expect(h.dragRect, isNull);
    });

    test('buildSelRect includes both corners', () {
      final r = SelectHandler.buildSelRect(const Offset(2, 3), const Offset(5, 7));
      expect(r.left, 2);
      expect(r.top, 3);
      expect(r.right, 6); // 5+1
      expect(r.bottom, 8); // 7+1
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
      // Screen (25, 45) → cell (1, 2) with 20px cells, clamped to 49
      final cell = SelectHandler.toSelCell(const Offset(25, 45), _vp, _patW, _patH);
      expect(cell.dx, 1);
      expect(cell.dy, 2);
    });

    test('toSelCell clamps negative coords to 0', () {
      final cell = SelectHandler.toSelCell(const Offset(-100, -100), _vp, _patW, _patH);
      expect(cell.dx, 0);
      expect(cell.dy, 0);
    });

    test('toSelCell clamps large coords to pattern edge', () {
      final cell =
          SelectHandler.toSelCell(const Offset(10000, 10000), _vp, _patW, _patH);
      expect(cell.dx, _patW - 1);
      expect(cell.dy, _patH - 1);
    });

    test('onPointerDown outside selection starts rubber-band', () {
      h.onPointerDown(
        const Offset(25, 45), _vp, _patW, _patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      expect(h.anchor, isNotNull);
      expect(h.isMoving, isFalse);
      expect(setRectCalls, [null]); // cleared any existing selection
    });

    test('onPointerDown not on canvas does not start rubber-band', () {
      h.onPointerDown(
        const Offset(25, 45), _vp, _patW, _patH,
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
        const Offset(25, 25), _vp, _patW, _patH, // cell (1,1) inside sel
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
        const Offset(25, 25), _vp, _patW, _patH,
        currentSelectionRect: sel,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      expect(warnCalls, isNotEmpty);
    });

    test('onPointerMove updates dragRect', () {
      h.onPointerDown(
        const Offset(25, 25), _vp, _patW, _patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerMove(const Offset(65, 65), _vp, _patW, _patH);
      expect(h.dragRect, isNotNull);
      expect(h.dragRect!.width, greaterThan(1));
    });

    test('onPointerUp with drag commits non-null selection', () {
      h.onPointerDown(
        const Offset(25, 25), _vp, _patW, _patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerMove(const Offset(65, 65), _vp, _patW, _patH);
      h.onPointerUp(const Offset(65, 65), _vp, _patW, _patH);
      // setRectCalls: first null (pointer-down clear), then the drag rect
      expect(setRectCalls.last, isNotNull);
      expect(h.anchor, isNull);
    });

    test('onPointerUp without drag commits null (bare click deselects)', () {
      h.onPointerDown(
        const Offset(25, 25), _vp, _patW, _patH,
        currentSelectionRect: null,
        hasSelectedStitches: false,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      // No move → no drag.
      h.onPointerUp(const Offset(25, 25), _vp, _patW, _patH);
      expect(setRectCalls.last, isNull);
    });

    test('onPointerUp after move commits movement', () {
      final sel = Rect.fromLTRB(0, 0, 5, 5);
      h.onPointerDown(
        const Offset(25, 25), _vp, _patW, _patH,
        currentSelectionRect: sel,
        hasSelectedStitches: true,
        canvasSelectionMode: false,
        isOnCanvas: true,
      );
      h.onPointerMove(const Offset(65, 25), _vp, _patW, _patH); // 2 cells right
      h.onPointerUp(const Offset(65, 25), _vp, _patW, _patH);
      expect(moveCalls, [(2, 0)]);
    });

    test('cancel clears all state', () {
      h.onPointerDown(
        const Offset(25, 25), _vp, _patW, _patH,
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

  // ─── PasteHandler ─────────────────────────────────────────────────────────

  group('PasteHandler', () {
    late List<(int, int)> commitCalls;
    late int cancelCalls;
    late int rebuildCount;
    late PasteHandler h;

    setUp(() {
      commitCalls = [];
      cancelCalls = 0;
      rebuildCount = 0;
      h = PasteHandler(
        onCommitPaste: (dx, dy) => commitCalls.add((dx, dy)),
        onCancelSelection: () => cancelCalls++,
        scheduleRebuild: () => rebuildCount++,
      );
    });

    test('initial state', () {
      expect(h.pasteOrigin, isNull);
      expect(h.ctrlHeld, isFalse);
      expect(h.shiftHeld, isFalse);
    });

    test('updateModifiers triggers rebuild on change', () {
      h.updateModifiers(ctrl: true, shift: false);
      expect(h.ctrlHeld, isTrue);
      expect(rebuildCount, 1);
    });

    test('updateModifiers does not rebuild when unchanged', () {
      h.updateModifiers(ctrl: false, shift: false);
      expect(rebuildCount, 0);
    });

    test('centeredOffset centres clipboard on cursor', () {
      // Clipboard: single stitch at (0,0), bounds 0..1 x 0..1, centre = (0.5, 0.5)
      // Cursor at (5, 5) → offset = (5 + 0.5 - 0.5, 5 + 0.5 - 0.5) = (5, 5)
      // Wait: centeredOffset(cursorCell, clips)
      // center = (0+1)/2 = 0.5
      // dx = (5.0 + 0.5 - 0.5).round() = 5
      final offset = h.centeredOffset(const Offset(5, 5), []);
      expect(offset, (5, 5)); // empty clips → cursor coords
    });

    test('updateOrigin deduplicates same cell', () {
      h.updateOrigin(const Offset(25, 45), _vp);
      final count = rebuildCount;
      h.updateOrigin(const Offset(25, 45), _vp); // same cell
      expect(rebuildCount, count); // no second rebuild
    });

    test('updateOrigin triggers rebuild on different cell', () {
      h.updateOrigin(const Offset(25, 45), _vp);
      final count = rebuildCount;
      h.updateOrigin(const Offset(65, 45), _vp);
      expect(rebuildCount, count + 1);
    });

    test('clearOrigin resets origin and rebuilds', () {
      h.updateOrigin(const Offset(25, 45), _vp);
      rebuildCount = 0;
      h.clearOrigin();
      expect(h.pasteOrigin, isNull);
      expect(rebuildCount, 1);
    });

    test('commit with no origin returns false', () {
      final result = h.commit(_fakePattern(), []);
      expect(result, isFalse);
      expect(commitCalls, isEmpty);
    });

    test('commit calls onCommitPaste', () {
      h.setOrigin(const Offset(100, 100), _vp);
      h.commit(_fakePattern(), []);
      expect(commitCalls, isNotEmpty);
    });

    test('commit without ctrl calls onCancelSelection', () {
      h.setOrigin(const Offset(100, 100), _vp);
      h.commit(_fakePattern(), []);
      expect(cancelCalls, 1);
    });

    test('commit with ctrl does not call onCancelSelection', () {
      h.updateModifiers(ctrl: true, shift: false);
      h.setOrigin(const Offset(100, 100), _vp);
      h.commit(_fakePattern(), []);
      expect(cancelCalls, 0);
    });
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

CrossStitchPattern _fakePattern() {
  return CrossStitchPattern(
    name: 'test',
    width: 20,
    height: 20,
    aidaColor: Colors.white,
    threads: const [],
    layerItems: const [],
  );
}
