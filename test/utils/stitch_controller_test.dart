import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/utils/stitch_controller.dart';

import '../widgets/test_helpers.dart';

// ── Minimal fake notifier ─────────────────────────────────────────────────

class _FakeNotifier implements EditorNotifier {
  final List<String> calls = [];

  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName.toString().replaceFirst('Symbol("', '').replaceFirst('")', ''));
  }

  @override
  void undoProgress() => calls.add('undoProgress');
  @override
  void redoProgress() => calls.add('redoProgress');
  @override
  void setDrawingMode(DrawingMode m) => calls.add('setDrawingMode:${m.name}');
  @override
  void navigatePageRight() => calls.add('navigatePageRight');
  @override
  void navigatePageLeft() => calls.add('navigatePageLeft');
  @override
  void navigatePageDown() => calls.add('navigatePageDown');
  @override
  void navigatePageUp() => calls.add('navigatePageUp');
  @override
  void cancelSelection() => calls.add('cancelSelection');
  @override
  void toggleStitchMode() => calls.add('toggleStitchMode');
}

// ── Helper ────────────────────────────────────────────────────────────────

KeyDownEvent _key(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

// StitchController.handle reads HardwareKeyboard.instance → binding needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StitchController', () {
    late _FakeNotifier notifier;
    late EditorState stitchState;
    late StitchController ctrl;

    setUp(() {
      notifier = _FakeNotifier();
      stitchState = fakeStitchState();
      ctrl = StitchController(
        notifier: notifier,
        getState: () => stitchState,
      );
    });

    test('ignores events when stitchMode is false', () {
      final editState = fakeEditState();
      ctrl = StitchController(notifier: notifier, getState: () => editState);
      final handled = ctrl.handle(_key(LogicalKeyboardKey.keyS));
      expect(handled, isFalse);
      expect(notifier.calls, isEmpty);
    });

    test('ignores KeyUpEvent', () {
      final event = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyS,
        logicalKey: LogicalKeyboardKey.keyS,
        timeStamp: Duration.zero,
      );
      expect(ctrl.handle(event), isFalse);
    });

    test('S key → setDrawingMode select', () {
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyS)), isTrue);
      expect(notifier.calls, ['setDrawingMode:select']);
    });

    test('Space → setDrawingMode pan', () {
      ctrl.handle(_key(LogicalKeyboardKey.space));
      expect(notifier.calls, ['setDrawingMode:pan']);
    });

    test('Escape with no selectionRect → toggleStitchMode', () {
      // fakeStitchState has selectionRect = null by default
      ctrl.handle(_key(LogicalKeyboardKey.escape));
      expect(notifier.calls, ['toggleStitchMode']);
    });

    test('Escape with selectionRect → cancelSelection', () {
      stitchState = fakeStitchState(hasSelection: true);
      ctrl = StitchController(notifier: notifier, getState: () => stitchState);
      ctrl.handle(_key(LogicalKeyboardKey.escape));
      expect(notifier.calls, ['cancelSelection']);
    });

    test('arrow keys ignored when pageConfig disabled', () {
      // fakeStitchState has pageConfig.enabled = false
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
      ]) {
        expect(ctrl.handle(_key(key)), isFalse,
            reason: 'key $key should be ignored when pages disabled');
      }
      expect(notifier.calls, isEmpty);
    });

    test('arrow keys fire navigation when pageConfig enabled and pageLayout set',
        () {
      stitchState = fakeStitchState(pagesEnabled: true);
      ctrl = StitchController(notifier: notifier, getState: () => stitchState);

      ctrl.handle(_key(LogicalKeyboardKey.arrowRight));
      ctrl.handle(_key(LogicalKeyboardKey.arrowLeft));
      ctrl.handle(_key(LogicalKeyboardKey.arrowDown));
      ctrl.handle(_key(LogicalKeyboardKey.arrowUp));

      expect(notifier.calls, [
        'navigatePageRight',
        'navigatePageLeft',
        'navigatePageDown',
        'navigatePageUp',
      ]);
    });

    test('unrecognised key returns false', () {
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyQ)), isFalse);
      expect(notifier.calls, isEmpty);
    });

    test('onSave is null — no crash on Cmd+S path', () {
      // Without modifier state injected the Cmd path is not reached; just
      // verifying constructor accepts null and single-key path doesn't throw.
      expect(() => ctrl.handle(_key(LogicalKeyboardKey.keyS)), returnsNormally);
    });
  });
}
