import 'dart:ui' show Rect;
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/layer.dart';
import 'package:stitches/models/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/pattern_progress.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/render_cache.dart';
import 'package:stitches/services/stitch_compositor.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Thread _thread(String code, Color color) =>
    Thread(dmcCode: code, color: color, name: code, symbol: code);

CrossStitchPattern _pattern({
  required List<Thread> threads,
  required List<Stitch> stitches,
}) {
  final layer = Layer(id: 'l', name: 'L', visible: true, opacity: 1.0, stitches: stitches);
  return CrossStitchPattern(
    name: 'Test',
    width: 20,
    height: 20,
    threads: {for (final t in threads) t.dmcCode: t},
    layerItems: [LayerLeaf(layer: layer)],
  );
}

CompositeLayer _composite(CrossStitchPattern pattern) =>
    StitchCompositor.computeLayer(pattern);

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  const cellSize = 20.0;
  const cfg = RenderViewConfig();

  // ── Basic rebuild ──────────────────────────────────────────────────────────

  test('clear: empty store after clear', () {
    final cache = RenderCache();
    cache.clear();
    expect(cache.store, isEmpty);
  });

  test('rebuild: single FullStitch → one rect in correct colour bucket', () {
    final t = _thread('310', const Color(0xFF000000));
    final p = _pattern(
      threads: [t],
      stitches: [FullStitch(x: 0, y: 0, threadId: '310')],
    );
    final cache = RenderCache();
    cache.rebuild(_composite(p), cfg, cellSize);

    expect(cache.store, hasLength(1));
    final bucket = cache.store[const Color(0xFF000000)];
    expect(bucket, isNotNull);
    expect(bucket!.values.expand((r) => r), hasLength(1));
  });

  test('rebuild: rect geometry matches FullStitch block (full cell)', () {
    final t = _thread('310', const Color(0xFF000000));
    final p = _pattern(
      threads: [t],
      stitches: [FullStitch(x: 2, y: 3, threadId: '310')],
    );
    final cache = RenderCache();
    cache.rebuild(_composite(p), cfg, cellSize);

    final rects = cache.store.values
        .expand((b) => b.values)
        .expand((r) => r)
        .toList();
    expect(rects, hasLength(1));
    expect(rects.first, equals(Rect.fromLTWH(2 * cellSize, 3 * cellSize, cellSize, cellSize)));
  });

  test('rebuild: HalfStitch forward → half-width rect', () {
    final t = _thread('310', const Color(0xFF000000));
    final p = _pattern(
      threads: [t],
      stitches: [HalfStitch(x: 1, y: 1, threadId: '310', isForward: true)],
    );
    final cache = RenderCache();
    cache.rebuild(_composite(p), cfg, cellSize);

    final rects = cache.store.values
        .expand((b) => b.values)
        .expand((r) => r)
        .toList();
    expect(rects, hasLength(1));
    // HalfStitch forward: right half → x = x+0.5, width = 0.5
    expect(rects.first.width, closeTo(cellSize * 0.5, 0.001));
  });

  test('rebuild: BackStitch not included in block store', () {
    final t = _thread('310', const Color(0xFF000000));
    final p = _pattern(
      threads: [t],
      stitches: [BackStitch(x1: 0, y1: 0, x2: 1, y2: 0, threadId: '310')],
    );
    final cache = RenderCache();
    cache.rebuild(_composite(p), cfg, cellSize);
    expect(cache.store, isEmpty);
  });

  // ── Version counter ────────────────────────────────────────────────────────

  test('version increments on rebuild', () {
    final t = _thread('310', const Color(0xFF000000));
    final composite = _composite(_pattern(threads: [t], stitches: []));
    final cache = RenderCache();
    final v0 = cache.version;
    cache.rebuild(composite, cfg, cellSize);
    expect(cache.version, equals(v0 + 1));
    cache.rebuild(composite, cfg, cellSize);
    expect(cache.version, equals(v0 + 2));
  });

  test('version increments on clear', () {
    final cache = RenderCache();
    final v0 = cache.version;
    cache.clear();
    expect(cache.version, equals(v0 + 1));
  });

  test('version increments on clearCells', () {
    final cache = RenderCache();
    cache.clear();
    final v = cache.version;
    cache.clearCells({'0,0'});
    expect(cache.version, equals(v + 1));
  });

  test('version increments on updateCells', () {
    final t = _thread('310', const Color(0xFF000000));
    final composite = _composite(_pattern(threads: [t], stitches: []));
    final cache = RenderCache();
    cache.clear();
    final v = cache.version;
    cache.updateCells({'0,0'}, composite, cfg, cellSize);
    expect(cache.version, equals(v + 1));
  });

  // ── Incremental updateCells ────────────────────────────────────────────────

  test('updateCells: removing a cell clears its rects', () {
    final t = _thread('310', const Color(0xFF000000));
    final p = _pattern(
      threads: [t],
      stitches: [
        FullStitch(x: 0, y: 0, threadId: '310'),
        FullStitch(x: 1, y: 1, threadId: '310'),
      ],
    );
    final cache = RenderCache();
    cache.rebuild(_composite(p), cfg, cellSize);
    expect(cache.store.values.expand((b) => b.values).expand((r) => r).length, 2);

    // Remove (0,0) by updating with a composite that has no stitch there.
    final emptyComposite = _composite(_pattern(threads: [t], stitches: []));
    cache.updateCells({'0,0'}, emptyComposite, cfg, cellSize);

    final remaining = cache.store.values.expand((b) => b.values).expand((r) => r).toList();
    expect(remaining, hasLength(1)); // only (1,1) remains
  });

  test('updateCells: updating a cell changes its colour', () {
    final red = _thread('321', const Color(0xFFFF0000));
    final blue = _thread('311', const Color(0xFF0000FF));
    final p = _pattern(
      threads: [red, blue],
      stitches: [FullStitch(x: 0, y: 0, threadId: '321')],
    );
    final cache = RenderCache();
    cache.rebuild(_composite(p), cfg, cellSize);
    expect(cache.store.containsKey(const Color(0xFFFF0000)), isTrue);

    // Update cell (0,0) to use blue thread.
    final p2 = _pattern(
      threads: [red, blue],
      stitches: [FullStitch(x: 0, y: 0, threadId: '311')],
    );
    cache.updateCells({'0,0'}, _composite(p2), cfg, cellSize);

    // Red bucket gone (or empty), blue bucket present.
    final redBucket = cache.store[const Color(0xFFFF0000)];
    expect(redBucket == null || redBucket.isEmpty, isTrue);
    expect(cache.store.containsKey(const Color(0xFF0000FF)), isTrue);
  });

  // ── Focus greying ──────────────────────────────────────────────────────────

  test('focus: unfocused cells rendered in uniform grey', () {
    final red   = _thread('321', const Color(0xFFFF0000));
    final black = _thread('310', const Color(0xFF000000));
    final p = _pattern(
      threads: [red, black],
      stitches: [
        FullStitch(x: 0, y: 0, threadId: '321'),
        FullStitch(x: 1, y: 0, threadId: '310'),
      ],
    );
    // Focus on red (321); black (310) should be greyed.
    const focusCfg = RenderViewConfig(focusThreadId: '321');
    final cache = RenderCache();
    cache.rebuild(_composite(p), focusCfg, cellSize);

    // Red cell: full colour
    expect(cache.store.containsKey(const Color(0xFFFF0000)), isTrue);
    // Black cell: greyed (not the original black)
    expect(cache.store.containsKey(const Color(0xFF000000)), isFalse);
    // Unfocused grey bucket present
    const unfocusedGrey = Color(0xA0B8B8B8);
    expect(cache.store.containsKey(unfocusedGrey), isTrue);
  });

  // ── B&W stitch mode ────────────────────────────────────────────────────────

  test('stitchMode: undone stitches rendered as greyscale', () {
    final red = _thread('321', const Color(0xFFFF0000));
    final p = _pattern(
      threads: [red],
      stitches: [FullStitch(x: 0, y: 0, threadId: '321')],
    );
    const bwCfg = RenderViewConfig(stitchMode: true);
    final cache = RenderCache();
    cache.rebuild(_composite(p), bwCfg, cellSize);

    // Original red not present — should be a greyscale colour.
    expect(cache.store.containsKey(const Color(0xFFFF0000)), isFalse);
    // Some greyscale colour present.
    final hasGrey = cache.store.keys.every((c) => c.r == c.g && c.g == c.b);
    expect(hasGrey, isTrue);
  });

  test('stitchMode: done stitch rendered at full colour', () {
    final red = _thread('321', const Color(0xFFFF0000));
    final p = _pattern(
      threads: [red],
      stitches: [FullStitch(x: 0, y: 0, threadId: '321')],
    );
    // Mark (0,0) as done.
    final progress = PatternProgress.empty.copyWith(
      completedStitches: {(0, 0)},
    );
    final bwCfg = RenderViewConfig(stitchMode: true, progress: progress);
    final cache = RenderCache();
    cache.rebuild(_composite(p), bwCfg, cellSize);

    // Done stitch → full red, not greyscale.
    expect(cache.store.containsKey(const Color(0xFFFF0000)), isTrue);
  });

  // ── rebuildViewConfig ──────────────────────────────────────────────────────

  test('rebuildViewConfig: bumps version', () {
    final t = _thread('310', const Color(0xFF000000));
    final composite = _composite(_pattern(threads: [t], stitches: []));
    final cache = RenderCache();
    cache.rebuild(composite, cfg, cellSize);
    final v = cache.version;
    cache.rebuildViewConfig(composite, cfg, cellSize);
    expect(cache.version, greaterThan(v));
  });

  // ── RenderViewConfig equality ──────────────────────────────────────────────

  test('RenderViewConfig: identical instances are equal', () {
    const a = RenderViewConfig(stitchMode: true, focusThreadId: '310');
    const b = RenderViewConfig(stitchMode: true, focusThreadId: '310');
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('RenderViewConfig: different focusThreadId → not equal', () {
    const a = RenderViewConfig(focusThreadId: '310');
    const b = RenderViewConfig(focusThreadId: '815');
    expect(a, isNot(equals(b)));
  });
}
