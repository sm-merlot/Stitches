---
'stitches': minor
---

**Step 16 — Complete command-based undo + delete snapshot stack**

All remaining mutation paths now route through `UndoManager` commands instead
of the `EditorState` snapshot stacks. The snapshot fields are deleted.

### New / changed APIs

- `UndoManager.replaceLast(cmd)` — replaces the top stack entry; used by
  `StitchController` to squash a single-tap + double-tap flood-fill into one
  undo step.
- `ProgressSnapshotCommand` — lightweight command that stores only
  `PatternProgress` before/after (not the full pattern) and applies it via a
  provided callback, so `progressLog` is intentionally never rolled back.
- `EditorNotifier.applyProgressSnapshot(progress)` — restores progress without
  touching `progressLog`; called by `ProgressSnapshotCommand`.
- `registerUndoDelegate` gains `pushProgressSnapshot` — routes direct-UI
  progress mutations (`markRegion`, `clearProgress`) through the controller's
  `UndoManager`.

### Deleted

- `EditorState._progressUndoStack` / `_progressRedoStack` and
  `canUndoProgress` / `canRedoProgress` getters.
- `EditorNotifier.undoProgress()` / `redoProgress()`.
- `EditorState.progressUndoStack` / `progressRedoStack` `copyWith` params.
- Abstract `_buildUndoStack()` from all mixins.

### Behaviour changes

- `StitchController` registers as undo delegate on `attachCanvas`; Cmd+Z in
  stitch mode undoes the most recent progress mark (toggle or region fill).
- `EditController` and `SnippetEditController` wrap `deleteSelection`,
  `flipSelectionH/V`, `rotateSelectionCW` keyboard shortcuts with
  `PatternSnapshotCommand` so they are now undoable via Cmd+Z.
- `SnippetEditController` wraps `onCommitPaste`, `onFloodFill`,
  `onMoveSelection` — previously these were not undo-able inside the snippet
  editor.
