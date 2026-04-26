---
"stitches": patch
---

Extract Draw, Select, Paste, Progress, PageNav, Hover handlers from PatternCanvas

Introduces six handler classes that own the mutable gesture/interaction state
previously scattered across `_PatternCanvasState`. Each handler receives
injected callbacks for writes (no direct `EditorNotifier` access) and accepts
`EditorState`/`CanvasViewport` as method parameters for reads — fully
unit-testable without Riverpod.

**`DrawHandler`** — stitch drawing and erasing. Owns `_fillFired` (per-tap
flood-fill guard) and `_backstitchHoverPoint`. Handles all `DrawingTool` and
`DrawingMode` dispatch including backstitch chain mode, layer-visibility
warnings, and sub-cell quadrant/half detection.

**`SelectHandler`** — rubber-band selection and selection-move. Owns anchor,
drag rect, move delta, and hasDragged flag. Exposes static helpers
`buildSelRect`, `cellInSelRect`, `toSelCell` used by the painter.

**`PasteHandler`** — paste origin, Ctrl/Shift modifier tracking, ghost-stitch
cache, and Shift edge-snapping. Ghost cache avoids re-allocating the offset
list when `(dx,dy)` and clipboard identity are unchanged across builds.

**`ProgressHandler`** — stitch-mode progress marking. Owns anchor, drag rect,
double-click detection (DOWN-to-DOWN within 500 ms), and backstitch hit-test.
Separate `onPointerMove` (screen-pixel threshold) and `onTouchMove` (rect-size
threshold) mirror the original split for stylus/mouse vs touch.

**`PageNavHandler`** — stateless const helper. `isNavZone` returns true when a
screen position falls in an edge/corner guard zone used to suppress canvas
input during page navigation.

**`HoverHandler`** — mouse/stylus hover cell tracking. Discriminates device
kinds so stylus-added events update the preview cell without clobbering the
mouse position, and vice-versa.

`PatternCanvas` wires each handler in `initState` with `EditorNotifier`
methods as callbacks, and all event methods delegate to the appropriate
handler. ~25 individual state fields and ~10 methods removed from
`_PatternCanvasState`.

48 new unit tests added covering all six handlers.
