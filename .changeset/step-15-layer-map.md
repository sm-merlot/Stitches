---
"stitches": patch
---

Step 15: Layer primary storage → Map, draw hot-path O(N) → O(N_cells)

**`Layer` data structure change**
- Primary storage is now `Map<Cell, List<Stitch>> stitchesByCell` + `List<BackStitch> backstitches`
- `List<Stitch> get stitches` is a computed getter (O(N)) for compatibility — serialisation, bulk transforms, non-hot-path code
- `stitchesAt(int x, int y)` is always O(1) with no lazy rebuild — the index exists from construction and is never discarded
- New incremental update methods for the hot draw path:
  - `withStitchAdded(stitch)` — O(N_cells) map copy, no O(N_stitches) index rebuild
  - `withStitchReplaced(stitch)` — same, overwrites same-geometry stitch at cell
  - `withStitchRemoved(stitch)` — O(N_cells) or O(n_back) for BackStitch
  - `withCellCleared(x, y)` — removes all cell stitches + any touching BackStitch

**Draw hot-path: O(N_stitches) → O(N_cells)**
- `addStitch` / `addStitchRaw`: replaced `[...layer.stitches, stitch]` (O(N_stitches) list copy) + `_buildCellIndex()` O(N_stitches) rebuild with `withStitchAdded`/`withStitchReplaced` (O(N_cells) map copy)
- `removeStitchesAt` / `removeStitchesAtRaw`: replaced `stitches.where(...).toList()` with `withCellCleared`; backstitch check uses `layer.backstitches` directly
- `removeStitchRaw`: uses `withStitchRemoved` + identity check instead of list scan
- `removeBackstitchAt`: uses `layer.backstitches` + `withStitchRemoved`
- `floodFill`: seed lookup via `stitchesAt` (O(1)); occupied map built from `stitchesByCell` directly
- `pickColorAtCell`: both loops use `stitchesAt(x, y)` instead of iterating all stitches

**`StitchCompositor._buildLayer`**
- Iterates `layer.stitchesByCell` + `layer.backstitches` directly instead of `layer.stitches` getter — avoids O(N) list allocation per layer per composite build

**`draw_handler._checkLayerWarning`**
- Erase/draw visibility checks use `stitchesAt(cellX, cellY).isNotEmpty` (O(1)) instead of `stitches.any(...)` (O(N))

**Net effect on 256×224 pattern (~6 300 occupied cells, ~19 000 stitches)**
- Per draw event: 3×O(N_stitches) → 1×O(N_cells) ≈ 3–10× fewer allocations in debug; eliminates the per-event `_buildCellIndex` rebuild that caused draw stutter
