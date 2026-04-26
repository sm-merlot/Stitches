---
"stitches": patch
---

Introduce ShortcutRouter — replace HardwareKeyboard handler in PatternCanvas

Adds `ShortcutRouter` singleton + `ShortcutHandler` interface as global
keyboard-shortcut infrastructure. No Flutter focus dependency — fires
regardless of which widget has focus, resolving the focus-stealing issues
with AppBar and dialogs.

`PatternCanvas` now implements `ShortcutHandler` and pushes/pops itself
on `ShortcutRouter` in `initState`/`dispose`, replacing the direct
`HardwareKeyboard.instance.addHandler` call. The handler behaviour is
unchanged: update `PasteHandler` Ctrl/Shift modifier state, return false
(do not consume).

`ShortcutRouter.init()` called once in `main()` after
`WidgetsFlutterBinding.ensureInitialized()`.

`ShortcutRouter.forTesting()` and `dispatchForTesting()` allow pure-Dart
unit tests without the Flutter binding.

8 new unit tests covering dispatch order, consume/propagate, push/pop,
and empty-stack safety. All 601 tests pass.
