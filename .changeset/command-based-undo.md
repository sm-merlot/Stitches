---
"stitches": minor
---

Step 11: Command-based undo for draw operations

- `AddStitchCommand`, `RemoveStitchesAtCommand`, `RemoveStitchesInBoxCommand` — concrete `Command` subclasses in `lib/utils/command.dart`; each captures pre-mutation state so `undo()` is an exact inverse without a full snapshot.
- `addStitchRaw`, `removeStitchRaw`, `removeStitchesAtRaw`, `removeStitchesInBoxRaw` — raw draw variants on `EditorNotifier` that mutate state without pushing to the snapshot undo stack; called by `Command.execute()` and `Command.undo()`.
- `EditController` and `SnippetEditController` `attachCanvas` now wrap `DrawHandler.onAddStitch`, `onRemoveAt`, and `onRemoveBox` in the appropriate `Command` and execute via `undoManager.execute(cmd)`.
- Undo delegate — `EditorNotifier.registerUndoDelegate` / `unregisterUndoDelegate` / `updateControllerUndoState`: the active controller registers callbacks so `notifier.undo()` / `notifier.redo()` route through the controller's `UndoManager` before falling back to the snapshot stack.
- `EditorState.controllerCanUndo` / `controllerCanRedo` — new bool fields; `canUndo` / `canRedo` getters now include them so the toolbar undo button reflects the live command stack.
- `test/utils/command_test.dart` — 15 tests: execute/undo round-trips for all three command types; raw variants do not push to snapshot stack; delegate registration, routing, and reset.
