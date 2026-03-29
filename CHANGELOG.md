# Changelog

## 0.1.1

### Patch Changes

- f46b748: Fix builds for all platforms

## 0.1.0

### Minor Changes

- 0981f9d: add github actions build pipeline

<!--
  For major version releases (x.0.0), add a hand-written summary section at
  the top of the release entry before merging the "Version Packages" PR.
  Curate the highlights from the preceding minor/patch cycle into a short
  narrative — the individual changeset entries will follow below it as usual.
-->

## 0.0.1

Initial release of StitchX — a free, open-source cross-stitch pattern editor for macOS, iOS, and Android.

### Pattern editing

- Draw full stitches, half stitches (forward `/` and backward `\`), quarter stitches, half-cell cross / petit point, and backstitches on a scalable grid
- Named canvas layers with per-layer visibility, opacity slider, drag-to-reorder, and collapsible named groups; composite view for printing or export
- DMC and Anchor colour palette — searchable library of ~300 DMC thread colours with Anchor cross-reference; threads enter the palette on first stitch and are pruned when erased
- Every thread gets a unique symbol from a curated pool of ~175 UTF-8 characters; long-press any thread row in the Colours panel to reassign via the symbol picker, or type any custom character directly
- Full undo / redo history (up to 200 steps) covering canvas stitches and palette assignments; double-tap to undo on touch devices
- Pinch-to-zoom, scroll-wheel zoom, and drag-to-pan; zoom range 0.1×–20×
- Resize the canvas after creation
- Semi-transparent reference image overlay with adjustable opacity

### Tools & selection

- Erase tool with size picker 1–10 (N×N box); hover preview; flood-erase sub-option for connected same-colour stitches
- Colour picker — samples the topmost visible stitch at the tapped cell
- Rubber-band selection with copy, paste, delete, flip (H/V), and rotate; paste opacity blends colours via CIE Lab nearest-DMC lookup
- Canvas mode toggle on selection — operates across all visible layers instead of only the active layer; applies to copy, move, delete, flip, rotate, and save-as-snippet
- Flood fill — 8-connected fill of same-colour or empty cells
- Block mode — renders all stitch types as solid coloured rectangles for an at-a-glance colour read

### Snippets

- Per-pattern snippet library stored inside the `.stitchx` file; thumbnails in a slide-up panel; tap to paste, long-press for rename / resize / flip / rotate / edit / delete
- Full snippet editor for drawing from scratch with preset or custom sizes
- Multi-palette snippets with a Palettes tab in the right sidebar; positional slot mapping; new colours drawn on the canvas propagate to all palettes automatically
- Sprite sheet importer — crop a region, match pixels to nearest DMC via CIE Lab, define multiple colour palettes from colour-strip regions; output saved as a snippet

### Files & workspace

- `.stitchx` file format (YAML internally)
- Folder workspace with a resizable file tree sidebar (160–480 px); PDF and image visibility toggles persist between sessions; toggling a filter only deselects the current item if it is of the filtered type
- Google Drive sync — connect an account; patterns auto-save and sync in the background
- Recent files list including Drive items

### View & platform

- Right sidebar (140–350 px, collapsible) with Layers and Colours tabs; Colours tab sorted in DMC or Anchor number order; Canvas / Layer toggle; stitch counts per thread
- Zoom-adaptive rendering — auto-switches to block rendering below a zoom threshold; backstitches and grid lines fade at very low zoom
- Stitch mode — simplified read-only view for stitching from a finished pattern; floating toggle button; keep-screen-on control
- Apple Pencil hover preview and double-tap draw/erase toggle
- Full keyboard shortcut set on desktop; `?` opens the shortcut reference
- PDF viewer and image viewer (PNG, JPG, GIF, WEBP) inline in the workspace

### PDF pattern scanner _(beta)_

- Convert a printed cross-stitch chart PDF into an editable `.stitchx` pattern with no AI or internet connection required
- User-guided symbol sampling and template matching; flagged cells can be reviewed and corrected manually

### Stitch demonstration _(beta)_

- Per-thread animated stitch-order demo with configurable playback speed
- Automatic path planning respecting front/back alternation rules; GIF export
