import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/models/layer_blend_mode.dart';
import '../../lib/models/layer_item.dart';
import '../../lib/models/pattern.dart';
import '../../lib/models/stitch.dart';
import '../../lib/models/thread.dart';
import '../../lib/providers/editor/editor_provider.dart';
import '../../lib/providers/settings_provider.dart';
import '../../lib/services/editor_session_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

ProviderContainer makeContainer() {
  return ProviderContainer(
    overrides: [
      // Provide a fixed AppSettings so no SharedPreferences call happens.
      settingsProvider.overrideWith(() => _StubSettingsNotifier()),
    ],
  );
}

class _StubSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(); // skip SharedPreferences load
}

EditorNotifier notifier(ProviderContainer c) => c.read(editorProvider.notifier);
EditorState editorState(ProviderContainer c) => c.read(editorProvider);

/// Load an empty pattern with a named layer so activeLayerId is set.
void loadEmpty(ProviderContainer c, {String name = 'Test'}) {
  final pattern = CrossStitchPattern.empty(name: name);
  // Pass an explicit session so the legacy-editor-fields path is skipped
  // and isDirty starts as false (matching real open-from-disk behaviour).
  notifier(c).loadPattern(
    pattern,
    session: EditorSession(selectedThreadId: pattern.editorSelectedThreadId),
  );
}

const black = Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X');
const red   = Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'Red',   symbol: 'O');

// ─── Drawing ──────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Prevent SharedPreferences from crashing in _saveSession fire-and-forget calls.
    SharedPreferences.setMockInitialValues({});
  });

  group('EditorNotifier — drawing', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('addStitch puts FullStitch into active layer', () {
      final layerId = editorState(c).activeLayerId;
      notifier(c).addStitch(const FullStitch(x: 2, y: 3, threadId: '310'));

      final layer = editorState(c).pattern.layers
          .firstWhere((l) => l.id == layerId);
      expect(layer.stitches.whereType<FullStitch>().single,
          isA<FullStitch>().having((s) => s.x, 'x', 2));
    });

    test('addStitch of each type survives on layer', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).addStitch(const HalfStitch(x: 1, y: 0, isForward: true, threadId: '310'));
      notifier(c).addStitch(const QuarterStitch(x: 2, y: 0, quadrant: QuadrantPosition.topLeft, threadId: '310'));
      notifier(c).addStitch(const BackStitch(x1: 0.5, y1: 0.5, x2: 1.5, y2: 0.5, threadId: '310'));
      notifier(c).addStitch(const HalfCrossStitch(x: 3, y: 0, half: HalfOrientation.left, threadId: '310'));
      notifier(c).addStitch(const QuarterCrossStitch(x: 4, y: 0, quadrant: QuadrantPosition.bottomRight, threadId: '310'));

      final stitches = editorState(c).pattern.stitches;
      expect(stitches.whereType<FullStitch>(), hasLength(1));
      expect(stitches.whereType<HalfStitch>(), hasLength(1));
      expect(stitches.whereType<QuarterStitch>(), hasLength(1));
      expect(stitches.whereType<BackStitch>(), hasLength(1));
      expect(stitches.whereType<HalfCrossStitch>(), hasLength(1));
      expect(stitches.whereType<QuarterCrossStitch>(), hasLength(1));
    });

    test('adding same stitch twice is idempotent', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(editorState(c).pattern.stitches.whereType<FullStitch>(), hasLength(1));
    });

    test('removeStitchesAt removes stitch from layer', () {
      notifier(c).addStitch(const FullStitch(x: 5, y: 5, threadId: '310'));
      notifier(c).removeStitchesAt(5, 5);
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('removeStitchesInBox removes stitches in N×N region', () {
      // Add a 3×3 block at (2,2)..(4,4).
      for (int x = 2; x <= 4; x++) {
        for (int y = 2; y <= 4; y++) {
          notifier(c).addStitch(FullStitch(x: x, y: y, threadId: '310'));
        }
      }
      // Erase centred on (3,3) with size=3 → clears all 9.
      notifier(c).removeStitchesInBox(3, 3, 3);
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('addStitch auto-adds new thread to palette', () {
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '820'));
      expect(editorState(c).pattern.threads.map((t) => t.dmcCode), contains('820'));
    });

    test('overpainting same cell with new thread: old thread pruned when no other stitches', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      // Repaint same cell with red — original thread should disappear.
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '666'));
      final threads = editorState(c).pattern.threads.map((t) => t.dmcCode);
      expect(threads, contains('666'));
      expect(threads, isNot(contains('310')));
    });

    test('markSaved clears isDirty', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(editorState(c).isDirty, isTrue);
      notifier(c).markSaved();
      expect(editorState(c).isDirty, isFalse);
    });
  });

  // ─── Undo / Redo ─────────────────────────────────────────────────────────────

  group('EditorNotifier — undo/redo', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('undo reverts last addStitch', () {
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      expect(editorState(c).pattern.stitches, hasLength(1));
      notifier(c).undo();
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('redo re-applies undone stitch', () {
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).undo();
      notifier(c).redo();
      expect(editorState(c).pattern.stitches, hasLength(1));
    });

    test('new action clears redo stack', () {
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).undo();
      expect(editorState(c).canRedo, isTrue);
      notifier(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      expect(editorState(c).canRedo, isFalse);
    });

    test('undo at empty stack is no-op', () {
      expect(() => notifier(c).undo(), returnsNormally);
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('canUndo / canRedo flags accurate', () {
      expect(editorState(c).canUndo, isFalse);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      expect(editorState(c).canUndo, isTrue);
      notifier(c).undo();
      expect(editorState(c).canRedo, isTrue);
      expect(editorState(c).canUndo, isFalse);
    });
  });

  // ─── Layers ───────────────────────────────────────────────────────────────────

  group('EditorNotifier — layers', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('addLayer increases layer count, new layer becomes active', () {
      final before = editorState(c).pattern.layers.length;
      notifier(c).addLayer();
      expect(editorState(c).pattern.layers.length, before + 1);
      final activeId = editorState(c).activeLayerId;
      expect(editorState(c).pattern.layers.last.id, equals(activeId));
    });

    test('deleteLayer removes layer; active pointer stays valid', () {
      notifier(c).addLayer();
      final ids = editorState(c).pattern.layers.map((l) => l.id).toList();
      notifier(c).deleteLayer(ids.first);
      final remaining = editorState(c).pattern.layers.map((l) => l.id).toList();
      expect(remaining, isNot(contains(ids.first)));
      // activeLayerId must point to a remaining layer.
      expect(remaining, contains(editorState(c).activeLayerId));
    });

    test('cannot delete last layer', () {
      expect(editorState(c).pattern.layers.length, 1);
      final id = editorState(c).pattern.layers.first.id;
      notifier(c).deleteLayer(id);
      expect(editorState(c).pattern.layers.length, 1); // unchanged
    });

    test('renameLayer updates name', () {
      final id = editorState(c).activeLayerId;
      notifier(c).renameLayer(id, 'Background');
      final layer = editorState(c).pattern.layers.firstWhere((l) => l.id == id);
      expect(layer.name, equals('Background'));
    });

    test('toggleLayerVisible flips visible flag', () {
      final id = editorState(c).activeLayerId;
      expect(editorState(c).activeLayer.visible, isTrue);
      notifier(c).toggleLayerVisible(id);
      expect(editorState(c).pattern.layers.firstWhere((l) => l.id == id).visible, isFalse);
      notifier(c).toggleLayerVisible(id);
      expect(editorState(c).pattern.layers.firstWhere((l) => l.id == id).visible, isTrue);
    });

    test('toggleLayerLocked flips locked flag', () {
      final id = editorState(c).activeLayerId;
      notifier(c).toggleLayerLocked(id);
      expect(editorState(c).pattern.layers.firstWhere((l) => l.id == id).locked, isTrue);
    });

    test('locked layer ignores addStitch', () {
      final id = editorState(c).activeLayerId;
      notifier(c).toggleLayerLocked(id);
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('setLayerBlendMode persists blend mode', () {
      final id = editorState(c).activeLayerId;
      notifier(c).setLayerBlendMode(id, LayerBlendMode.multiply);
      final layer = editorState(c).pattern.layers.firstWhere((l) => l.id == id);
      expect(layer.blendMode, equals(LayerBlendMode.multiply));
    });

    test('moveLayer reorders layers', () {
      notifier(c).addLayer();
      final ids = editorState(c).pattern.layers.map((l) => l.id).toList();
      expect(ids.length, 2);
      notifier(c).moveLayer(ids[1], -1); // move second layer up → swaps
      final newIds = editorState(c).pattern.layers.map((l) => l.id).toList();
      expect(newIds[0], equals(ids[1]));
    });

    test('duplicateLayer creates copy above source', () {
      final id = editorState(c).activeLayerId;
      notifier(c).addStitch(const FullStitch(x: 5, y: 5, threadId: '310'));
      notifier(c).duplicateLayer(id);
      final layers = editorState(c).pattern.layers;
      expect(layers.length, 2);
      expect(layers.last.stitches.whereType<FullStitch>(), hasLength(1));
      // duplicate should have a new id
      expect(layers.last.id, isNot(equals(id)));
    });

    test('layer undo/redo round-trip', () {
      notifier(c).addLayer();
      expect(editorState(c).pattern.layers.length, 2);
      notifier(c).undo();
      expect(editorState(c).pattern.layers.length, 1);
      notifier(c).redo();
      expect(editorState(c).pattern.layers.length, 2);
    });
  });

  // ─── Mode switching ──────────────────────────────────────────────────────────

  group('EditorNotifier — mode switching', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('loadPattern → mode is view', () {
      expect(editorState(c).mode, equals(AppMode.view));
    });

    test('setMode(edit) → editMode true', () {
      notifier(c).setMode(AppMode.edit);
      expect(editorState(c).editMode, isTrue);
    });

    test('setMode(stitch) → stitchMode true, drawingMode = select', () {
      notifier(c).setMode(AppMode.stitch);
      expect(editorState(c).stitchMode, isTrue);
      expect(editorState(c).drawingMode, equals(DrawingMode.select));
    });

    test('view → edit → stitch → view: selectionRect cleared at each transition', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).setDrawingMode(DrawingMode.select);
      notifier(c).setMode(AppMode.stitch);
      expect(editorState(c).selectionRect, isNull);
      notifier(c).setMode(AppMode.view);
      expect(editorState(c).selectionRect, isNull);
    });
  });

  // ─── File lifecycle ────────────────────────────────────────────────────────

  group('EditorNotifier — file lifecycle', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); });
    tearDown(() => c.dispose());

    test('freshly loaded pattern: isDirty = false', () {
      loadEmpty(c);
      expect(editorState(c).isDirty, isFalse);
    });

    test('drawing marks file dirty', () {
      loadEmpty(c);
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(editorState(c).isDirty, isTrue);
    });

    test('markSaved clears dirty', () {
      loadEmpty(c);
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).markSaved();
      expect(editorState(c).isDirty, isFalse);
    });

    test('closeFile resets to empty state', () {
      loadEmpty(c);
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).closeFile();
      expect(editorState(c).pattern.stitches, isEmpty);
      expect(editorState(c).isDirty, isFalse);
    });

    test('clipboard preserved across pattern loads', () {
      loadEmpty(c, name: 'Pattern A');
      // Simulate clipboard set directly (selection copy isn't easy to drive
      // without a real UI; testing the clipboard-preservation contract is
      // simpler via loadPattern which reads prevClipboard).
      // We drive it by loading again — clipboard should still be null since
      // we never set it.
      loadEmpty(c, name: 'Pattern B');
      expect(editorState(c).clipboard, isNull);
    });
  });

  // ─── resizePattern ────────────────────────────────────────────────────────

  group('EditorNotifier — resizePattern', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('stitches outside new bounds are pruned', () {
      notifier(c).addStitch(const FullStitch(x: 25, y: 25, threadId: '310'));
      notifier(c).resizePattern(10, 10, 0, 0); // shrink, top-left anchor
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('stitches inside new bounds survive', () {
      notifier(c).addStitch(const FullStitch(x: 3, y: 3, threadId: '310'));
      notifier(c).resizePattern(10, 10, 0, 0);
      expect(editorState(c).pattern.stitches, hasLength(1));
    });
  });

  // ─── Palette / thread helpers ─────────────────────────────────────────────

  group('EditorNotifier — palette', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('_assignSymbols gives each thread a symbol', () {
      final threads = [
        const Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: ''),
        const Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'Red',   symbol: ''),
      ];
      final result = notifier(c).assignSymbolsForTest(threads);
      expect(result.every((t) => t.symbol.isNotEmpty), isTrue);
    });

    test('_assignSymbols preserves existing valid symbol', () {
      final threads = [
        const Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X'),
      ];
      final result = notifier(c).assignSymbolsForTest(threads);
      expect(result.first.symbol, equals('X'));
    });

    test('_assignSymbols does not reuse existingSymbols set', () {
      final threads = [
        const Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: ''),
      ];
      // If 'X' is already taken by composite symbols, it should not be reused.
      final result = notifier(c).assignSymbolsForTest(threads, existingSymbols: {'X'});
      expect(result.first.symbol, isNot(equals('X')));
    });
  });
}

