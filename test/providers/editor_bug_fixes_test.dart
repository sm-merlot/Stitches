// Regression tests for the bugs fixed on branch
// fix/canvas-update-snippet-palette-symbols.
//
// Each group maps to one task in that bug-fix session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/layer.dart';
import 'package:stitches/models/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/snippet.dart';
import 'package:stitches/models/snippet_palette.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

ProviderContainer makeContainer() {
  return ProviderContainer(
    overrides: [settingsProvider.overrideWith(() => _StubSettings())],
  );
}

class _StubSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

EditorNotifier n(ProviderContainer c) => c.read(editorProvider.notifier);
EditorState s(ProviderContainer c) => c.read(editorProvider);

void loadEmpty(ProviderContainer c) {
  final p = CrossStitchPattern.empty(name: 'Test');
  n(c).loadPattern(p,
      session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
}

const _black =
    Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X');
const _red =
    Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'Red', symbol: 'O');

// ─── Task 1: newPattern() opens in edit mode ───────────────────────────────────

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Bug fix T1 — newPattern() opens in edit/draw mode', () {
    late ProviderContainer c;
    setUp(() => c = makeContainer());
    tearDown(() => c.dispose());

    test('newPattern sets editMode = true', () {
      n(c).newPattern(CrossStitchPattern.empty(name: 'New'));
      expect(s(c).editMode, isTrue);
    });

    test('newPattern sets drawingMode = draw so canvas accepts input', () {
      n(c).newPattern(CrossStitchPattern.empty(name: 'New'));
      expect(s(c).drawingMode, DrawingMode.draw);
    });

    test('can addStitch immediately after newPattern without switching mode', () {
      n(c).newPattern(CrossStitchPattern.empty(name: 'New'));
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(s(c).pattern.stitches.whereType<FullStitch>(), hasLength(1));
    });
  });

  // ─── Task 2: loadSnippetToClipboard switches to edit mode ─────────────────────

  group('Bug fix T2 — loadSnippetToClipboard enters edit+paste mode', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c); // loads in view mode (AppMode.view)
    });
    tearDown(() => c.dispose());

    test('loadSnippetToClipboard from view mode switches to edit mode', () async {
      final snippet = Snippet.create(
        name: 'Corner',
        width: 2,
        height: 2,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      // Add snippet to pattern first.
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      expect(s(c).editMode, isFalse, reason: 'loadPattern stays in view mode');

      await n(c).loadSnippetToClipboard(snippet);

      expect(s(c).editMode, isTrue,
          reason: 'loadSnippetToClipboard should switch to edit mode');
      expect(s(c).drawingMode, DrawingMode.paste,
          reason: 'should enter paste mode so commitPaste guard passes');
    });

    test('commitPaste works after loadSnippetToClipboard from view mode', () async {
      final snippet = Snippet.create(
        name: 'Dot',
        width: 1,
        height: 1,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));

      await n(c).loadSnippetToClipboard(snippet);
      n(c).commitPaste(2, 3);

      // Stitch should appear at the stamped offset.
      final placed = s(c).pattern.stitches.whereType<FullStitch>()
          .where((st) => st.x == 2 && st.y == 3);
      expect(placed, hasLength(1));
    });
  });

  // ─── Task 7: drawing operations clear compositeResult ─────────────────────────

  group('Bug fix T7 — drawing ops clear compositeResult so canvas repaints', () {
    late ProviderContainer c;

    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    /// Seeds a non-null compositeResult so subsequent checks are meaningful.
    void seedComposite() {
      n(c).refreshCompositeCache();
      assert(s(c).compositeResult != null,
          'refreshCompositeCache should produce non-null result');
    }

    test('addStitch clears compositeResult', () {
      seedComposite();
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(s(c).compositeResult, isNull,
          reason: 'compositeResult must be null so shouldRepaint returns true '
              'and the canvas shows the new stitch');
    });

    test('removeStitchesAt clears compositeResult', () {
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      seedComposite();
      n(c).removeStitchesAt(0, 0);
      expect(s(c).compositeResult, isNull);
    });

    test('removeStitchesInBox clears compositeResult', () {
      n(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      seedComposite();
      n(c).removeStitchesInBox(2, 2, 1);
      expect(s(c).compositeResult, isNull);
    });

    test('floodFill refreshes compositeResult (not left stale)', () {
      n(c).setMode(AppMode.edit);
      n(c).setSelectedThread('310');
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      final before = s(c).compositeResult;
      n(c).floodFill(0, 0, erase: true);
      // floodFill calls refreshCompositeCache() synchronously — result is fresh,
      // not the same stale object.
      expect(identical(s(c).compositeResult, before), isFalse);
    });

    test('removeBackstitchAt refreshes compositeResult', () {
      n(c).addStitch(const BackStitch(
          x1: 0.0, y1: 0.0, x2: 1.0, y2: 0.0, threadId: '310'));
      seedComposite();
      final before = s(c).compositeResult;
      n(c).removeBackstitchAt(0.0, 0.0, 1.0, 0.0);
      expect(identical(s(c).compositeResult, before), isFalse);
    });

    test('deleteSelection clears and refreshes compositeResult', () {
      n(c).setMode(AppMode.edit);
      n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      seedComposite();
      final before = s(c).compositeResult;
      n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 3, 3));
      n(c).deleteSelection();
      expect(identical(s(c).compositeResult, before), isFalse);
    });

    test('commitPaste clears and refreshes compositeResult', () async {
      // Set up a snippet to paste.
      final snippet = Snippet.create(
        name: 'Dot',
        width: 1,
        height: 1,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      n(c).setMode(AppMode.edit);
      await n(c).loadSnippetToClipboard(snippet);
      seedComposite();
      final before = s(c).compositeResult;

      n(c).commitPaste(0, 0);

      expect(identical(s(c).compositeResult, before), isFalse);
    });

    test('moveSelection clears and refreshes compositeResult', () {
      n(c).setMode(AppMode.edit);
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      seedComposite();
      final before = s(c).compositeResult;
      n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 2, 2));
      n(c).moveSelection(1, 1);
      expect(identical(s(c).compositeResult, before), isFalse);
    });
  });

  // ─── Task 2 (extra): loadSnippetToClipboard clipboardFromSnippet flag ─────────

  group('Bug fix T2 — clipboardFromSnippet flag set', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('clipboardFromSnippet is true after loadSnippetToClipboard', () async {
      final snippet = Snippet.create(
        name: 'S',
        width: 1,
        height: 1,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      await n(c).loadSnippetToClipboard(snippet);
      expect(s(c).clipboardFromSnippet, isTrue);
    });
  });

  // ─── Task 3: setSnippetPaletteThreadColor marks snippetPalettes dirty ─────────
  //
  // The underlying provider behaviour: calling setSnippetPaletteThreadColor
  // must produce a NEW snippetPalettes list so identity-based dirty detection
  // in _SnippetEditorBodyState._isDirty() fires.

  group('Bug fix T3 — setSnippetPaletteThreadColor changes snippetPalettes identity', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('setSnippetPaletteThreadColor produces new snippetPalettes instance', () {
      n(c).initSnippetPalettesLocal(
          [SnippetPalette.create(name: 'P1', threads: [_black])], 0);
      final before = s(c).snippetPalettes;

      n(c).setSnippetPaletteThreadColor(0, 0, _red);

      expect(identical(s(c).snippetPalettes, before), isFalse,
          reason: 'setSnippetPaletteThreadColor must return a new List instance '
              'so identity-based dirty detection in the snippet editor triggers');
    });
  });

  // ─── Two-layer blend: compositeResult contains all visible stitches ────────────

  group('Bug fix T7 (multi-layer) — composite refresh after draw on layered pattern', () {
    late ProviderContainer c;

    /// Build a 2-layer pattern and load it.
    void loadTwoLayer(ProviderContainer c) {
      final layer1 = Layer.create(name: 'Layer 1');
      final layer2 = Layer.create(name: 'Layer 2');
      final p = CrossStitchPattern(
        name: 'Test',
        width: 10,
        height: 10,
        threads: const [_black, _red],
        layerItems: [LayerLeaf(layer: layer1), LayerLeaf(layer: layer2)],
      );
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: '310'));
      n(c).setMode(AppMode.edit);
    }

    setUp(() {
      c = makeContainer();
      loadTwoLayer(c);
    });
    tearDown(() => c.dispose());

    test('after addStitch compositeResult is null (canvas will recompute)', () {
      n(c).refreshCompositeCache(); // prime cache
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(s(c).compositeResult, isNull);
    });

    test('after removeStitchesAt compositeResult is null', () {
      n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      n(c).refreshCompositeCache();
      n(c).removeStitchesAt(1, 1);
      expect(s(c).compositeResult, isNull);
    });
  });
}
