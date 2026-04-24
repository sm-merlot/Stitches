---
"stitches": patch
---

Extract RenderCache — remove static caches from painter, painter now pure draw

Introduces `RenderCache` and `RenderViewConfig`:

- `RenderCache` owns `Map<Color, Map<cellKey, List<Rect>>>` — pre-resolved stitch
  block rects grouped by colour, with a reverse-index enabling O(1) cell removal.
  `version` counter replaces object-identity cache-key comparisons.
- `RenderViewConfig` is an immutable value object capturing focus thread,
  stitch/back/cross mode, palette override, progress, and page config.

`CanvasStaticPainter` gains a `renderCache` field and loses both static caches
(`_blockRectsByLayer`, `_occlusionCache`) and all the domain helpers that fed
them (`_resolveStitchColor`, `_applyPaletteOverride`, `_bwGreyscale`,
`_muteColor`, `_greyColor`, `_nearestThread`, `_getOrBuildBlockRects`,
`_drawLayerStitchesAsBlocks`, `_drawLayerBlocksWithPageFilter`,
`_getOcclusionSets`). Block rendering is now a simple nested iteration of
`renderCache.store`. Symbol rendering uses `compositeResult.dedupedNonBack`
(the symbol-winner list already produced by `StitchCompositor`) so occlusion
sets are no longer needed.

`PatternCanvas` owns the `RenderCache` and calls `_syncRenderCache` at the
top of `build()` — rebuilding only when pattern/composite/view-config identity
changes, not on pan/zoom. `rebuildViewConfig` is used for focus/mode changes
(recolour only, no geometry recomputation).

15 new unit tests added covering rebuild, incremental `updateCells`, focus
greying, B&W stitch mode, version counter, and `RenderViewConfig` equality.
All 482 existing tests pass.
