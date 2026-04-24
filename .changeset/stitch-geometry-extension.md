---
"stitches": patch
---

Consolidate stitch geometry into StitchGeometry extension on Stitch

Adds `cellCoords`, `bounds`, `blockCells`, and `isInViewport` extension
getters/methods, replacing 5 duplicate switch-based geometry helpers scattered
across `canvas_painter`, `pattern_canvas`, `editor_state`, and two stitch ops
screens. `EditorState.cellCoords` and `stitchXY` free function now delegate to
the extension. 16 new unit tests added.
