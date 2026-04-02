---
"stitches": patch
---

Phone layout polish and quick swatch improvements

- Compact toolbar buttons and labels on phones (short Drive button, "+" new pattern, etc.)
- Sidebar mutual exclusion on phones — only one panel open at a time
- Phone editor toolbar splits into two rows: drawing tools on top, colour controls on bottom
- Bottom colour row: snippet button left, quick swatches fill right-to-left flush against selected colour, undo/redo right
- Quick swatch size unified with selected colour swatch (24 px)
- Fix quick swatch count silently decreasing when switching threads — outgoing thread is now always preserved in history
- Increase recent thread history cap from 5 to 10
- Threads not yet added to the pattern now remain visible in quick swatches via DMC database fallback
