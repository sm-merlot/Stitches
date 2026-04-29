---
"stitches": patch
---

Step 15: Layer Map primary storage + O(1) draw hot-path + CompositeLayer version counter

**`Layer` data structure change**
- Primary storage is now `Map<Cell, List<Stitch>> stitchesByCell` + `List<BackStitch> backstitches`
- `List<Stitch> get stitches` is a computed getter (O(N)) for compatibility — serialisation, bulk transforms, non-hot-path code
- `stitchesAt(int x, int y)` is always O(1) — no lazy rebuild, index exists from construction
- Immutable update methods for snapshot-undo paths (paste, move, delete, etc.):
  - `withStitchAdded`, `withStitchReplaced`, `withStitchRemoved`, `withCellCleared` — O(N_cells) map copy
- In-place mutation methods for 120 Hz draw hot-path (via UndoManager commands):
  - `addStitchInPlace`, `replaceStitchInPlace`, `removeStitchInPlace`, `clearCellInPlace` — O(1), zero map copy

**Draw hot-path: O(N_stitches) → O(1)**
- `addStitchRaw`: `addStitchInPlace` mutates map directly — no copy
- `removeStitchRaw`: `removeStitchInPlace` — no copy
- `removeStitchesAtRaw`: `clearCellInPlace` — no copy
- `removeStitchesInBoxRaw`: `clearCellInPlace` per box cell — O(box²)
- Safe because UndoManager commands reverse mutations exactly (add ↔ remove); snapshot undo always uses immutable methods that create new Layer instances

**`CompositeLayer` version counter + in-place mutation**
- `patchLayer`: mutates `old.fullStitches` in-place + bumps `version` — eliminates O(N_cells) `Map.from` copy
- `patchCells(old, pattern, cells)`: new method for multi-cell patches (paste, etc.) — O(cells × layers_per_cell)
- `patchAffectedLayer`: thin wrapper around `patchCells`, in-place mutation
- `_syncRenderCache` detects changes via version counter instead of `identical()`

**`toggleLayerVisible` / `setLayerBlendMode` → `patchAffectedLayer`**
- Now that `patchAffectedLayer` is in-place (no Map.from copy), it's faster than `computeComposite` for visibility/blend toggles — resolves only cells the changed layer touches

**`commitPaste` → `patchCells`**
- Paste uses `patchCells(dirtyCells)` for incremental composite — only resolves pasted cells instead of full recompute

**Rename: `computeLayer` → `computeComposite`**
- Clearer name: computes composite from ALL visible layers, not a single layer

**Controller hot-path fixes**
- `EditController` / `SnippetEditController` `onAddStitch` and `onRemoveAt` callbacks use `stitchesAt` (O(1)) instead of `layer.stitches` getter (O(N) allocation)
- `draw_handler._checkLayerWarning` uses `stitchesAt` (O(1))
- `pickColorAtCell`, `floodFill`: use `stitchesAt` / `stitchesByCell` directly

**Net effect on 256×224 pattern (~6 300 cells, ~19 000 stitches)**
- Per draw event: 3×O(19k) → O(1) — zero list copies, zero map copies, zero index rebuilds
- Visibility toggle: O(19k) full recompute → O(6.3k cells × ~1 layer) incremental
- Paste 50 stitches: O(19k) full recompute → O(50 cells) incremental
