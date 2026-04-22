---
"stitches": minor
---

Add PatternKeeper PDF import and export support.

**Import (Tier-1 parser):** When opening a PDF in workspace scan mode, StitchX now tries a text-layer parse before falling back to the manual raster scan. PatternKeeper-format PDFs (and most PDFs produced by MacStitch, WinStitch, PCStitch) embed symbols as selectable TTF characters — the parser reads symbol positions and the legend table directly from the text layer with no user input required. Falls back automatically to the existing sample-one-cell raster scan for image-only PDFs.

**Export:** A new "Also export PatternKeeper PDF" checkbox appears in the PDF export/share picker. When checked, a `_PatternKeeper.pdf` is generated alongside the standard PDF. The PatternKeeper-format PDF omits the title page (which PatternKeeper would misread as chart data), caps pages at 60 stitches, and renders the colour legend with `Symbol`/`Number` column headers and TTF symbol characters as selectable text — satisfying PatternKeeper's import requirements.
