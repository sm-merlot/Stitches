---
"stitches": patch
---

fix: materials list skein calculation and quarter-skein precision

Shows skein quantities as fractions (¼, ½, ¾, 1, 1¼…) instead of decimals, and fixes two bugs in the underlying formula:

- Cross-stitch thread factor corrected to `4 × √2` per stitch (was `4 × √2 × √2 = 8`, doubling the estimate)
- Strand scaling fixed to be linear — skeins now scale proportionally with strand count (was scaling as strands², so 1-strand was too low and 3-strand too high)
