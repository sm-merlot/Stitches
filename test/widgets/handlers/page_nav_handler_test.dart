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

    test('left edge hit', () {
      expect(
        h.isNavZone(const Offset(10, 300), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true),
        isTrue,
      );
    });

    test('right edge hit', () {
      expect(
        h.isNavZone(Offset(size.width - 10, 300), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true),
        isTrue,
      );
    });

    test('top edge hit', () {
      expect(
        h.isNavZone(const Offset(200, 10), size,
            stitchMode: true, pageEnabled: true, hasPageLayout: true),
        isTrue,
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
