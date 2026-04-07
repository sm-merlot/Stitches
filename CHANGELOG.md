# Changelog

## 0.5.0

### Minor Changes

- ac6935d: Bump `file_picker` from 10.3.10 to 11.0.1

  A package that allows you to use a native file explorer to pick single or multiple absolute file paths, with extension filtering support.

- 29a3f2f: feat: open .stitches files directly from Finder, Files app, and Android file managers

  Double-clicking (or tapping) a `.stitches` file in the OS now opens it straight into the editor. Works on macOS (Finder double-click, AirDrop), iOS/iPadOS (Files app, AirDrop, Mail attachments), and Android (any file manager). Handles both cold-start (app not running) and warm-start (file opened while app is already running).

- 29a3f2f: feat: open folders with the app on macOS, iOS, and Android

  Folders can now be opened directly into the workspace view from the OS. On macOS, drag a folder onto the dock icon or use "Open With" in Finder. On iOS, use "Open With" from the Files app. On Android, open a folder from a file manager (primary storage; cloud provider URIs are not supported).

- 951c2cb: Create v2 of .stitches file format which better separates concerns. Add automatic and silent upgrader when reading v1 files.
- e98a38f: Home screen uplift: rich recents list with thumbnails, unified local and Drive pickers, and workspace improvements.

  - Recent files and folders shown on the home screen with pattern thumbnails; most-recently-opened appears on top in folder thumbnail strips
  - Folder items show a stacked thumbnail strip drawn from their contents; Drive folder strips populate in the background at launch without requiring a workspace visit
  - Files opened inside a workspace folder do not appear as standalone recent items — the folder entry is the canonical recent with its strip
  - Local "Open" picker uses a single macOS NSOpenPanel to select either a file or folder with no separate buttons
  - Google Drive picker unified into a single browser — navigate folders and tap a file to open it, or press "Open This Folder" to open as a workspace; no separate file/folder buttons
  - macOS file-open channel now registered in `awakeFromNib` (FlutterViewController guaranteed available) fixing a `MissingPluginException` on first launch
  - Workspace background thumbnail scan is now recursive (local and Drive), picking up files in subdirectories
  - Type badges on recents thumbnails: cloud icon for Drive items, folder icon for folder workspaces
  - New unsaved desktop patterns show a red "not saved" icon instead of a spinning sync indicator; navigate-away dialog clarifies the pattern hasn't been saved and offers "Save As…"

- 9642d33: Add page mode to stitch view: split patterns into configurable pages with optional fuzzy edges that snap to natural colour changes. Navigate via on-screen arrows, page indicator (tap for grid), or keyboard arrow keys.
- 4ab0cc8: Add stitch progress tracking in Stitch mode: tap to mark individual stitches done, drag to mark a region, and double-tap to flood fill all connected stitches of the same colour. Progress is saved with the pattern file.

  - Progress bar shows stitches done / total, percentage, pages done (page mode), and colours completed
  - Undo/redo buttons in the progress bar for progress operations (separate from pattern edit undo)
  - Colour completion toast when all stitches of a thread are marked done
  - Double-tap flood fill is a single undo step (not two)
  - Page mode: marking and flood fill constrained to the current page only
  - Page position remembered between sessions: re-opening a file in Stitch mode returns to the last active page (only when page mode is on and progress has started)
  - Share / Export .stitches: optional checkboxes to strip progress data and/or page settings from the exported file

- b69b33f: Unified Share and Export with support for all four formats from a single entry point.

  - Share button (iOS, Android, macOS) and Export button are now direct app bar actions — no overflow menu
  - Both Share and Export support `.stitches`, `.oxs`, `.pdf`, and `.png`
  - Export to Drive-backed files shows the Drive folder picker; includes a "Save to local storage" escape hatch
  - Export to local files opens the native save dialog with the current file's folder pre-selected
  - Non-native files (`.oxs`, etc.) open in read-only view mode with a "Convert to .stitches" banner; if the `.stitches` sibling already exists, shows "Open .stitches" instead
  - App bar overflow menus removed — Reference Image and Resize Aida are direct icon buttons in Edit mode

- 009ee20: Replace the two-mode design/stitch toggle with three purposeful modes: View (default, read-only overview), Edit (full pattern editor), and Stitch (active stitching session). Files now always open in View mode — no accidental edits or progress marks.

  - File sidebar is now View-mode only — slides out of the way in Edit and Stitch so the canvas always has full focus
  - Sidebar slides as an overlay so the canvas grid never moves or resizes
  - Block mode toggle moved into the AppBar title area, consistent across all three modes
  - Dirty-dot removed from title; replaced with a persistent save state indicator — spinner while saving, cloud icon (Google Drive) or checkmark (local) when saved; Drive indicator shows immediately on first edit
  - Demo button moved to the colours sidebar; enabled only when stitches are selected on the canvas
  - Focus mode greying now applies in all three modes, not just Stitch

### Patch Changes

- a6a4c9c: fix: DMC color list — auto-retire discontinued colors in monthly sync

  The monthly GitHub Action that keeps the DMC color list current now automatically removes colors absent from the community source from `dmcColors` and adds placeholder entries to `dmcReplacements`. The resulting PR shows exactly what changed so you can fill in replacement codes before merging, or revert individual entries if the community source is wrong.

  - Removes the AI/Anchor-code lookup from the script and workflow (can be done manually when reviewing the PR)
  - Auto-migration at pattern load skips placeholder entries (empty replacement) until a confirmed replacement is filled in
  - Discontinued codes removed from `dmcColors` in a previous step, plus 9 migration tests

- 2e93108: fix: materials list skein calculation and quarter-skein precision

  Shows skein quantities as fractions (¼, ½, ¾, 1, 1¼…) instead of decimals, and fixes two bugs in the underlying formula:

  - Cross-stitch thread factor corrected to `4 × √2` per stitch (was `4 × √2 × √2 = 8`, doubling the estimate)
  - Strand scaling fixed to be linear — skeins now scale proportionally with strand count (was scaling as strands², so 1-strand was too low and 3-strand too high)

- 82d19a2: refactor: extract StitchCompositor as single source of truth for layer compositing

  Replaces three divergent in-house implementations (canvas painter `_buildBlendMap`, PDF service `_compositeNonBack`, and `computeCompositeThreads`) with a single `StitchCompositor.compute()` that produces a `CompositeResult` in one pass. Fixes stitch double-counting across layers in PDF exports.

## 0.4.0

### Minor Changes

- f8c365e: Google Drive auth overhaul and UX polish

  - Migrate Google Sign-In to v7 SDK on iOS/Android; fix auth state bugs where sign-in button disappeared after sign-out, first sign-in attempt failed, and UI did not update after signing in via Settings
  - Drive recent files now show a warning and are unclickable when not signed in or signed in as a different account
  - Screen lock button in stitch mode redesigned as a visual toggle with lock/unlock icons and primary-colour fill when active; shows a brief toast on touch devices when toggled
  - Fix spurious Google Drive uploads triggered by toggling stitch mode
  - Fix legacy `.stitches` files with `editor:` YAML fields being re-saved unnecessarily on first open
  - Remove block mode toggle from stitch mode AppBar on Android (was appearing on Android only, inconsistent with other platforms)
  - Bump `share_plus` to v12, `google_sign_in` to v7, `font_awesome_flutter` to v11, `wakelock_plus` to v1.5, `package_info_plus` to v9; update Android AGP to 8.12.1 to match share_plus v12 requirements

### Patch Changes

- e51689f: Fix Google Sign-In on Android

  - Register the correct debug keystore SHA-1 (used by Flutter builds via `~/.config/.android`) as an Android OAuth client in GCP; the previously registered SHA-1 was never used by any Flutter build
  - Remove explicit `serverClientId` from `GoogleSignIn.instance.initialize()` on Android — the SDK reads it automatically from `google-services.json`
  - Restore silent sign-in (`attemptLightweightAuthentication`) on app startup

- 17e5799: Fix Windows app icon and confirm Google Drive support on Windows

  - Regenerate Windows app icon as a proper multi-size ICO (16, 24, 32, 48, 64, 128, 256 px) from the source PNG; previously the icon was incorrect
  - Add Windows to `flutter_launcher_icons` config so future icon updates are applied automatically
  - Google Drive sync confirmed working on Windows

- 97fd766: Phone layout polish and quick swatch improvements

  - Compact toolbar buttons and labels on phones (short Drive button, "+" new pattern, etc.)
  - Sidebar mutual exclusion on phones — only one panel open at a time
  - Phone editor toolbar splits into two rows: drawing tools on top, colour controls on bottom
  - Bottom colour row: snippet button left, quick swatches fill right-to-left flush against selected colour, undo/redo right
  - Quick swatch size unified with selected colour swatch (24 px)
  - Fix quick swatch count silently decreasing when switching threads — outgoing thread is now always preserved in history
  - Increase recent thread history cap from 5 to 10
  - Threads not yet added to the pattern now remain visible in quick swatches via DMC database fallback

## 0.3.0

### Minor Changes

- 0e9b3c8: Stitch focus mode: draw an orange perimeter outline around connected groups of focused cells when the thread colour would be hard to see against the unfocused-grey background. Trigger uses CIE Lab ΔE so only near-grey colours are affected; vivid hues are unaffected.
- d824929: Finalise name change from stitchx to stitches
- b94d823: Polish: bug fixes and small features — app rename to Stitches (bundle ID com.scme0.stitches), view position persistence, block mode in stitch mode AppBar, focus mode colour fixes, stitch count corrections, Apple Pencil paste fix.
- c64ad3e: Add materials list / skein calculator

  Shows a shopping bag icon in stitch mode. Opens a materials list with aida count and strand count dropdowns, fabric size, per-thread skein counts, and a share button that exports a plain-text checklist via the native share sheet.

- 3194f07: PDF export improvements: symbol visibility filtering, blended cell colours, composite symbol map, skein calculator, pattern metadata fields, and unit tests covering all new logic.

## 0.2.1

### Patch Changes

- b5ee54a: Fix android gradle configuration for ci

## 0.2.0

### Minor Changes

- 79e5520: iPad & polish improvements: layer group locking, gzip file compression, block mode AppBar toggle, Apple Pencil opt-in paste mode, enlarged touch targets, focus mode fix for multi-layer blended cells, layer blend mode now persisted correctly to file, BackStitch clip boundary fix on snippet resize, and initial unit test suite.

## 0.1.3

### Patch Changes

- a07cefa: Fix gdrive signin on android

## 0.1.2

### Patch Changes

- 9f3a2d8: fix macos build

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

Initial release of Stitches — a free, open-source cross-stitch pattern editor for macOS, iOS, and Android.

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

- Per-pattern snippet library stored inside the `.stitches` file; thumbnails in a slide-up panel; tap to paste, long-press for rename / resize / flip / rotate / edit / delete
- Full snippet editor for drawing from scratch with preset or custom sizes
- Multi-palette snippets with a Palettes tab in the right sidebar; positional slot mapping; new colours drawn on the canvas propagate to all palettes automatically
- Sprite sheet importer — crop a region, match pixels to nearest DMC via CIE Lab, define multiple colour palettes from colour-strip regions; output saved as a snippet

### Files & workspace

- `.stitches` file format (YAML internally)
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

- Convert a printed cross-stitch chart PDF into an editable `.stitches` pattern with no AI or internet connection required
- User-guided symbol sampling and template matching; flagged cells can be reviewed and corrected manually

### Stitch demonstration _(beta)_

- Per-thread animated stitch-order demo with configurable playback speed
- Automatic path planning respecting front/back alternation rules; GIF export
