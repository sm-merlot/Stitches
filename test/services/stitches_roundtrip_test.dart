import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../lib/models/layer.dart';
import '../../lib/models/layer_blend_mode.dart';
import '../../lib/models/layer_item.dart';
import '../../lib/models/page_config.dart';
import '../../lib/models/pattern.dart';
import '../../lib/models/pattern_progress.dart';
import '../../lib/models/progress_log.dart';
import '../../lib/models/snippet.dart';
import '../../lib/models/snippet_palette.dart';
import '../../lib/models/stitch.dart';
import '../../lib/models/thread.dart';
import '../../lib/services/file_service.dart';

void main() {
  group('.stitches round-trip', () {
    test('v2 pattern survives YAML serialize/parse with core fields intact', () {
      final original = _buildRichPattern();

      final yaml = FileService.toYamlString(original);
      final parsed = FileService.parseYamlString(yaml);

      expect(parsed.name, equals(original.name));
      expect(parsed.width, equals(original.width));
      expect(parsed.height, equals(original.height));
      expect(parsed.aidaColor.value, equals(original.aidaColor.value));
      expect(parsed.designer, equals(original.designer));
      expect(parsed.description, equals(original.description));
      expect(parsed.difficulty, equals(original.difficulty));
      expect(parsed.estimatedHours, equals(original.estimatedHours));
      expect(parsed.copyright, equals(original.copyright));
      expect(parsed.materialsSuggestions, equals(original.materialsSuggestions));

      expect(parsed.threads.length, equals(3));
      expect(parsed.threads.map((t) => t.dmcCode), containsAll(['310', '666', '820']));

      expect(parsed.layerItems, hasLength(2));
      final group = parsed.layerItems.first as LayerGroup;
      expect(group.name, equals('Foreground'));
      expect(group.groupVisible, isTrue);
      expect(group.groupLocked, isTrue);
      expect(group.layers, hasLength(1));
      expect(group.layers.first.blendMode, equals(LayerBlendMode.multiply));

      final layerStitches = group.layers.first.stitches;
      expect(layerStitches.whereType<FullStitch>().single.threadId, equals('310'));
      expect(layerStitches.whereType<HalfStitch>().single.threadId, equals('666'));
      expect(layerStitches.whereType<QuarterStitch>().single.threadId, equals('820'));
      expect(layerStitches.whereType<HalfCrossStitch>().single.threadId, equals('310'));
      expect(layerStitches.whereType<QuarterCrossStitch>().single.threadId, equals('666'));
      expect(layerStitches.whereType<BackStitch>().single.threadId, equals('820'));

      final looseLayer = (parsed.layerItems[1] as LayerLeaf).layer;
      expect(looseLayer.name, equals('Loose layer'));
      expect(looseLayer.stitches, hasLength(1));
      expect(looseLayer.stitches.single, isA<FullStitch>());

      expect(parsed.snippets, hasLength(1));
      final snippet = parsed.snippets.single;
      expect(snippet.palettes, hasLength(2));
      expect(snippet.activePaletteIndex, equals(1));
      expect(snippet.stitches.length, equals(2));

      expect(parsed.compositeSymbols, equals({'310': '#', '666': '@'}));
      expect(
        parsed.pageConfig,
        equals(const PageConfig(enabled: true, pageWidth: 12, pageHeight: 8, fuzzyAmount: 1)),
      );
      expect(
        parsed.progress,
        equals(
          PatternProgress(
            completedStitches: {(1, 1), (2, 2)},
            completedBackstitches: {(0.5, 0.5, 1.5, 1.5)},
            completedPages: {0, 3},
          ),
        ),
      );
      expect(
        parsed.progressLog,
        equals(const [
          ProgressLogEntry(isoDate: '2026-04-01', stitchCount: 9, backstitchCount: 1),
          ProgressLogEntry(isoDate: '2026-04-02', stitchCount: 12, backstitchCount: 2),
        ]),
      );
    });

    test('parseBytesToPattern handles compressed and uncompressed payloads', () async {
      final pattern = _buildRichPattern();
      final yaml = FileService.toYamlString(pattern);

      final plain = Uint8List.fromList(utf8.encode(yaml));
      final compressed = Uint8List.fromList(gzip.encode(utf8.encode(yaml)));

      final (plainPattern, plainCompressedFlag) = await FileService.parseBytesToPattern(plain);
      final (gzipPattern, gzipCompressedFlag) = await FileService.parseBytesToPattern(compressed);

      expect(plainCompressedFlag, isFalse);
      expect(gzipCompressedFlag, isTrue);

      expect(plainPattern.name, equals(pattern.name));
      expect(gzipPattern.name, equals(pattern.name));
      expect(plainPattern.progressLog.length, equals(pattern.progressLog.length));
      expect(gzipPattern.progressLog.length, equals(pattern.progressLog.length));
      expect(plainPattern.snippets.single.palettes.length, equals(2));
      expect(gzipPattern.snippets.single.palettes.length, equals(2));
    });

    test('unknown YAML keys are safely ignored while known fields survive', () {
      const yaml = '''
version: 2
futureTopLevel: keep_or_ignore
patternInfo:
  name: 'Unknown Keys'
  description: 'still parses'
pattern:
  width: 4
  height: 3
  aidaColor: '#FFFFFF'
  unknownPatternField: 123
  threads:
    - dmcCode: '310'
      color: '#000000'
      name: 'Black'
      symbol: 'x'
  layerItems:
    - type: layer
      id: 'layer-1'
      name: 'Layer 1'
      visible: true
      opacity: 1.0
      stitches: []
stitching:
  unknownStitchingField: true
''';

      final parsed = FileService.parseYamlString(yaml);

      expect(parsed.name, equals('Unknown Keys'));
      expect(parsed.width, equals(4));
      expect(parsed.height, equals(3));
      expect(parsed.description, equals('still parses'));
      expect(parsed.threads.single.dmcCode, equals('310'));
    });

    test('legacy v1-style fixture (flat stitches list) still loads', () async {
      final fixturePath = p.join(
        Directory.current.path,
        'test/fixtures/legacy_v1_flat.stitches',
      );

      final (pattern, _, wasCompressed) = await FileService.openFileFromPath(fixturePath);

      expect(wasCompressed, isFalse);
      expect(pattern.name, equals('legacy_v1_flat'));
      expect(pattern.layerItems, hasLength(1));
      final layer = (pattern.layerItems.single as LayerLeaf).layer;
      expect(layer.stitches.length, equals(3));
      expect(layer.stitches.whereType<FullStitch>(), hasLength(1));
      expect(layer.stitches.whereType<HalfStitch>(), hasLength(1));
      expect(layer.stitches.whereType<BackStitch>(), hasLength(1));
    });
  });
}

CrossStitchPattern _buildRichPattern() {
  const black = Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black', symbol: 'X');
  const red = Thread(dmcCode: '666', color: Color(0xFFCC0000), name: 'Bright Red', symbol: 'O');
  const blue = Thread(dmcCode: '820', color: Color(0xFF0F4FA8), name: 'Royal Blue', symbol: '+');

  final groupedLayer = Layer(
    id: 'layer-grouped',
    name: 'Layer A',
    visible: true,
    locked: false,
    opacity: 0.72,
    blendMode: LayerBlendMode.multiply,
    stitches: const [
      FullStitch(x: 1, y: 1, threadId: '310'),
      HalfStitch(x: 2, y: 1, isForward: true, threadId: '666'),
      QuarterStitch(x: 3, y: 1, quadrant: QuadrantPosition.topRight, threadId: '820'),
      HalfCrossStitch(x: 1, y: 2, half: HalfOrientation.left, threadId: '310'),
      QuarterCrossStitch(x: 2, y: 2, quadrant: QuadrantPosition.bottomLeft, threadId: '666'),
      BackStitch(x1: 0.5, y1: 0.5, x2: 1.5, y2: 1.5, threadId: '820'),
    ],
  );

  final looseLayer = Layer(
    id: 'layer-loose',
    name: 'Loose layer',
    visible: false,
    opacity: 0.33,
    stitches: const [
      FullStitch(x: 7, y: 3, threadId: '310'),
    ],
  );

  return CrossStitchPattern(
    name: 'Roundtrip Rich',
    width: 40,
    height: 30,
    aidaColor: const Color(0xFFF8F1E6),
    designer: 'Coverage Bot',
    description: 'Exercises v2 YAML fields',
    difficulty: 'Intermediate',
    estimatedHours: '18',
    copyright: '2026',
    materialsSuggestions: const [
      (aidaCount: 14, strands: 2),
      (aidaCount: 18, strands: 3),
    ],
    threads: const [black, red, blue],
    layerItems: [
      LayerGroup(
        id: 'group-1',
        name: 'Foreground',
        collapsed: true,
        groupVisible: true,
        groupLocked: true,
        layers: [groupedLayer],
      ),
      LayerLeaf(layer: looseLayer),
    ],
    snippets: const [
      Snippet(
        id: 'snippet-1',
        name: 'Corner motif',
        width: 3,
        height: 2,
        activePaletteIndex: 1,
        palettes: [
          SnippetPalette(
            id: 'pal-1',
            name: 'Default',
            threads: [black, red],
          ),
          SnippetPalette(
            id: 'pal-2',
            name: 'Alt',
            threads: [red, blue],
          ),
        ],
        stitches: [
          FullStitch(x: 0, y: 0, threadId: '666'),
          QuarterCrossStitch(x: 1, y: 0, quadrant: QuadrantPosition.topLeft, threadId: '820'),
        ],
      ),
    ],
    compositeSymbols: const {'310': '#', '666': '@'},
    pageConfig: const PageConfig(
      enabled: true,
      pageWidth: 12,
      pageHeight: 8,
      fuzzyAmount: 1,
    ),
    progress: PatternProgress(
      completedStitches: {(1, 1), (2, 2)},
      completedBackstitches: {(0.5, 0.5, 1.5, 1.5)},
      completedPages: {0, 3},
    ),
    // Intentionally out of order; serializer should write sorted-by-date.
    progressLog: const [
      ProgressLogEntry(isoDate: '2026-04-02', stitchCount: 12, backstitchCount: 2),
      ProgressLogEntry(isoDate: '2026-04-01', stitchCount: 9, backstitchCount: 1),
    ],
  );
}
