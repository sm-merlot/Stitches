import 'package:flutter/widgets.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/widgets/paste_handler.dart';
import 'test_helpers.dart';

void main() {
  group('PasteHandler', () {
    late List<(int, int)> commitCalls;
    late int cancelCalls;
    late int rebuildCount;
    late PasteHandler h;

    setUp(() {
      commitCalls = [];
      cancelCalls = 0;
      rebuildCount = 0;
      h = PasteHandler(
        onCommitPaste: (dx, dy) => commitCalls.add((dx, dy)),
        onCancelSelection: () => cancelCalls++,
        scheduleRebuild: () => rebuildCount++,
      );
    });

    test('initial state', () {
      expect(h.pasteOrigin, isNull);
      expect(h.ctrlHeld, isFalse);
      expect(h.shiftHeld, isFalse);
    });

    test('updateModifiers triggers rebuild on change', () {
      h.updateModifiers(ctrl: true, shift: false);
      expect(h.ctrlHeld, isTrue);
      expect(rebuildCount, 1);
    });

    test('updateModifiers does not rebuild when unchanged', () {
      h.updateModifiers(ctrl: false, shift: false);
      expect(rebuildCount, 0);
    });

    test('centeredOffset with empty clipboard returns cursor coords', () {
      expect(h.centeredOffset(const Offset(5, 5), []), (5, 5));
    });

    test('updateOrigin deduplicates same cell', () {
      h.updateOrigin(const Offset(25, 45), vp);
      final count = rebuildCount;
      h.updateOrigin(const Offset(25, 45), vp);
      expect(rebuildCount, count);
    });

    test('updateOrigin triggers rebuild on different cell', () {
      h.updateOrigin(const Offset(25, 45), vp);
      final count = rebuildCount;
      h.updateOrigin(const Offset(65, 45), vp);
      expect(rebuildCount, count + 1);
    });

    test('clearOrigin resets origin and rebuilds', () {
      h.updateOrigin(const Offset(25, 45), vp);
      rebuildCount = 0;
      h.clearOrigin();
      expect(h.pasteOrigin, isNull);
      expect(rebuildCount, 1);
    });

    test('commit with no origin returns false', () {
      expect(h.commit(fakePattern(), []), isFalse);
      expect(commitCalls, isEmpty);
    });

    test('commit calls onCommitPaste', () {
      h.setOrigin(const Offset(100, 100), vp);
      h.commit(fakePattern(), []);
      expect(commitCalls, isNotEmpty);
    });

    test('commit without ctrl calls onCancelSelection', () {
      h.setOrigin(const Offset(100, 100), vp);
      h.commit(fakePattern(), []);
      expect(cancelCalls, 1);
    });

    test('commit with ctrl does not call onCancelSelection', () {
      h.updateModifiers(ctrl: true, shift: false);
      h.setOrigin(const Offset(100, 100), vp);
      h.commit(fakePattern(), []);
      expect(cancelCalls, 0);
    });
  });
}
