---
"stitches": patch
---

refactor: extract StitchCompositor as single source of truth for layer compositing

Replaces three divergent in-house implementations (canvas painter `_buildBlendMap`, PDF service `_compositeNonBack`, and `computeCompositeThreads`) with a single `StitchCompositor.compute()` that produces a `CompositeResult` in one pass. Fixes stitch double-counting across layers in PDF exports.
