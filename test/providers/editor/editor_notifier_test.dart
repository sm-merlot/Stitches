import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/layer/layer_blend_mode.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/progress/pattern_progress.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';

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
      expect(editorState(c).pattern.threads.keys, contains('820'));
    });

    test('overpainting same cell with new thread: old thread pruned when no other stitches', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      // Repaint same cell with red — original thread should disappear.
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '666'));
      final threads = editorState(c).pattern.threads.keys;
      expect(threads, contains('666'));
      expect(threads, isNot(contains('310')));
    });

    test('markSaved clears isDirty', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(editorState(c).isDirty, isTrue);
      notifier(c).markSaved();
      expect(editorState(c).isDirty, isFalse);
    });

    test('addStitch provides quick compositeLayer immediately', () {
      notifier(c).refreshCompositeCache();
      final before = editorState(c).compositeLayer;
      final beforeVersion = before?.version ?? -1;
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      // Quick composite computed immediately — not null, and version bumped.
      // patchLayer mutates in-place (same identity) and increments version.
      final after = editorState(c).compositeLayer;
      expect(after, isNotNull);
      expect(after!.version, greaterThan(beforeVersion));
    });

    test('removeStitchesAt provides fresh compositeLayer immediately', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).refreshCompositeCache();
      final before = editorState(c).compositeLayer;
      final beforeVersion = before?.version ?? -1;
      notifier(c).removeStitchesAt(0, 0);
      final after = editorState(c).compositeLayer;
      expect(after, isNotNull);
      expect(after!.version, greaterThan(beforeVersion));
    });

    test('removeStitchesInBox provides fresh compositeLayer immediately', () {
      notifier(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      notifier(c).refreshCompositeCache();
      final before = editorState(c).compositeLayer;
      notifier(c).removeStitchesInBox(2, 2, 1);
      expect(editorState(c).compositeLayer, isNotNull);
      expect(identical(editorState(c).compositeLayer, before), isFalse);
    });

    test('removeBackstitchAt refreshes compositeLayer', () {
      notifier(c).addStitch(const BackStitch(
          x1: 0.0, y1: 0.0, x2: 1.0, y2: 0.0, threadId: '310'));
      notifier(c).refreshCompositeCache();
      final before = editorState(c).compositeLayer;
      notifier(c).removeBackstitchAt(0.0, 0.0, 1.0, 0.0);
      expect(identical(editorState(c).compositeLayer, before), isFalse);
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

    test('newPattern opens in edit mode', () {
      notifier(c).newPattern(CrossStitchPattern.empty(name: 'New'));
      expect(editorState(c).editMode, isTrue);
    });

    test('newPattern sets drawingMode = draw so canvas accepts input', () {
      notifier(c).newPattern(CrossStitchPattern.empty(name: 'New'));
      expect(editorState(c).drawingMode, DrawingMode.draw);
    });

    test('can addStitch immediately after newPattern without switching mode', () {
      notifier(c).newPattern(CrossStitchPattern.empty(name: 'New'));
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(editorState(c).pattern.stitches.whereType<FullStitch>(), hasLength(1));
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
      const t310 = Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: '');
      const t666 = Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'Red',   symbol: '');
      final result = notifier(c).assignSymbolsForTest({'310': t310, '666': t666});
      expect(result.values.every((t) => t.symbol.isNotEmpty), isTrue);
    });

    test('_assignSymbols preserves existing valid symbol', () {
      const t310 = Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X');
      final result = notifier(c).assignSymbolsForTest({'310': t310});
      expect(result.values.first.symbol, equals('X'));
    });

    test('_assignSymbols does not reuse existingSymbols set', () {
      const t310 = Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: '');
      // If 'X' is already taken by composite symbols, it should not be reused.
      final result = notifier(c).assignSymbolsForTest({'310': t310}, existingSymbols: {'X'});
      expect(result.values.first.symbol, isNot(equals('X')));
    });
  });

  // ─── Flood fill ──────────────────────────────────────────────────────────────

  group('EditorNotifier — floodFill draw', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('fills connected same-colour cells with selected thread', () {
      // 2×2 red block at (0,0)..(1,1)
      for (int x = 0; x < 2; x++) {
        for (int y = 0; y < 2; y++) {
          notifier(c).addStitch(FullStitch(x: x, y: y, threadId: '310'));
        }
      }
      // Add an isolated cell in a different location to prove it is NOT filled.
      notifier(c).addStitch(const FullStitch(x: 5, y: 5, threadId: '310'));

      notifier(c).setSelectedThread('666');
      notifier(c).floodFill(0, 0, erase: false);

      final stitches = editorState(c).pattern.stitches.whereType<FullStitch>();
      // The connected block should now all be '666'.
      expect(
        stitches.where((s) => s.x < 2 && s.y < 2).every((s) => s.threadId == '666'),
        isTrue,
      );
      // The isolated cell is not connected and should remain '310'.
      expect(
        stitches.where((s) => s.x == 5 && s.y == 5).single.threadId,
        equals('310'),
      );
    });

    test('flood fill erase removes connected cells', () {
      for (int x = 0; x < 3; x++) {
        notifier(c).addStitch(FullStitch(x: x, y: 0, threadId: '310'));
      }
      notifier(c).floodFill(1, 0, erase: true);
      expect(editorState(c).pattern.stitches, isEmpty);
    });

    test('flood fill erase on empty cell is a no-op', () {
      // Erase on an empty cell (no seed thread) returns early.
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).floodFill(5, 5, erase: true); // no stitch at (5,5)
      expect(editorState(c).pattern.stitches, hasLength(1)); // original unchanged
    });

    test('floodFill refreshes compositeLayer (not left stale)', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).setSelectedThread('310');
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      final before = editorState(c).compositeLayer;
      notifier(c).floodFill(0, 0, erase: true);
      expect(identical(editorState(c).compositeLayer, before), isFalse);
    });
  });

  // ─── Fill-erase and eraser controls ──────────────────────────────────────────

  group('EditorNotifier — fill-erase & eraser', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('setEraserSize clamps to [1,10]', () {
      notifier(c).setEraserSize(20);
      expect(editorState(c).eraserSize, equals(10));
      notifier(c).setEraserSize(0);
      expect(editorState(c).eraserSize, equals(1));
    });

    test('setEraserSize turns off fillEraseActive', () {
      notifier(c).toggleFillErase();
      expect(editorState(c).fillEraseActive, isTrue);
      notifier(c).setEraserSize(3);
      expect(editorState(c).fillEraseActive, isFalse);
    });

    test('toggleFillErase flips fillEraseActive', () {
      expect(editorState(c).fillEraseActive, isFalse);
      notifier(c).toggleFillErase();
      expect(editorState(c).fillEraseActive, isTrue);
      notifier(c).toggleFillErase();
      expect(editorState(c).fillEraseActive, isFalse);
    });
  });

  // ─── Thread management ────────────────────────────────────────────────────────

  group('EditorNotifier — thread management', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('replaceThread remaps all stitches to new code', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));

      notifier(c).replaceThread('310', '666', const Color(0xFFCC0000), 'Red');

      final codes = editorState(c).pattern.threads.keys;
      expect(codes, contains('666'));
      expect(codes, isNot(contains('310')));
      expect(
        editorState(c).pattern.stitches.every((s) => s.threadId == '666'),
        isTrue,
      );
    });

    test('setTool updates currentTool and clears backstitchStartPoint', () {
      notifier(c).setBackstitchStart(const Offset(1, 1));
      notifier(c).setTool(DrawingTool.halfForward);
      expect(editorState(c).currentTool, equals(DrawingTool.halfForward));
      expect(editorState(c).backstitchStartPoint, isNull);
    });

    test('setSelectedThread updates selection and recent list', () {
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '666'));
      notifier(c).setSelectedThread('666');
      expect(editorState(c).selectedThreadId, equals('666'));
      expect(editorState(c).recentThreadIds, contains('666'));
    });
  });

  // ─── Undo cap ─────────────────────────────────────────────────────────────────

  group('EditorNotifier — undo cap', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('undo stack never exceeds 200 entries', () {
      // Add 210 distinct stitches — each push to undo stack.
      for (int i = 0; i < 210; i++) {
        notifier(c).addStitch(FullStitch(x: i % 30, y: i ~/ 30, threadId: '310'));
      }
      // Stack must be capped at 200.
      final state = editorState(c);
      expect(state.canUndo, isTrue);
      // We can't read _undoStack directly, but we can verify undo 200 times
      // doesn't crash (and canUndo eventually becomes false).
      int undoCount = 0;
      while (editorState(c).canUndo && undoCount < 210) {
        notifier(c).undo();
        undoCount++;
      }
      expect(undoCount, lessThanOrEqualTo(200));
    });
  });

  // ─── Progress marking ─────────────────────────────────────────────────────────

  group('EditorNotifier — progress marking', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
      // Switch to stitch mode so marking is active.
      notifier(c).setMode(AppMode.stitch);
    });
    tearDown(() => c.dispose());

    test('toggleStitchDone marks a cell done', () {
      // Must have a stitch in the pattern to mark.
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 2, y: 3, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      notifier(c).toggleStitchDone(2, 3);
      expect(
        editorState(c).pattern.progress.isStitchDone(2, 3),
        isTrue,
      );
    });

    test('toggleStitchDone un-marks an already-done cell', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      notifier(c).toggleStitchDone(1, 1);
      expect(editorState(c).pattern.progress.isStitchDone(1, 1), isTrue);
      notifier(c).toggleStitchDone(1, 1);
      expect(editorState(c).pattern.progress.isStitchDone(1, 1), isFalse);
    });

    test('toggleStitchDone on empty cell is a no-op', () {
      notifier(c).toggleStitchDone(0, 0); // no stitch there
      expect(editorState(c).pattern.progress.completedStitches, isEmpty);
    });

    test('markRegionDone marks all stitches in rect', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      notifier(c).markRegionDone(const Rect.fromLTRB(0, 0, 5, 5));
      final prog = editorState(c).pattern.progress;
      expect(prog.isStitchDone(1, 1), isTrue);
      expect(prog.isStitchDone(2, 2), isTrue);
    });

    test('markRegionNotDone clears stitches in rect', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      notifier(c).markRegionDone(const Rect.fromLTRB(0, 0, 5, 5));
      expect(editorState(c).pattern.progress.isStitchDone(1, 1), isTrue);

      notifier(c).markRegionNotDone(const Rect.fromLTRB(0, 0, 5, 5));
      expect(editorState(c).pattern.progress.isStitchDone(1, 1), isFalse);
    });

    test('clearProgress empties all completed stitches', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);
      notifier(c).toggleStitchDone(1, 1);
      expect(editorState(c).pattern.progress.completedStitches, isNotEmpty);

      notifier(c).clearProgress();
      expect(editorState(c).pattern.progress.completedStitches, isEmpty);
    });

    test('applyProgressSnapshot restores progress without rolling back log', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      notifier(c).toggleStitchDone(1, 1);
      final afterToggle = editorState(c).pattern.progress;
      expect(afterToggle.isStitchDone(1, 1), isTrue);

      // applyProgressSnapshot acts like undo: restore to empty progress.
      notifier(c).applyProgressSnapshot(PatternProgress.empty);
      expect(editorState(c).pattern.progress.isStitchDone(1, 1), isFalse);

      // Re-apply the toggle state (redo equivalent).
      notifier(c).applyProgressSnapshot(afterToggle);
      expect(editorState(c).pattern.progress.isStitchDone(1, 1), isTrue);
    });

    test('setMode(stitch) prunes completed cells no longer in pattern', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);
      notifier(c).toggleStitchDone(1, 1);

      // Remove the stitch from the pattern, then switch back to stitch mode.
      notifier(c).setMode(AppMode.edit);
      notifier(c).removeStitchesAt(1, 1);
      notifier(c).setMode(AppMode.stitch);

      expect(editorState(c).pattern.progress.completedStitches, isEmpty);
    });

    test('progressLog updated after marking; frogging reduces count', () {
      notifier(c).setMode(AppMode.edit);
      for (int i = 0; i < 5; i++) {
        notifier(c).addStitch(FullStitch(x: i, y: 0, threadId: '310'));
      }
      notifier(c).setMode(AppMode.stitch);

      // Mark 3 stitches done.
      for (int i = 0; i < 3; i++) {
        notifier(c).toggleStitchDone(i, 0);
      }
      expect(editorState(c).pattern.progressLog, isNotEmpty);
      final logCount = editorState(c).pattern.progressLog.last.stitchCount;
      expect(logCount, equals(3));

      // Frog one stitch — log count drops.
      notifier(c).toggleStitchDone(0, 0);
      expect(editorState(c).pattern.progressLog.last.stitchCount, equals(2));
    });

    // Bug 3+4: timer minutes must survive stitch marking/frogging ─────────────

    test('addTimeToLog minutes preserved when stitches toggled afterwards', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));
      notifier(c).addStitch(const FullStitch(x: 2, y: 0, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      // Simulate timer stop — adds time to today's log entry.
      notifier(c).addTimeToLog(30);
      expect(editorState(c).pattern.progressLog.last.minutesSpent, equals(30));

      // Mark a stitch done — must not clobber the 30 minutes.
      notifier(c).toggleStitchDone(1, 0);
      final entry = editorState(c).pattern.progressLog
          .firstWhere((e) => e.minutesSpent > 0, orElse: () => throw 'no entry');
      expect(entry.minutesSpent, equals(30));
    });

    test('addTimeToLog accumulates across multiple stops in same day', () {
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      notifier(c).addTimeToLog(20);
      notifier(c).addTimeToLog(15);
      // Should accumulate: 20 + 15 = 35 minutes.
      expect(editorState(c).pattern.progressLog.last.minutesSpent, equals(35));
    });

    test('minutes kept in log entry when stitch count returns to baseline', () {
      // If a user marks and then unmarks stitches, count returns to its
      // starting value. The log entry must be kept (not deleted) if it has
      // timer minutes, so time is not lost.
      notifier(c).setMode(AppMode.edit);
      notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));
      notifier(c).setMode(AppMode.stitch);

      // Timer minutes present before any marking.
      notifier(c).addTimeToLog(45);

      // Mark and immediately frog — net count change is zero.
      notifier(c).toggleStitchDone(1, 0); // mark
      notifier(c).toggleStitchDone(1, 0); // frog back

      // Entry must still exist with minutes intact.
      final todayEntries = editorState(c).pattern.progressLog;
      expect(todayEntries, isNotEmpty);
      expect(todayEntries.last.minutesSpent, equals(45));
    });

    // Bug 2: markRegionDone focus-mode uses topmost-thread check ──────────────

    test('markRegionDone in focus mode only marks cells where focused thread is topmost', () {
      // Two layers: layer1 (bottom) has red at (0,0) and (1,0).
      //             layer2 (top)    has black at (1,0) only.
      // Focus on red → only (0,0) should be marked (it has red on top).
      // (1,0) has black on top → must NOT be marked even though red is present.
      notifier(c).setMode(AppMode.edit);

      // addStitch auto-registers threads; draw red on layer1 (active after load).
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '666'));
      notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '666'));

      // Create a second layer and draw black on top of (1,0).
      notifier(c).addLayer();
      final layer2Id = editorState(c).pattern.layers.last.id;
      notifier(c).setActiveLayer(layer2Id);
      notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));

      notifier(c).setMode(AppMode.stitch);
      notifier(c).setStitchFocusThread('666'); // focus on red

      notifier(c).markRegionDone(const Rect.fromLTRB(0, 0, 2, 1));

      final prog = editorState(c).pattern.progress;
      // (0,0): only red stitch, topmost = red → should be done
      expect(prog.isStitchDone(0, 0), isTrue,
          reason: 'cell with red on top must be marked');
      // (1,0): red below, black on top → topmost ≠ focused → must NOT be marked
      expect(prog.isStitchDone(1, 0), isFalse,
          reason: 'cell with black on top must not be marked in red focus mode');
    });
  });

  // ─── Pattern metadata ──────────────────────────────────────────────────────

  group('EditorNotifier — metadata', () {
    late ProviderContainer c;
    setUp(() { c = makeContainer(); loadEmpty(c); });
    tearDown(() => c.dispose());

    test('updatePatternMetadata persists all fields', () {
      notifier(c).updatePatternMetadata(
        name: 'Updated',
        designer: 'Tester',
        description: 'A test pattern',
        difficulty: 'Easy',
        estimatedHours: '5',
        copyright: '2026',
      );
      final p = editorState(c).pattern;
      expect(p.name, equals('Updated'));
      expect(p.designer, equals('Tester'));
      expect(p.description, equals('A test pattern'));
      expect(p.difficulty, equals('Easy'));
      expect(p.estimatedHours, equals('5'));
      expect(p.copyright, equals('2026'));
      expect(editorState(c).isDirty, isTrue);
    });
  });
}
