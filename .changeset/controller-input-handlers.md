---
'stitches': patch
---

Complete controller handler composition (PR 7a)

`EditController` now owns `DrawHandler`, `SelectHandler`, `PasteHandler`, and
`HoverHandler`; `StitchController` owns `ProgressHandler`, `PageNavHandler`,
and `HoverHandler`. Both controllers expose an `attachCanvas(CanvasCallbacks)`
/ `detachCanvas()` lifecycle so `PatternCanvas` can inject view-level callbacks
at mount time. `PatternCanvas` delegates all pointer events to the active
controller and reads overlay state (hover cell, paste origin, selection rect)
directly from controller-owned handlers.
