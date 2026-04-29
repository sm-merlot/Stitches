import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/utils/controllers/canvas_callbacks.dart';
import 'package:stitches/utils/controllers/view_mode_controller.dart';

import '../../widgets/test_helpers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _cb = CanvasCallbacks(
  scheduleRebuild: () {},
  onWarning: (_) {},
  getPencilPasteConfirm: () => false,
);

KeyDownEvent _key(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

ViewModeController _attached({EditorState? state}) {
  final viewState = state ?? fakeViewState();
  final ctrl = ViewModeController(getState: () => viewState);
  ctrl.attachCanvas(_cb);
  return ctrl;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewModeController — handle()', () {
    test('always returns false for any KeyDownEvent', () {
      final ctrl = _attached();
      for (final key in [
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.delete,
      ]) {
        expect(ctrl.handle(_key(key)), isFalse,
            reason: 'key $key should not be consumed in view mode');
      }
    });

    test('returns false for KeyUpEvent', () {
      final ctrl = _attached();
      final event = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyS,
        logicalKey: LogicalKeyboardKey.keyS,
        timeStamp: Duration.zero,
      );
      expect(ctrl.handle(event), isFalse);
    });
  });

  group('ViewModeController — lifecycle', () {
    test('hover is null before attachCanvas', () {
      final ctrl = ViewModeController(getState: () => fakeViewState());
      expect(ctrl.hover, isNull);
    });

    test('hover is non-null after attachCanvas', () {
      final ctrl = _attached();
      expect(ctrl.hover, isNotNull);
    });

    test('hover is null after detachCanvas', () {
      final ctrl = _attached();
      ctrl.detachCanvas();
      expect(ctrl.hover, isNull);
    });
  });

  group('ViewModeController — hover tracking', () {
    test('onPointerHover sets mouseScreenPos and hoverCell for in-bounds pos', () {
      final state = fakeViewState();
      final ctrl = _attached(state: state);

      // Cell (2, 3) → screen pos (2*20 + 10, 3*20 + 10) = (50, 70)
      ctrl.onPointerHover(
        const Offset(50, 70),
        PointerDeviceKind.mouse,
        vp,
        state,
      );

      expect(ctrl.hover!.mouseScreenPos, const Offset(50, 70));
      expect(ctrl.hover!.hoverCell, (2, 3));
    });

    test('onPointerHover with out-of-bounds pos → hoverCell null', () {
      final state = fakeViewState();
      final ctrl = _attached(state: state);
      // patW = patH = 20, so pos beyond 20*20=400 is out of bounds
      ctrl.onPointerHover(
        const Offset(9999, 9999),
        PointerDeviceKind.mouse,
        vp,
        state,
      );
      expect(ctrl.hover!.hoverCell, isNull);
    });

    test('onPointerHover no-ops when detached', () {
      final state = fakeViewState();
      final ctrl = ViewModeController(getState: () => state);
      // No attachCanvas — should not throw.
      expect(
        () => ctrl.onPointerHover(
          const Offset(50, 70),
          PointerDeviceKind.mouse,
          vp,
          state,
        ),
        returnsNormally,
      );
    });

    test('onHoverExit clears mouseScreenPos and hoverCell', () {
      final state = fakeViewState();
      final ctrl = _attached(state: state);
      ctrl.onPointerHover(const Offset(50, 70), PointerDeviceKind.mouse, vp, state);
      expect(ctrl.hover!.hoverCell, isNotNull);

      ctrl.onHoverExit();

      expect(ctrl.hover!.mouseScreenPos, isNull);
      expect(ctrl.hover!.hoverCell, isNull);
    });

    test('onStylusAdded sets hoverCell for in-bounds position', () {
      final state = fakeViewState();
      final ctrl = _attached(state: state);

      ctrl.onStylusAdded(
        const Offset(50, 70), // cell (2, 3)
        vp,
        state.pattern.width,
        state.pattern.height,
      );

      expect(ctrl.hover!.hoverCell, (2, 3));
    });

    test('onStylusAdded out-of-bounds → hoverCell unchanged', () {
      final state = fakeViewState();
      final ctrl = _attached(state: state);

      ctrl.onStylusAdded(
        const Offset(9999, 9999),
        vp,
        state.pattern.width,
        state.pattern.height,
      );

      expect(ctrl.hover!.hoverCell, isNull);
    });

    test('onStylusRemoved clears hoverCell', () {
      final state = fakeViewState();
      final ctrl = _attached(state: state);
      ctrl.onStylusAdded(const Offset(50, 70), vp, state.pattern.width, state.pattern.height);
      expect(ctrl.hover!.hoverCell, isNotNull);

      ctrl.onStylusRemoved();

      expect(ctrl.hover!.hoverCell, isNull);
    });

    test('onStylusAdded and onStylusRemoved no-op when detached', () {
      final state = fakeViewState();
      final ctrl = ViewModeController(getState: () => state);
      expect(() => ctrl.onStylusAdded(Offset.zero, vp, 20, 20), returnsNormally);
      expect(() => ctrl.onStylusRemoved(), returnsNormally);
    });
  });

  group('ViewModeController — structural guarantees', () {
    test('has no draw, select, or paste handler', () {
      final ctrl = _attached();
      // ViewModeController only exposes hover — no draw/select/paste fields.
      // Verified at compile time; this test documents the contract.
      expect(ctrl.hover, isNotNull);
    });

    test('handle() never consumes events regardless of AppMode', () {
      // Even if somehow constructed with a stitch-mode state, still returns false.
      final ctrl = ViewModeController(getState: () => fakeStitchState());
      ctrl.attachCanvas(_cb);
      expect(ctrl.handle(_key(LogicalKeyboardKey.escape)), isFalse);
      expect(ctrl.handle(_key(LogicalKeyboardKey.keyS)), isFalse);
    });
  });
}
