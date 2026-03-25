# StitchX

> Built with the assistance of AI tools (Claude Code / Anthropic Claude).

A cross-stitch pattern editor for macOS, iOS, and Android. StitchX lets you design and edit counted cross-stitch patterns using DMC thread colors, with a touch- and Apple Pencil-friendly canvas.

## Features

### Pattern editing
- **Pattern canvas** — draw full stitches, half stitches (forward `/` and backward `\`), quarter stitches, and backstitches on a scalable grid
- **DMC / Anchor color palette** — searchable library of ~300 DMC thread colors with Anchor cross-reference numbers; toggle between DMC and Anchor codes in Settings
- **Undo / redo** — full history stack (up to 200 steps); double-tap to undo on touch devices
- **Zoom & pan** — pinch-to-zoom, scroll-wheel zoom, drag to pan; zoom range 0.1×–20×
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
- Color picker (sample a stitch's thread)
- Selection (rubber-band, copy, paste, delete regions); paste opacity slider blends colours with the canvas via CIE Lab nearest-DMC lookup

### Snippets
- **Per-pattern snippet library** — save any selection or clipboard as a named snippet stored inside the `.stitchx` file
- **Snippet panel** — slide-up panel showing all snippets as thumbnails; tap to enter paste mode, long-press or tap ⋮ for rename / resize / edit / delete
- **Snippet editor** — full canvas editor for drawing a snippet from scratch, with preset sizes (8×8 up to 64×64) or a custom size; paste any other snippet from the library directly onto the canvas via the toolbar
- **Save as snippet** — one-tap save of the current selection or paste clipboard to the snippet library; unnamed by default, rename anytime
- **Sprite sheet importer** — open any sprite sheet image, select a tile or crop a region, pixel colours matched to nearest DMC thread via CIE Lab colour space; output saved directly as a snippet

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
- **Block mode** — renders all stitches as solid coloured rectangles instead of X-shapes; half stitches occupy half the cell, quarter stitches a quarter cell. Makes it easy to read the overall colour distribution of a design. Toggle in the ⋮ overflow menu. In stitch mode, symbols remain visible when zoomed in; in design mode the view stays clean.
- **Zoom-adaptive rendering** — below a zoom threshold, stitches automatically switch to block rendering; backstitches and grid lines fade out at very low zoom

### Platform & input
- **Multi-platform** — macOS, iOS, Android
- **Apple Pencil** — hover preview shows the cell under the pencil before touching; double-tap toggles draw/erase mode
- **Touch** — rubber-band selection, copy/paste, and pan all work with finger on iPad
- **Stitch mode** — simplified read-only view for stitching from a finished pattern; accessible via a floating action button; keep-screen-on option
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

### Improvements & polish

1. ~~**Canvas performance**~~ ✓ — `CanvasPainter` split into a static layer (stitches + grid, RepaintBoundary-cached) and a lightweight overlay layer (cursor, ghost stitches, selection rect), plus viewport culling, grid-line path batching, zoom-adaptive rendering, and frame coalescing. Fixes choppiness on large patterns (256×220+).

2. ~~**Resize snippets**~~ ✓ — "Resize…" in the snippet ⋮ menu. Three modes: *Clip* (trim stitches outside new bounds), *Scale* (proportionally remap all stitch positions), and *Expand* (change declared size, keep all stitches). Supports undo.

3. ~~**Paste opacity / colour blend**~~ ✓ — opacity slider (5–100%) appears in the toolbar during paste mode. Ghost stitches render at the chosen opacity. On stamp at < 100%, each stitch's colour is linearly blended with the background (existing stitch or aida) then snapped to the nearest DMC colour via CIE Lab distance matching.

4. ~~**Block view**~~ ✓ — toggle in the ⋮ overflow menu renders all stitches as solid coloured rectangles. Half stitches draw as half-cell rects, quarter stitches as quarter-cell rects. In stitch mode, symbols remain visible when zoomed in. In design mode, the view stays clean with no symbols.

5. ~~**Images in folder view**~~ ✓ — `.png`, `.jpg`, `.gif`, `.bmp`, `.webp` files appear in the workspace folder tree with an image icon. Tap to view inline in the canvas area (pinch/scroll to zoom). Right-click → "Import as Sprite Sheet" when a pattern is open; for Google Drive images the file is downloaded to a local cache first. Sidebar PDF and image visibility can be toggled independently via header icon buttons. Sidebar width is now draggable and persisted.

6. ~~**Snippet colour palette**~~ ✓ — each snippet card in the panel shows a row of 8 px colour dots (up to 12; "+N" if more) derived from its thread list. Purely informational — no interaction required.

7. ~~**Colour replacement**~~ ✓ — long-press any thread row in the palette dialog to get a "Replace colour…" action. Opens the colour picker in replace mode; selecting a new DMC colour remaps every stitch of the old colour to the new one, merging palette entries if the target colour is already in use. Preserves the thread's symbol. Pushes an undo step. Works identically in the snippet editor (via its isolated `editorProvider`).

8. **Thread count in palette** — palette shows stitch count per thread and a total at the top (e.g. "14 colours · 3,240 stitches"). Optionally shows estimated thread length (full stitch ≈ 45 cm).

9. **Edge snapping for paste** — hold **Shift** while positioning a paste/snippet ghost to snap its edges to the canvas boundary (left, right, top, bottom, or centre). Separate from Ctrl (multi-stamp).

10. ~~**Snippets from snippets**~~ ✓ — while editing a snippet, a `library_add_outlined` button appears in the toolbar (same slot as the snippets button on the main canvas) when sibling snippets exist. Tapping it opens a picker sheet showing all other snippets as thumbnails; tap one to enter paste mode with it as the clipboard on the snippet canvas.
