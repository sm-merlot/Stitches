import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;

/// Called when [ShortcutRouter] dispatches a [KeyEvent].
///
/// Return `true` to consume the event and stop propagation.
/// Return `false` to let the event fall through to the next handler.
abstract interface class ShortcutHandler {
  bool handle(KeyEvent event);
}

/// Global keyboard-shortcut dispatcher.
///
/// Owns a single [HardwareKeyboard.instance] listener and dispatches events
/// down a push/pop stack of [ShortcutHandler]s — top of stack gets first
/// crack, returns `true` = consumed.
///
/// No Flutter focus dependency: fires regardless of which widget has focus,
/// so shortcuts work even when a toolbar button or dialog has grabbed focus.
///
/// **Lifecycle** (called once at the app root):
/// ```dart
/// // App.initState
/// ShortcutRouter.instance.init();
///
/// // App.dispose
/// ShortcutRouter.instance.dispose();
/// ```
///
/// **Per-widget usage:**
/// ```dart
/// // initState
/// ShortcutRouter.instance.push(this);   // `this` implements ShortcutHandler
///
/// // dispose
/// ShortcutRouter.instance.pop(this);
/// ```
class ShortcutRouter {
  ShortcutRouter._();

  static final instance = ShortcutRouter._();

  /// Creates an isolated instance for unit testing — does NOT register a
  /// [HardwareKeyboard] listener, so tests run without Flutter binding.
  @visibleForTesting
  factory ShortcutRouter.forTesting() => ShortcutRouter._();

  final List<ShortcutHandler> _stack = [];
  bool _registered = false;

  /// Registers the [HardwareKeyboard] listener.
  /// Call once after [WidgetsFlutterBinding.ensureInitialized].
  void init() {
    HardwareKeyboard.instance.addHandler(_onKey);
    _registered = true;
  }

  /// Removes the [HardwareKeyboard] listener and clears the stack.
  /// Safe to call even if [init] was never called (e.g. in tests).
  void dispose() {
    if (_registered) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      _registered = false;
    }
    _stack.clear();
  }

  /// Pushes [handler] onto the top of the stack.
  void push(ShortcutHandler handler) => _stack.add(handler);

  /// Removes [handler] from the stack (by identity).
  void pop(ShortcutHandler handler) => _stack.remove(handler);

  bool _onKey(KeyEvent event) {
    // Iterate top → bottom (most recently pushed first).
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].handle(event)) return true;
    }
    return false;
  }

  /// Dispatches [event] directly for unit testing without a [HardwareKeyboard].
  @visibleForTesting
  bool dispatchForTesting(KeyEvent event) => _onKey(event);
}
