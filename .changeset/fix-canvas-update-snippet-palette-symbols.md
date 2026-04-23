---
"stitches": patch
---

Fix canvas not updating after drawing, snippet palette save, and symbol picker

- Canvas now repaints immediately after every draw/erase/fill/paste/move/delete operation — previously required hiding and re-showing a layer to trigger a repaint
- `loadSnippetToClipboard` auto-switches to edit mode so pasting a snippet from view mode works without a manual mode switch
- Snippet palette colour changes now mark the editor dirty so they can be saved
- Layer-thread symbol picker no longer allows picking a symbol already used by a composite (blended) thread
- `newPattern` opens directly in edit/draw mode instead of view mode
