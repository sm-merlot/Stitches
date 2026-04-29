import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/utils/commands/shortcut_router.dart';

// ─── Test double ──────────────────────────────────────────────────────────────

class _RecordingHandler implements ShortcutHandler {
  final List<KeyEvent> received = [];
  bool consume;

  _RecordingHandler({this.consume = false});

  @override
  bool handle(KeyEvent event) {
    received.add(event);
    return consume;
  }
}

KeyDownEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyA, // physical key is irrelevant here
      timeStamp: Duration.zero,
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // Create a fresh router for each test to avoid singleton pollution.
  late ShortcutRouter router;

  setUp(() => router = ShortcutRouter.forTesting());
  tearDown(() => router.dispose());

  group('ShortcutRouter', () {
    test('dispatches event to pushed handler', () {
      final h = _RecordingHandler();
      router.push(h);
      router.dispatchForTesting(_keyDown(LogicalKeyboardKey.keyA));
      expect(h.received, hasLength(1));
    });

    test('top of stack gets event first', () {
      final order = <int>[];
      final h1 = _FnHandler((_) { order.add(1); return false; });
      final h2 = _FnHandler((_) { order.add(2); return false; });
      router.push(h1);
      router.push(h2);
      router.dispatchForTesting(_keyDown(LogicalKeyboardKey.keyA));
      expect(order, [2, 1]); // h2 pushed last → top of stack → first
    });

    test('consuming handler stops propagation', () {
      final h1 = _RecordingHandler();
      final h2 = _RecordingHandler(consume: true); // top, consumes
      router.push(h1);
      router.push(h2);
      router.dispatchForTesting(_keyDown(LogicalKeyboardKey.keyA));
      expect(h2.received, hasLength(1));
      expect(h1.received, isEmpty); // blocked
    });

    test('non-consuming handler propagates to next', () {
      final h1 = _RecordingHandler();
      final h2 = _RecordingHandler(consume: false);
      router.push(h1);
      router.push(h2);
      router.dispatchForTesting(_keyDown(LogicalKeyboardKey.keyA));
      expect(h1.received, hasLength(1));
      expect(h2.received, hasLength(1));
    });

    test('pop removes handler by identity', () {
      final h = _RecordingHandler();
      router.push(h);
      router.pop(h);
      router.dispatchForTesting(_keyDown(LogicalKeyboardKey.keyA));
      expect(h.received, isEmpty);
    });

    test('pop is a no-op for unknown handler', () {
      final h = _RecordingHandler();
      expect(() => router.pop(h), returnsNormally);
    });

    test('empty stack does not throw', () {
      expect(
        () => router.dispatchForTesting(_keyDown(LogicalKeyboardKey.keyA)),
        returnsNormally,
      );
    });

    test('dispose clears stack', () {
      final h = _RecordingHandler();
      router.push(h);
      router.dispose();
      // Re-init so tearDown's dispose() doesn't error.
      router = ShortcutRouter.forTesting();
    });
  });
}

// ─── Helper ───────────────────────────────────────────────────────────────────

class _FnHandler implements ShortcutHandler {
  final bool Function(KeyEvent) fn;
  const _FnHandler(this.fn);

  @override
  bool handle(KeyEvent event) => fn(event);
}
