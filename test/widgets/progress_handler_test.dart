import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/pattern_progress.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/widgets/progress_handler.dart';
import 'test_helpers.dart';

void main() {
  group('ProgressHandler', () {
    late List<(int, int)> toggledStitches;
    late List<(double, double, double, double)> toggledBackstitches;
    late List<(int, int, bool?, bool)> floodFills;
    late List<Rect?> progressRegions;
    late int rebuildCount;
    late ProgressHandler h;

    setUp(() {
      toggledStitches = [];
      toggledBackstitches = [];
      floodFills = [];
      progressRegions = [];
      rebuildCount = 0;
      h = ProgressHandler(
        onToggleStitchDone: (x, y) => toggledStitches.add((x, y)),
        onToggleBackstitchDone: (x1, y1, x2, y2) =>
            toggledBackstitches.add((x1, y1, x2, y2)),
        onFloodFillDone: (x, y,
                {bool? originalStartIsDone, bool afterSingleTap = false}) =>
            floodFills.add((x, y, originalStartIsDone, afterSingleTap)),
        onSetProgressRegion: (r) => progressRegions.add(r),
        scheduleRebuild: () => rebuildCount++,
      );
    });

    // ── initial state ─────────────────────────────────────────────────────────

    test('initial state', () {
      expect(h.isActive, isFalse);
      expect(h.anchor, isNull);
      expect(h.dragRect, isNull);
      expect(h.hasDragged, isFalse);
    });

    // ── pointer down ──────────────────────────────────────────────────────────

    test('onPointerDown sets anchor and schedules rebuild', () {
      final state = fakeStitchState();
      rebuildCount = 0;
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      expect(h.isActive, isTrue);
      expect(h.anchor, isNotNull);
      expect(rebuildCount, greaterThan(0));
    });

    // ── pointer move (mouse/stylus) ───────────────────────────────────────────

    test('onPointerMove registers drag after crossing kDragThreshold', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      // Move less than kDragThreshold (10px) — no drag yet
      h.onPointerMove(const Offset(30, 25), vp, patW, patH);
      expect(h.hasDragged, isFalse);
      // Move past threshold
      h.onPointerMove(const Offset(45, 25), vp, patW, patH);
      expect(h.hasDragged, isTrue);
    });

    test('onPointerMove updates dragRect', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerMove(const Offset(65, 65), vp, patW, patH);
      expect(h.dragRect, isNotNull);
    });

    // ── touch move ────────────────────────────────────────────────────────────

    test('onTouchMove registers drag when rect grows beyond 1 cell', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      // Same cell — no drag
      h.onTouchMove(const Offset(30, 25), vp, patW, patH);
      expect(h.hasDragged, isFalse);
      // Different cell
      h.onTouchMove(const Offset(65, 25), vp, patW, patH);
      expect(h.hasDragged, isTrue);
    });

    // ── pointer up — tap (single toggle) ─────────────────────────────────────

    test('onPointerUp without drag calls onToggleStitchDone', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state); // cell (1,1)
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      expect(toggledStitches, [(1, 1)]);
      expect(h.isActive, isFalse);
    });

    // ── pointer up — drag (region) ────────────────────────────────────────────

    test('onPointerUp after drag calls onSetProgressRegion with non-null rect', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerMove(const Offset(65, 65), vp, patW, patH); // crosses threshold
      h.onPointerUp(const Offset(65, 65), vp, patW, patH, state);
      expect(progressRegions.last, isNotNull);
      expect(progressRegions.last!.width, greaterThan(1));
    });

    // ── double-click flood fill ───────────────────────────────────────────────

    test('double-click fires onFloodFillDone', () {
      final state = fakeStitchState();
      // First down+up
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      // Second down immediately after (< 500 ms, same cell) triggers double-click
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      expect(floodFills, hasLength(1));
      expect(floodFills.first.$1, 1); // cell x
      expect(floodFills.first.$2, 1); // cell y
    });

    test('triple-click does not fire a second flood fill', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state); // triggers double-click
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      // Third down — timer was reset so it's a fresh first-click
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      // Only one flood fill total
      expect(floodFills, hasLength(1));
    });

    // ── backstitch hit ────────────────────────────────────────────────────────

    test('getBackstitchHit returns backstitch within hit radius', () {
      // BackStitch from (0,0)→(1,0) in cell space.
      // Screen (10, 4) → canvas (10,4) → px=0.5, py=0.2 → dist to segment ≈ 0.2 < 0.3
      const bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: 'DMC310');
      final layer = fakeLayer(stitches: [bs]);
      final state = fakeStitchState(pattern: fakePattern(layers: [layer]));
      final hit = h.getBackstitchHit(const Offset(10, 4), vp, state);
      expect(hit, isNotNull);
    });

    test('getBackstitchHit returns null outside hit radius', () {
      const bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: 'DMC310');
      final layer = fakeLayer(stitches: [bs]);
      final state = fakeStitchState(pattern: fakePattern(layers: [layer]));
      // Screen (10, 10) → py = 0.5 > 0.3 → no hit
      final hit = h.getBackstitchHit(const Offset(10, 10), vp, state);
      expect(hit, isNull);
    });

    test('getBackstitchHit returns null in stitchCrossMode', () {
      const bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: 'DMC310');
      final layer = fakeLayer(stitches: [bs]);
      final state = fakeStitchState(
          pattern: fakePattern(layers: [layer]), stitchCrossMode: true);
      final hit = h.getBackstitchHit(const Offset(10, 4), vp, state);
      expect(hit, isNull);
    });

    test('getBackstitchHit respects stitchFocusThreadId filter', () {
      const bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: 'DMC310');
      final layer = fakeLayer(stitches: [bs]);
      final state = fakeStitchState(
          pattern: fakePattern(layers: [layer]),
          stitchFocusThreadId: 'DMC321'); // different thread
      final hit = h.getBackstitchHit(const Offset(10, 4), vp, state);
      expect(hit, isNull);
    });

    // ── backstitch tap ────────────────────────────────────────────────────────

    test('tapping a backstitch calls onToggleBackstitchDone', () {
      const bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: 'DMC310');
      final layer = fakeLayer(stitches: [bs]);
      final state = fakeStitchState(pattern: fakePattern(layers: [layer]));
      // Pointer down on backstitch
      h.onPointerDown(const Offset(10, 4), vp, patW, patH, state);
      h.onPointerUp(const Offset(10, 4), vp, patW, patH, state);
      expect(toggledBackstitches, hasLength(1));
      expect(toggledBackstitches.first, (0.0, 0.0, 1.0, 0.0));
      // Normal stitch toggle NOT called
      expect(toggledStitches, isEmpty);
    });

    // ── progress region with completed stitch ─────────────────────────────────

    test('wasProgressCellDone reflects cell state before toggle', () {
      final progress = PatternProgress(
        completedStitches: {(1, 1)}, // cell (1,1) already done
      );
      final pat = fakePattern().copyWith(progress: progress);
      final state = fakeStitchState(pattern: pat);
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state); // cell (1,1)
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      // Second tap (double-click): originalStartIsDone should be true
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.onPointerUp(const Offset(25, 25), vp, patW, patH, state);
      expect(floodFills.first.$3, isTrue);
    });

    // ── cancel ────────────────────────────────────────────────────────────────

    test('cancel resets all state', () {
      final state = fakeStitchState();
      h.onPointerDown(const Offset(25, 25), vp, patW, patH, state);
      h.cancel();
      expect(h.isActive, isFalse);
      expect(h.anchor, isNull);
      expect(h.dragRect, isNull);
      expect(h.hasDragged, isFalse);
    });
  });
}
