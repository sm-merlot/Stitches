import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/pattern.dart';
import '../models/stitch.dart';

const int _kThumbW = 160;
const int _kThumbH = 110;

/// Renders [pattern] to a 160×110 PNG thumbnail.
/// Returns null if the pattern has no stitches or rendering fails.
Future<Uint8List?> generatePatternThumbnail(CrossStitchPattern pattern) async {
  // Build a colour map from threadId → Color for fast lookup.
  final colorMap = pattern.threads.map((k, v) => MapEntry(k, v.color));

  // Collect all visible stitches across all layers.
  final allLayers = pattern.layers;
  final visibleStitches = <Stitch>[];
  for (final layer in allLayers) {
    if (layer.visible) visibleStitches.addAll(layer.stitches);
  }
  if (visibleStitches.isEmpty) return null;

  final patternW = pattern.width;
  final patternH = pattern.height;

  // Scale to fit inside thumbnail, preserving aspect ratio.
  final scaleX = _kThumbW / patternW;
  final scaleY = _kThumbH / patternH;
  final scale = scaleX < scaleY ? scaleX : scaleY;

  final drawW = patternW * scale;
  final drawH = patternH * scale;
  final offsetX = (_kThumbW - drawW) / 2;
  final offsetY = (_kThumbH - drawH) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // Aida background.
  canvas.drawRect(
    Rect.fromLTWH(0, 0, _kThumbW.toDouble(), _kThumbH.toDouble()),
    Paint()..color = const Color(0xFFF5F0E8),
  );

  // Draw stitch cells — use a cell rect sized to scale.
  final cellSize = scale;

  // Batch by colour to minimise Paint object churn.
  final batches = <Color, List<Rect>>{};
  for (final stitch in visibleStitches) {
    if (stitch is BackStitch) continue; // skip backstitches for thumbnail
    final color = colorMap[stitch.threadId];
    if (color == null) continue;
    final rect = _stitchRect(stitch, offsetX, offsetY, cellSize);
    if (rect == null) continue;
    (batches[color] ??= []).add(rect);
  }

  final paint = Paint()..style = PaintingStyle.fill;
  for (final entry in batches.entries) {
    paint.color = entry.key;
    for (final rect in entry.value) {
      canvas.drawRect(rect, paint);
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(_kThumbW, _kThumbH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData?.buffer.asUint8List();
}

Rect? _stitchRect(
    Stitch stitch, double offsetX, double offsetY, double cellSize) {
  return switch (stitch) {
    FullStitch(:final x, :final y) => Rect.fromLTWH(
        offsetX + x * cellSize,
        offsetY + y * cellSize,
        cellSize,
        cellSize,
      ),
    HalfStitch(:final x, :final y, :final isForward) => isForward
        ? Rect.fromLTWH(
            offsetX + x * cellSize + cellSize / 2,
            offsetY + y * cellSize,
            cellSize / 2,
            cellSize,
          )
        : Rect.fromLTWH(
            offsetX + x * cellSize,
            offsetY + y * cellSize,
            cellSize / 2,
            cellSize,
          ),
    QuarterStitch(:final x, :final y, :final quadrant) =>
      _quadrantRect(x, y, quadrant, offsetX, offsetY, cellSize),
    HalfCrossStitch(:final x, :final y, :final half) =>
      _halfCrossRect(x, y, half, offsetX, offsetY, cellSize),
    QuarterCrossStitch(:final x, :final y, :final quadrant) =>
      _quadrantRect(x, y, quadrant, offsetX, offsetY, cellSize),
    BackStitch() => null,
  };
}

Rect _quadrantRect(int x, int y, QuadrantPosition q, double offsetX,
    double offsetY, double cellSize) {
  final left = offsetX + x * cellSize;
  final top = offsetY + y * cellSize;
  final half = cellSize / 2;
  return switch (q) {
    QuadrantPosition.topLeft => Rect.fromLTWH(left, top, half, half),
    QuadrantPosition.topRight => Rect.fromLTWH(left + half, top, half, half),
    QuadrantPosition.bottomLeft => Rect.fromLTWH(left, top + half, half, half),
    QuadrantPosition.bottomRight =>
      Rect.fromLTWH(left + half, top + half, half, half),
  };
}

Rect _halfCrossRect(int x, int y, HalfOrientation h, double offsetX,
    double offsetY, double cellSize) {
  final left = offsetX + x * cellSize;
  final top = offsetY + y * cellSize;
  final half = cellSize / 2;
  return switch (h) {
    HalfOrientation.left => Rect.fromLTWH(left, top, half, cellSize),
    HalfOrientation.right => Rect.fromLTWH(left + half, top, half, cellSize),
    HalfOrientation.top => Rect.fromLTWH(left, top, cellSize, half),
    HalfOrientation.bottom => Rect.fromLTWH(left, top + half, cellSize, half),
  };
}
