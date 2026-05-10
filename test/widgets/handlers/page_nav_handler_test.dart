import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/widgets/handlers/page_nav_handler.dart';

void main() {
  group('PageNavHandler', () {
    const h = PageNavHandler();
    const size = Size(400, 600);

    test('returns false when stitchMode is false', () {
      expect(
        h.isNavZone(const Offset(10, 10), size,
            stitchMode: false, pageEnabled: true, hasPageLayout: true),
        isFalse,
      );
    });

    test('returns false when pageEnabled is false', () {
      expect(
        h.isNavZone(const Offset(10, 10), size,
            stitchMode: true, pageEnabled: false, hasPageLayout: true),
        isFalse,
      );
    });

    test('returns false when hasPageLayout is false', () {
      expect(
        h.isNavZone(const Offset(10, 10), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: false),
        isFalse,
      );
    });

    test('left edge hit when hasLeft is true', () {
      expect(
        h.isNavZone(const Offset(10, 300), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasLeft: true),
        isTrue,
      );
    });

    test('left edge not a nav zone when hasLeft is false', () {
      expect(
        h.isNavZone(const Offset(10, 300), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasLeft: false),
        isFalse,
      );
    });

    test('right edge hit when hasRight is true', () {
      expect(
        h.isNavZone(Offset(size.width - 10, 300), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasRight: true),
        isTrue,
      );
    });

    test('right edge not a nav zone when hasRight is false', () {
      expect(
        h.isNavZone(Offset(size.width - 10, 300), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasRight: false),
        isFalse,
      );
    });

    test('top centre hit when hasUp is true', () {
      // Centre of the up-arrow button strip (width/2, within button height)
      expect(
        h.isNavZone(Offset(size.width / 2, 10), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasUp: true),
        isTrue,
      );
    });

    test('top centre not a nav zone when hasUp is false', () {
      expect(
        h.isNavZone(Offset(size.width / 2, 10), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasUp: false),
        isFalse,
      );
    });

    test('top edge outside up-button strip is not a nav zone', () {
      // Far left of canvas top — no left button on this row, no up button
      expect(
        h.isNavZone(const Offset(10, 10), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true,
            hasLeft: false, hasUp: true),
        isFalse,
      );
    });

    test('bottom guard hit', () {
      expect(
        h.isNavZone(Offset(200, size.height - 10), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true),
        isTrue,
      );
    });

    test('centre of canvas is not a nav zone', () {
      expect(
        h.isNavZone(Offset(size.width / 2, size.height / 2), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true),
        isFalse,
      );
    });
  });
}
