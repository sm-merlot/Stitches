---
"stitches": patch
---

Fix single-tap stitch unmark ignoring page boundaries

- `toggleStitchDone` page-mode guard moved before the mark/unmark branch so it applies to both adding and removing completed stitches
- Previously, tapping a completed stitch on a different page would incorrectly unmark it
