---
'stitches': patch
---

**Step 18 — Polish, bug fixes, and stitch-mode architectural enforcement**

### Bug fixes

- **Canvas blank after addGroup / layer ops** — all 13 layer-mutation methods
  now call `refreshCompositeCache()` immediately instead of setting
  `compositeLayer: null` and waiting for the next repaint.
- **setLayerOpacity flash** — replaced `compositeLayer: null` + 150 ms debounce
  with `patchAffectedLayer()` for O(cells) incremental update; no more visible
  flash on every slider tick.
- **Focus-mode mark/frog ignores composite stitches** — `markRegionDone`,
  `markRegionNotDone`, `floodFillDone`, and the sidebar mark/demo buttons now
  compare against `resolvedThread.dmcCode` from `compositeLayer` instead of
  raw `stitch.threadId`, so blended/composite cells respect the focus filter.
- **Text field typing blocked in colour picker** — `FocusNode.context.widget`
  is a `Focus` widget (child of `EditableText`), not `EditableText` itself.
  Guard now uses `findAncestorStateOfType<EditableTextState>()` to walk the
  element tree correctly. Colour picker and DMC picker gain `autofocus: true`.
- **Reference image visible in stitch mode** — painter now checks `!stitchMode`
  before drawing the overlay; reference image is edit-mode only.
- **Drive Open modal hid Drive section on first render** — `build()` now
  returns `DriveState(isConfigured: _auth.isConfigured)` synchronously.
- **Stitch demo used pattern aida colour** — demo background is always white
  (demo shows technique, not pattern colours).

### Architecture

- **`StitchStateView` facade** — read-only projection of `EditorState` for
  stitch-mode code. Exposes `compositeLayer`, `stitchSession`, `progress`,
  `progressLog`, `threads`; deliberately omits `pattern.layers`. `ProgressMixin`
  reads exclusively through `_stitch: StitchStateView`; sidebar stitch-mode
  helpers (`_regionHasPageStitches`, `_isRegionAllDone`, `_buildTopThread`,
  `_stitchPool`) accept `StitchStateView` — raw layer access in stitch mode is
  now a compile error.
- **`CompositeLayer` helpers** — `topThreadAt(Cell)` and `hasCrossStitchAt(Cell)`
  added for O(1) single-cell lookup used by toggle/flood-fill paths.
