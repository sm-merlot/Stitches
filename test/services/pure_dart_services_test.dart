/// Tests for pure-Dart services: color_space, dashed_line.
///
/// No Flutter imports, no fakes needed — these functions are stateless.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/color_space.dart';
import '../../lib/services/dashed_line.dart';

void main() {
  // ─── color_space ──────────────────────────────────────────────────────────

  group('color_space — rgbToLab', () {
    test('pure black → L=0, a≈0, b≈0', () {
      final (l, a, b) = rgbToLab(0, 0, 0);
      expect(l, closeTo(0.0, 0.5));
      expect(a, closeTo(0.0, 0.5));
      expect(b, closeTo(0.0, 0.5));
    });

    test('pure white → L≈100, a≈0, b≈0', () {
      final (l, a, b) = rgbToLab(255, 255, 255);
      expect(l, closeTo(100.0, 1.0));
      expect(a, closeTo(0.0, 1.0));
      expect(b, closeTo(0.0, 1.0));
    });

    test('neutral grey has a≈0, b≈0', () {
      final (_, a, b) = rgbToLab(128, 128, 128);
      expect(a, closeTo(0.0, 1.0));
      expect(b, closeTo(0.0, 1.0));
    });

    test('pure red has a > 0 (reddish hue)', () {
      final (_, a, __) = rgbToLab(255, 0, 0);
      expect(a, greaterThan(30.0));
    });

    test('pure blue has b < 0 (blue hue)', () {
      final (_, __, b) = rgbToLab(0, 0, 255);
      expect(b, lessThan(-30.0));
    });

    test('round-trip: different greys maintain strict L ordering', () {
      final l1 = rgbToLab(50, 50, 50).$1;
      final l2 = rgbToLab(128, 128, 128).$1;
      final l3 = rgbToLab(200, 200, 200).$1;
      expect(l1, lessThan(l2));
      expect(l2, lessThan(l3));
    });
  });

  group('color_space — labDistance / labDistanceSquared', () {
    test('distance from a colour to itself is 0', () {
      final lab = rgbToLab(100, 150, 200);
      expect(labDistance(lab, lab), closeTo(0.0, 1e-9));
      expect(labDistanceSquared(lab, lab), closeTo(0.0, 1e-9));
    });

    test('distance(a,b) == distance(b,a)', () {
      final a = rgbToLab(255, 0, 0);
      final b = rgbToLab(0, 0, 255);
      expect(labDistance(a, b), closeTo(labDistance(b, a), 1e-9));
    });

    test('black–white distance is large (> 50)', () {
      final black = rgbToLab(0, 0, 0);
      final white = rgbToLab(255, 255, 255);
      expect(labDistance(black, white), greaterThan(50.0));
    });

    test('labDistanceSquared == labDistance^2', () {
      final a = rgbToLab(200, 100, 50);
      final b = rgbToLab(50, 200, 100);
      final dist = labDistance(a, b);
      expect(labDistanceSquared(a, b), closeTo(dist * dist, 1e-6));
    });

    test('perceptually similar colors are closer than dissimilar ones', () {
      final target = rgbToLab(200, 0, 0);
      final nearRed = rgbToLab(210, 10, 10);
      final blue = rgbToLab(0, 0, 200);
      expect(labDistance(target, nearRed), lessThan(labDistance(target, blue)));
    });
  });

  group('color_space — nearestLabIndex', () {
    test('returns -1 for empty list', () {
      expect(nearestLabIndex([], rgbToLab(255, 0, 0)), equals(-1));
    });

    test('returns 0 for single-element list', () {
      final lab = rgbToLab(100, 100, 100);
      expect(nearestLabIndex([lab], lab), equals(0));
    });

    test('returns the index of the nearest entry', () {
      final target = rgbToLab(200, 0, 0);
      final labs = [
        rgbToLab(0, 0, 255),   // blue — far
        rgbToLab(210, 10, 0),  // near-red — closest
        rgbToLab(0, 200, 0),   // green — far
      ];
      expect(nearestLabIndex(labs, target), equals(1));
    });

    test('exact match returns that index', () {
      final red = rgbToLab(255, 0, 0);
      final green = rgbToLab(0, 255, 0);
      final blue = rgbToLab(0, 0, 255);
      expect(nearestLabIndex([red, green, blue], green), equals(1));
    });
  });

  // ─── dashed_line ─────────────────────────────────────────────────────────

  group('dashed_line — forEachDashSegment', () {
    List<(double, double, double, double)> segments(
      double x1,
      double y1,
      double x2,
      double y2, {
      double dashLen = 5.0,
      double gapLen = 3.0,
    }) {
      final result = <(double, double, double, double)>[];
      forEachDashSegment(x1, y1, x2, y2,
          dashLen: dashLen,
          gapLen: gapLen,
          onSegment: (sx, sy, ex, ey) => result.add((sx, sy, ex, ey)));
      return result;
    }

    test('zero-length line produces no segments', () {
      expect(segments(5, 5, 5, 5), isEmpty);
    });

    test('line shorter than one dash gives exactly one segment', () {
      final s = segments(0, 0, 3, 0, dashLen: 5.0, gapLen: 3.0);
      expect(s.length, equals(1));
      // The segment should span the whole line.
      expect(s.single.$1, closeTo(0.0, 1e-9));
      expect(s.single.$3, closeTo(3.0, 1e-9));
    });

    test('horizontal line of exactly 8 units (5 dash + 3 gap) gives one segment', () {
      final s = segments(0, 0, 8, 0, dashLen: 5.0, gapLen: 3.0);
      expect(s.length, equals(1));
      expect(s.single.$3, closeTo(5.0, 1e-9)); // clamped to dash length
    });

    test('horizontal line of 16 units gives two dash segments', () {
      // 5 dash + 3 gap + 5 dash + 3 gap = 16
      final s = segments(0, 0, 16, 0, dashLen: 5.0, gapLen: 3.0);
      expect(s.length, equals(2));
    });

    test('all segment start points lie within the line', () {
      final s = segments(0, 0, 100, 0, dashLen: 7.0, gapLen: 4.0);
      for (final seg in s) {
        expect(seg.$1, greaterThanOrEqualTo(0.0));
        expect(seg.$3, lessThanOrEqualTo(100.0 + 1e-9));
      }
    });

    test('segments are non-overlapping and in order', () {
      final s = segments(0, 0, 50, 0, dashLen: 4.0, gapLen: 2.0);
      for (var i = 1; i < s.length; i++) {
        // Each segment starts after the previous one ends.
        expect(s[i].$1, greaterThan(s[i - 1].$3 - 1e-9));
      }
    });

    test('diagonal line produces segments on the same line (unit vector)', () {
      final s = segments(0, 0, 10, 10, dashLen: 3.0, gapLen: 2.0);
      expect(s, isNotEmpty);
      for (final seg in s) {
        // Each segment should be parallel to the original direction: dy/dx == 1
        final dx = seg.$3 - seg.$1;
        final dy = seg.$4 - seg.$2;
        if (dx.abs() > 1e-9) {
          expect(dy / dx, closeTo(1.0, 1e-6));
        }
      }
    });
  });
}

