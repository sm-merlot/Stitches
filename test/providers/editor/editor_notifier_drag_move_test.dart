import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer() => ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => _StubSettings())],
    );

class _StubSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

EditorNotifier _n(ProviderContainer c) => c.read(editorProvider.notifier);
EditorState _s(ProviderContainer c) => c.read(editorProvider);

void _loadEmpty(ProviderContainer c) {
  final p = CrossStitchPattern.empty(name: 'Test');
  _n(c).loadPattern(p, session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
  _n(c).setMode(AppMode.edit);
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  // ── copySelectionForDrag ─────────────────────────────────────────────────────

  group('EditorNotifier — copySelectionForDrag', () {
    late ProviderContainer c;
    setUp(() { c = _makeContainer(); _loadEmpty(c); });
    tearDown(() => c.dispose());

    test('returns false when no selection rect', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      // No setSelectionRect — rect is null.
      expect(_n(c).copySelectionForDrag(), isFalse);
    });

    test('returns false when selection rect covers no stitches', () {
      // Stitches outside the rect.
      _n(c).addStitch(const FullStitch(x: 9, y: 9, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 3, 3));
      expect(_n(c).copySelectionForDrag(), isFalse);
    });

    test('returns true and enters paste mode when stitches are in selection', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      expect(_n(c).copySelectionForDrag(), isTrue);
      expect(_s(c).editSession.drawingMode, equals(DrawingMode.paste));
    });

    test('clipboard contains stitches offset to selection origin', () {
      // Stitch at (3,3); selection rect at (2,2)→(7,7) → clipboard offset = (-2,-2) → (1,1).
      _n(c).addStitch(const FullStitch(x: 3, y: 3, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(2, 2, 5, 5));
      _n(c).copySelectionForDrag();
      final clips = _s(c).editSession.clipboard!;
      expect(clips, hasLength(1));
      final s = clips.first as FullStitch;
      expect(s.x, equals(1));
      expect(s.y, equals(1));
    });

    test('clipboard excludes stitches outside selection rect', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310')); // inside
      _n(c).addStitch(const FullStitch(x: 8, y: 8, threadId: '310')); // outside
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).copySelectionForDrag();
      expect(_s(c).editSession.clipboard, hasLength(1));
    });

    test('clears selection rect after populating clipboard', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).copySelectionForDrag();
      expect(_s(c).editSession.selectionRect, isNull);
    });
  });

  // ── deleteStitchesInRect ─────────────────────────────────────────────────────

  group('EditorNotifier — deleteStitchesInRect', () {
    late ProviderContainer c;
    setUp(() { c = _makeContainer(); _loadEmpty(c); });
    tearDown(() => c.dispose());

    test('removes stitches inside rect', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      _n(c).addStitch(const FullStitch(x: 8, y: 8, threadId: '310'));
      _n(c).deleteStitchesInRect(const Rect.fromLTWH(0, 0, 5, 5));
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((s) => s.x == 1), isFalse);
      expect(stitches.any((s) => s.x == 8), isTrue);
    });

    test('leaves stitches outside rect intact', () {
      _n(c).addStitch(const FullStitch(x: 9, y: 9, threadId: '310'));
      _n(c).deleteStitchesInRect(const Rect.fromLTWH(0, 0, 5, 5));
      expect(_s(c).pattern.stitches, hasLength(1));
    });

    test('no-op when rect contains no stitches', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      _n(c).deleteStitchesInRect(const Rect.fromLTWH(8, 8, 3, 3));
      expect(_s(c).pattern.stitches, hasLength(1));
    });

    test('works for every stitch type', () {
      _n(c).addStitch(const HalfStitch(x: 0, y: 0, isForward: true, threadId: '310'));
      _n(c).addStitch(const QuarterStitch(
          x: 1, y: 0, quadrant: QuadrantPosition.topLeft, threadId: '310'));
      _n(c).addStitch(const HalfCrossStitch(
          x: 2, y: 0, half: HalfOrientation.right, threadId: '310'));
      _n(c).addStitch(const ThreeQuarterStitch(
          x: 3, y: 0, quadrant: QuadrantPosition.bottomLeft, isForward: false, threadId: '310'));
      _n(c).deleteStitchesInRect(const Rect.fromLTWH(0, 0, 10, 10));
      expect(_s(c).pattern.stitches, isEmpty);
    });
  });

  // ── commitPaste — position correctness ───────────────────────────────────────

  group('EditorNotifier — commitPaste position', () {
    late ProviderContainer c;
    setUp(() { c = _makeContainer(); _loadEmpty(c); });
    tearDown(() => c.dispose());

    test('places stitches at correct absolute offset', () {
      // Stitch at (0,0); selection at origin → clipboard stitch at (0,0).
      // commitPaste(5,5) should land it at (5,5).
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 3, 3));
      _n(c).copySelectionForDrag();
      _n(c).commitPaste(5, 5);
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((s) => s.x == 5 && s.y == 5), isTrue,
          reason: 'stitch must land at (5,5) after paste offset (5,5)');
    });

    test('clips stitches that would land outside pattern bounds', () {
      // Pattern is 30×30 (default). Stitch at (0,0); paste at (28,28) → (28,28) in bounds.
      // A second stitch at (2,0) → offset (2,0) + (28,28) = (30,28) out of bounds.
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).addStitch(const FullStitch(x: 2, y: 0, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).copySelectionForDrag();
      _n(c).commitPaste(28, 28);
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((s) => s.x == 28 && s.y == 28), isTrue);
      expect(stitches.any((s) => s.x == 30), isFalse,
          reason: 'stitch at x=30 is out of bounds and must be dropped');
    });

    test('replaces existing stitch at destination cell', () {
      // Existing stitch at (5,5) with red; paste a black stitch onto (5,5).
      _n(c).addStitch(const FullStitch(x: 5, y: 5, threadId: '666'));
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 3, 3));
      _n(c).copySelectionForDrag();
      _n(c).commitPaste(5, 5);
      final at55 = _s(c).pattern.stitches
          .whereType<FullStitch>()
          .where((s) => s.x == 5 && s.y == 5)
          .toList();
      expect(at55, hasLength(1));
      expect(at55.single.threadId, equals('310'),
          reason: 'pasted stitch must replace the old one at destination');
    });
  });

  // ── Drag-to-move — regression tests ─────────────────────────────────────────
  //
  // These specifically test the delete-before-paste ordering fix. The buggy
  // behaviour (paste-then-delete) caused stitches in the overlap between source
  // and destination rects to be deleted after they had just been placed.

  group('EditorNotifier — drag-to-move', () {
    late ProviderContainer c;
    setUp(() { c = _makeContainer(); _loadEmpty(c); });
    tearDown(() => c.dispose());

    test('stitches appear at destination, erased from source (no overlap)', () {
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));
      const sourceRect = Rect.fromLTWH(0, 0, 4, 4);
      _n(c).setSelectionRect(sourceRect);
      _n(c).copySelectionForDrag();
      // Correct order: delete source first, then paste at destination.
      _n(c).deleteStitchesInRect(sourceRect);
      _n(c).commitPaste(5, 5);
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((s) => s.x == 5 && s.y == 5), isTrue);
      expect(stitches.any((s) => s.x == 6 && s.y == 5), isTrue);
      expect(stitches.any((s) => s.x == 0), isFalse);
      expect(stitches.any((s) => s.x == 1), isFalse);
    });

    test('regression: partial overlap — destination stitches survive', () {
      // Source: stitches at (0,0) and (1,0). Move right by 1: dest (1,0) and (2,0).
      // (1,0) is in BOTH source and destination.
      // Bug (paste-then-delete): all three positions get wiped.
      // Fix (delete-then-paste): (1,0) and (2,0) survive.
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));
      const sourceRect = Rect.fromLTWH(0, 0, 3, 3);
      _n(c).setSelectionRect(sourceRect);
      _n(c).copySelectionForDrag();
      // delete first (correct order matching the fixed controller code)
      _n(c).deleteStitchesInRect(sourceRect);
      _n(c).commitPaste(1, 0); // shift right by 1
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((s) => s.x == 1 && s.y == 0), isTrue,
          reason: 'stitch at destination (1,0) must not be deleted by source erase');
      expect(stitches.any((s) => s.x == 2 && s.y == 0), isTrue,
          reason: 'stitch at destination (2,0) must exist');
      expect(stitches.any((s) => s.x == 0 && s.y == 0), isFalse,
          reason: 'source (0,0) must be erased');
    });

    test('regression: wrong order (paste-then-delete) loses overlap stitches', () {
      // This test documents the BUGGY behaviour: if you paste before deleting
      // the source, the delete wipes newly-placed stitches in the overlap zone.
      // It is here so that if someone reverts the ordering fix, this test fails.
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));
      const sourceRect = Rect.fromLTWH(0, 0, 3, 3);
      _n(c).setSelectionRect(sourceRect);
      _n(c).copySelectionForDrag();
      // Wrong order: paste first, then delete — overlap stitch at (1,0) gets wiped.
      _n(c).commitPaste(1, 0);
      _n(c).deleteStitchesInRect(sourceRect);
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      // With the wrong order, (1,0) is deleted even though it was just placed.
      expect(stitches.any((s) => s.x == 1 && s.y == 0), isFalse,
          reason: 'wrong order causes overlap stitch to be lost — confirms the bug');
    });

    test('move all stitch types — none lost in transit', () {
      _n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      _n(c).addStitch(const HalfStitch(x: 1, y: 0, isForward: true, threadId: '310'));
      _n(c).addStitch(const QuarterStitch(
          x: 2, y: 0, quadrant: QuadrantPosition.topLeft, threadId: '310'));
      _n(c).addStitch(const HalfCrossStitch(
          x: 3, y: 0, half: HalfOrientation.right, threadId: '310'));
      _n(c).addStitch(const ThreeQuarterStitch(
          x: 4, y: 0, quadrant: QuadrantPosition.bottomLeft, isForward: false, threadId: '310'));
      const sourceRect = Rect.fromLTWH(0, 0, 6, 2);
      _n(c).setSelectionRect(sourceRect);
      _n(c).copySelectionForDrag();
      _n(c).deleteStitchesInRect(sourceRect);
      _n(c).commitPaste(0, 5); // move down 5 rows
      final stitches = _s(c).pattern.stitches;
      // All five stitch types must exist at y=5.
      expect(stitches.whereType<FullStitch>().any((s) => s.y == 5), isTrue);
      expect(stitches.whereType<HalfStitch>().any((s) => s.y == 5), isTrue);
      expect(stitches.whereType<QuarterStitch>().any((s) => s.y == 5), isTrue);
      expect(stitches.whereType<HalfCrossStitch>().any((s) => s.y == 5), isTrue);
      expect(stitches.whereType<ThreeQuarterStitch>().any((s) => s.y == 5), isTrue);
      // Nothing left at y=0.
      expect(stitches.whereType<FullStitch>().any((s) => s.y == 0), isFalse);
      expect(stitches.whereType<HalfStitch>().any((s) => s.y == 0), isFalse);
      expect(stitches.whereType<QuarterStitch>().any((s) => s.y == 0), isFalse);
      expect(stitches.whereType<HalfCrossStitch>().any((s) => s.y == 0), isFalse);
      expect(stitches.whereType<ThreeQuarterStitch>().any((s) => s.y == 0), isFalse);
    });
  });
}
