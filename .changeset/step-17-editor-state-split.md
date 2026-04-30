---
'stitches': patch
---

**Step 17 — EditorState split into grouped value classes**

The `EditorState` monolith's ~30 flat fields are now grouped into four
dedicated value classes. No behaviour change — pure structural refactor.

### New types

- `ViewState` — `panX`, `panY`, `scale` (replaces `viewPanX/Y/viewScale`)
- `StitchSessionState` — `crossMode`, `backMode`, `focusThreadId`,
  `showPageColours`, `currentPage`, `pageLayout`, `pendingFitPage`,
  `progressRegion`
- `EditSessionState` — `currentTool`, `drawingMode`, `backstitchStartPoint`,
  `backstitchChainMode`, `selectionRect`, `clipboard`, `clipboardThreads`,
  `clipboardFromSnippet`, `eraserSize`, `fillEraseActive`,
  `canvasSelectionMode`, `pendingCanvasWarning`, `referenceImage`,
  `referenceOpacity`, `referenceVisible`, `colourMode`
- `SnippetEditorState` — `palettes`, `activePaletteIndex`

### EditorState API changes

Flat fields replaced by grouped accessors:

```dart
// Before
state.viewPanX / state.currentPage / state.currentTool / state.snippetPalettes

// After
state.viewState.panX / state.stitchSession.currentPage
state.editSession.currentTool / state.snippetEditorState.palettes
```

`EditorState.copyWith` now accepts grouped params (`viewState:`,
`stitchSession:`, `editSession:`, `snippetEditorState:`) instead of the
individual flat params. `dirtyCellKeys` remains a flat field (moving it out
requires a new provider↔widget communication channel — deferred).
