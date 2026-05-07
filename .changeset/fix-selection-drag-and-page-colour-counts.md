---
"stitches": patch
---

Fix selection drag starting new selection, and fix page colour done counts

- **Selection**: clicking or dragging inside an existing selection now always starts a new rubber-band selection instead of entering move mode
- **Page colours**: done stitch counts in the page-filtered colour panel now reflect only stitches on the current page, instead of showing global totals against page-scoped totals
- **Refactor**: gesture recognition (tap, double-tap, drag) is now a shared `GestureHandler` layer; double-tap window reduced from 500 ms to 300 ms to match mobile standard
