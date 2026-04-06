---
"stitches": minor
---

Add stitch progress tracking in Stitch mode: tap to mark individual stitches done, drag to mark a region, and double-tap to flood fill all connected stitches of the same colour. Progress is saved with the pattern file.

- Progress bar shows stitches done / total, percentage, pages done (page mode), and colours completed
- Undo/redo buttons in the progress bar for progress operations (separate from pattern edit undo)
- Colour completion toast when all stitches of a thread are marked done
- Double-tap flood fill is a single undo step (not two)
- Page mode: marking and flood fill constrained to the current page only
- Share / Export .stitches: optional checkboxes to strip progress data and/or page settings from the exported file
