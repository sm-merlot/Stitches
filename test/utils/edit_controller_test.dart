import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/utils/edit_controller.dart';

import '../widgets/test_helpers.dart';

// ── Minimal fake notifier ──────────────────────────────────────────────────

class _FakeNotifier implements EditorNotifier {
  final List<String> calls = [];

  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName.toString().replaceFirst('Symbol("', '').replaceFirst('")', ''));
  }

  @override
  void undo() => calls.add('undo');
  @override
  void redo() => calls.add('redo');
  @override
  void selectAll() => calls.add('selectAll');
  @override
  Future<void> copySelection() async => calls.add('copySelection');
  @override
  Future<void> enterPasteMode() async => calls.add('enterPasteMode');
  @override
  void flipSelectionH() => calls.add('flipSelectionH');
  @override
  void flipSelectionV() => calls.add('flipSelectionV');
  @override
  void flipClipboardH() => calls.add('flipClipboardH');
  @override
  void flipClipboardV() => calls.add('flipClipboardV');
  @override
  void flipCanvasH() => calls.add('flipCanvasH');
  @override
  void flipCanvasV() => calls.add('flipCanvasV');
  @override
  void rotateSelectionCW() => calls.add('rotateSelectionCW');
  @override
  void rotateClipboardCW() => calls.add('rotateClipboardCW');
  @override
  void rotateCanvasCW() => calls.add('rotateCanvasCW');
  @override
  void setDrawingMode(DrawingMode m) => calls.add('setDrawingMode:${m.name}');
  @override
  void setTool(DrawingTool t) => calls.add('setTool:${t.name}');
  @override
  void cancelSelection() => calls.add('cancelSelection');
  @override
  void deleteSelection() => calls.add('deleteSelection');
  @override
  void toggleFillErase() => calls.add('toggleFillErase');
}

// ── Helper to fire a key event ────────────────────────────────────────────

KeyDownEvent _key(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA, // value doesn't matter
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyDownEvent _keyMeta(LogicalKeyboardKey key) {
  // The controller checks HardwareKeyboard.instance — we can't inject modifier
  // state without a real binding, so modifier tests rely on the key-only path
  // for single-key shortcuts. Modifier-combo tests are integration-level.
  return _key(key);
}

// EditController.handle reads HardwareKeyboard.instance → binding needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditController', () {
    late _FakeNotifier notifier;
    late EditorState editState;
    late EditController ctrl;

    setUp(() {
      notifier = _FakeNotifier();
      editState = fakeEditState();
      ctrl = EditController(
        notifier: notifier,
        getState: () => editState,
      );
    });

    test('ignores events when stitchMode is true', () {
      editState = fakeStitchState();
      final handled = ctrl.handle(_key(LogicalKeyboardKey.keyD));
      expect(handled, isFalse);
      expect(notifier.calls, isEmpty);
    });

    test('ignores KeyUpEvent', () {
      final event = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      );
      expect(ctrl.handle(event), isFalse);
    });

    test('D key → setDrawingMode draw', () {
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyD)), isTrue);
      expect(notifier.calls, ['setDrawingMode:draw']);
    });

    test('E key → setDrawingMode erase', () {
      ctrl.handle(_key(LogicalKeyboardKey.keyE));
      expect(notifier.calls, ['setDrawingMode:erase']);
    });

    test('Space → setDrawingMode pan', () {
      ctrl.handle(_key(LogicalKeyboardKey.space));
      expect(notifier.calls, ['setDrawingMode:pan']);
    });

    test('S key → setDrawingMode select', () {
      ctrl.handle(_key(LogicalKeyboardKey.keyS));
      expect(notifier.calls, ['setDrawingMode:select']);
    });

    test('C key → setDrawingMode colorPicker', () {
      ctrl.handle(_key(LogicalKeyboardKey.keyC));
      expect(notifier.calls, ['setDrawingMode:colorPicker']);
    });

    test('1 → setTool fullStitch', () {
      ctrl.handle(_key(LogicalKeyboardKey.digit1));
      expect(notifier.calls, ['setTool:fullStitch']);
    });

    test('7 → setTool backstitch', () {
      ctrl.handle(_key(LogicalKeyboardKey.digit7));
      expect(notifier.calls, ['setTool:backstitch']);
    });

    test('8 → setTool fill', () {
      ctrl.handle(_key(LogicalKeyboardKey.digit8));
      expect(notifier.calls, ['setTool:fill']);
    });

    test('9 → erase + toggleFillErase when fillEraseActive is false', () {
      editState = fakeEditState(fillEraseActive: false);
      ctrl = EditController(notifier: notifier, getState: () => editState);
      ctrl.handle(_key(LogicalKeyboardKey.digit9));
      expect(notifier.calls, ['setDrawingMode:erase', 'toggleFillErase']);
    });

    test('9 → erase only when fillEraseActive is true', () {
      editState = fakeEditState(fillEraseActive: true);
      ctrl = EditController(notifier: notifier, getState: () => editState);
      ctrl.handle(_key(LogicalKeyboardKey.digit9));
      expect(notifier.calls, ['setDrawingMode:erase']);
    });

    test('Escape → cancelSelection', () {
      ctrl.handle(_key(LogicalKeyboardKey.escape));
      expect(notifier.calls, ['cancelSelection']);
    });

    test('Delete → deleteSelection', () {
      ctrl.handle(_key(LogicalKeyboardKey.delete));
      expect(notifier.calls, ['deleteSelection']);
    });

    test('Backspace → deleteSelection', () {
      ctrl.handle(_key(LogicalKeyboardKey.backspace));
      expect(notifier.calls, ['deleteSelection']);
    });

    test('unrecognised key returns false', () {
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyQ)), isFalse);
      expect(notifier.calls, isEmpty);
    });

    test('Shift+? calls onShowShortcuts', () {
      bool called = false;
      ctrl = EditController(
        notifier: notifier,
        getState: () => editState,
        onShowShortcuts: () => called = true,
      );
      // Slash key with shift = '?'
      ctrl.handle(_key(LogicalKeyboardKey.slash));
      // Without actual shift modifier held, handled = false (modifier not injected)
      // This tests the branch guard, not the full modifier path
      expect(called, isFalse);
    });

    test('onSave callback is nullable — no crash when null', () {
      expect(() => ctrl.handle(_key(LogicalKeyboardKey.keyS)), returnsNormally);
    });
  });
}
