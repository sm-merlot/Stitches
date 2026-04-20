import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:stitches/models/layer.dart';
import 'package:stitches/models/layer_item.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/models/thread.dart';
import 'package:stitches/services/format_service.dart';

void main() {
  group('FormatService OXS', () {
    final fixturePath = p.join(Directory.current.path, 'test/fixtures/minimal.oxs');

    test('importFile parses minimal fixture correctly', () async {
      final pattern = await FormatService.importFile(fixturePath);

      expect(pattern.name, equals('minimal'));
      expect(pattern.width, equals(10));
      expect(pattern.height, equals(10));
      expect(pattern.aidaColor, equals(const Color(0xFFFFFFFF)));

      // Threads: index 0 is cloth (skipped), index 1 is DMC 310
      expect(pattern.threads.length, 1);
      expect(pattern.threads.first.dmcCode, equals('310'));

      final item = pattern.layerItems.first;
      expect(item, isA<LayerLeaf>());
      final stitches = (item as LayerLeaf).layer.stitches;
      expect(stitches.length, 8);

      // Full stitch check
      expect(stitches.any((s) => s is FullStitch && s.x == 1 && s.y == 1),
          isTrue);

      // Half stitch checks
      expect(stitches.any((s) => s is HalfStitch && s.isForward == false && s.x == 2),
          isTrue);
      expect(stitches.any((s) => s is HalfStitch && s.isForward == true && s.x == 3),
          isTrue);

      // Quarter stitch checks
      expect(stitches.any((s) => s is QuarterStitch && s.quadrant == QuadrantPosition.topLeft && s.x == 4),
          isTrue);
      expect(stitches.any((s) => s is QuarterStitch && s.quadrant == QuadrantPosition.bottomRight && s.x == 5),
          isTrue);
      expect(stitches.any((s) => s is QuarterStitch && s.quadrant == QuadrantPosition.topRight && s.x == 6),
          isTrue);
      expect(stitches.any((s) => s is QuarterStitch && s.quadrant == QuadrantPosition.bottomLeft && s.x == 7),
          isTrue);

      // Back stitch check
      expect(stitches.any((s) => s is BackStitch && s.x1 == 8.0 && s.y2 == 9.0),
          isTrue);
    });

    test('round-trip: encode -> decode preserves pattern structure', () async {
      // Create complex pattern manually
      final thread = Thread(dmcCode: '310', color: const Color(0xFF000000), name: 'Black');
      final stitches = [
        FullStitch(x: 5, y: 5, threadId: '310'),
        HalfStitch(x: 2, y: 2, isForward: true, threadId: '310'),
        QuarterStitch(x: 1, y: 1, quadrant: QuadrantPosition.topLeft, threadId: '310'),
        BackStitch(x1: 0.5, y1: 0.5, x2: 1.5, y2: 1.5, threadId: '310'),
      ];

      final original = CrossStitchPattern(
        name: 'roundtrip',
        width: 20,
        height: 20,
        aidaColor: const Color(0xFFF0F0F0),
        threads: [thread],
        layerItems: [
          LayerLeaf(
            layer: Layer(
              id: const Uuid().v4(),
              name: 'Test Layer',
              visible: true,
              opacity: 1.0,
              stitches: stitches,
            ),
          ),
        ],
      );

      // Encode
      final encoded = FormatService.encodeFile(original, CrossStitchFormat.oxs);

      // Use a temp file to simulate import (since importFile reads from disk)
      final tempDir = Directory.systemTemp.createTempSync();
      final tempFile = File(p.join(tempDir.path, 'roundtrip.oxs'));
      await tempFile.writeAsString(encoded);

      try {
        // Decode
        final decoded = await FormatService.importFile(tempFile.path);

        // Assertions
        expect(decoded.name, equals('roundtrip'));
        expect(decoded.width, equals(20));
        expect(decoded.height, equals(20));
        expect(decoded.aidaColor, equals(original.aidaColor));
        expect(decoded.threads.length, 1);
        expect(decoded.threads.first.dmcCode, equals('310'));

        final item = decoded.layerItems.first;
        expect(item, isA<LayerLeaf>());
        final decodedStitches = (item as LayerLeaf).layer.stitches;
        expect(decodedStitches.length, equals(4));
        expect(decodedStitches[0], isA<FullStitch>());
        expect((decodedStitches[0] as FullStitch).x, equals(5));
        expect(decodedStitches[1], isA<HalfStitch>());
        expect((decodedStitches[1] as HalfStitch).isForward, isTrue);
        expect(decodedStitches[2], isA<QuarterStitch>());
        expect((decodedStitches[2] as QuarterStitch).quadrant, equals(QuadrantPosition.topLeft));
        expect(decodedStitches[3], isA<BackStitch>());
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
