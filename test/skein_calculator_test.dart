// Unit tests for the skein calculator.
//
// Coverage:
//   • Minimum of 1 skein enforced for any thread
//   • Large stitch counts produce correct ceil'd multi-skein results
//   • Backstitch-only threads calculated from Euclidean cell-unit length
//   • Mixed cross + backstitch usage is additive
//   • Higher aida count → smaller cells → less thread → fewer skeins
//   • More strands per needle → more thread used → more skeins
//   • Thread absent from both maps → minimum 1 skein

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/services/skein_calculator.dart';

void main() {
  group('calculateSkeins', () {
    test('single full stitch always returns minimum 1 skein', () {
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(1));
    });

    test('zero stitches returns minimum 1 skein', () {
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(1));
    });

    test('1000 full stitches, 14-count, 2 strands → 2 skeins', () {
      // hand-calculated: 1000 * 0.02668m = 26.68m; usable = 24m; ceil(26.68/24) = 2
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1000.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(2));
    });

    test('backstitch-only thread, 1000 cell-units, 14-count, 2 strands → 1 skein', () {
      // hand-calculated: 1000 * 0.009434m = 9.43m; usable = 24m; ceil(9.43/24) = 1
      final result = calculateSkeins(
        dmcCode: '815',
        crossEquiv: {},
        backCells: {'815': 1000.0},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(1));
    });

    test('mixed cross + backstitch usage is additive', () {
      // 1000 full (26.68m) + 1000 back (9.43m) = 36.11m; ceil(36.11/24) = 2
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 1000.0},
        backCells: {'310': 1000.0},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(2));
    });

    test('higher aida count (18) needs less thread than 14-count for same stitches', () {
      // 1000 full, 14ct: 2 skeins; 18ct: smaller cells, less thread per stitch
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
      // 500 full, 14ct: 2str→1 skein, 3str→2 skeins
      final skeins2 = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 500.0},
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      final skeins3 = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'310': 500.0},
        backCells: {},
        aidaCount: 14,
        strands: 3,
      );
      expect(skeins3, greaterThan(skeins2));
    });

    test('thread absent from both maps → 1 skein', () {
      final result = calculateSkeins(
        dmcCode: '310',
        crossEquiv: {'321': 100.0}, // different thread
        backCells: {},
        aidaCount: 14,
        strands: 2,
      );
      expect(result, equals(1));
    });
  });
}
