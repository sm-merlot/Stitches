// Unit tests for the skein calculator.
//
// Coverage:
//   • Minimum of ¼ skein enforced for any thread
//   • Large stitch counts produce correct quarter-ceil'd results
//   • Backstitch-only threads calculated from Euclidean cell-unit length
//   • Mixed cross + backstitch usage is additive
//   • Higher aida count → smaller cells → less thread → fewer skeins
//   • More strands per needle → more thread used → more skeins
//   • Thread absent from both maps → minimum ¼ skein
//   • skeinLabel formats quarter-precision values correctly

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/services/skein_calculator.dart';

void main() {
  group('calculateSkeins', () {
    test('single full stitch returns minimum ¼ skein', () {
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(0.25));
    });

    test('zero stitches returns minimum ¼ skein', () {
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(0.25));
    });

    test('1000 full stitches, 14-count, 2 strands → ¾ skein', () {
      // cellMm=1.814; 1000 * 0.01334m = 13.34m; usable=24m; ceil(13.34/24*4)/4 = 3/4 = 0.75
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1000.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(0.75));
    });

    test('backstitch-only thread, 1000 cell-units, 14-count, 2 strands → ¼ skein', () {
      // cellMm=1.814; 2 strands * 1000 * 0.00472m = 9.43m; skein=48m; ceil(9.43/48*4)/4 = 1/4 = 0.25
      final result = calculateSkeins(
        dmcCode: '815',
        crossEquiv: {},
        backCells: {'815': 1000.0},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(0.25));
    });

    test('mixed cross + backstitch usage is additive', () {
      // 2 strands * (1000 cross * 0.01334m + 1000 back * 0.00472m) = 36.12m; skein=48m; ceil(36.12/48*4)/4 = 4/4 = 1.0
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1000.0},
        backCells: {'310': 1000.0},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(1.0));
    });

    test('higher aida count (18) needs less thread than 14-count for same stitches', () {
      final skeins14 = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1000.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      final skeins18 = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1000.0},
        backCells: {},
        aidaCount: 18,
        strands: 2,
      );
      expect(skeins18, lessThanOrEqualTo(skeins14));
    });

    test('more strands (3 vs 2) uses more thread → more skeins for same stitch count', () {
      final skeins2 = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 700.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      final skeins3 = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 700.0},
        backCells: {},
        aidaCount: 14,
        strands: 3,
      );
      expect(skeins3, greaterThan(skeins2));
    });

    test('thread absent from both maps → minimum ¼ skein', () {
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'321': 100.0}, // different thread
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(0.25));
    });

    test('result is always a multiple of 0.25', () {
      for (final equiv in [1.0, 50.0, 200.0, 999.0]) {
        final result = calculateSkeins(
          dmcCode: '310',
          crossEquiv: {'310': equiv},
          backCells: {},
          aidaCount: 14,
          strands: 2,
        );
        expect((result * 4).roundToDouble(), equals(result * 4),
            reason: '$result is not a quarter-skein multiple');
      }
    });
  });

  group('skeinLabel', () {
    test('0.25 → ¼', () => expect(skeinLabel(0.25), '¼'));
    test('0.5  → ½', () => expect(skeinLabel(0.5), '½'));
    test('0.75 → ¾', () => expect(skeinLabel(0.75), '¾'));
    test('1.0  → 1', () => expect(skeinLabel(1.0), '1'));
    test('1.25 → 1¼', () => expect(skeinLabel(1.25), '1¼'));
    test('1.5  → 1½', () => expect(skeinLabel(1.5), '1½'));
    test('1.75 → 1¾', () => expect(skeinLabel(1.75), '1¾'));
    test('2.0  → 2', () => expect(skeinLabel(2.0), '2'));
    test('3.5  → 3½', () => expect(skeinLabel(3.5), '3½'));
  });
}
