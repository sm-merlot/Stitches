// Run with:
//   flutter test test/grid_detector_test.dart -v
//
// Place test images in test/fixtures/ before running:
//   grid_test_lighthouse.png  — Evening Lighthouse (75×75 stitches)
//   grid_test_anchor.png      — Stitch Life / Anchor (90×95 stitches)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/services/grid_detector.dart';

// ── Expected values — fill these in once you have confirmed coordinates ───────
//
// Format: (gridLeft, gridTop, gridRight, gridBottom, approxCellPx)
// Set to null to skip assertions for that image (still prints detected values).

const _lighthouseExpected = (
  gridLeft: 0.0,   // TODO: replace with actual
  gridTop: 0.0,    // TODO: replace with actual
  gridRight: 0.0,  // TODO: replace with actual
  gridBottom: 0.0, // TODO: replace with actual
  cellPx: 0.0,     // TODO: replace with actual (approximate pixels per cell)
);
const _lighthouseExpectedKnown = false; // set true once coords are filled in

const _anchorExpected = (
  gridLeft: 0.0,
  gridTop: 0.0,
  gridRight: 0.0,
  gridBottom: 0.0,
  cellPx: 0.0,
);
const _anchorExpectedKnown = false;

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _gridTest(
    label: 'Evening Lighthouse (75×75)',
    fixtureName: 'grid_test_lighthouse.png',
    expected: _lighthouseExpected,
    expectedKnown: _lighthouseExpectedKnown,
    knownCols: 75,
    knownRows: 75,
  );

  _gridTest(
    label: 'Stitch Life / Anchor (90×95)',
    fixtureName: 'grid_test_anchor.png',
    expected: _anchorExpected,
    expectedKnown: _anchorExpectedKnown,
    knownCols: 90,
    knownRows: 95,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

void _gridTest({
  required String label,
  required String fixtureName,
  required ({
    double gridLeft,
    double gridTop,
    double gridRight,
    double gridBottom,
    double cellPx
  }) expected,
  required bool expectedKnown,
  required int knownCols,
  required int knownRows,
}) {
  test(label, () async {
    final file = File('test/fixtures/$fixtureName');
    if (!file.existsSync()) {
      printOnFailure('  ⚠  Fixture not found — skipping: ${file.path}');
      markTestSkipped('fixture missing');
      return;
    }

    final bytes = file.readAsBytesSync();
    final result = await GridDetector.detectPage(bytes);

    _printResult(label, result, knownCols, knownRows);

    expect(result, isNotNull, reason: 'GridDetector returned null — no grid found');
    final r = result!;

    // Derived values.
    final detectedCols = r.cellW > 0 ? (r.gridWidth / r.cellW).round() : 0;
    final detectedRows = r.cellH > 0 ? (r.gridHeight / r.cellH).round() : 0;

    // Always assert col/row counts are within ±3 of the known pattern dimensions.
    expect(detectedCols, closeTo(knownCols, 3),
        reason: 'Column count off: got $detectedCols, expected ~$knownCols');
    expect(detectedRows, closeTo(knownRows, 3),
        reason: 'Row count off: got $detectedRows, expected ~$knownRows');

    // Confidence sanity check.
    expect(r.confidence, greaterThan(0.15),
        reason: 'Confidence too low: ${r.confidence.toStringAsFixed(2)}');

    if (expectedKnown) {
      const tol = 20.0; // allow ±20 px tolerance on grid bounds
      expect(r.gridLeft,   closeTo(expected.gridLeft,   tol), reason: 'gridLeft');
      expect(r.gridTop,    closeTo(expected.gridTop,    tol), reason: 'gridTop');
      expect(r.gridRight,  closeTo(expected.gridRight,  tol), reason: 'gridRight');
      expect(r.gridBottom, closeTo(expected.gridBottom, tol), reason: 'gridBottom');
      expect(r.cellW,      closeTo(expected.cellPx,     2.0), reason: 'cellW');
      expect(r.cellH,      closeTo(expected.cellPx,     2.0), reason: 'cellH');
    }
  });
}

void _printResult(
  String label,
  GridDetectionResult? result,
  int knownCols,
  int knownRows,
) {
  // ignore: avoid_print
  print('\n── $label ─────────────────────────────');
  if (result == null) {
    // ignore: avoid_print
    print('  RESULT: null (detection failed)');
    return;
  }

  final detectedCols = result.cellW > 0
      ? (result.gridWidth / result.cellW).round()
      : 0;
  final detectedRows = result.cellH > 0
      ? (result.gridHeight / result.cellH).round()
      : 0;

  // ignore: avoid_print
  print('  gridLeft:      ${result.gridLeft.round()}');
  // ignore: avoid_print
  print('  gridTop:       ${result.gridTop.round()}');
  // ignore: avoid_print
  print('  gridRight:     ${result.gridRight.round()}');
  // ignore: avoid_print
  print('  gridBottom:    ${result.gridBottom.round()}');
  // ignore: avoid_print
  print('  gridWidth:     ${result.gridWidth.round()} px');
  // ignore: avoid_print
  print('  gridHeight:    ${result.gridHeight.round()} px');
  // ignore: avoid_print
  print('  cellW:         ${result.cellW.toStringAsFixed(2)} px');
  // ignore: avoid_print
  print('  cellH:         ${result.cellH.toStringAsFixed(2)} px');
  // ignore: avoid_print
  print('  phaseX:        ${result.phaseX.toStringAsFixed(2)} px');
  // ignore: avoid_print
  print('  phaseY:        ${result.phaseY.toStringAsFixed(2)} px');
  // ignore: avoid_print
  print('  detectedCols:  $detectedCols  (expected ~$knownCols)');
  // ignore: avoid_print
  print('  detectedRows:  $detectedRows  (expected ~$knownRows)');
  // ignore: avoid_print
  print('  confidence:    ${result.confidence.toStringAsFixed(3)}');
}
