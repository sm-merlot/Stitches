// Unit tests for core models and business logic.
//
// Coverage:
//   • Stitch YAML round-trip (all 6 types)
//   • EditorState.isStitchInRect (cell vs grid-point boundaries)
//   • BackStitch clip bug regression — resizeSnippet and
//     resizeEditorPatternAsSnippet must keep backstitches whose endpoints
//     land exactly on the new right/bottom edge (grid-point coords are
//     0..width inclusive, not 0..width-1 like cell coords).
//   • Layer group visibility + lock propagation through pattern.layers
//   • YAML serialization of layer lock / group lock fields
//   • File compression: FileService.toYamlString + saveFile/compress param
//   • AppSettings.compressNewFiles default and EditorState.compressOnSave default
//   • CrossStitchPattern metadata YAML round-trip (description, copyright, materialsSuggestions)
//   • EditorNotifier._assignSymbols — symbol auto-assignment and conflict avoidance

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stitches/models/layer/layer.dart';
import 'package:stitches/models/layer/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/snippet/snippet.dart';
import 'dart:convert';
import 'package:stitches/models/snippet/snippet_palette.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/file_service.dart';

void main() {
  // ─── Stitch YAML round-trip ────────────────────────────────────────────────

  group('Stitch YAML round-trip', () {
    test('FullStitch', () {
      const s = FullStitch(x: 3, y: 7, threadId: '310');
      final back = Stitch.fromYaml(s.toYaml());
      expect(back, isA<FullStitch>());
      final fs = back as FullStitch;
      expect(fs.x, 3);
      expect(fs.y, 7);
      expect(fs.threadId, '310');
    });

    test('HalfStitch forward', () {
      const s = HalfStitch(x: 1, y: 2, isForward: true, threadId: '321');
      final back = Stitch.fromYaml(s.toYaml()) as HalfStitch;
      expect(back.x, 1);
      expect(back.y, 2);
      expect(back.isForward, true);
      expect(back.threadId, '321');
    });

    test('HalfStitch backward', () {
      const s = HalfStitch(x: 0, y: 0, isForward: false, threadId: '900');
      final back = Stitch.fromYaml(s.toYaml()) as HalfStitch;
      expect(back.isForward, false);
    });

    test('QuarterStitch all quadrants', () {
      for (final q in QuadrantPosition.values) {
        final s = QuarterStitch(x: 2, y: 2, quadrant: q, threadId: 'White');
        final back = Stitch.fromYaml(s.toYaml()) as QuarterStitch;
        expect(back.quadrant, q);
      }
    });

    test('HalfCrossStitch all orientations', () {
      for (final h in HalfOrientation.values) {
        final s = HalfCrossStitch(x: 1, y: 1, half: h, threadId: '815');
        final back = Stitch.fromYaml(s.toYaml()) as HalfCrossStitch;
        expect(back.half, h);
      }
    });

    test('ThreeQuarterStitch all quadrants and directions', () {
      for (final q in QuadrantPosition.values) {
        for (final forward in [true, false]) {
          final s = ThreeQuarterStitch(
              x: 0, y: 0, quadrant: q, isForward: forward, threadId: '321');
          final back = Stitch.fromYaml(s.toYaml()) as ThreeQuarterStitch;
          expect(back.quadrant, q);
          expect(back.isForward, forward);
        }
      }
    });

    test('quartercross YAML is silently dropped via fromYamlOrNull', () {
      final yaml = {
        'type': 'quartercross',
        'x': 5,
        'y': 3,
        'quadrant': 'topLeft',
        'thread': '310',
      };
      expect(Stitch.fromYamlOrNull(yaml), isNull);
    });

    test('quartercross stitches are dropped in listFromYaml', () {
      final list = Stitch.listFromYaml([
        {'type': 'full', 'x': 0, 'y': 0, 'thread': '310'},
        {'type': 'quartercross', 'x': 1, 'y': 0, 'quadrant': 'topLeft', 'thread': '310'},
        {'type': 'full', 'x': 2, 'y': 0, 'thread': '310'},
      ]);
      expect(list, hasLength(2));
      expect(list.every((s) => s is FullStitch), isTrue);
    });

    test('BackStitch', () {
      const s = BackStitch(
          x1: 0.5, y1: 1.0, x2: 3.5, y2: 2.0, threadId: '310');
      final back = Stitch.fromYaml(s.toYaml()) as BackStitch;
      expect(back.x1, 0.5);
      expect(back.y1, 1.0);
      expect(back.x2, 3.5);
      expect(back.y2, 2.0);
      expect(back.threadId, '310');
    });

    test('unknown type throws FormatException', () {
      expect(
        () => Stitch.fromYaml({'type': 'unknown', 'thread': '310'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ─── isStitchInRect ────────────────────────────────────────────────────────

  group('EditorState.isStitchInRect', () {
    // rect covers cells (0,0)..(3,3) — i.e. Rect.fromLTWH(0,0,4,4)
    final rect = const Rect.fromLTWH(0, 0, 4, 4);

    test('FullStitch inside', () {
      expect(
          EditorState.isStitchInRect(
              const FullStitch(x: 2, y: 2, threadId: 'x'), rect),
          isTrue);
    });

    test('FullStitch on right edge (exclusive)', () {
      // x==4 is the right boundary — cell coords use <, so this is OUTSIDE.
      expect(
          EditorState.isStitchInRect(
              const FullStitch(x: 4, y: 0, threadId: 'x'), rect),
          isFalse);
    });

    test('FullStitch at last cell (3,3)', () {
      expect(
          EditorState.isStitchInRect(
              const FullStitch(x: 3, y: 3, threadId: 'x'), rect),
          isTrue);
    });

    test('BackStitch both endpoints inside', () {
      expect(
          EditorState.isStitchInRect(
              const BackStitch(
                  x1: 1.0, y1: 1.0, x2: 3.0, y2: 3.0, threadId: 'x'),
              rect),
          isTrue);
    });

    test('BackStitch endpoint on right boundary (inclusive for grid points)', () {
      // Grid point x=4 is the right edge of a 4-wide pattern — must be inside.
      expect(
          EditorState.isStitchInRect(
              const BackStitch(
                  x1: 0.0, y1: 0.0, x2: 4.0, y2: 4.0, threadId: 'x'),
              rect),
          isTrue);
    });

    test('BackStitch endpoint outside', () {
      expect(
          EditorState.isStitchInRect(
              const BackStitch(
                  x1: 0.0, y1: 0.0, x2: 5.0, y2: 0.0, threadId: 'x'),
              rect),
          isFalse);
    });
  });

  // ─── BackStitch clip regression ────────────────────────────────────────────
  //
  // Bug: resizeSnippet and resizeEditorPatternAsSnippet used `< newW`/`< newH`
  // for BackStitch clip, which incorrectly removed backstitches whose endpoints
  // land exactly on the right/bottom edge (grid-point coords are 0..width).
  // Fixed to use `<= newW`/`<= newH` matching resizePattern's inBounds check.

  group('BackStitch clip boundary (regression)', () {
    // Build a minimal snippet: 4×4, one backstitch from (0,0)→(4,4).
    // That endpoint at (4,4) is the corner grid point of the snippet.
    // Clipping to the same 4×4 size must keep the stitch.
    Snippet makeSnippet({
      required int w,
      required int h,
      required List<Stitch> stitches,
    }) {
      return Snippet(
        id: 'test',
        name: 'test',
        width: w,
        height: h,
        stitches: stitches,
        palettes: [SnippetPalette.create()],
        activePaletteIndex: 0,
      );
    }

    test('clip keeps backstitch endpoint exactly on right/bottom edge', () {
      // A 4×4 snippet with a backstitch from (0,0) to (4,4).
      final snippet = makeSnippet(
        w: 4,
        h: 4,
        stitches: [
          const BackStitch(x1: 0, y1: 0, x2: 4, y2: 4, threadId: 't'),
        ],
      );

      // Clip to the same size — the backstitch should survive.
      final clipped = _clipSnippetStitches(snippet.stitches, 4, 4);
      expect(clipped, hasLength(1));
    });

    test('clip keeps backstitch touching only the right edge', () {
      final snippet = makeSnippet(
        w: 3,
        h: 3,
        stitches: [
          const BackStitch(x1: 1, y1: 0, x2: 3, y2: 2, threadId: 't'),
        ],
      );
      final clipped = _clipSnippetStitches(snippet.stitches, 3, 3);
      expect(clipped, hasLength(1));
    });

    test('clip removes backstitch whose endpoint is outside', () {
      final snippet = makeSnippet(
        w: 3,
        h: 3,
        stitches: [
          const BackStitch(x1: 0, y1: 0, x2: 4, y2: 4, threadId: 't'),
        ],
      );
      final clipped = _clipSnippetStitches(snippet.stitches, 3, 3);
      expect(clipped, isEmpty);
    });

    test('clip keeps cell stitches within bounds', () {
      final snippet = makeSnippet(
        w: 4,
        h: 4,
        stitches: [
          const FullStitch(x: 3, y: 3, threadId: 't'),
          const FullStitch(x: 4, y: 0, threadId: 't'), // out-of-bounds
        ],
      );
      final clipped = _clipSnippetStitches(snippet.stitches, 4, 4);
      expect(clipped, hasLength(1));
      expect((clipped.first as FullStitch).x, 3);
    });
  });

  // ─── Layer lock propagation ────────────────────────────────────────────────

  group('Layer lock propagation', () {
    Layer makeLayer({required String id, bool locked = false}) => Layer(
          id: id,
          name: id,
          visible: true,
          locked: locked,
          opacity: 1.0,
          stitches: const [],
        );

    test('locked layer is returned as locked in pattern.layers', () {
      final layer = makeLayer(id: 'L1', locked: true);
      final pattern = CrossStitchPattern(
        name: 'p',
        width: 10,
        height: 10,
        threads: const {},
        layerItems: [LayerLeaf(layer: layer)],
      );
      expect(pattern.layers.single.locked, isTrue);
    });

    test('unlocked layer remains unlocked', () {
      final layer = makeLayer(id: 'L1', locked: false);
      final pattern = CrossStitchPattern(
        name: 'p',
        width: 10,
        height: 10,
        threads: const {},
        layerItems: [LayerLeaf(layer: layer)],
      );
      expect(pattern.layers.single.locked, isFalse);
    });

    test('groupLocked forces all child layers to locked', () {
      final layers = [
        makeLayer(id: 'L1', locked: false),
        makeLayer(id: 'L2', locked: false),
      ];
      final group = LayerGroup(
        id: 'G1',
        name: 'Group',
        collapsed: false,
        groupVisible: true,
        groupLocked: true,
        layers: layers,
      );
      final pattern = CrossStitchPattern(
        name: 'p',
        width: 10,
        height: 10,
        threads: const {},
        layerItems: [group],
      );
      for (final l in pattern.layers) {
        expect(l.locked, isTrue,
            reason: 'groupLocked should force child ${l.id} locked');
      }
    });

    test('groupLocked=false leaves child lock states unchanged', () {
      final layers = [
        makeLayer(id: 'L1', locked: true),
        makeLayer(id: 'L2', locked: false),
      ];
      final group = LayerGroup(
        id: 'G1',
        name: 'Group',
        collapsed: false,
        groupVisible: true,
        groupLocked: false,
        layers: layers,
      );
      final pattern = CrossStitchPattern(
        name: 'p',
        width: 10,
        height: 10,
        threads: const {},
        layerItems: [group],
      );
      expect(pattern.layers[0].locked, isTrue);
      expect(pattern.layers[1].locked, isFalse);
    });

    test('groupVisible=false forces all child layers invisible', () {
      final layers = [
        makeLayer(id: 'L1'),
        makeLayer(id: 'L2'),
      ];
      final group = LayerGroup(
        id: 'G1',
        name: 'Group',
        collapsed: false,
        groupVisible: false,
        groupLocked: false,
        layers: layers,
      );
      final pattern = CrossStitchPattern(
        name: 'p',
        width: 10,
        height: 10,
        threads: const {},
        layerItems: [group],
      );
      for (final l in pattern.layers) {
        expect(l.visible, isFalse);
      }
    });

    test('both groupVisible=false and groupLocked=true stack correctly', () {
      final layers = [makeLayer(id: 'L1')];
      final group = LayerGroup(
        id: 'G1',
        name: 'Group',
        collapsed: false,
        groupVisible: false,
        groupLocked: true,
        layers: layers,
      );
      final pattern = CrossStitchPattern(
        name: 'p',
        width: 10,
        height: 10,
        threads: const {},
        layerItems: [group],
      );
      expect(pattern.layers.single.visible, isFalse);
      expect(pattern.layers.single.locked, isTrue);
    });
  });

  // ─── Layer YAML serialization ──────────────────────────────────────────────

  group('Layer.locked YAML round-trip', () {
    test('locked=true survives toYaml/fromYaml', () {
      final layer = Layer(
        id: 'abc',
        name: 'Test',
        visible: true,
        locked: true,
        opacity: 1.0,
        stitches: const [],
      );
      final yaml = layer.toYaml();
      expect(yaml['locked'], isTrue);
      final back = Layer.fromYaml(Map<String, dynamic>.from(yaml));
      expect(back.locked, isTrue);
    });

    test('locked=false omitted from YAML (defaults false on read)', () {
      final layer = Layer(
        id: 'abc',
        name: 'Test',
        visible: true,
        locked: false,
        opacity: 1.0,
        stitches: const [],
      );
      final yaml = layer.toYaml();
      expect(yaml.containsKey('locked'), isFalse,
          reason: 'false should be omitted to keep files compact');
      final back = Layer.fromYaml(Map<String, dynamic>.from(yaml));
      expect(back.locked, isFalse);
    });
  });

  // ─── CrossStitchPattern.fromYaml — legacy migration ───────────────────────

  group('CrossStitchPattern.fromYaml migration', () {
    test('v1 (stitches key only) creates a single LayerLeaf', () {
      final yaml = {
        'name': 'Old Pattern',
        'width': 5,
        'height': 5,
        'threads': [
          {'dmcCode': '310', 'name': 'Black', 'color': '#000000'},
        ],
        'stitches': [
          {'type': 'full', 'x': 1, 'y': 1, 'thread': '310'},
        ],
      };
      final p = CrossStitchPattern.fromYaml(yaml);
      expect(p.layerItems, hasLength(1));
      expect(p.layerItems.single, isA<LayerLeaf>());
      expect(p.stitches, hasLength(1));
    });

    test('v2 (layers key) wraps each layer in a LayerLeaf', () {
      final yaml = {
        'name': 'v2 Pattern',
        'width': 4,
        'height': 4,
        'threads': [],
        'layers': [
          {
            'id': 'l1',
            'name': 'Layer 1',
            'visible': true,
            'opacity': 1.0,
            'stitches': [],
          },
          {
            'id': 'l2',
            'name': 'Layer 2',
            'visible': true,
            'opacity': 0.8,
            'stitches': [],
          },
        ],
      };
      final p = CrossStitchPattern.fromYaml(yaml);
      expect(p.layerItems, hasLength(2));
      expect(p.layerItems.every((i) => i is LayerLeaf), isTrue);
    });
  });

  // ─── Compression settings ───────────────────────────────────────────────────

  group('Compression settings', () {
    test('AppSettings.compressNewFiles defaults to true', () {
      const settings = AppSettings();
      expect(settings.compressNewFiles, isTrue);
    });

    test('AppSettings.copyWith preserves compressNewFiles', () {
      const settings = AppSettings(compressNewFiles: false);
      final copy = settings.copyWith(useDmc: false);
      expect(copy.compressNewFiles, isFalse);
    });

    test('AppSettings.copyWith overrides compressNewFiles', () {
      const settings = AppSettings(compressNewFiles: true);
      final copy = settings.copyWith(compressNewFiles: false);
      expect(copy.compressNewFiles, isFalse);
    });

    test('EditorState.compressOnSave defaults to true', () {
      final state = EditorState(pattern: CrossStitchPattern.empty());
      expect(state.compressOnSave, isTrue);
    });

    test('EditorState.copyWith toggles compressOnSave', () {
      final state = EditorState(pattern: CrossStitchPattern.empty());
      expect(state.copyWith(compressOnSave: false).compressOnSave, isFalse);
      expect(state.copyWith(compressOnSave: true).compressOnSave, isTrue);
    });

    test('FileService.toYamlString produces text parseable by parseYamlString', () {
      final pattern = CrossStitchPattern.empty().copyWith(name: 'Compression Test');
      final yaml = FileService.toYamlString(pattern);
      final reloaded = FileService.parseYamlString(yaml);
      expect(reloaded.name, equals('Compression Test'));
    });

    test('Uncompressed YAML bytes do not have gzip magic bytes', () {
      final pattern = CrossStitchPattern.empty();
      final bytes = utf8.encode(FileService.toYamlString(pattern));
      // gzip magic: 0x1f 0x8b
      expect(bytes[0], isNot(0x1f));
    });
  });

  // ─── CrossStitchPattern metadata YAML round-trip ──────────────────────────

  group('CrossStitchPattern metadata YAML round-trip', () {
    test('description survives toYaml/fromYaml', () {
      final p = CrossStitchPattern.empty().copyWith(description: 'A nice pattern');
      final yaml = FileService.toYamlString(p);
      final back = FileService.parseYamlString(yaml);
      expect(back.description, equals('A nice pattern'));
    });

    test('copyright survives toYaml/fromYaml', () {
      final p = CrossStitchPattern.empty().copyWith(copyright: '© 2026 Test');
      final yaml = FileService.toYamlString(p);
      final back = FileService.parseYamlString(yaml);
      expect(back.copyright, equals('© 2026 Test'));
    });

    test('materialsSuggestions survive toYaml/fromYaml', () {
      final p = CrossStitchPattern.empty().copyWith(
        materialsSuggestions: [
          (aidaCount: 14, strands: 2),
          (aidaCount: 18, strands: 3),
        ],
      );
      final yaml = FileService.toYamlString(p);
      final back = FileService.parseYamlString(yaml);
      expect(back.materialsSuggestions, hasLength(2));
      expect(back.materialsSuggestions[0].aidaCount, equals(14));
      expect(back.materialsSuggestions[0].strands, equals(2));
      expect(back.materialsSuggestions[1].aidaCount, equals(18));
      expect(back.materialsSuggestions[1].strands, equals(3));
    });

    test('null metadata fields are omitted from YAML output', () {
      final p = CrossStitchPattern.empty();
      final yaml = FileService.toYamlString(p);
      expect(yaml, isNot(contains('description:')));
      expect(yaml, isNot(contains('copyright:')));
    });

    test('empty materialsSuggestions list is omitted from YAML', () {
      final p = CrossStitchPattern.empty();
      final yaml = FileService.toYamlString(p);
      expect(yaml, isNot(contains('materialsSuggestions:')));
    });
  });

  // ─── EditorNotifier._assignSymbols ────────────────────────────────────────

  group('EditorNotifier._assignSymbols', () {
    EditorNotifier notifier() {
      final container = ProviderContainer();
      return container.read(editorProvider.notifier);
    }

    Thread t(String code, String symbol) => Thread(
          dmcCode: code,
          color: const Color(0xFF000000),
          name: code,
          symbol: symbol,
        );

    test('thread with valid visible symbol keeps it unchanged', () {
      final result = notifier().assignSymbolsForTest({'310': t('310', 'A')});
      expect(result.values.single.symbol, equals('A'));
    });

    test('thread with empty symbol gets auto-assigned from kPatternSymbols', () {
      final result = notifier().assignSymbolsForTest({'310': t('310', '')});
      expect(result.values.single.symbol, isNotEmpty);
    });

    test('thread with PDF-unsupported symbol gets reassigned', () {
      final result = notifier().assignSymbolsForTest({'310': t('310', '↑')});
      expect(result.values.single.symbol, isNot(equals('↑')));
      expect(result.values.single.symbol, isNotEmpty);
    });

    test('two threads without symbols get distinct symbols', () {
      final result = notifier().assignSymbolsForTest({'310': t('310', ''), '321': t('321', '')});
      expect(result.values.elementAt(0).symbol, isNotEmpty);
      expect(result.values.elementAt(1).symbol, isNotEmpty);
      expect(result.values.elementAt(0).symbol, isNot(equals(result.values.elementAt(1).symbol)));
    });

    test('existingSymbols param blocks those symbols from assignment', () {
      // 'A' is the first symbol in kPatternSymbols — passing it as existing
      // means the first empty thread must receive something else.
      final result = notifier()
          .assignSymbolsForTest({'310': t('310', '')}, existingSymbols: {'A'});
      expect(result.values.single.symbol, isNot(equals('A')));
      expect(result.values.single.symbol, isNotEmpty);
    });

    test('composite symbols in existingSymbols are not reused for layer threads', () {
      // Simulate a pattern where '■' is already used by a composite thread.
      // A regular thread with no symbol should not be assigned '■'.
      final result = notifier()
          .assignSymbolsForTest({'310': t('310', '')}, existingSymbols: {'A', '■'});
      expect(result.values.single.symbol, isNot(equals('A')));
      expect(result.values.single.symbol, isNot(equals('■')));
    });
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

/// Mirrors the clip logic from resizeSnippet / resizeEditorPatternAsSnippet
/// so the regression tests don't depend on provider state.
/// MUST stay in sync with the production clip predicate.
List<Stitch> _clipSnippetStitches(
    List<Stitch> stitches, int newW, int newH) {
  return stitches.where((s) {
    return switch (s) {
      FullStitch(:final x, :final y) => x < newW && y < newH,
      HalfStitch(:final x, :final y) => x < newW && y < newH,
      QuarterStitch(:final x, :final y) => x < newW && y < newH,
      HalfCrossStitch(:final x, :final y) => x < newW && y < newH,
      ThreeQuarterStitch(:final x, :final y) => x < newW && y < newH,
      // BackStitch grid-point coords: right/bottom boundary is inclusive.
      BackStitch(:final x1, :final y1, :final x2, :final y2) =>
        x1 <= newW && y1 <= newH && x2 <= newW && y2 <= newH,
    };
  }).toList();
}
