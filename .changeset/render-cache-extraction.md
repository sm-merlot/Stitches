---
"stitches": patch
---

Extract RenderCache and delete CompositeResult — painter receives pre-resolved data

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
`renderCache.store`. Symbol rendering iterates `compositeLayer.fullStitches`
and `otherStitches` (symbol-winner already applied by `StitchCompositor`) so
occlusion sets are no longer needed.

`PatternCanvas` owns the `RenderCache` and calls `_syncRenderCache` at the
top of `build()` — rebuilding only when pattern/composite/view-config identity
changes, not on pan/zoom. `rebuildViewConfig` is used for focus/mode changes
(recolour only, no geometry recomputation).

`CompositeResult` deleted in full — `StitchCompositor.compute()`,
`CompositeLayer.toCompositeResult()`, and `StitchCompositor.compositeResult`
are all removed. All callers now use `StitchCompositor.computeLayer()` and
access `CompositeLayer` fields directly (`fullStitches`, `otherStitches`,
`backstitches`, `crossStitchEquiv`, `backStitchEquiv`). Migrated files:
`EditorState`, all `editor_provider_*` mixins, `canvas_painter.dart`,
`pattern_canvas.dart`, `right_sidebar_colours_panel.dart`,
`editor_toolbar_color_controls.dart`, `stitch_ops_screen.dart`,
`materials_list_screen.dart`, `pdf_service.dart`, `png_export_service.dart`,
`page_layout.dart`, and all affected tests.

15 new unit tests added covering rebuild, incremental `updateCells`, focus
greying, B&W stitch mode, version counter, and `RenderViewConfig` equality.
All 480 tests pass.
