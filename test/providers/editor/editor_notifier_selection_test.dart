import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';

// ── Helpers (mirror editor_notifier_test.dart) ────────────────────────────────

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

  // ── deleteSelection ──────────────────────────────────────────────────────────

  group('EditorNotifier — deleteSelection', () {
    late ProviderContainer c;
    setUp(() { c = _makeContainer(); _loadEmpty(c); });
    tearDown(() => c.dispose());

    test('removes FullStitch inside selection rect', () {
      _n(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      _n(c).addStitch(const FullStitch(x: 10, y: 10, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      final stitches = _s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((s) => s.x == 2), isFalse);
      expect(stitches.any((s) => s.x == 10), isTrue);
    });

    test('leaves stitches outside selection rect intact', () {
      _n(c).addStitch(const FullStitch(x: 8, y: 8, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches, hasLength(1));
    });

    test('no-op when selection rect is null', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      _n(c).deleteSelection(); // no rect set
      expect(_s(c).pattern.stitches, hasLength(1));
    });

    test('clears selection rect from session after delete', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).editSession.selectionRect, isNull);
    });

    test('removes HalfStitch inside rect', () {
      _n(c).addStitch(const HalfStitch(x: 1, y: 1, isForward: true, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches.whereType<HalfStitch>(), isEmpty);
    });

    test('removes QuarterStitch inside rect', () {
      _n(c).addStitch(const QuarterStitch(
          x: 1, y: 1, quadrant: QuadrantPosition.topLeft, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches.whereType<QuarterStitch>(), isEmpty);
    });

    test('removes HalfCrossStitch inside rect', () {
      _n(c).addStitch(const HalfCrossStitch(
          x: 1, y: 1, half: HalfOrientation.left, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches.whereType<HalfCrossStitch>(), isEmpty);
    });

    test('removes ThreeQuarterStitch inside rect', () {
      _n(c).addStitch(const ThreeQuarterStitch(
          x: 1, y: 1, quadrant: QuadrantPosition.bottomRight, isForward: true, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches.whereType<ThreeQuarterStitch>(), isEmpty);
    });

    test('removes BackStitch whose both endpoints are inside rect', () {
      // Both endpoints (0.5,0.5)→(1.5,0.5) are within the 5×5 rect.
      _n(c).addStitch(const BackStitch(
          x1: 0.5, y1: 0.5, x2: 1.5, y2: 0.5, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches.whereType<BackStitch>(), isEmpty);
    });

    test('leaves BackStitch whose endpoint falls outside rect', () {
      // x2 = 8.0 is outside the 5×5 rect.
      _n(c).addStitch(const BackStitch(
          x1: 1.0, y1: 1.0, x2: 8.0, y2: 1.0, threadId: '310'));
      _n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 5, 5));
      _n(c).deleteSelection();
      expect(_s(c).pattern.stitches.whereType<BackStitch>(), hasLength(1));
    });
  });

  // ── commitPaste — safe no-op guards ──────────────────────────────────────────

  group('EditorNotifier — commitPaste guards', () {
    late ProviderContainer c;
    setUp(() { c = _makeContainer(); _loadEmpty(c); });
    tearDown(() => c.dispose());

    test('no-op when clipboard is null', () {
      _n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      final before = _s(c).pattern.stitches.length;
      _n(c).commitPaste(5, 5);
      expect(_s(c).pattern.stitches.length, equals(before));
    });

    test('no-op when not in edit mode', () {
      _n(c).setMode(AppMode.view);
      // Even if we could somehow set a clipboard, commitPaste must bail out.
      final before = _s(c).pattern.stitches.length;
      _n(c).commitPaste(0, 0);
      expect(_s(c).pattern.stitches.length, equals(before));
    });
  });
}
