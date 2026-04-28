---
"stitches": minor
---

Step 10: Introduce SnippetEditController and CanvasEditController interface

- `SnippetEditController` — distinct controller class for snippet canvas editing. No save/PDF-zoom/shortcuts-dialog callbacks; no stitchMode guard; owns an independent `UndoManager` instance isolated from the parent pattern undo stack.
- `CanvasEditController` — abstract interface implemented by both `EditController` and `SnippetEditController`. `AidaWidget.editController` is now typed to the interface rather than the concrete class.
- `SnippetEditView` now wires `SnippetEditController` instead of `EditController`.
- `patchLayer` unit tests added to `StitchCompositorTest`.
- `SnippetEditController` isolation tests verify independent `UndoManager`, absence of save/shortcuts shortcuts, and correct editing shortcut dispatch.
