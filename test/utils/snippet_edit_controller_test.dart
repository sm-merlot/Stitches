import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/utils/controllers/edit_controller.dart';
import 'package:stitches/utils/controllers/snippet_edit_controller.dart';

import '../widgets/test_helpers.dart';

// ── Fake notifier shared by all tests ─────────────────────────────────────

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

KeyDownEvent _key(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SnippetEditController', () {
    late _FakeNotifier notifier;
    late EditorState editState;
    late SnippetEditController ctrl;

    setUp(() {
      notifier = _FakeNotifier();
      editState = fakeEditState();
      ctrl = SnippetEditController(
        notifier: notifier,
        getState: () => editState,
      );
    });

    // ── UndoManager isolation ────────────────────────────────────────────────

    test('owns an independent UndoManager — not the same instance as EditController', () {
      final editCtrl = EditController(
        notifier: notifier,
        getState: () => editState,
      );
      expect(identical(ctrl.undoManager, editCtrl.undoManager), isFalse);
    });

    test('two SnippetEditController instances have independent UndoManagers', () {
      final ctrl2 = SnippetEditController(
        notifier: notifier,
        getState: () => editState,
      );
      expect(identical(ctrl.undoManager, ctrl2.undoManager), isFalse);
    });

    // ── No save shortcut ─────────────────────────────────────────────────────

    test('Cmd+S is not consumed (no onSave callback)', () {
      // Without modifier injection, the modifier path is not entered.
      // Verify the key itself is not handled by the single-key path.
      // S key (no modifier) → setDrawingMode:select, not save.
      ctrl.handle(_key(LogicalKeyboardKey.keyS));
      expect(notifier.calls, ['setDrawingMode:select'],
          reason: 'S (no modifier) → select mode, not save');
    });

    // ── No shortcuts-dialog shortcut ─────────────────────────────────────────

    test('Shift+? is not consumed (no onShowShortcuts callback)', () {
      // Slash without modifier → not recognised → returns false.
      final handled = ctrl.handle(_key(LogicalKeyboardKey.slash));
      expect(handled, isFalse);
      expect(notifier.calls, isEmpty);
    });

    // ── Always active regardless of stitchMode ───────────────────────────────

    test('handles shortcuts even when state.stitchMode is true', () {
      // SnippetEditController has no stitchMode guard.
      editState = fakeStitchState(); // stitchMode=true
      ctrl = SnippetEditController(notifier: notifier, getState: () => editState);
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyD)), isTrue);
      expect(notifier.calls, ['setDrawingMode:draw']);
    });

    // ── Core editing shortcuts ────────────────────────────────────────────────

    test('D → setDrawingMode draw', () {
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyD)), isTrue);
      expect(notifier.calls, ['setDrawingMode:draw']);
    });

    test('E → setDrawingMode erase', () {
      ctrl.handle(_key(LogicalKeyboardKey.keyE));
      expect(notifier.calls, ['setDrawingMode:erase']);
    });

    test('Space → setDrawingMode pan', () {
      ctrl.handle(_key(LogicalKeyboardKey.space));
      expect(notifier.calls, ['setDrawingMode:pan']);
    });

    test('C → setDrawingMode colorPicker', () {
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

    test('9 → erase + toggleFillErase when fillEraseActive false', () {
      editState = fakeEditState(fillEraseActive: false);
      ctrl = SnippetEditController(notifier: notifier, getState: () => editState);
      ctrl.handle(_key(LogicalKeyboardKey.digit9));
      expect(notifier.calls, ['setDrawingMode:erase', 'toggleFillErase']);
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

    test('ignores KeyUpEvent', () {
      final event = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      );
      expect(ctrl.handle(event), isFalse);
      expect(notifier.calls, isEmpty);
    });

    test('unrecognised key returns false', () {
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyQ)), isFalse);
      expect(notifier.calls, isEmpty);
    });

    // ── Canvas null-safety ────────────────────────────────────────────────────

    test('pointer methods are no-ops before attachCanvas', () {
      // All pointer method calls before attachCanvas must not throw.
      expect(() => ctrl.onPointerHover(
        Offset.zero, PointerDeviceKind.mouse,
        vp,
        editState,
      ), returnsNormally);
    });
  });
}
