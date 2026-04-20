/// Tests for SpriteImporter — the pure-matching logic.
///
/// matchPixel is a static method with no side effects beyond a lazy-init
/// cache. importRegion is exercised with a small synthetic image built using
/// the `image` package (already a direct dependency).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:stitches/models/stitch.dart';
import 'package:stitches/services/sprite_importer.dart';

void main() {
  // ─── matchPixel ───────────────────────────────────────────────────────────

  group('SpriteImporter.matchPixel', () {
    test('fully transparent pixel returns null', () {
      expect(SpriteImporter.matchPixel(255, 0, 0, 0), isNull);
      expect(SpriteImporter.matchPixel(255, 0, 0, 127), isNull);
    });

    test('opaque pixel returns a non-null DmcColor', () {
      expect(SpriteImporter.matchPixel(0, 0, 0, 255), isNotNull);
    });

    test('pure black pixel matches a dark DMC colour', () {
      final match = SpriteImporter.matchPixel(0, 0, 0, 255);
      expect(match, isNotNull);
      // DMC 310 is the canonical black — value of L in Lab should be small
      final c = match!.color;
      final brightness = (c.r + c.g + c.b) / 3.0;
      expect(brightness, lessThan(0.25)); // very dark
    });

    test('pure white pixel matches a light DMC colour', () {
      final match = SpriteImporter.matchPixel(255, 255, 255, 255);
      expect(match, isNotNull);
      final c = match!.color;
      final brightness = (c.r + c.g + c.b) / 3.0;
      expect(brightness, greaterThan(0.7)); // very light
    });

    test('same pixel called twice returns same code (cache stable)', () {
      final a = SpriteImporter.matchPixel(200, 50, 50, 255);
      final b = SpriteImporter.matchPixel(200, 50, 50, 255);
      expect(a?.code, equals(b?.code));
    });
  });

  // ─── importRegion ─────────────────────────────────────────────────────────

  group('SpriteImporter.importRegion', () {
    /// Build a small solid-colour image.
    img.Image solid(int r, int g, int b, {int w = 4, int h = 4}) {
      final image = img.Image(width: w, height: h, numChannels: 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      return image;
    }

    test('solid black 4×4 → 16 FullStitches, all same threadId', () {
      final image = solid(0, 0, 0);
      final result = SpriteImporter.importRegion(image, 0, 0, 4, 4);
      expect(result.stitches, hasLength(16));
      expect(result.stitches.whereType<FullStitch>(), hasLength(16));
      final codes = result.threads.map((t) => t.dmcCode).toSet();
      expect(codes, hasLength(1));
    });

    test('transparent image produces no stitches', () {
      final image = img.Image(width: 4, height: 4, numChannels: 4);
      // All pixels are default transparent.
      final result = SpriteImporter.importRegion(image, 0, 0, 4, 4);
      expect(result.stitches, isEmpty);
      expect(result.threads, isEmpty);
    });

    test('region clamp: requesting out-of-bounds region does not throw', () {
      final image = solid(0, 0, 0, w: 3, h: 3);
      expect(
        () => SpriteImporter.importRegion(image, 2, 2, 10, 10),
        returnsNormally,
      );
    });

    test('stitches are normalised to start at (0,0) relative to region', () {
      final image = solid(0, 0, 0, w: 10, h: 10);
      // Import a 2×2 region starting at (3,5).
      final result = SpriteImporter.importRegion(image, 3, 5, 2, 2);
      final xs = result.stitches.whereType<FullStitch>().map((s) => s.x);
      final ys = result.stitches.whereType<FullStitch>().map((s) => s.y);
      expect(xs, everyElement(lessThan(2)));
      expect(ys, everyElement(lessThan(2)));
    });

    test('mergeThreshold 0 disables merging — all distinct colours survive', () {
      // Two-colour 2×2 checkerboard.
      final image = img.Image(width: 2, height: 2, numChannels: 4);
      image.setPixelRgba(0, 0, 0, 0, 0, 255);     // black
      image.setPixelRgba(1, 0, 255, 255, 255, 255); // white
      image.setPixelRgba(0, 1, 255, 255, 255, 255); // white
      image.setPixelRgba(1, 1, 0, 0, 0, 255);       // black
      final result = SpriteImporter.importRegion(image, 0, 0, 2, 2,
          mergeThreshold: 0);
      expect(result.threads.length, greaterThanOrEqualTo(2));
    });
  });
}

