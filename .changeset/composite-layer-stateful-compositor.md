---
"stitches": patch
---

Introduce CompositeLayer and stateful StitchCompositor

Adds `CompositeStitch` and `CompositeLayer` types as the rendering-oriented
output of layer compositing. `CompositeLayer.fullStitches` maps each occupied
cell to a `CompositeStitch` carrying resolved colour, resolved thread, and an
`isBlended` flag — no further layer logic required downstream.

`StitchCompositor` is now instantiable: `StitchCompositor(pattern)` holds the
pattern and lazily maintains a cached `CompositeLayer`. Incremental update
methods `updateCell`, `updateCells`, `updateLayer`, and `rebuild` invalidate
the cache; the next `compositeLayer` access rebuilds only what changed (full
rebuild for now; cell-level invalidation follows in the RenderCache step).

The static `compute()` and `computeLayer()` convenience helpers remain for
services and tests that do not need the stateful API. `CompositeResult` is
retained unchanged — `CompositeLayer.toCompositeResult()` bridges the two.

10 new unit tests added covering `CompositeLayer` structure, `isBlended` flag
accuracy, and the cache invalidation / lazy-rebuild contract.
