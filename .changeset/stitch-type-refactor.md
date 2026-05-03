---
"stitches": minor
---

Step 20: Stitch type refactor — toolbar consolidation + three-quarter stitch + overlap system

- `ThreeQuarterStitch` — new stitch type: full diagonal + quarter diagonal to corner. Block mode: half-cell triangle. Realistic: two thread lines.
- Removed single-diagonal quarter stitch; old `'quarter'` YAML entries silently dropped on load. Petit point (X in quarter cell) kept as `QuarterStitch` with YAML type `'quartercross'`.
- Toolbar: 6 partial stitch buttons consolidated to 1 button with tap-to-open dropdown selector + dropdown arrow indicator. Keyboard shortcuts 2–6 unchanged.
- `BlockShape` sealed class (`RectShape` / `PathShape`) replaces raw `Rect` in `RenderCache`. `HalfStitch` renders as thick diagonal parallelogram, `ThreeQuarterStitch` as filled triangle. `drawRect` GPU fast path preserved for rect-based stitch types.
- `PartialSubTool` enum + `partialSubTool` field on `EditSessionState`. `DrawingTool` enum consolidated: `halfForward`/`halfBackward`/`halfCross`/`quarterDiag`/`quarterCross` replaced by single `partial` value. Session migration handles old tool names.
- Overlap-aware stitch placement via `CellRegion` quadrant system. Non-overlapping partial stitches coexist in the same cell. Overlapping stitch replaces existing.
- Cross-layer compositor: same regions → blend, partial overlap → top occludes, no overlap → both visible.
