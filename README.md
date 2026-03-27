# StitchX
> [!NOTE]
> Built with the assistance of AI tools (Claude Code).

A free* and open source cross-stitch pattern editor for Desktop (macOS, Windows), Mobile, and Tablet (iOS, Android). StitchX lets you design and edit counted cross-stitch patterns using DMC (or Anchor) thread colors, with a touch- and Apple Pencil-friendly canvas.
> [!NOTE]
> *may not be free on Apple App Store (when it's eventually published there) to offset the Apple Developer Program fees (99USD/year).

## Features

### Pattern editing
- **Pattern canvas** — draw full stitches, half stitches (forward `/` and backward `\`), quarter stitches, and backstitches on a scalable grid
- **Canvas layers** — named layers with per-layer visibility toggle and opacity slider; layers panel in the right sidebar; stitches scoped to the active layer; reorder layers by drag; layers collapse into a single composite view for printing or export
- **DMC / Anchor color palette** — searchable library of ~300 DMC thread colors with Anchor cross-reference numbers; toggle between DMC and Anchor codes in Settings; threads enter the palette automatically on first stitch and are pruned when the last stitch is erased
- **Symbols** — every palette thread and composite thread gets a unique symbol from a pool of ~180 UTF-8 characters; symbols are stable across save/reload and opacity changes; tap any symbol to reassign it via the symbol picker
- **Undo / redo** — full history stack (up to 200 steps); double-tap to undo on touch devices
- **Zoom & pan** — pinch-to-zoom, scroll-wheel zoom, drag to pan, middle-click drag to pan; zoom range 0.1×–20×
- **Resize canvas** — adjust pattern dimensions after creation
- **Reference image overlay** — import a photo as a semi-transparent overlay on the canvas to trace from; adjustable opacity

### Tools
- Full stitch
- Half stitch (forward / backward)
- Quarter stitch (any corner)
- Half-cell cross / petit point
- Backstitch (tap two grid intersections)
- Navigate (pan without drawing)
- Erase
- Color picker — samples a stitch's thread colour; layer-aware (picks the topmost visible stitch at the tapped cell)
- Selection (rubber-band, copy, paste, delete regions); paste opacity slider blends colours with the canvas via CIE Lab nearest-DMC lookup
- **Fill colour** — 8-connected flood fill; fills all connected cells of the same colour (or empty) with the selected thread `[8]`
- **Fill erase** — 8-connected flood fill erase; removes all connected full stitches of the same colour `[9]`

### Snippets
- **Per-pattern snippet library** — save any selection or clipboard as a named snippet stored inside the `.stitchx` file
- **Snippet panel** — slide-up panel showing all snippets as thumbnails; tap to enter paste mode, long-press or tap ⋮ for rename / resize / flip / rotate / edit / delete
- **Snippet editor** — full canvas editor for drawing a snippet from scratch, with preset sizes (8×8 up to 64×64) or a custom size; paste any other snippet from the library directly onto the canvas via the toolbar; block mode toggle in the AppBar inherits the main canvas state
- **Save as snippet** — one-tap save of the current selection or paste clipboard to the snippet library; unnamed by default, rename anytime
- **Sprite sheet importer** — open any sprite sheet image and crop a region; pixel colours matched to nearest DMC thread via CIE Lab colour space; palette simplification slider merges rare colours; output saved directly as a snippet

### Files & workspace
- **File format** — patterns saved as `.stitchx` files (YAML internally)
- **Folder workspace** — open a local folder as a workspace with a file tree sidebar
- **Google Drive sync** — connect a Google Drive account; patterns auto-save and sync in the background
- **Recent files** — quick access to recently opened files and folders, including Drive items

### PDF pattern scanner *(beta)*
Convert a printed cross-stitch chart PDF into an editable pattern without any AI or internet connection required.

1. **Page selection** — choose which PDF pages contain the legend and the stitch grid
2. **Grid crop** — auto-detect the grid bounds on each page; adjust manually if needed
3. **Pattern dimensions** — enter the stitch count (cols × rows) for the design
4. **Symbol sampling** — tap one or more cells in the grid for each unique symbol and assign the matching DMC thread code; the app builds reference templates from your samples
5. **Template matching** — every cell is compared against the sampled templates using mean absolute pixel difference; cells with ambiguous matches are flagged for manual review
6. **Review** — tap any flagged cell to reassign it; confirm to finish

The resulting pattern is saved automatically as a `.stitchx` file next to the source PDF.

> The scanner works best on clean, high-contrast charts. Backstitches and half-stitches are not extracted (full stitches only in this release).

### Stitch demonstration *(beta)*
- **Animated stitch order** — per-thread step-by-step animation showing exactly how to stitch the pattern, with configurable playback speed
- **Stitch planner** — automatic path planning that determines an efficient stitch order, respecting front/back alternation rules
- **Start cell selection** — tap any cell on the demo canvas to set the stitching start point
- **GIF export** — download the stitch order animation as a GIF file
- **Color-coded passes** — front passes (purple / green), back passes (gold / red / blue) with perpendicular offset rendering so overlapping stitches on the same line are all visible

> The stitch demonstration is in beta. Some pattern shapes may produce incorrect or suboptimal stitch paths.

### View options
- **Block mode** — renders all stitches as solid coloured rectangles instead of X-shapes; half stitches occupy half the cell, quarter stitches a quarter cell. Makes it easy to read the overall colour distribution of a design. Toggle in the ⋮ overflow menu (main canvas) or the AppBar (snippet editor). In stitch mode, symbols remain visible when zoomed in; in design mode the view stays clean.
- **Zoom-adaptive rendering** — below a zoom threshold, stitches automatically switch to block rendering; backstitches and grid lines fade out at very low zoom

### Platform & input
- **Multi-platform** — macOS, iOS, Android
- **Apple Pencil** — hover preview shows the cell under the pencil before touching; double-tap toggles draw/erase mode
- **Touch** — rubber-band selection, copy/paste, and pan all work with finger on iPad
- **Stitch mode** — simplified read-only view for stitching from a finished pattern; accessible via a floating action button; keep-screen-on option; composite thread palette shows the actual blended DMC colours produced by layer opacity settings, each with a unique symbol
- **Keyboard shortcuts** — full shortcut set on desktop and in snippet editor (undo, redo, tool switching, modes); `?` opens shortcut reference
- **PDF viewer** — view reference PDFs alongside the pattern canvas
- **Image viewer** — view `.png`, `.jpg`, `.gif`, `.webp`, and other image files inline in the canvas area; click any image in the sidebar to open it, click another to switch instantly
- **Resizable sidebar** — drag the sidebar edge to any width between 160–480 px; width is remembered between sessions
- **Sidebar type filters** — toggle PDF and image visibility in the folder tree independently; settings are persisted

## Getting Started

```bash
flutter run -d macos
```

Requires Flutter 3.41.4+.

## Roadmap

- **Proton Drive sync**
- **Snippet multi-palette** — multiple named colour palettes per snippet, switchable via dots in the snippet panel or the palette manager in the snippet editor; sprite importer extended with a palette-strip selection tool to import multiple palettes directly from a sprite sheet

### Improvements & polish

1. ~~**Canvas performance**~~ ✓ — `CanvasPainter` split into a static layer (stitches + grid, RepaintBoundary-cached) and a lightweight overlay layer (cursor, ghost stitches, selection rect), plus viewport culling, grid-line path batching, zoom-adaptive rendering, and frame coalescing. Fixes choppiness on large patterns (256×220+).

2. ~~**Resize snippets**~~ ✓ — "Resize…" in the snippet ⋮ menu. Three modes: *Clip* (trim stitches outside new bounds), *Scale* (proportionally remap all stitch positions), and *Expand* (change declared size, keep all stitches). Supports undo.

3. ~~**Paste opacity / colour blend**~~ ✓ — opacity slider (5–100%) appears in the toolbar during paste mode. Ghost stitches render at the chosen opacity. On stamp at < 100%, each stitch's colour is linearly blended with the background (existing stitch or aida) then snapped to the nearest DMC colour via CIE Lab distance matching.

4. ~~**Block view**~~ ✓ — toggle in the ⋮ overflow menu renders all stitches as solid coloured rectangles. Half stitches draw as half-cell rects, quarter stitches as quarter-cell rects. In stitch mode, symbols remain visible when zoomed in. In design mode, the view stays clean with no symbols.

5. ~~**Images in folder view**~~ ✓ — `.png`, `.jpg`, `.gif`, `.bmp`, `.webp` files appear in the workspace folder tree with an image icon. Tap to view inline in the canvas area (pinch/scroll to zoom). Right-click → "Import as Sprite Sheet" when a pattern is open; for Google Drive images the file is downloaded to a local cache first. Sidebar PDF and image visibility can be toggled independently via header icon buttons. Sidebar width is now draggable and persisted.

6. ~~**Snippet colour palette**~~ ✓ — each snippet card in the panel shows a row of 8 px colour dots (up to 12; "+N" if more) derived from its thread list. Purely informational — no interaction required.

7. ~~**Colour replacement**~~ ✓ — long-press any thread row in the palette dialog to get a "Replace colour…" action. Opens the colour picker in replace mode; selecting a new DMC colour remaps every stitch of the old colour to the new one, merging palette entries if the target colour is already in use. Preserves the thread's symbol. Pushes an undo step. Works identically in the snippet editor (via its isolated `editorProvider`).

8. ~~**Thread count in palette**~~ ✓ — palette header shows "N colours · M stitches". Each thread row shows its stitch count. Threads added to the palette but not used are flagged "unused".

9. ~~**Edge snapping for paste**~~ ✓ — hold **Shift** while positioning a paste/snippet ghost to snap its edges to: (a) the canvas boundary (left, right, top, bottom, centre); (b) the nearest same-colour stitch in each axis — if any clipboard thread colour exists on the canvas, the ghost snaps so its edge butts flush against the closest same-colour stitch in the drag direction. X and Y axes snap independently so corner placement always works correctly. Separate from Ctrl (multi-stamp).

10. ~~**Snippets from snippets**~~ ✓

11. ~~**OXS import/export**~~ ✓ — import and export WinStitch/MacStitch `.oxs` format (open XML-based cross-stitch format). Further format support planned: Pattern Maker (`.xsd`), PC Stitch (`.pat`), and others.

12. ~~**Rename "Done" → "Close"**~~ ✓ — sprite sheet importer AppBar dismiss button renamed to "Close". Pattern scanner "Done" buttons advance wizard steps and are unchanged.

13. ~~**Canvas layers**~~ ✓ — named layers with per-layer visibility and opacity; layers panel in the right sidebar; stitches scoped to the active layer; composite thread view in stitch mode with stable unique symbols; layer-aware colour picker; thread auto-registration (threads enter palette on first stitch, pruned on last erase); symbol pool extended to ~180 UTF-8 characters; freed composite symbols recycled to newly-appearing colours when opacity changes.
