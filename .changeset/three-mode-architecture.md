---
"stitches": minor
---

Replace the two-mode design/stitch toggle with three purposeful modes: View (default, read-only overview), Edit (full pattern editor), and Stitch (active stitching session). Files now always open in View mode — no accidental edits or progress marks.

- File sidebar is now View-mode only — slides out of the way in Edit and Stitch so the canvas always has full focus
- Sidebar slides as an overlay so the canvas grid never moves or resizes
- Block mode toggle moved into the AppBar title area, consistent across all three modes
- Dirty-dot removed from title; replaced with a persistent save state indicator — spinner while saving, cloud icon (Google Drive) or checkmark (local) when saved; Drive indicator shows immediately on first edit
- Demo button moved to the colours sidebar; enabled only when stitches are selected on the canvas
- Focus mode greying now applies in all three modes, not just Stitch
