---
"stitches": patch
---

Step 14: Architecture thinning, dead code pass, O(1) pipeline bottleneck fixes

**Dead code removed**
- `lib/services/ai/` directory deleted — `ai_provider.dart` was an unreferenced duplicate of `ScannedThread`/`ScannedStitch`/`PatternScanResult` already in `lib/services/scan/scan_result.dart`
- `changeThreadSymbol`, `removeThread` — 0 callers in production code
- `transformSnippet`, `addSnippetPalette`, `deleteSnippetPalette`, `renameSnippetPalette`, `reorderSnippetPalette` — test-only or 0 callers; superseded by `*Local()` variants
- `SnippetTransform` enum removed (no remaining callers)
- Tests for all removed methods removed

**Render pipeline: O(n) → O(1) hot-path fixes**
- `StitchCompositor.patchLayer`: inner loop now calls `layer.stitchesAt(x, y)` (O(1) via `_cellIndex`) instead of scanning all of `layer.stitches`; `BackStitch` exclusion implicit since it has no `cellCoords`
- `addStitch` / `addStitchRaw`: `alreadyExists` check uses `stitchesAt` — O(1) for the common case, O(n) fallback only for `BackStitch`
- `removeStitchesAt` / `removeStitchesAtRaw`: early-return guard checks `stitchesAt(x,y).isEmpty` first; only scans for backstitch when cell is otherwise empty

**`StitchCompositor.patchAffectedLayer` — new**
- Patches only cells that a changed layer touches; used by `toggleLayerVisible` and `setLayerBlendMode`
- Previously both called `refreshCompositeCache()` → `computeLayer()` = O(total_stitches)
- Now O(cells_in_layer × avg_layers_per_cell) — effectively O(1) for sparse single-layer patterns

**EditorState field audit**
- Fields grouped and annotated by mode ownership (edit / stitch / snippet / view / render pipeline) to guide future per-mode state extraction
