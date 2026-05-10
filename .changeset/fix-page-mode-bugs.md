---
"stitches": patch
---

Fix page-mode bugs and middle-click marking; centralise mouse-button filtering

- **Auto-select page**: opening stitch mode now lands on the first unfinished page (not marked done) instead of always defaulting to page 1
- **Page colours default**: stitch-mode colour panel now defaults to "Page" filter instead of "All"; segment order swapped so Page is on the left and All on the right
- **Top-row tap**: tapping or starting a selection in the top rows of a page-mode pattern now works correctly; the nav-zone guard is precise to each button's actual footprint rather than a blanket 56 px strip, so cells alongside or below nav arrows are no longer blocked
- **Middle-click**: middle mouse button no longer marks stitches in stitch mode or draws in edit mode; the `kMiddleMouseButton` guard is now enforced once in `AidaWidget._onPointerDown` and removed from individual controllers (`EditController`, `SnippetEditController`, `StitchController`), eliminating a class of per-controller omission bugs
