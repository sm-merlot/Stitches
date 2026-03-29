# StitchX
> [!NOTE]
> Built with the assistance of AI tools (Claude Code).

A free* and open source cross-stitch pattern editor for Desktop (macOS, Windows), Mobile, and Tablet (iOS, Android). StitchX lets you design and edit counted cross-stitch patterns using DMC (or Anchor) thread colors, with a touch- and Apple Pencil-friendly canvas.
> [!NOTE]
> *may not be free on Apple App Store (when it's eventually published there) to offset the Apple Developer Program fees (99USD/year).

## Features

### Pattern editing
- **Pattern canvas** — draw full stitches, half stitches (forward `/` and backward `\`), quarter stitches, and backstitches on a scalable grid
- **Canvas layers** — named layers with per-layer visibility toggle and opacity slider; layers panel in the right sidebar; stitches scoped to the active layer; drag to reorder; organise layers into collapsible named groups; add Layer / Group buttons appear inline below the list; layers collapse into a single composite view for printing or export
- **DMC / Anchor color palette** — searchable library of ~300 DMC thread colors with Anchor cross-reference numbers; toggle between DMC and Anchor codes in Settings; threads enter the palette automatically on first stitch and are pruned when the last stitch is erased
- **Symbols** — every palette thread and composite thread gets a unique symbol from a pool of ~180 UTF-8 characters; symbols are stable across save/reload and opacity changes; tap any symbol to reassign it via the symbol picker
- **Undo / redo** — full history stack (up to 200 steps) covering both canvas stitches and palette colour assignments; double-tap to undo on touch devices
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
- **Erase** — size picker 1–10 (erases an N×N box of cells centred on the cursor); hover preview shows the exact cells that will be erased; **fill erase** sub-option flood-erases all connected full stitches of the same colour `[9]`
- Color picker — samples a stitch's thread colour; layer-aware (picks the topmost visible stitch at the tapped cell)
- Selection (rubber-band, copy, paste, delete regions); paste opacity slider blends colours with the canvas via CIE Lab nearest-DMC lookup
- **Flip & rotate** — flip or rotate the active selection, paste clipboard, or full canvas; available in the toolbar and via keyboard shortcuts
- **Fill colour** — 8-connected flood fill; fills all connected cells of the same colour (or empty) with the selected thread `[8]`

### Snippets
- **Per-pattern snippet library** — save any selection or clipboard as a named snippet stored inside the `.stitchx` file
- **Snippet panel** — slide-up panel showing all snippets as thumbnails; tap to enter paste mode, long-press or tap ⋮ for rename / resize / flip / rotate / edit / delete
- **Snippet editor** — full canvas editor for drawing a snippet from scratch, with preset sizes (8×8 up to 64×64) or a custom size; paste any other snippet from the library directly onto the canvas via the toolbar; block mode toggle in the AppBar with visual active state
- **Multi-palette snippets** — each snippet can hold multiple named colour palettes; switch between palettes via the palette manager in the snippet editor or the palette dots in the snippet panel; palettes use positional slot mapping so swapping applies consistently across the whole design; new colours drawn on the canvas propagate to all palettes automatically
- **Save as snippet** — one-tap save of the current selection or paste clipboard to the snippet library; unnamed by default, rename anytime
- **Sprite sheet importer** — open any sprite sheet image and crop a region; pixel colours matched to nearest DMC thread via CIE Lab colour space; define multiple colour palettes by selecting colour-strip regions on the image; background pixels outside the palette are dropped automatically; output saved directly as a snippet; available on tablet and desktop

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
- **Stitch mode** — simplified read-only view for stitching from a finished pattern; toggle via a floating action button (bottom-right); keep-screen-on icon toggle in the AppBar; composite thread palette shows the actual blended DMC colours produced by layer opacity settings, each with a unique symbol
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

## Backlog

### Snippet editor
- Palette editing inside the snippet editor (rename, reorder, manage colours per palette)
- Palette list in the right sidebar (where the layers panel lives in the main editor)
- Hide canvas/layer mode buttons and "drawing on layer X" label — not relevant in the snippet editor
- Warn on close if there are unsaved changes (dirty state)

### Snippet panel
- "Manage palettes" in the snippet ⋮ menu currently opens the snippet editor — clarify intent or provide a dedicated inline palette manager

### Main editor
- Active thread palette in the right sidebar, below the layers/palette list; always visible including in stitch mode
- Remove pan mode — middle-click or two-finger drag handles panning; no dedicated pan tool needed
- Layer mode colour list should only show colours of the currently selected layer, not all layers combined
- Stitch numbers and usage counts are incorrect for composite threads in the canvas-mode palette
- Remove the opacity-layers info icon / tooltip

### Stitch mode
- Remove drawing tools — stitch mode is always in select/read-only mode; middle-click or two-finger drag pans
- Prevent accidental moves — click-and-drag on a selection should not move stitches in stitch mode
- Palette shows incorrect colours — should reflect only composite canvas colours (excluding threads present only in hidden/merged layers)
- Palette list becomes the focus-mode selector
- Stitch visibility/greying controls and demo button move to the palette side panel

### Mobile / tablet
- Review all UI elements for touch-friendliness — check button sizes, tap targets, and layout on small screens

### Snippets
- Snippet palettes: colours should not be auto-pruned when a snippet has multiple palettes (pruning breaks alternate palette slots)

### Files & sync
- `.stitchx` file compression at rest
- Proton Drive support — **on hold, waiting for SDK to mature** (expected 2026). The E2E encryption stack (OpenPGP/GopenPGP key chains) makes an unofficial implementation risky and fragile. When the official SDK ships: if an OpenAPI spec is available, generate a Dart client and wrap it in a service layer (same pattern as `google_drive_service.dart`); if only native iOS/Android SDKs are provided, consider a Flutter plugin. Plan to publish the Proton Drive integration as a standalone Dart package rather than embedding it in the app.
- Extend supported import/export file types (Pattern Maker `.xsd`, PC Stitch `.pat`, others)

### Engineering
- Better test coverage
- Code cleanup and refactoring
- GitHub Actions: automated build, version management, and release publishing
