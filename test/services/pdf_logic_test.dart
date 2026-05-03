// Unit tests for PDF service logic and StitchCompositor integration.
//
// Coverage:
//   • PdfService.buildPdfSymbolMapForTest — filters invisible / PDF-unsupported symbols
//   • StitchCompositor.computeComposite       — layer compositing for the PDF chart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/cell.dart';
import 'package:stitches/models/layer/layer.dart';
import 'package:stitches/models/layer/layer_blend_mode.dart';
import 'package:stitches/models/layer/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/pdf_service.dart';
import 'package:stitches/services/stitch_compositor.dart';

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
    threads: {for (final t in threads) t.dmcCode: t},
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

  // ─── StitchCompositor integration (replaces compositeNonBack tests) ───────────

  group('StitchCompositor via PDF data prep', () {
    test('single layer, single stitch → fullStitches length 1, not blended', () {
      final t = _thread('310', 'X');
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.fullStitches, hasLength(1));
      expect(r.fullStitches[const Cell(0, 0)]?.isBlended, false);
    });

    test('hidden layer is excluded', () {
      final t = _thread('310', 'X');
      final pattern = _pattern(
        threads: [t],
        layers: [
          _layer(
            stitches: [const FullStitch(x: 0, y: 0, threadId: '310')],
            visible: false,
          ),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.fullStitches, isEmpty);
      expect(r.otherStitches, isEmpty);
    });

    test('two layers, same cell → top layer occludes regardless of blend mode', () {
      final t1 = _thread('310', 'X');
      final t2 = _thread('321', 'O');
      final pattern = _pattern(
        threads: [t1, t2],
        layers: [
          _layer(stitches: [const FullStitch(x: 2, y: 3, threadId: '310')]),
          _layer(
            stitches: [const FullStitch(x: 2, y: 3, threadId: '321')],
            blendMode: LayerBlendMode.add,
          ),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.fullStitches, hasLength(1));
      expect(r.fullStitches[const Cell(2, 3)]?.isBlended, false);
      final winner = r.fullStitches[const Cell(2, 3)]?.stitch as FullStitch;
      expect(winner.threadId, '321'); // top layer wins
    });

    test('non-FullStitch types go to otherStitches without deduplication', () {
      final t = _thread('310', 'X');
      final pattern = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            const HalfStitch(x: 0, y: 0, isForward: true, threadId: '310'),
            const HalfStitch(x: 1, y: 0, isForward: false, threadId: '310'),
          ]),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.otherStitches, hasLength(2));
      expect(r.fullStitches, isEmpty);
    });

    test('thread missing from threadMap — FullStitch cell skipped', () {
      final t = _thread('310', 'X');
      final pattern = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: 'UNKNOWN')]),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.fullStitches, isEmpty);
      expect(r.otherStitches, isEmpty);
    });

    test('two different cells, no overlap — both in fullStitches, not blended', () {
      final t1 = _thread('310', 'X');
      final t2 = _thread('321', 'O');
      final pattern = _pattern(
        threads: [t1, t2],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
          _layer(stitches: [const FullStitch(x: 1, y: 0, threadId: '321')]),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.fullStitches, hasLength(2));
      expect(r.fullStitches.values.any((cs) => cs.isBlended), false);
    });

    test('overlapping layers count as ONE stitch total, not two', () {
      final t1 = _thread('310', 'X');
      final t2 = _thread('321', 'O');
      final pattern = _pattern(
        threads: [t1, t2],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '321')]),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      final total = r.crossStitchEquiv.values.fold(0.0, (a, b) => a + b);
      expect(total, closeTo(1.0, 0.001));
    });

    test('BackStitch goes to backstitches, not fullStitches', () {
      final t = _thread('310', 'X');
      final bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: '310');
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [bs])],
      );
      final r = StitchCompositor.computeComposite(pattern);
      expect(r.fullStitches, isEmpty);
      expect(r.backstitches, hasLength(1));
    });

    test('Normal blend, top layer at full opacity → top stitch identity wins', () {
      final t1 = _thread('310', 'X');
      final t2 = _thread('321', 'O');
      final pattern = _pattern(
        threads: [t1, t2],
        layers: [
          _layer(stitches: [const FullStitch(x: 0, y: 0, threadId: '310')]),
          _layer(
            stitches: [const FullStitch(x: 0, y: 0, threadId: '321')],
            blendMode: LayerBlendMode.normal,
          ),
        ],
      );
      final r = StitchCompositor.computeComposite(pattern);
      final winner = r.fullStitches[const Cell(0, 0)]?.stitch as FullStitch;
      expect(winner.threadId, '321');
    });
  });
}
