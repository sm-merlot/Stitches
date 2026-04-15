# PDF Import Research — PatternKeeper & Markup R-XP

Research notes on how the two leading cross-stitch progress trackers handle
PDF import, and ideas worth stealing for StitchX. Living document — add to it
as we learn more.

## PatternKeeper's approach (constrained, reliable)

Key insight: they don't try to be magic. PK leans heavily on PDFs being
*text-native*, not raster.

- **TTF symbols are mandatory.** Symbols must be selectable text in the PDF —
  verifiable by opening the PDF and clicking a symbol. PK reads symbols via
  the PDF text layer, not OCR. Massively more reliable than image recognition.
- **Designer fingerprinting.** PK detects the publisher (HAED, Artecy,
  Chatelaine, etc.) and applies preset rules for that designer's known layout
  — grid spacing, key column headers, page overlap. Unknown designers get a
  manual config dialog.
- **Grid is human-assisted, not auto.** A turquoise overlay is shown and users
  drag corner handles / +/− to align it. PK validates by checking pages tile
  into a rectangle (rows same height, columns same width) and rejects layouts
  that don't.
- **Required key headers.** The legend must use specific column header names
  ("Number", "Name") and not word-wrap, so PK can parse it deterministically
  as a table.
- **Page constraints.** Letter/A4 portrait, ≤100 (ideally ~60) stitches per
  page, no preview thumbnails (PK would treat the preview as chart data).
- **Limitations:** full stitches only, no backstitch / fractionals (only
  tentative recent support).

## Markup R-XP's approach (permissive, guessy)

- Accepts **PDFs, images, photos, scanned paper** — any source. Will even find
  the grid from a phone photo.
- **Auto-detects grid, symbols, colours** from raster, then stitches
  multi-page PDFs into one chart automatically.
- Two import modes ("standard" and "extra") — likely a fast path vs. a deeper
  analysis pass.
- Manual fallbacks for everything: chart overlap, key region, gridlines if
  auto fails.
- **Trade-off:** more flexible inputs, but error-prone enough that there's a
  cottage industry on Etsy of people *converting* PDFs to be "100%
  PatternKeeper or Markup compatible."

## Ideas worth stealing for StitchX

In rough order of bang-for-buck:

1. **Read the PDF text layer first.** This is the single biggest win. If the
   PDF has TTF symbols (which most pro patterns from MacStitch/WinStitch/
   PCStitch do), you get exact symbol positions and the entire key as
   parseable text — no template matching needed. The current
   `project_pdf_scanner_redesign.md` (sample-one-cell template matching) is a
   great fallback for raster PDFs and photos, but should be the *second*
   path, not the first.

2. **Designer/exporter fingerprinting.** Detect the producer string in PDF
   metadata (`/Producer`, `/Creator`) — MacStitch, WinStitch, PCStitch,
   KG-Chart, StitchFiddle all stamp themselves. Hardcode known geometry (grid
   pitch, key column layout, overlap) per producer. Turns a hard CV problem
   into a lookup.

3. **Human-assisted grid alignment as the contract.** Don't try to fully
   auto-detect the grid. Show a draggable overlay and let the user snap it to
   the first/last gridline. PK proves users will gladly do 10 seconds of
   alignment for a reliable result.

4. **Validate page tiling.** PK's "all pages in a row must be the same
   height" check is a cheap, powerful sanity test that catches misaligned
   imports before they corrupt the result.

5. **Required key format with explicit headers.** When *exporting* StitchX
   patterns to PDF, include a machine-readable key (specific column headers,
   no wrap, TTF symbols) so other StitchX users — or future you — can
   round-trip cleanly. Optionally embed a hidden JSON sidecar in the PDF
   (`/Metadata` or an attached file stream) for lossless re-import.

6. **Multi-page auto-stitching with user-confirmed overlap.** Most multi-page
   charts repeat 1–2 rows/columns of overlap. Default to known designer
   values, prompt only when unknown.

7. **Reject the preview thumbnail.** PK's gotcha — if a chart has a coloured
   preview, it gets read as data. Detect by aspect ratio / coloured-pixel
   density and skip.

8. **"Supported designers" page as a marketing wedge.** PK's biggest moat
   isn't tech, it's the curated list of designers it's known to import
   cleanly. Once StitchX handles even 3–4 of the big names (HAED, Artecy,
   Stoney Creek), publish the list — it's how stitchers choose these apps.

## Concrete recommendation

A **two-tier import pipeline** — Tier 1 is now implemented:

- **Tier 1 (text-native PDFs) — ✅ DONE** (`lib/services/pdf_pattern_keeper_parser.dart`):
  Load each page's structured text layer via pdfrx `loadStructuredText()`.
  Detect the legend table (rows where a fragment matches a known DMC code),
  build a symbol→DMC map, then parse the chart grid from character positions.
  Multi-page grids are stitched together with automatic overlap detection.
  Zero user input required — falls through silently to Tier 2 if detection
  fails.  `/Producer` fingerprinting not yet implemented (not needed in
  practice — the legend-detection heuristic is sufficient).
- **Tier 2 (raster PDFs / photos):** existing sample-one-cell template-
  matching design, with the human-assisted grid overlay borrowed from PK.

## Sources

- https://patternkeeper.app/
- https://patternkeeper.app/help/importing-a-chart/
- https://patternkeeper.app/help/inputting-grids/
- https://patternkeeper.app/help/exporting-charts-from-winstitch-macstitch/
- https://patternkeeper.app/supported-designers/
- https://patternkeeper.app/faq/
- https://ursasoftware.com/help/2023/ExporttoPDFforPatternKeeper.html
- https://markuprxp.co.uk/
- https://www.atomheartcrossstitch.com/post/pattern-keeper-vs-markup-rx-p
- https://www.etsy.com/listing/4380117891/convert-a-pdf-cross-stitch-pattern-to-be
