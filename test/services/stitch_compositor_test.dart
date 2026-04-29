import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/cell.dart';
import 'package:stitches/models/layer/layer.dart';
import 'package:stitches/models/layer/layer_blend_mode.dart';
import 'package:stitches/models/layer/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch/stitch.dart';
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
      threads: {for (final t in threads) t.dmcCode: t},
      layerItems: layers.map((l) => LayerLeaf(layer: l)).toList(),
    );

void main() {
  // ─── Single layer ────────────────────────────────────────────────────────────

  test('single layer, one FullStitch → one entry in fullStitches, no blend', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
    );
    final layer = StitchCompositor.computeLayer(pattern);

    expect(layer.fullStitches, hasLength(1));
    expect(layer.fullStitches[const Cell(0, 0)]?.resolvedThread.dmcCode, '310');
    expect(layer.fullStitches[const Cell(0, 0)]?.isBlended, false);
    expect(layer.backstitches, isEmpty);
  });

  test('single layer, FullStitch → crossStitchEquiv 1.0 for that thread', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.crossStitchEquiv['310'], 1.0);
  });

  test('single layer, HalfStitch → crossStitchEquiv 0.5', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [HalfStitch(x: 0, y: 0, isForward: true, threadId: '310')])],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.crossStitchEquiv['310'], closeTo(0.5, 0.001));
  });

  test('single layer, QuarterStitch → crossStitchEquiv 0.25', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [
        QuarterStitch(x: 0, y: 0, quadrant: QuadrantPosition.topLeft, threadId: '310'),
      ])],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.crossStitchEquiv['310'], closeTo(0.25, 0.001));
  });

  test('hidden layer is excluded entirely', () {
    final t = _thread('310', const Color(0xFF000000));
    final pattern = _pattern(
      threads: [t],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')], visible: false),
      ],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.fullStitches, isEmpty);
    expect(layer.otherStitches, isEmpty);
    expect(layer.crossStitchEquiv, isEmpty);
  });

  // ─── Multi-layer deduplication ───────────────────────────────────────────────

  test('two layers with FullStitch at same cell → ONE entry in fullStitches, isBlended', () {
    final t1 = _thread('310', const Color(0xFF000000));
    final t2 = _thread('321', const Color(0xFFFF0000));
    final pattern = _pattern(
      threads: [t1, t2],
      layers: [
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
        _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '321')]),
      ],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.fullStitches, hasLength(1));
    expect(layer.fullStitches[const Cell(0, 0)]?.isBlended, true);
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
    final layer = StitchCompositor.computeLayer(pattern);
    final total = layer.crossStitchEquiv.values.fold(0.0, (a, b) => a + b);
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
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.fullStitches, hasLength(2));
    expect(layer.fullStitches[const Cell(0, 0)]?.isBlended, false);
    expect(layer.fullStitches[const Cell(1, 0)]?.isBlended, false);
    final total = layer.crossStitchEquiv.values.fold(0.0, (a, b) => a + b);
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
    final layer = StitchCompositor.computeLayer(pattern);
    final cs = layer.fullStitches[const Cell(0, 0)];
    expect(cs?.stitch, isA<FullStitch>());
    expect((cs?.stitch as FullStitch).threadId, '321'); // top layer wins
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
    final layer = StitchCompositor.computeLayer(pattern);
    final cs = layer.fullStitches[const Cell(0, 0)];
    expect((cs?.stitch as FullStitch).threadId, '310'); // bottom layer wins for Add blend
  });

  // ─── Backstitches ────────────────────────────────────────────────────────────

  test('BackStitch is in backstitches and counted in backStitchEquiv', () {
    final t = _thread('310', const Color(0xFF000000));
    final bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: '310');
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [bs])],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.backstitches, hasLength(1));
    expect(layer.backStitchEquiv['310'], closeTo(1.0, 0.001));
    expect(layer.fullStitches, isEmpty);
    expect(layer.crossStitchEquiv, isEmpty);
  });

  test('diagonal BackStitch length is Euclidean', () {
    final t = _thread('310', const Color(0xFF000000));
    // (0,0) → (3,4) has length 5.0
    final bs = BackStitch(x1: 0, y1: 0, x2: 3, y2: 4, threadId: '310');
    final pattern = _pattern(
      threads: [t],
      layers: [_layer(stitches: [bs])],
    );
    final layer = StitchCompositor.computeLayer(pattern);
    expect(layer.backStitchEquiv['310'], closeTo(5.0, 0.001));
  });

  // ─── patchLayer ──────────────────────────────────────────────────────────────

  group('StitchCompositor.patchLayer', () {
    test('adds a stitch: cell absent in old, present in new → entry added', () {
      final t = _thread('310', const Color(0xFF000000));
      final old = CompositeLayer(
        fullStitches: {},
        otherStitches: [],
        backstitches: [],
        crossStitchEquiv: {},
        backStitchEquiv: {},
      );
      final newPat = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 3, y: 4, threadId: '310')])],
      );
      final patched = StitchCompositor.patchLayer(old, newPat, 3, 4);
      expect(patched.fullStitches, hasLength(1));
      expect(patched.fullStitches[const Cell(3, 4)]?.resolvedThread.dmcCode, '310');
      expect(patched.fullStitches[const Cell(3, 4)]?.isBlended, false);
    });

    test('removes a stitch: cell present in old, absent in new → entry removed', () {
      final t = _thread('310', const Color(0xFF000000));
      final oldPat = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 3, y: 4, threadId: '310')])],
      );
      final old = StitchCompositor.computeLayer(oldPat);
      expect(old.fullStitches, contains(const Cell(3, 4)));

      final newPat = _pattern(threads: [t], layers: [_layer(stitches: [])]);
      final patched = StitchCompositor.patchLayer(old, newPat, 3, 4);
      expect(patched.fullStitches, isEmpty);
    });

    test('replaces a stitch: cell changes thread → updated entry', () {
      final t1 = _thread('310', const Color(0xFF000000));
      final t2 = _thread('321', const Color(0xFFFF0000));
      final oldPat = _pattern(
        threads: [t1],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      final old = StitchCompositor.computeLayer(oldPat);

      final newPat = _pattern(
        threads: [t1, t2],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '321')])],
      );
      final patched = StitchCompositor.patchLayer(old, newPat, 0, 0);
      expect(patched.fullStitches[const Cell(0, 0)]?.resolvedThread.dmcCode, '321');
      expect(patched.fullStitches[const Cell(0, 0)]?.isBlended, false);
    });

    test('untouched cells are carried over unchanged', () {
      final t = _thread('310', const Color(0xFF000000));
      final oldPat = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            FullStitch(x: 0, y: 0, threadId: '310'),
            FullStitch(x: 5, y: 5, threadId: '310'),
          ])
        ],
      );
      final old = StitchCompositor.computeLayer(oldPat);
      // Patch (0,0) — add a second thread there; (5,5) must survive.
      final t2 = _thread('321', const Color(0xFFFF0000));
      final newPat = _pattern(
        threads: [t, t2],
        layers: [
          _layer(stitches: [
            FullStitch(x: 0, y: 0, threadId: '321'),
            FullStitch(x: 5, y: 5, threadId: '310'),
          ])
        ],
      );
      final patched = StitchCompositor.patchLayer(old, newPat, 0, 0);
      expect(patched.fullStitches, hasLength(2));
      // (5,5) still the original CompositeStitch instance.
      expect(identical(patched.fullStitches[const Cell(5, 5)], old.fullStitches[const Cell(5, 5)]), true);
      expect(patched.fullStitches[const Cell(0, 0)]?.resolvedThread.dmcCode, '321');
    });

    test('multi-layer cell: isBlended true, symbol from bottom when Add blend', () {
      final t1 = _thread('310', const Color(0xFF000000));
      final t2 = _thread('321', const Color(0xFFFF0000));
      final old = CompositeLayer(
        fullStitches: {},
        otherStitches: [],
        backstitches: [],
        crossStitchEquiv: {},
        backStitchEquiv: {},
      );
      final newPat = _pattern(
        threads: [t1, t2],
        layers: [
          _layer(stitches: [FullStitch(x: 2, y: 2, threadId: '310')]),
          _layer(
            stitches: [FullStitch(x: 2, y: 2, threadId: '321')],
            blendMode: LayerBlendMode.add,
          ),
        ],
      );
      final patched = StitchCompositor.patchLayer(old, newPat, 2, 2);
      final cs = patched.fullStitches[const Cell(2, 2)];
      expect(cs?.isBlended, true);
      // Add blend → symbol winner is bottom layer (thread 310).
      expect((cs?.stitch as FullStitch).threadId, '310');
    });

    test('backstitchesChanged=false: backstitches list carried from old', () {
      final t = _thread('310', const Color(0xFF000000));
      final bs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: '310');
      final old = CompositeLayer(
        fullStitches: {},
        otherStitches: [],
        backstitches: [bs],
        crossStitchEquiv: {},
        backStitchEquiv: {},
      );
      final newPat = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      // backstitchesChanged defaults to false — old.backstitches carried over.
      final patched = StitchCompositor.patchLayer(old, newPat, 0, 0);
      expect(identical(patched.backstitches, old.backstitches), true);
    });

    test('backstitchesChanged=true: backstitches rescanned from new pattern', () {
      final t = _thread('310', const Color(0xFF000000));
      final oldBs = BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: '310');
      final old = CompositeLayer(
        fullStitches: {},
        otherStitches: [],
        backstitches: [oldBs],
        crossStitchEquiv: {},
        backStitchEquiv: {},
      );
      // New pattern has no backstitches.
      final newPat = _pattern(threads: [t], layers: [_layer(stitches: [])]);
      final patched = StitchCompositor.patchLayer(
        old, newPat, 0, 0, backstitchesChanged: true);
      expect(patched.backstitches, isEmpty);
    });

    test('patchLayer result matches computeLayer for a single-stitch add', () {
      final t = _thread('310', const Color(0xFF000000));
      // Start empty, add one stitch.
      final emptyOld = CompositeLayer(
        fullStitches: {},
        otherStitches: [],
        backstitches: [],
        crossStitchEquiv: {},
        backStitchEquiv: {},
      );
      final newPat = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 7, y: 3, threadId: '310')])],
      );
      final patched = StitchCompositor.patchLayer(emptyOld, newPat, 7, 3);
      final full = StitchCompositor.computeLayer(newPat);

      expect(patched.fullStitches.keys.toSet(), full.fullStitches.keys.toSet());
      expect(patched.fullStitches[const Cell(7, 3)]?.resolvedThread.dmcCode,
          full.fullStitches[const Cell(7, 3)]?.resolvedThread.dmcCode);
      expect(patched.fullStitches[const Cell(7, 3)]?.isBlended,
          full.fullStitches[const Cell(7, 3)]?.isBlended);
    });
  });

  // ─── CompositeLayer / instance API ───────────────────────────────────────────

  group('StitchCompositor instance + CompositeLayer', () {
    test('CompositeLayer.fullStitches has one entry per full-stitch cell', () {
      final t = _thread('310', const Color(0xFF000000));
      final pattern = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            FullStitch(x: 0, y: 0, threadId: '310'),
            FullStitch(x: 1, y: 1, threadId: '310'),
          ])
        ],
      );
      final layer = StitchCompositor.computeLayer(pattern);
      expect(layer.fullStitches, hasLength(2));
      expect(layer.fullStitches[const Cell(0, 0)]?.resolvedThread.dmcCode, '310');
      expect(layer.fullStitches[const Cell(0, 0)]?.isBlended, false);
    });

    test('CompositeStitch.isBlended is true for multi-layer overlapping cells', () {
      final t1 = _thread('310', const Color(0xFF000000));
      final t2 = _thread('815', const Color(0xFF800000));
      final pattern = _pattern(
        threads: [t1, t2],
        layers: [
          _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')]),
          _layer(stitches: [FullStitch(x: 0, y: 0, threadId: '815')]),
        ],
      );
      final layer = StitchCompositor.computeLayer(pattern);
      final cs = layer.fullStitches[const Cell(0, 0)];
      expect(cs, isNotNull);
      expect(cs!.isBlended, true);
    });

    test('CompositeStitch.isBlended is false for single-layer cells', () {
      final t = _thread('310', const Color(0xFF000000));
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 5, y: 5, threadId: '310')])],
      );
      final layer = StitchCompositor.computeLayer(pattern);
      expect(layer.fullStitches[const Cell(5, 5)]?.isBlended, false);
    });

    test('otherStitches contains half/quarter stitches with resolved thread', () {
      final t = _thread('321', const Color(0xFFCC0000));
      final pattern = _pattern(
        threads: [t],
        layers: [
          _layer(stitches: [
            HalfStitch(x: 1, y: 1, threadId: '321', isForward: true),
          ])
        ],
      );
      final layer = StitchCompositor.computeLayer(pattern);
      expect(layer.fullStitches, isEmpty);
      expect(layer.otherStitches, hasLength(1));
      expect(layer.otherStitches.first.resolvedThread.dmcCode, '321');
    });

    test('instance: compositeLayer is lazily built and cached', () {
      final t = _thread('310', const Color(0xFF000000));
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      final compositor = StitchCompositor(pattern);
      final first = compositor.compositeLayer;
      final second = compositor.compositeLayer;
      expect(identical(first, second), true); // same instance — not rebuilt
    });

    test('instance: updateCell invalidates cache — next access rebuilds', () {
      final t = _thread('310', const Color(0xFF000000));
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      final compositor = StitchCompositor(pattern);
      final before = compositor.compositeLayer;
      compositor.updateCell(0, 0);
      final after = compositor.compositeLayer;
      expect(identical(before, after), false); // rebuilt after invalidation
    });

    test('instance: updateCells invalidates cache', () {
      final t = _thread('310', const Color(0xFF000000));
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      final compositor = StitchCompositor(pattern);
      final before = compositor.compositeLayer;
      compositor.updateCells([(0, 0), (1, 1)]);
      final after = compositor.compositeLayer;
      expect(identical(before, after), false);
    });

    test('instance: rebuild invalidates cache', () {
      final t = _thread('310', const Color(0xFF000000));
      final pattern = _pattern(
        threads: [t],
        layers: [_layer(stitches: [FullStitch(x: 0, y: 0, threadId: '310')])],
      );
      final compositor = StitchCompositor(pattern);
      final before = compositor.compositeLayer;
      compositor.rebuild();
      final after = compositor.compositeLayer;
      expect(identical(before, after), false);
    });
  });
}
