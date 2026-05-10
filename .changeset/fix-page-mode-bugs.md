---
"stitches": patch
---

Fix three page-mode bugs: auto-select first unfinished page, page colours default, top-row tap dead zone

- **Auto-select page**: opening stitch mode now lands on the first unfinished page (not marked done) instead of always defaulting to page 1
- **Page colours default**: stitch-mode colour panel now defaults to "Page" filter instead of "All"; segment order swapped so Page is on the left and All on the right
- **Top-row tap**: tapping or starting a selection in the top rows of a page-mode pattern now works correctly; the nav-zone guard is precise to each button's actual footprint rather than a blanket 56 px strip, so cells alongside or below nav arrows are no longer blocked
