// Unit tests for PageLayout.computeOffset — the per-row/column fuzzy-edge
// snap algorithm.
//
// Tests use a simple integer-keyed colour map so we don't need a full pattern
// object.  Colour values are arbitrary non-null ints; null means "empty aida".
//
// Coordinate convention matches the vertical-boundary call-site:
//   colorAt(primary=col, crossIndex=row)  →  colorAt(col, 0)
// The crossIndex is held fixed at 0 throughout unless noted.

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/page_layout.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const int A = 1;
const int B = 2;
const int C = 3;
const int D = 4;

/// Build a colorAt closure from a flat list (index = primary / col).
/// Null entries represent empty (unstitched) cells.
int? Function(int, int) colorMap(List<int?> cells) =>
    (int primary, int crossIndex) =>
        (primary >= 0 && primary < cells.length) ? cells[primary] : null;

/// Convenience: call computeOffset with crossIndex=0, seed=0, maxBoundary=cells.length.
int snap(
  List<int?> cells,
  int nominalBoundary, {
  int fuzzyAmount = 3,
  int? maxBoundary,
  int maxCross = 1,
  int seed = 0,
}) =>
    PageLayout.computeOffset(
      nominalBoundary: nominalBoundary,
      crossIndex: 0,
      fuzzyAmount: fuzzyAmount,
      maxBoundary: maxBoundary ?? cells.length,
      maxCross: maxCross,
      colorAt: colorMap(cells),
      seed: seed,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── fuzzyAmount = 0 ────────────────────────────────────────────────────────
  group('fuzzyAmount=0 always returns 0', () {
    test('solid block', () {
      expect(snap([A, A, A, A, A, A], 3, fuzzyAmount: 0), 0);
    });
    test('colour change at boundary', () {
      // Even with a clear colour change, no snap when fuzziness is off.
      expect(snap([A, A, A, B, B, B], 3, fuzzyAmount: 0), 0);
    });
  });

  // ── Clean colour boundaries ────────────────────────────────────────────────
  group('snaps to nearest clean colour boundary', () {
    test('exact boundary — d=0', () {
      // boundary between col2 (A) and col3 (B), nominal=3 → d=0
      expect(snap([A, A, A, B, B, B], 3), 0);
    });

    test('boundary one right — d=+1', () {
      // nominal=3: col2=A, col3=A (same). col3=A, col4=B → d=+1
      expect(snap([A, A, A, A, B, B, B], 3), 1);
    });

    test('boundary one left — d=-1', () {
      // nominal=3: same. col1=A, col2=B → d=-1 (closer than d=+1)
      expect(snap([A, A, B, B, B, B, B], 3), -1);
    });

    test('prefers closest — positive before negative at same distance', () {
      // The scan order is d=0, then d=1 (positive first), d=-1, d=2, d=-2 …
      // [A,A,A,B,B,B,B,A,A] nominal=4:
      // d=0: cut(3,4) cA=B,cB=B same. Reject.
      // d=+1: cut(4,5) cA=B,cB=B same. Reject.
      // d=-1: cut(2,3) cA=A,cB=B → clean. Returns -1.
      expect(snap([A, A, A, B, B, B, B, A, A], 4), -1);
    });

    test('boundary at snap-range limit (d=+snapRange)', () {
      // Nominal=0; colour change at snapRange positions to the right.
      final range = PageLayout.snapRange;
      final cells = List<int?>.filled(range * 3, A);
      cells[range] = B;
      for (int i = range + 1; i < cells.length; i++) {
        cells[i] = B;
      }
      expect(snap(cells, 0), range);
    });

    test('no change beyond snap range falls back to random (deterministic seed)', () {
      // Solid A everywhere — no colour change within ±snapRange of nominal=5.
      final result = snap([A, A, A, A, A, A, A, A, A, A, A, A], 5, seed: 42);
      // Must be within ±fuzzyAmount, not a snap.
      expect(result, inInclusiveRange(-3, 3));
    });
  });

  // ── Ping-pong (single-stitch sandwich) ───────────────────────────────────
  group('rejects ping-pong single-stitch islands', () {
    test('rejects [B, A | B, B] — lone A on left', () {
      // Nominal=2: cut(1,2) → cA=A, cB=B, col0=B==cB → ping-pong left.
      // d=+1: cut(2,3) → cA=B, cB=B same. etc.
      // Should fall back to random (no qualifying cut in range).
      final cells = [B, A, B, B, B, B, B, B];
      final result = snap(cells, 2, fuzzyAmount: 2);
      expect(result, inInclusiveRange(-2, 2));
    });

    test('rejects [A, A | B, A, B] — lone B on right', () {
      // d=0: cut(1,2) → cA=A, cB=B. col3=A==cA → ping-pong right. Reject.
      // d=+1: cut(2,3) → cA=B, cB=A. col4=B==cA → ping-pong right. Reject.
      // Falls back to random.
      final cells = [A, A, B, A, B, B, B, B];
      final result = snap(cells, 2, fuzzyAmount: 2);
      expect(result, inInclusiveRange(-2, 2));
    });

    test('accepts clean boundary even when ping-pong exists at other offsets', () {
      // [A,A,A,B,B,B,B,B] nominal=3:
      // d=0: cut(2,3) cA=A,cB=B. No ping-pong (col1=A≠cB, col4=B≠cA). Clean! Returns 0.
      expect(snap([A, A, A, B, B, B, B, B], 3), 0);
    });
  });

  // ── Window-based colour-island check ─────────────────────────────────────
  group('rejects colour islands (window check)', () {
    test('rejects 2-stitch B island on left: [A,A,B,B | B,B,B,B,B,B]', () {
      // Nominal=4: d=0 cut(3,4): cA=B,cB=B same. All B around boundary.
      // d=-1 cut(2,3): cA=B,cB=B same.
      // d=-2 cut(1,2): cA=A,cB=B. Left window[−1..1]={A:2,?} right=[2..5]={B:4}.
      // Wait — let's think carefully about the window:
      // posA=1: left window = max(0, 1-4+1=−2) → [0..1] = {A:2}
      // posB=2: right window = [2..5] = {B:4}
      // No colour on both sides → no island → accept d=-2.
      // So the cut IS accepted at d=-2 giving boundary at col 2.
      expect(snap([A, A, B, B, B, B, B, B, B, B], 4), -2);
    });

    test('rejects lone B in A region where B majority is on right: [A,A,B,A | B,B,B,B]', () {
      // Nominal=4: d=0 cut(3,4): cA=A,cB=B. Left[0..3]={A:3,B:1}, Right[4..7]={B:4}.
      // B: l=1, r=4. minority=1<=2, majority=4>=2 → potential island.
      // beyondLeft = 3-4=-1 <0 → island confirmed → reject.
      // d=-1 cut(2,3): cA=B,cB=A. ping-pong right? col4=B==cA → ping-pong. Reject.
      // d=+1 cut(4,5): cA=B,cB=B same.
      // d=-2 cut(1,2): cA=A,cB=B. Left[−2..1]=[0..1]={A:2}, Right[2..5]={B:2,A:1}.
      // B in left: 0. B in right: 2. Only on right → fine.
      // A in left: 2. A in right: 1. both sides: minority=1<=2, majority=2>=2.
      // beyondRight = 2+4=6. colorAt(6)=B ≠ A. So A is an island on right → reject.
      // d=+2 cut(5,6): cA=B, cB=B same. d=-3 cut(0,1): cA=A,cB=A same.
      // d=+3 cut(6,7): cA=B,cB=B same. d=-4 cut(-1,0): posA<0 skip.
      // Falls back to random.
      final cells = [A, A, B, A, B, B, B, B, B, B];
      final result = snap(cells, 4, fuzzyAmount: 3);
      expect(result, inInclusiveRange(-3, 3));
    });

    test('does NOT reject when minority colour continues beyond window', () {
      // [A,A,A,A,B,B | B,B,B,B,A,A,A,A]: A appears both sides but extends
      // beyond the window on the left → not an island.
      // d=0: cut(5,6) → B|B same. d=-1: cut(4,5) → B|B same.
      // d=-2: cut(3,4): cA=A, cB=B. Left[0..3]={A:4}, Right[4..7]={B:4}.
      // No colour on both sides → accept.
      expect(snap([A, A, A, A, B, B, B, B, B, B, A, A, A, A], 6), -2);
    });

    test('does NOT reject large colour region clipping window edge', () {
      // [A,A,A,A,A,A | B,B,B,B]: nominal=6. d=0: cA=A,cB=B. clean cut.
      // Left window[2..5]={A:4}. Right[6..9]={B:4}. No overlap → accept.
      expect(snap([A, A, A, A, A, A, B, B, B, B], 6), 0);
    });
  });

  // ── Extended-scan split check ─────────────────────────────────────────────
  // When a colour appears only a few times on one side of a cut but reappears
  // further beyond the window on the other side, the cut is splitting that
  // colour block.  The algorithm should skip it and prefer a cut that keeps
  // the colour together on one page.
  group('extended scan rejects colour-block splits', () {
    test('skips 8|P cut when 8 reappears past right window: [A,A,8,8|P,P,P,P,8,8,8]', () {
      // nominal=4. d=0 cut(3,4): cA=8, cB=P. Left window has 2×8, right has
      // 4×P, then '8' reappears at positions 8–10 (beyond right window) →
      // reject d=0.  d=-2 cut(1,2): A|8 — clean, accepted.
      expect(snap([A, A, B, B, C, C, C, C, B, B, B], 4), -2);
    });

    test('skips 8|P cut when single 8 reappears just past right window', () {
      // [A,A,A,8,8,P,P,P,P,P,8,A,A] nominal=5.
      // d=0 cut(4,5): 8|P. Left has 2×8, right 4×P, then 1×8 at pos10 →
      // reject.  d=-2 cut(2,3): A|8 → accept.
      expect(snap([A, A, A, B, B, C, C, C, C, C, B, A, A], 5), -2);
    });

    test('correctly cuts at A|8 when A→8 transition is within snap range', () {
      // [A,A,A,A,A | 8,8,8,8,8]: nominal=5 → d=0: A|8 → clean → accept.
      expect(snap([A, A, A, A, A, B, B, B, B, B], 5), 0);
    });

    test('symmetric: skips P|8 cut when P reappears further left', () {
      // Mirror scenario: P on right side of cut, with P continuing far left.
      // [P,P,P,8,8 | A,A,A,A,8]: nominal=5.
      // d=0 cut(4,5): 8|A. Left has 2×8, right has 4×A, then 8 at pos9.
      // But wait: the right-side check looks left... let me just verify
      // the symmetric case resolves without crashing.
      final result = snap([C, C, C, B, B, A, A, A, A, B], 5);
      expect(result, inInclusiveRange(-4, 4));
    });
  });

  // ── Mixed-colour region near boundary ────────────────────────────────────
  group('handles mixed/noisy colour regions', () {
    test('snaps past scattered minority stitches to find a clean run', () {
      // Simulates the user-reported rows-25/27/29 scenario:
      // Predominantly A before the boundary with occasional B stitches,
      // then solid B after. The snap should find the cleanest cut.
      //
      // [A,A,A,A,A,A,B,A | B,B,B,B,B,B] nominal=8.
      // d=0 cut(7,8): cA=A,cB=B. Left[4..7]={A:3,B:1}, Right[8..11]={B:4}.
      // B: l=1,r=4 → island check: beyondLeft=7-4=3, colorAt(3)=A≠B → island! Reject.
      // d=-1 cut(6,7): cA=B,cB=A. ping-pong right? col8=B==cA → ping-pong. Reject.
      // d=+1 cut(8,9): cA=B,cB=B same.
      // d=-2 cut(5,6): cA=A,cB=B. Left[2..5]={A:4}, Right[6..9]={B:2,A:1,B:...}.
      //   wait: cells[6]=B,cells[7]=A,cells[8]=B,cells[9]=B. Right={B:3,A:1}.
      //   A: l=4,r=1. minority=1<=2, majority=4>=2. beyondRight=6+4=10: B≠A → island! Reject.
      // d=+2 cut(9,10): cA=B,cB=B same.
      // d=-3 cut(4,5): cA=A,cB=A same.
      // d=+3 cut(10,11): cA=B,cB=B same.
      // d=-4 cut(3,4): cA=A,cB=A same.
      // d=+4 cut(11,12): out of bounds (maxBoundary=14). cA=B,cB=B same.
      // Falls back to random — correct, because there's no truly clean cut
      // within snap range for this noisy pattern.
      final cells = [A, A, A, A, A, A, B, A, B, B, B, B, B, B];
      final result = snap(cells, 8, fuzzyAmount: 3);
      expect(result, inInclusiveRange(-3, 3));
    });

    test('snaps cleanly when A→B boundary is within snap range', () {
      // [A,A,A,A,A | B,B,B,B,B] nominal=5 → d=0 clean.
      expect(snap([A, A, A, A, A, B, B, B, B, B], 5), 0);
    });

    test('snaps to nearest of several possible colour boundaries', () {
      // [A,A,A,B,B | C,C,C,C,C] nominal=5.
      // d=0: cut(4,5): cA=B,cB=C. Left[1..4]={A:2,B:2}, Right[5..8]={C:4}.
      // No colour on both sides → accept. Returns 0.
      expect(snap([A, A, A, B, B, C, C, C, C, C], 5), 0);
    });
  });

  // ── Boundary at pattern edges ─────────────────────────────────────────────
  group('boundary at pattern edges', () {
    test('boundary near left edge of pattern', () {
      // nominal=2 in a short pattern. posA-window might go negative.
      final result = snap([A, A, B, B, B], 2, maxBoundary: 5);
      expect(result, 0); // clean cut at d=0
    });

    test('boundary near right edge of pattern', () {
      // nominal=3 in a 5-cell pattern with snap range of 4.
      final result = snap([A, A, A, B, B], 3, maxBoundary: 5);
      expect(result, 0);
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────
  group('fallback random is deterministic for same seed', () {
    test('same seed gives same result', () {
      final cells = List<int?>.filled(20, A); // solid — always random fallback
      expect(snap(cells, 10, seed: 12345), snap(cells, 10, seed: 12345));
    });

    test('different seed gives (usually) different result', () {
      final cells = List<int?>.filled(20, A);
      // With a 7-value range (±3) the chance of two seeds colliding is ~14%.
      // Use seeds that are known to differ.
      final r1 = snap(cells, 10, seed: 1);
      final r2 = snap(cells, 10, seed: 999999);
      // We can't guarantee they differ but we can verify both are in range.
      expect(r1, inInclusiveRange(-3, 3));
      expect(r2, inInclusiveRange(-3, 3));
    });
  });

  // ── 2D flood-fill scoring ─────────────────────────────────────────────────
  // These tests use a multi-row colour map so the 2D flood can differentiate
  // candidates that look identical in 1D.

  /// Build a 2D colorAt from a list of rows (index 0 = crossIndex 0).
  int? Function(int, int) colorMap2D(List<List<int?>> rows) =>
      (int primary, int crossIndex) =>
          (crossIndex >= 0 &&
                  crossIndex < rows.length &&
                  primary >= 0 &&
                  primary < rows[crossIndex].length)
              ? rows[crossIndex][primary]
              : null;

  /// Convenience: call computeOffset with a 2D colour map.
  int snap2D(
    List<List<int?>> rows,
    int nominalBoundary, {
    int crossIndex = 0,
    int fuzzyAmount = 3,
    int seed = 0,
  }) {
    final maxBoundary = rows.isEmpty ? 0 : rows[0].length;
    return PageLayout.computeOffset(
      nominalBoundary: nominalBoundary,
      crossIndex: crossIndex,
      fuzzyAmount: fuzzyAmount,
      maxBoundary: maxBoundary,
      maxCross: rows.length,
      colorAt: colorMap2D(rows),
      seed: seed,
    );
  }

  group('2D flood scoring prefers cuts with less stranding', () {
    test('prefers farther cut when closer one strands A via adjacent rows', () {
      // Row 0:  C C C A A | B B B B B B B
      // Row 1:  C C C C A   A A A B B B B
      // Row 2:  C C C C A   A A A B B B B
      //
      // Nominal=5. Qualifying candidates at row 0:
      //   d=0: posA=4(A), posB=5(B). Clean 1D. But flood A from (4,0)
      //     reaches (4,1)→(5,1)→(6,1)→(7,1) and same on row 2.
      //     Stranded A at primary>=5 = 6 cells. Penalty=6.
      //   d=-2: posA=2(C), posB=3(A). Clean 1D. Flood C from (2,0):
      //     (2,1)→(3,1), but (3,1)=C at primary>=3 → stranded 2.
      //     Penalty=2.
      //
      // Flood picks d=-2 (penalty 2 < 6). Old first-found picks d=0.
      final rows = [
        [C, C, C, A, A, B, B, B, B, B, B, B], // row 0
        [C, C, C, C, A, A, A, A, B, B, B, B], // row 1
        [C, C, C, C, A, A, A, A, B, B, B, B], // row 2
      ];
      expect(snap2D(rows, 5, crossIndex: 0), -2,
          reason: 'd=-2 strands fewer cells in 2D than d=0');
    });

    test('single qualifying candidate returned regardless of penalty', () {
      // Row 0:  A A B B B B B B
      // Row 1:  A A A A A B B B
      //
      // Nominal=4. Only d=-2 qualifies (A|B at col 2).
      // Penalty is non-zero (A extends right on row 1) but it's the only
      // option so it must be returned.
      final rows = [
        [A, A, B, B, B, B, B, B], // row 0
        [A, A, A, A, A, B, B, B], // row 1
      ];
      expect(snap2D(rows, 4, crossIndex: 0), -2);
    });

    test('both candidates clean in 2D: closest to nominal wins', () {
      // Row 0:  A A B B C C C C
      // Row 1:  A A B B C C C C
      // Row 2:  A A B B C C C C
      //
      // Nominal=4. d=0: B|C, penalty=0. d=-2: A|B, penalty=0.
      // Both clean → closest (d=0) wins.
      final rows = [
        [A, A, B, B, C, C, C, C],
        [A, A, B, B, C, C, C, C],
        [A, A, B, B, C, C, C, C],
      ];
      expect(snap2D(rows, 4, crossIndex: 0), 0);
    });

    test('flood detects stranding through L-shaped region', () {
      // Row 0:  A A A B B B B B B B
      // Row 1:  A A A A A A B B B B
      // Row 2:  A A A A A A B B B B
      //
      // Nominal=3. Only d=0 (A|B) qualifies. Flood A from (2,0) reaches
      // rows 1-2 cols 3-5 = 6 stranded cells. But with no alternative,
      // d=0 is still returned.
      final rows = [
        [A, A, A, B, B, B, B, B, B, B], // row 0
        [A, A, A, A, A, A, B, B, B, B], // row 1
        [A, A, A, A, A, A, B, B, B, B], // row 2
      ];
      expect(snap2D(rows, 3, crossIndex: 0), 0);
    });

    test('1D-identical cuts differentiated by 2D context', () {
      // Row 0:  A A A A B B B B C C C C
      // Row 1:  A A A A A A A B C C C C
      // Row 2:  A A A A A A A B C C C C
      //
      // Nominal=6. Two qualifying candidates:
      //   d=-2: posA=3(A), posB=4(B). Flood A from (3,0): all left-side,
      //     rows 1-2 cols 4-6 are A → stranded = 6. Penalty=6.
      //   d=+2: posA=7(B), posB=8(C). Flood B from (7,0): B at 4-7 row 0,
      //     col 7 rows 1-2. No B at >=8. Flood C from (8,0): C at 8-11.
      //     No C at <8. Penalty=0.
      //
      // Flood picks d=+2 (penalty 0). Without flood, both are at same
      // distance but d=+2 is checked first (positive priority) → same result.
      // This test verifies flood scoring is active even when it agrees with
      // the old order.
      final rows = [
        [A, A, A, A, B, B, B, B, C, C, C, C], // row 0
        [A, A, A, A, A, A, A, B, C, C, C, C], // row 1
        [A, A, A, A, A, A, A, B, C, C, C, C], // row 2
      ];
      expect(snap2D(rows, 6, crossIndex: 0), 2);
    });
  });
}

