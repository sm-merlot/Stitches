// Unit tests for PDF service logic exposed via @visibleForTesting wrappers.
//
// Coverage:
//   • PdfService.buildPdfSymbolMapForTest — filters invisible / PDF-unsupported symbols
//   • PdfService.compositeNonBackForTest  — layer compositing for the PDF chart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/layer.dart';
import 'package:stitches/models/layer_blend_mode.dart';
import 'package:stitches/models/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/pdf_service.dart';

// ─── Test helpers ─────────────────────────────────────────────────────────────

Thread _thread(String code, String symbol) => Thread(
      dmcCode: code,
      color: Colors.black,
      name: code,
      symbol: symbol,
    );

CrossStitchPattern _pattern({
  required List<Thread> threads,
  required List<Layer> layers,
}) {
  return CrossStitchPattern(
    name: 'Test',
    width: 10,
    height: 10,
    threads: threads,
    layerItems: layers.map((l) => LayerLeaf(layer: l)).toList(),
  );
}

Layer _layer({
  required List<Stitch> stitches,
  bool visible = true,
  double opacity = 1.0,
  LayerBlendMode blendMode = LayerBlendMode.normal,
}) =>
    Layer(
      id: 'l',
      name: 'L',
      visible: visible,
      opacity: opacity,
      blendMode: blendMode,
      stitches: stitches,
    );

void main() {
  // ─── _buildPdfSymbolMap ────────────────────────────────────────────────────

  group('buildPdfSymbolMap', () {
    test('visible supported symbol is included', () {
      final map = PdfService.buildPdfSymbolMapForTest([_thread('310', 'A')]);
      expect(map, containsPair('310', 'A'));
    });

    test('empty symbol is excluded', () {
      final map = PdfService.buildPdfSymbolMapForTest([_thread('310', '')]);
      expect(map, isEmpty);
    });

    test('PDF-unsupported symbol (arrow) is excluded', () {
      final map = PdfService.buildPdfSymbolMapForTest([_thread('310', '↑')]);
      expect(map, isEmpty);
    });

    test('mix of valid and invalid threads — only valid appear', () {
      final map = PdfService.buildPdfSymbolMapForTest([
        _thread('310', 'A'),  // valid
        _thread('321', '↑'),  // unsupported
        _thread('blanc', ''), // invisible
        _thread('815', 'B'),  // valid
      ]);
      expect(map.keys, containsAll(['310', '815']));
      expect(map.keys, isNot(contains('321')));
      expect(map.keys, isNot(contains('blanc')));
    });

    test('duplicate dmcCode — last entry wins (Map semantics)', () {
      final map = PdfService.buildPdfSymbolMapForTest([
        _thread('310', 'A'),
        _thread('310', 'B'),
      ]);
      expect(map['310'], equals('B'));
    });
  });

  // ─── _compositeNonBack ─────────────────────────────────────────────────────

  group('compositeNonBack', () {
    test('single visible layer, single FullStitch — passes through, no blend', () {
      final t = _thread('310', 'A');
      final p = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': t});
      expect(nonBack, hasLength(1));
      expect(blendedColors, isEmpty);
    });

    test('hidden layer stitches are excluded', () {
      final t = _thread('310', 'A');
      final p = _pattern(
        threads: [t],
        layers: [
          _layer(
            stitches: [const FullStitch(x: 0, y: 0, threadId: '310')],
            visible: false,
          ),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': t});
      expect(nonBack, isEmpty);
      expect(blendedColors, isEmpty);
    });

    test('BackStitch in layer is excluded from nonBack', () {
      final t = _thread('310', 'A');
      final p = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            const BackStitch(x1: 0, y1: 0, x2: 1, y2: 1, threadId: '310'),
          ]),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': t});
      expect(nonBack, isEmpty);
    });

    test('two layers, same cell, Normal at full opacity — top stitch identity wins', () {
      final tBottom = _thread('310', 'A');
      final tTop = _thread('321', 'B');
      final p = _pattern(
        threads: [tBottom, tTop],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '321')]),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': tBottom, '321': tTop});
      expect(nonBack, hasLength(1));
      expect((nonBack.first as FullStitch).threadId, equals('321'));
    });

    test('two layers, same cell, Add blend — bottom stitch identity used; blendedColors present', () {
      final tBottom = _thread('310', 'A');
      final tTop = _thread('321', 'B');
      final p = _pattern(
        threads: [tBottom, tTop],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
          _layer(
            stitches: [const FullStitch(x: 0, y: 0, threadId: '321')],
            blendMode: LayerBlendMode.add,
          ),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': tBottom, '321': tTop});
      expect(nonBack, hasLength(1));
      // Add blend → top is not normal full-opacity → bottom layer identity
      expect((nonBack.first as FullStitch).threadId, equals('310'));
      expect(blendedColors, contains('0,0'));
    });

    test('non-FullStitch types pass through in otherNonBack without deduplication', () {
      final t = _thread('310', 'A');
      final p = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            const HalfStitch(x: 0, y: 0, isForward: true, threadId: '310'),
            const QuarterStitch(
                x: 1, y: 1, quadrant: QuadrantPosition.topLeft, threadId: '310'),
          ]),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': t});
      expect(nonBack, hasLength(2));
      expect(blendedColors, isEmpty);
    });

    test('thread missing from threadMap — cell skipped', () {
      final p = _pattern(
        threads: [],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {}); // empty map
      expect(nonBack, isEmpty);
    });

    test('two different cells, no overlap — both stitches in result, no blend', () {
      final t = _thread('310', 'A');
      final p = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            const FullStitch(x: 0, y: 0, threadId: '310'),
            const FullStitch(x: 1, y: 1, threadId: '310'),
          ]),
        ],
      );
      final (:nonBack, :blendedColors) =
          PdfService.compositeNonBackForTest(p, {'310': t});
      expect(nonBack, hasLength(2));
      expect(blendedColors, isEmpty);
    });
  });
}
