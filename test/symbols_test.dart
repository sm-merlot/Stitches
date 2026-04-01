// Unit tests for symbol visibility, PDF-unsupported filtering, and similarity groups.
//
// Coverage:
//   • symbolIsVisible — invisible/control/whitespace chars, visible chars
//   • symbolIsPdfUnsupported — arrows, circled operators, cross mark
//   • symbolSimilarityGroup — group membership and -1 for unrecognised symbols

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/data/symbols.dart';

void main() {
  // ─── symbolIsVisible ───────────────────────────────────────────────────────

  group('symbolIsVisible', () {
    test('empty string → false', () {
      expect(symbolIsVisible(''), isFalse);
    });

    test('plain space → false', () {
      expect(symbolIsVisible(' '), isFalse);
    });

    test('NBSP (U+00A0) → false', () {
      expect(symbolIsVisible('\u00A0'), isFalse);
    });

    test('zero-width space (U+200B) → false', () {
      expect(symbolIsVisible('\u200B'), isFalse);
    });

    test('BOM / zero-width no-break space (U+FEFF) → false', () {
      expect(symbolIsVisible('\uFEFF'), isFalse);
    });

    test('string of only invisible chars → false', () {
      // NBSP + zero-width space
      expect(symbolIsVisible('\u00A0\u200B'), isFalse);
    });

    test('ASCII letter A → true', () {
      expect(symbolIsVisible('A'), isTrue);
    });

    test('digit 3 → true', () {
      expect(symbolIsVisible('3'), isTrue);
    });

    test('filled square ■ → true', () {
      expect(symbolIsVisible('■'), isTrue);
    });

    test('Greek alpha α → true', () {
      expect(symbolIsVisible('α'), isTrue);
    });
  });

  // ─── symbolIsPdfUnsupported ────────────────────────────────────────────────

  group('symbolIsPdfUnsupported', () {
    test('up arrow ↑ → true', () {
      expect(symbolIsPdfUnsupported('↑'), isTrue);
    });

    test('circled plus ⊕ → true', () {
      expect(symbolIsPdfUnsupported('⊕'), isTrue);
    });

    test('cross mark ✝ → true', () {
      expect(symbolIsPdfUnsupported('✝'), isTrue);
    });

    test('ASCII A → false', () {
      expect(symbolIsPdfUnsupported('A'), isFalse);
    });

    test('filled square ■ → false', () {
      expect(symbolIsPdfUnsupported('■'), isFalse);
    });
  });

  // ─── symbolSimilarityGroup ─────────────────────────────────────────────────

  group('symbolSimilarityGroup', () {
    test('O and 0 are in the same group', () {
      final gO = symbolSimilarityGroup('O');
      final g0 = symbolSimilarityGroup('0');
      expect(gO, isNonNegative);
      expect(gO, equals(g0));
    });

    test('I and 1 are in the same group', () {
      final gI = symbolSimilarityGroup('I');
      final g1 = symbolSimilarityGroup('1');
      expect(gI, isNonNegative);
      expect(gI, equals(g1));
    });

    test('● and ◉ are in the same group', () {
      final gA = symbolSimilarityGroup('●');
      final gB = symbolSimilarityGroup('◉');
      expect(gA, isNonNegative);
      expect(gA, equals(gB));
    });

    test('A is not in any group → -1', () {
      expect(symbolSimilarityGroup('A'), equals(-1));
    });

    test('two similar symbols both return the same non-negative index', () {
      // ★ and ✦ are in the stars group
      final g1 = symbolSimilarityGroup('★');
      final g2 = symbolSimilarityGroup('✦');
      expect(g1, isNonNegative);
      expect(g1, equals(g2));
    });
  });
}
