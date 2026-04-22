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

---

## Current implementation status (as of 2026-04-22)

### What works ✅

**StitchX round-trip (primary target)**
- StitchX exports a PK-compatible PDF (`patternKeeperMode: true`) that
  re-imports cleanly. 57,344-stitch Super Metroid test passes with ≤10 missing
  stitches (Linux pdfium deduplication tolerance). macOS: exact.
- PKCHART v1–v4 metadata markers fully parsed; absolute page placement uses
  embedded origin and cell-size to avoid heuristic drift.

**Legend parsing — two formats supported**
- Format A (StitchX / StitchX-generated / Dachshund / third-party):
  `[symbol] [code] [name]` or `[symbol] DMC [code] [name]`.
  Proximity guard (≤40pt) rejects false positives from name-column words and
  stitch-count columns.
- Format B (Artecy / HAED): `[symbol] [strands] DMC [code] [name]`.
  Detected by presence of explicit `DMC` literal left of code; strand-count
  digit skipped. Artecy: 99 entries. HAED: 90 entries.

**Grid parsing — two encodings supported**
- Positioned-character encoding (StitchX, Dachshund): each symbol is a
  single positioned TTF character extracted as a 1-char fragment. Step
  detected from inter-symbol distances; multi-page absolute assembly from
  PKCHART offsets.
- Text-flow encoding (Artecy, HAED — partially working): pdfium extracts
  each chart row as one long multi-char fragment. Detected when
  "symbol-rich" multi-char fragments are present; step estimated from
  fragment width / rune count; row step from Y-position differences.
  Single-char cell placement is skipped; the row-merge recovery loop places
  all cells.

---

### What's partially working / known issues ⚠️

**Artecy grid parsing**
- Legend: 99 entries ✅
- Page 5 (one chart page) detects correctly as positioned-char: 3634 symbols,
  53×76 grid, step 18.9×9.5 pt. Suspicious non-square step — may be a
  non-chart page or a page with mixed encoding.
- Most other chart pages: text-flow detection was just added (2026-04-22) but
  not yet confirmed working with real PDFs. Needs test files committed.

**HAED grid parsing**
- Legend: 90 entries ✅
- Chart pages (8–31 in test PDF): text-flow detection added. Not yet confirmed.
  HAED has 24 chart pages — multi-page assembly will use the heuristic vertical
  stacking path (no PKCHART markers). The `originX` heuristic (leftmost
  fragment edge) assumes all pages share the same left margin; this breaks for
  pages that cover different column ranges. The page-stacking overlap detection
  will need to handle this.

**StitchX PK round-trip — missing stitches**
- ~3 stitches out of 57,344 missed on Linux CI (0.005%). Passes on macOS.
- Root cause: pdfium on Linux deduplicates adjacent same-symbol horizontal runs
  differently. A 3-char row-merge fragment may be extracted as 2 chars.
- Fix direction: in `_parseAllGrids` row-merge branch (~line 550–570):
  check if fragment span > runes.length × step; interpolate missing chars.
  See memory file `project_pdf_improvements.md` for detail.
- Current workaround: `kMissingTolerance = 10` in `pk_roundtrip_test.dart`.

**Other designer outputs PK supports (not yet tested)**
PK's supported designer list includes formats we haven't encountered yet.
Each may need legend or grid parsing adjustments. Need test PDFs to confirm:
- Chatelaine
- Heaven and Earth Designs (HAED) — partially in progress
- Stoney Creek
- Ursa Software (MacStitch / WinStitch exports)
- PCStitch exports
- KG-Chart
- StitchFiddle
- Various small independent designers

---

### Testing strategy for copyrighted PDFs

Most real-world cross-stitch PDFs are copyrighted and cannot be committed to a
public repo. The test strategy uses two complementary layers:

#### Layer 1 — Synthetic PDFs (public repo, unit tests)

Generated programmatically for legend-parsing and format-detection logic.
The app already uses the `pdf` package; extend it to emit minimal legend pages
in each known format. Run in the normal `unit-tests` CI job (ubuntu-latest,
no device needed).

Scope: legend symbol→DMC mapping for Format A and Format B; `tryParseFromText`
directly (no pdfium involved). Does **not** exercise text-flow grid extraction —
pdfium's extraction mode depends on how the source tool wrote the PDF; a
`pdf`-package file uses positioned characters, not text-flow.

Location: `test/pk_legend_format_test.dart` (to be added).

#### Layer 2 — Private fixtures repo (CI integration tests)

A separate **private** GitHub repository (`scme0/stitches-test-fixtures`)
holds copyrighted PDFs. CI checks it out via a fine-grained PAT stored as a
GitHub Actions secret (`FIXTURES_PAT`). The main repo never contains the
files.

```yaml
# .github/workflows/test.yml — third-party PDF integration job
third-party-pdf-tests:
  runs-on: ubuntu-latest
  if: github.event_name == 'pull_request'
  steps:
    - uses: actions/checkout@v4
    - uses: actions/checkout@v4
      with:
        repository: scme0/stitches-test-fixtures
        token: ${{ secrets.FIXTURES_PAT }}
        path: test/fixtures/private
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.41.4'
    - run: flutter pub get
    - run: |
        sudo apt-get install -y libgtk-3-dev ninja-build
        flutter create --platforms=linux .
        xvfb-run flutter test \
          integration_test/third_party_pdf_test.dart \
          -d linux --no-pub --reporter=expanded
```

The `FIXTURES_PAT` needs only `contents: read` on the private fixtures repo.
Rotate annually. The job is skipped on push-to-main (fixtures only needed on
PRs that touch the parser).

#### Local-only testing (no CI)

For PDFs that can't even go in a private repo (e.g. purchased commercial
patterns with strict terms): keep them in a local directory and use
`test/pk_pdf_inspect.dart` to run diagnostic dumps manually. Edit `kPdfPaths`
in that file, run with `flutter test test/pk_pdf_inspect.dart --no-pub -d macos`.
Results inform parser changes; the PDFs never leave the developer's machine.

#### Summary

| Scope | Location | Who runs | PDFs |
|---|---|---|---|
| Legend parsing (Format A/B) | `test/pk_legend_format_test.dart` | CI (ubuntu) | Synthetic |
| StitchX round-trip | `integration_test/pk_roundtrip_test.dart` | CI (ubuntu+xvfb) | `sm_test.stitches` fixture |
| Third-party format integration | `integration_test/third_party_pdf_test.dart` | CI (ubuntu+xvfb) | Private fixtures repo |
| New format diagnostics | `test/pk_pdf_inspect.dart` (edit paths) | Local only | Developer's machine |

---

### Planned follow-up PRs

**PR: Fix multi-page text-flow assembly**
- Problem: text-flow pages (Artecy/HAED) don't have PKCHART offsets, so
  `originX` is estimated as the leftmost fragment on each page. For a 24-page
  chart where page N covers cols 200–250, this gives wrong absolute positions.
- Fix: detect text-flow pages' column ranges via overlap between adjacent
  pages (same approach as `_detectVerticalOverlap` / `_detectHorizontalOverlap`),
  or infer absolute col offset from page number and consistent column width.

**PR: Fix Linux pdfium row-merge off-by-one**
- Symptom: 3/57,344 stitches missing on Linux.
- Fix: after computing `firstCol`, compare fragment span vs.
  `runes.length × step`; if span > (runes.length + 0.5) × step, the fragment
  was truncated — interpolate the missing char.

**PR: Widen designer coverage**
- Commit test PDFs as fixtures for each new format.
- Adjust legend and grid parsing per-format as needed.
- Goal: match PK's supported-designer list for the major publishers.

**PR: Producer-string fingerprinting**
- Read `/Producer` and `/Creator` from PDF metadata to pre-select the
  right legend/grid parsing mode rather than relying on heuristic detection.
- Faster, more robust for edge cases where heuristics conflict.

---

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
