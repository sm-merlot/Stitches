---
"stitches": minor
---

PR7: Introduce mode controllers (EditController, StitchController), UndoManager + Command infrastructure

- `Command` abstract class + `UndoManager` per editing context (edit, stitch, snippet editor)
- `EditController` — ShortcutHandler for edit mode; owns all pattern-editing keyboard shortcuts
- `StitchController` — ShortcutHandler for stitch mode; owns progress undo/redo, page navigation, mode-switch keys
- `EditorScreen` converted from ConsumerWidget → ConsumerStatefulWidget for lifecycle hooks
- `WorkspaceScreen` and `SnippetEditorScreen` migrated to push/pop controllers via ShortcutRouter
- Removed `editor_key_handler.dart` and all `Focus(onKeyEvent: ...)` wrappers
- 39 new unit tests for UndoManager, EditController, StitchController
