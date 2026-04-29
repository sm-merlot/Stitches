import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/snippet.dart';
import 'package:stitches/models/snippet_palette.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';

// ─── Helpers (same pattern as editor_notifier_test.dart) ─────────────────────

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

void loadEmpty(ProviderContainer c, {String name = 'Test'}) {
  final p = CrossStitchPattern.empty(name: name);
  n(c).loadPattern(p,
      session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
}

const _black = Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X');
const _red   = Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'Red',   symbol: 'O');

Snippet _makeSnippet({String name = 'Corner'}) =>
    Snippet.create(
      name: name,
      width: 3,
      height: 2,
      threads: const [_black],
      stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
    );

// ─── Snippet CRUD ─────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('EditorNotifier — snippet CRUD', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('addSnippet appends snippet and marks dirty', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      expect(s(c).pattern.snippets, hasLength(1));
      expect(s(c).pattern.snippets.single.id, equals(snip.id));
      expect(s(c).isDirty, isTrue);
    });

    test('addSnippet multiple snippets all stored', () {
      n(c).addSnippet(_makeSnippet(name: 'A'));
      n(c).addSnippet(_makeSnippet(name: 'B'));
      n(c).addSnippet(_makeSnippet(name: 'C'));
      expect(s(c).pattern.snippets, hasLength(3));
    });

    test('deleteSnippet removes by id', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      n(c).addSnippet(_makeSnippet(name: 'Other'));
      n(c).deleteSnippet(snip.id);
      expect(s(c).pattern.snippets, hasLength(1));
      expect(s(c).pattern.snippets.single.name, equals('Other'));
    });

    test('deleteSnippet on unknown id is a no-op', () {
      n(c).addSnippet(_makeSnippet());
      n(c).deleteSnippet('non-existent');
      expect(s(c).pattern.snippets, hasLength(1));
    });

    test('updateSnippet replaces by id', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      final updated = snip.copyWith(name: 'Updated Name');
      n(c).updateSnippet(updated);
      expect(s(c).pattern.snippets.single.name, equals('Updated Name'));
    });
  });

  // ─── Snippet resize ───────────────────────────────────────────────────────────

  group('EditorNotifier — snippet resize', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('resizeSnippet clip: stitches outside new bounds removed', () {
      final snip = Snippet.create(
        name: 'S',
        width: 5,
        height: 5,
        threads: const [_black],
        stitches: const [
          FullStitch(x: 0, y: 0, threadId: '310'),
          FullStitch(x: 4, y: 4, threadId: '310'),
        ],
      );
      n(c).addSnippet(snip);
      n(c).resizeSnippet(snip.id, 2, 2, SnippetResizeMode.clip);
      final resized = s(c).pattern.snippets.single;
      expect(resized.width, 2);
      expect(resized.height, 2);
      expect(resized.stitches.whereType<FullStitch>(), hasLength(1));
      expect(resized.stitches.whereType<FullStitch>().single.x, equals(0));
    });

    test('resizeSnippet expand: all stitches preserved, dimensions grow', () {
      final snip = Snippet.create(
        name: 'S',
        width: 2,
        height: 2,
        threads: const [_black],
        stitches: const [FullStitch(x: 1, y: 1, threadId: '310')],
      );
      n(c).addSnippet(snip);
      n(c).resizeSnippet(snip.id, 5, 5, SnippetResizeMode.expand);
      final resized = s(c).pattern.snippets.single;
      expect(resized.width, 5);
      expect(resized.height, 5);
      expect(resized.stitches, hasLength(1));
    });
  });

  // ─── Snippet transform ────────────────────────────────────────────────────────

  group('EditorNotifier — snippet transform', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('transformSnippet flipH mirrors x coordinate', () {
      // 3-wide snippet; stitch at x=0 → after flipH should be at x=2
      final snip = Snippet.create(
        name: 'S',
        width: 3,
        height: 1,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      n(c).addSnippet(snip);
      n(c).transformSnippet(snip.id, SnippetTransform.flipH);
      final flipped = s(c).pattern.snippets.single.stitches.whereType<FullStitch>().single;
      expect(flipped.x, equals(2)); // 3-1-0 = 2
    });

    test('transformSnippet flipV mirrors y coordinate', () {
      final snip = Snippet.create(
        name: 'S',
        width: 1,
        height: 3,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      n(c).addSnippet(snip);
      n(c).transformSnippet(snip.id, SnippetTransform.flipV);
      final flipped = s(c).pattern.snippets.single.stitches.whereType<FullStitch>().single;
      expect(flipped.y, equals(2)); // 3-1-0 = 2
    });

    test('transformSnippet rotateCW swaps dimensions', () {
      final snip = Snippet.create(
        name: 'S',
        width: 4,
        height: 2,
        threads: const [_black],
        stitches: const [FullStitch(x: 0, y: 0, threadId: '310')],
      );
      n(c).addSnippet(snip);
      n(c).transformSnippet(snip.id, SnippetTransform.rotateCW);
      final rotated = s(c).pattern.snippets.single;
      expect(rotated.width, equals(2));   // old height
      expect(rotated.height, equals(4));  // old width
    });
  });

  // ─── Snippet palette management ───────────────────────────────────────────────

  group('EditorNotifier — snippet palettes', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('addSnippetPalette appends palette and sets it active', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      final newPal = SnippetPalette.create(name: 'Alt', threads: const [_red]);
      n(c).addSnippetPalette(snip.id, newPal);
      final updated = s(c).pattern.snippets.single;
      expect(updated.palettes, hasLength(2));
      expect(updated.activePaletteIndex, equals(1));
    });

    test('deleteSnippetPalette cannot delete last palette', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      final palId = s(c).pattern.snippets.single.palettes.first.id;
      n(c).deleteSnippetPalette(snip.id, palId);
      expect(s(c).pattern.snippets.single.palettes, hasLength(1)); // unchanged
    });

    test('deleteSnippetPalette removes second palette', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      final newPal = SnippetPalette.create(name: 'Alt', threads: const [_red]);
      n(c).addSnippetPalette(snip.id, newPal);
      final palId = s(c).pattern.snippets.single.palettes.last.id;
      n(c).deleteSnippetPalette(snip.id, palId);
      expect(s(c).pattern.snippets.single.palettes, hasLength(1));
    });

    test('setSnippetActivePalette updates index, clamped', () {
      final snip = _makeSnippet();
      n(c).addSnippet(snip);
      n(c).setSnippetActivePalette(snip.id, 99); // clamps to 0 (only 1 palette)
      expect(s(c).pattern.snippets.single.activePaletteIndex, equals(0));
    });

    test('syncPaletteSymbolsToPrimary propagates slot symbols from primary', () {
      final pal1 = SnippetPalette.create(name: 'P1',
          threads: [const Thread(dmcCode: '310', color: Color(0xFF000000), name: 'B', symbol: 'X')]);
      final pal2 = SnippetPalette.create(name: 'P2',
          threads: [const Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'R', symbol: '')]);
      final synced = n(c).syncPaletteSymbolsToPrimary([pal1, pal2]);
      // Slot 0 of P2 should now have P1's slot 0 symbol.
      expect(synced[1].threads.first.symbol, equals('X'));
    });

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

  // ─── saveSelectionAsSnippet ───────────────────────────────────────────────────

  group('EditorNotifier — saveSelectionAsSnippet', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
      n(c).setMode(AppMode.edit);
    });
    tearDown(() => c.dispose());

    test('saves selected stitches as new snippet', () {
      n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      n(c).addStitch(const FullStitch(x: 2, y: 1, threadId: '310'));
      n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 4, 4));
      final ok = n(c).saveSelectionAsSnippet('My Motif');
      expect(ok, isTrue);
      expect(s(c).pattern.snippets, hasLength(1));
      expect(s(c).pattern.snippets.single.name, equals('My Motif'));
      expect(s(c).pattern.snippets.single.stitches, hasLength(2));
    });

    test('saveSelectionAsSnippet with no selection → returns false + warning', () {
      // No selectionRect set.
      final ok = n(c).saveSelectionAsSnippet('Empty');
      expect(ok, isFalse);
      expect(s(c).pendingCanvasWarning, isNotNull);
    });

    test('stitches offset relative to selection origin in saved snippet', () {
      n(c).addStitch(const FullStitch(x: 5, y: 3, threadId: '310'));
      n(c).setSelectionRect(const Rect.fromLTRB(5, 3, 8, 6));
      n(c).saveSelectionAsSnippet('Offset Test');
      final snip = s(c).pattern.snippets.single;
      // Stitch at (5,3) with rect origin (5,3) → stored at (0,0).
      expect(snip.stitches.whereType<FullStitch>().single.x, equals(0));
      expect(snip.stitches.whereType<FullStitch>().single.y, equals(0));
    });
  });

  // ─── Selection & clipboard ────────────────────────────────────────────────────

  group('EditorNotifier — selection', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
      n(c).setMode(AppMode.edit);
    });
    tearDown(() => c.dispose());

    test('setSelectionRect stores rect', () {
      n(c).setSelectionRect(const Rect.fromLTRB(1, 2, 5, 6));
      expect(s(c).selectionRect, equals(const Rect.fromLTRB(1, 2, 5, 6)));
    });

    test('selectAll sets rect to full canvas', () {
      n(c).selectAll();
      final r = s(c).selectionRect!;
      expect(r.left, equals(0));
      expect(r.top, equals(0));
      expect(r.width, equals(s(c).pattern.width.toDouble()));
      expect(r.height, equals(s(c).pattern.height.toDouble()));
      expect(s(c).drawingMode, equals(DrawingMode.select));
    });

    test('cancelSelection clears rect (stays in select mode; draw mode not changed)', () {
      n(c).selectAll();
      expect(s(c).selectionRect, isNotNull);
      n(c).cancelSelection();
      expect(s(c).selectionRect, isNull);
      // cancelSelection in select mode only clears rect; mode stays select.
      // To return to draw, the caller invokes setDrawingMode explicitly.
    });
  });

  // ─── copy / paste round-trip ─────────────────────────────────────────────────

  group('EditorNotifier — copy/paste', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
      n(c).setMode(AppMode.edit);
    });
    tearDown(() => c.dispose());

    test('copySelection populates in-memory clipboard and enters paste mode', () async {
      n(c).addStitch(const FullStitch(x: 2, y: 3, threadId: '310'));
      n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 5, 5));
      await n(c).copySelection();
      expect(s(c).clipboard, isNotNull);
      expect(s(c).clipboard, isNotEmpty);
      expect(s(c).drawingMode, equals(DrawingMode.paste));
      expect(s(c).selectionRect, isNull); // cleared on copy
    });

    test('copySelection on empty selection → warning, no clipboard change', () async {
      n(c).setSelectionRect(const Rect.fromLTRB(5, 5, 10, 10)); // no stitches there
      final prevClip = s(c).clipboard;
      await n(c).copySelection();
      expect(s(c).clipboard, equals(prevClip)); // unchanged
      expect(s(c).pendingCanvasWarning, isNotNull);
    });

    test('commitPaste stamps clipboard at offset onto active layer', () async {
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 3, 3));
      await n(c).copySelection();
      // Paste offset by (5,5)
      n(c).commitPaste(5, 5);
      final stitches = s(c).pattern.stitches.whereType<FullStitch>();
      expect(stitches.any((st) => st.x == 5 && st.y == 5), isTrue);
    });

    test('paste auto-adds clipboard threads not in pattern', () async {
      // Draw a red stitch, copy it, then switch to a fresh pattern and paste.
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '666'));
      n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 3, 3));
      await n(c).copySelection();
      // Load a second pattern (no red thread).
      final p2 = CrossStitchPattern.empty(name: 'P2');
      n(c).loadPattern(p2,
          session: EditorSession(selectedThreadId: p2.editorSelectedThreadId));
      n(c).setMode(AppMode.edit);
      // Re-enter paste mode using the preserved clipboard.
      await n(c).enterPasteMode();
      n(c).commitPaste(1, 1);
      expect(
        s(c).pattern.threads.keys,
        contains('666'),
      );
    });

    test('copySelection with no selectionRect → warning', () async {
      // No rect set at all.
      await n(c).copySelection();
      expect(s(c).pendingCanvasWarning, isNotNull);
    });

    test('commitPaste clears and refreshes compositeLayer', () async {
      final snippet = _makeSnippet();
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      n(c).setMode(AppMode.edit);
      await n(c).loadSnippetToClipboard(snippet);
      n(c).refreshCompositeCache();
      final before = s(c).compositeLayer;
      n(c).commitPaste(0, 0);
      expect(identical(s(c).compositeLayer, before), isFalse);
    });
  });

  // ─── loadSnippetToClipboard ───────────────────────────────────────────────────

  group('EditorNotifier — loadSnippetToClipboard', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('switches to edit mode when called from view mode', () async {
      final snippet = _makeSnippet();
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      expect(s(c).editMode, isFalse, reason: 'loadPattern stays in view mode');

      await n(c).loadSnippetToClipboard(snippet);

      expect(s(c).editMode, isTrue);
      expect(s(c).drawingMode, DrawingMode.paste,
          reason: 'must enter paste mode so commitPaste guard passes');
    });

    test('commitPaste works after loadSnippetToClipboard from view mode', () async {
      final snippet = _makeSnippet();
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      await n(c).loadSnippetToClipboard(snippet);
      n(c).commitPaste(2, 3);
      final placed = s(c).pattern.stitches.whereType<FullStitch>()
          .where((st) => st.x == 2 && st.y == 3);
      expect(placed, hasLength(1));
    });

    test('clipboardFromSnippet is true after loadSnippetToClipboard', () async {
      final snippet = _makeSnippet();
      final p = s(c).pattern.copyWith(snippets: [snippet]);
      n(c).loadPattern(p,
          session: EditorSession(selectedThreadId: p.editorSelectedThreadId));
      await n(c).loadSnippetToClipboard(snippet);
      expect(s(c).clipboardFromSnippet, isTrue);
    });
  });

  // ─── deleteSelection / moveSelection ──────────────────────────────────────────

  group('EditorNotifier — deleteSelection / moveSelection', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
      n(c).setMode(AppMode.edit);
    });
    tearDown(() => c.dispose());

    test('deleteSelection removes stitches in selection rect', () {
      n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      n(c).addStitch(const FullStitch(x: 8, y: 8, threadId: '310'));
      n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 5, 5));
      n(c).deleteSelection();
      expect(s(c).pattern.stitches.whereType<FullStitch>(), hasLength(1));
      expect(s(c).pattern.stitches.whereType<FullStitch>().single.x, equals(8));
    });

    test('moveSelection shifts stitches by delta', () {
      n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      n(c).setSelectionRect(const Rect.fromLTRB(0, 0, 5, 5));
      n(c).moveSelection(3, 2);
      final stitch = s(c).pattern.stitches.whereType<FullStitch>().single;
      expect(stitch.x, equals(4)); // 1 + 3
      expect(stitch.y, equals(3)); // 1 + 2
    });

    test('deleteSelection clears and refreshes compositeLayer', () {
      n(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      n(c).refreshCompositeCache();
      final before = s(c).compositeLayer;
      n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 3, 3));
      n(c).deleteSelection();
      expect(identical(s(c).compositeLayer, before), isFalse);
    });

    test('moveSelection clears and refreshes compositeLayer', () {
      n(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      n(c).refreshCompositeCache();
      final before = s(c).compositeLayer;
      n(c).setSelectionRect(const Rect.fromLTWH(0, 0, 2, 2));
      n(c).moveSelection(1, 1);
      expect(identical(s(c).compositeLayer, before), isFalse);
    });
  });
}

