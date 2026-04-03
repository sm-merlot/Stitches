import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/layer.dart';
import 'package:stitches/models/layer_blend_mode.dart';
import 'package:stitches/models/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/stitch_compositor.dart';

// ─── Test helpers ─────────────────────────────────────────────────────────────

Thread _thread(String code, Color color) =>
    Thread(dmcCode: code, color: color, name: code, symbol: code);

Layer _layer({
  required List<Stitch> stitches,
  bool visible = true,
  double opacity = 1.0,
  LayerBlendMode blendMode = LayerBlendMode.normal,
}) =>
    Layer(
      id: 'l${stitches.hashCode}',
      name: 'L',
      visible: visible,
      opacity: opacity,
      blendMode: blendMode,
      stitches: stitches,
    );

CrossStitchPattern _pattern({
  required List<Thread> threads,
  required List<Layer> layers,
}) =>
    CrossStitchPattern(
      name: 'Test',
      width: 10,
      height: 10,
      threads: threads,
      layerItems: layers.map((l) => LayerLeaf(layer: l)).toList(),
    );

void main() {
  // ─── Single layer ────────────────────────────────────────────────────────────

  test('single layer, one FullStitch → one entry in compositeThreads, no blend', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
    );
    final r = StitchCompositor.compute(pattern);

    expect(r.compositeThreads, hasLength(1));
    expect(r.compositeThreads['0,0']?.dmcCode, '310');
    expect(r.blendedColors, isEmpty);
    expect(r.dedupedNonBack, hasLength(1));
    expect(r.backstitches, isEmpty);
  });

  test('single layer, FullStitch → crossStitchEquiv 1.0 for that thread', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.crossStitchEquiv['310'], 1.0);
  });

  test('single layer, HalfStitch → crossStitchEquiv 0.5', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [HalfStitch(x: 0, y: 0, isForward: true, threadId: '310')])],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.crossStitchEquiv['310'], closeTo(0.5, 0.001));
  });

  test('single layer, QuarterStitch → crossStitchEquiv 0.25', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [
        QuarterStitch(x: 0, y: 0, quadrant: QuadrantPosition.topLeft, threadId: '310'),
      ])],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.crossStitchEquiv['310'], closeTo(0.25, 0.001));
  });

  test('hidden layer is excluded entirely', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')], visible: false),
      ],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.compositeThreads, isEmpty);
    expect(r.dedupedNonBack, isEmpty);
    expect(r.crossStitchEquiv, isEmpty);
  });

  // ─── Multi-layer deduplication ───────────────────────────────────────────────

  test('two layers with FullStitch at same cell → ONE entry in dedupedNonBack', () {
    final t1 = _thread('310', const Color(0xFF000000));
    final t2 = _thread('321', const Color(0xFFFF0000));
    final pattern = _pattern(
      threads: [t1, t2],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '321')]),
      ],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.dedupedNonBack, hasLength(1));
    expect(r.blendedColors, contains('0,0'));
  });

  test('two layers same cell → crossStitchEquiv totals 1.0 (not 2.0)', () {
    final t1 = _thread('310', const Color(0xFF000000));
    final t2 = _thread('321', const Color(0xFFFF0000));
    final pattern = _pattern(
      threads: [t1, t2],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '321')]),
      ],
    );
    final r = StitchCompositor.compute(pattern);
    final total = r.crossStitchEquiv.values.fold(0.0, (a, b) => a + b);
    expect(total, closeTo(1.0, 0.001));
  });

  test('two layers different cells → two independent entries', () {
    final t1 = _thread('310', const Color(0xFF000000));
    final t2 = _thread('321', const Color(0xFFFF0000));
    final pattern = _pattern(
      threads: [t1, t2],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
        _layer(stitches: [FullStitch(x: 1, y: 0, threadId: '321')]),
      ],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.dedupedNonBack, hasLength(2));
    expect(r.blendedColors, isEmpty);
    final total = r.crossStitchEquiv.values.fold(0.0, (a, b) => a + b);
    expect(total, closeTo(2.0, 0.001));
  });

  // ─── Normal blend symbol-winner logic ────────────────────────────────────────

  test('Normal blend, top layer opacity >= 0.99 → top stitch wins', () {
    final t1 = _thread('310', const Color(0xFF000000));
    final t2 = _thread('321', const Color(0xFFFF0000));
    final pattern = _pattern(
      threads: [t1, t2],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
        _layer(
          stitches: [FullStitch(x: 0, y: 0, threadId: '321')],
          blendMode: LayerBlendMode.normal,
          opacity: 1.0,
        ),
      ],
    );
    final r = StitchCompositor.compute(pattern);
    final winner = r.dedupedNonBack.whereType<FullStitch>().first;
    expect(winner.threadId, '321'); // top layer wins
  });

  test('Add blend → bottom stitch wins (symbol identity from base)', () {
    final t1 = _thread('310', const Color(0xFF000000));
    final t2 = _thread('321', const Color(0xFFFF0000));
    final pattern = _pattern(
      threads: [t1, t2],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
        _layer(
          stitches: [FullStitch(x: 0, y: 0, threadId: '321')],
          blendMode: LayerBlendMode.add,
          opacity: 1.0,
        ),
      ],
    );
    final r = StitchCompositor.compute(pattern);
    final winner = r.dedupedNonBack.whereType<FullStitch>().first;
    expect(winner.threadId, '310'); // bottom layer wins for Add blend
  });

  // ─── Backstitches ────────────────────────────────────────────────────────────

  test('BackStitch is in backstitches and counted in backStitchEquiv', () {
    final t = _thread('310', const Color(0xFF000000));
    final bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: '310');
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [bs])],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.backstitches, hasLength(1));
    expect(r.backStitchEquiv['310'], closeTo(1.0, 0.001));
    expect(r.dedupedNonBack, isEmpty);
    expect(r.crossStitchEquiv, isEmpty);
  });

  test('diagonal BackStitch length is Euclidean', () {
    final t = _thread('310', const Color(0xFF000000));
    // (0,0) → (3,4) has length 5.0
    final bs = BackStitch(x1: 0, y1: 0, x2: 3, y2: 4, threadId: '310');
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [bs])],
    );
    final r = StitchCompositor.compute(pattern);
    expect(r.backStitchEquiv['310'], closeTo(5.0, 0.001));
  });
}
