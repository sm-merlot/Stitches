---
"stitches": patch
---

Fix canvas not refreshing after flood fill, resize, and undo

- Flood fill BFS: replace `List.removeAt(0)` (O(n)) with `Queue.removeFirst()` (O(1)), eliminating the main-thread freeze that blocked vsync delivery on large patterns
- `resizePattern` / `resizeEditorPatternAsSnippet`: were updating `pattern` but not `compositeLayer`, so the canvas rebuilt from the stale composite showing stitches at wrong positions; now clears composite and calls `refreshCompositeCache()`
- `applyPatternSnapshot` (used by undo/redo for paste and flood fill): was computing composite inline without `refreshCompositeCache()`, leaving `pattern.compositeSymbols` stale; now does a full cache refresh so the canvas correctly reflects the restored state
