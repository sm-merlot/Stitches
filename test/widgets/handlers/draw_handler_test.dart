import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/widgets/handlers/draw_handler.dart';
import '../test_helpers.dart';

void main() {
  group('DrawHandler', () {
    late List<Stitch> addedStitches;
    late List<(int, int)> removedAt;
    late List<(int, int, int)> removedBox;
    late List<(int, int, bool)> floodFills;
    late List<(int, int)> pickedColors;
    late List<Offset?> backstitchStarts;
    late List<String> warnings;
    late bool ctrlHeld;
    late DrawHandler h;

    setUp(() {
      addedStitches = [];
      removedAt = [];
      removedBox = [];
      floodFills = [];
      pickedColors = [];
      backstitchStarts = [];
      warnings = [];
      ctrlHeld = false;
      h = DrawHandler(
        onAddStitch: (s) => addedStitches.add(s),
        onRemoveAt: (x, y) => removedAt.add((x, y)),
        onRemoveBox: (x, y, sz) => removedBox.add((x, y, sz)),
        onFloodFill: (x, y, {required bool erase}) =>
            floodFills.add((x, y, erase)),
        onPickColor: (x, y) => pickedColors.add((x, y)),
        onSetBackstitchStart: (p) => backstitchStarts.add(p),
        onLayerWarning: (m) => warnings.add(m),
        getCtrlHeld: () => ctrlHeld,
      );
    });

    // ── editMode guard ────────────────────────────────────────────────────────

    test('does nothing when not in edit mode', () {
      final state = fakeEditState().copyWith(mode: AppMode.view);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(addedStitches, isEmpty);
      expect(removedAt, isEmpty);
    });

    // ── draw — full stitch ────────────────────────────────────────────────────

    test('adds FullStitch at correct cell in draw mode', () {
      final state = fakeEditState();
      h.handleDrawAt(const Offset(10, 10), state, vp); // canvas (10,10) → cell (0,0)
      expect(addedStitches, hasLength(1));
      final s = addedStitches.first as FullStitch;
      expect(s.x, 0);
      expect(s.y, 0);
      expect(s.threadId, 'DMC310');
    });

    test('does nothing when cell is out of bounds', () {
      final state = fakeEditState();
      h.handleDrawAt(const Offset(-5, -5), state, vp); // cell (-1,-1)
      expect(addedStitches, isEmpty);
    });

    test('does nothing when no thread selected', () {
      final state = fakeEditState(selectedThreadId: null);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(addedStitches, isEmpty);
    });

    test('adds HalfStitch(forward) for halfForward tool', () {
      final state = fakeEditState(currentTool: DrawingTool.halfForward);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(addedStitches.first, isA<HalfStitch>());
      expect((addedStitches.first as HalfStitch).isForward, isTrue);
    });

    test('adds HalfStitch(backward) for halfBackward tool', () {
      final state = fakeEditState(currentTool: DrawingTool.halfBackward);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect((addedStitches.first as HalfStitch).isForward, isFalse);
    });

    test('adds QuarterStitch for quarterDiag tool', () {
      final state = fakeEditState(currentTool: DrawingTool.quarterDiag);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(addedStitches.first, isA<QuarterStitch>());
    });

    // ── erase mode ────────────────────────────────────────────────────────────

    test('calls onRemoveAt in erase mode', () {
      final state = fakeEditState(drawingMode: DrawingMode.erase);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(removedAt, [(0, 0)]);
    });

    test('calls onRemoveBox when eraserSize > 1', () {
      final state = fakeEditState(drawingMode: DrawingMode.erase, eraserSize: 3);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(removedBox, [(0, 0, 3)]);
    });

    test('calls onFloodFill(erase:true) when fillEraseActive', () {
      final state = fakeEditState(
          drawingMode: DrawingMode.erase, fillEraseActive: true);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(floodFills, [(0, 0, true)]);
    });

    test('fill-erase guard fires only once per pointer down', () {
      final state = fakeEditState(
          drawingMode: DrawingMode.erase, fillEraseActive: true);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(floodFills, hasLength(1));
    });

    test('onPointerUp resets fill-erase guard', () {
      final state = fakeEditState(
          drawingMode: DrawingMode.erase, fillEraseActive: true);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      h.onPointerUp();
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(floodFills, hasLength(2));
    });

    // ── fill tool ─────────────────────────────────────────────────────────────

    test('calls onFloodFill(erase:false) for fill tool', () {
      final state = fakeEditState(currentTool: DrawingTool.fill);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(floodFills, [(0, 0, false)]);
    });

    test('fill tool guard fires only once per pointer down', () {
      final state = fakeEditState(currentTool: DrawingTool.fill);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(floodFills, hasLength(1));
    });

    test('onPointerUp resets fill-tool guard', () {
      final state = fakeEditState(currentTool: DrawingTool.fill);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      h.onPointerUp();
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(floodFills, hasLength(2));
    });

    // ── color picker ──────────────────────────────────────────────────────────

    test('calls onPickColor in colorPicker mode', () {
      final state = fakeEditState(drawingMode: DrawingMode.colorPicker);
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(pickedColors, [(0, 0)]);
    });

    // ── backstitch ────────────────────────────────────────────────────────────

    test('first backstitch tap sets start point', () {
      final state = fakeEditState(currentTool: DrawingTool.backstitch);
      h.handleDrawAt(const Offset(0, 0), state, vp);
      expect(backstitchStarts, hasLength(1));
      expect(backstitchStarts.first, isNotNull);
    });

    test('second backstitch tap at different point adds BackStitch', () {
      // Start already set at grid (0,0)
      final state = fakeEditState(
        currentTool: DrawingTool.backstitch,
        backstitchStartPoint: const Offset(0.0, 0.0),
      );
      // Screen (20, 0) → canvas (20,0) → gridPt (1.0, 0.0)
      h.handleDrawAt(const Offset(20, 0), state, vp);
      expect(addedStitches, hasLength(1));
      final bs = addedStitches.first as BackStitch;
      expect(bs.x1, 0.0);
      expect(bs.y1, 0.0);
      expect(bs.x2, 1.0);
      expect(bs.y2, 0.0);
    });

    test('second backstitch tap at same point cancels start', () {
      final state = fakeEditState(
        currentTool: DrawingTool.backstitch,
        backstitchStartPoint: const Offset(0.0, 0.0),
      );
      // Screen (0, 0) → gridPt (0.0, 0.0) — same as start
      h.handleDrawAt(const Offset(0, 0), state, vp);
      expect(backstitchStarts.last, isNull);
      expect(addedStitches, isEmpty);
    });

    test('backstitch with chain mode: start chains to end point', () {
      final state = fakeEditState(
        currentTool: DrawingTool.backstitch,
        backstitchStartPoint: const Offset(0.0, 0.0),
        backstitchChainMode: true,
      );
      h.handleDrawAt(const Offset(20, 0), state, vp); // gridPt (1.0, 0.0)
      // Chain mode → new start = end point
      expect(backstitchStarts.last, const Offset(1.0, 0.0));
    });

    test('backstitch with ctrl held: start chains to end point', () {
      ctrlHeld = true;
      final state = fakeEditState(
        currentTool: DrawingTool.backstitch,
        backstitchStartPoint: const Offset(0.0, 0.0),
      );
      h.handleDrawAt(const Offset(20, 0), state, vp);
      expect(backstitchStarts.last, const Offset(1.0, 0.0));
    });

    // ── backstitch hover ──────────────────────────────────────────────────────

    test('updateBackstitchHover sets hover point', () {
      h.updateBackstitchHover(const Offset(10, 10), vp);
      expect(h.backstitchHoverPoint, isNotNull);
    });

    test('clearBackstitchHover clears hover point', () {
      h.updateBackstitchHover(const Offset(10, 10), vp);
      h.clearBackstitchHover();
      expect(h.backstitchHoverPoint, isNull);
    });

    // ── layer warnings ────────────────────────────────────────────────────────

    test('warns when drawing on hidden active layer', () {
      final layer = fakeLayer(visible: false);
      final state = fakeEditState(pattern: fakePattern(layers: [layer]));
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(warnings, isNotEmpty);
    });

    test('warns when erasing on wrong layer', () {
      // active layer has no stitch; a different visible layer does
      const existingStitch = FullStitch(x: 0, y: 0, threadId: 'DMC310');
      final otherLayer = fakeLayer(id: 'other', stitches: [existingStitch]);
      final activeLayer = fakeLayer(); // empty active layer
      final state = fakeEditState(
        pattern: fakePattern(layers: [activeLayer, otherLayer]),
        drawingMode: DrawingMode.erase,
      );
      h.handleDrawAt(const Offset(10, 10), state, vp);
      expect(warnings, isNotEmpty);
    });
  });
}
