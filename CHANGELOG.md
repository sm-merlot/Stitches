# Changelog

## 0.7.0

### Minor Changes

- c51f671: allow user to pass explicit stitches to generate gif
- 66d71c0: Smarter fuzzy page edges: 2D floodfill scoring and vertical column detection to avoid stranding colour islands and produce consistent vertical boundaries
- 29cd74b: ## Time tracking in StitchOps

  Track how long you spend stitching, right inside StitchOps.

  ### Timer

  A **Timer** button appears in the stitch-mode right sidebar (below Mark and StitchDemo). Tap it to start a session; the button counts up live (`MM:SS` / `HH:MM:SS`) and turns highlighted while running. Tap again to stop — the elapsed time is saved to that day's log entry automatically.

  The timer survives device sleep and app kills: the session start time is persisted to `SharedPreferences` and restored on next launch. Sessions older than 24 hours are discarded as stale.

  ### Time section in StitchOps

  A new **Time** card appears in StitchOps whenever any stitching has been logged:

  - **Total** — all recorded stitching time across the project's lifetime
  - **Today** / **Week** — rolling totals
  - **Stitches / hour** — overall efficiency derived from logged time

  ### Manual time adjustment

  A pencil icon in the Time card header opens the **Edit time history** dialog. Every day with stitching activity is listed (newest first, with Today always at the top), each with editable **h** and **m** fields. Only changed entries are saved on confirm. Useful for correcting sessions where the timer was left running, or for retroactively logging time for days the timer wasn't used.

  StitchOps updates immediately after saving — no need to close and reopen the dialog.

  ### Persistence

  Time is stored as a `minutes:` field on each `progressLog` entry in the `.stitches` file. Existing files load fine; the field is omitted when zero.

### Patch Changes

- aa52d2a: fix copty selection when "selecting from all visible layers" is enabled.
- a42e79e: Add a tooltip that appears while dragging a selection or progress region, showing the selection size (W × H) and the from/to cell coordinates. The tooltip positions itself in the corner matching the drag direction.
- 26252fc: In stitch mode with page mode enabled, add an "All / Page" toggle to the Colours panel. When "Page" is selected, only threads that have stitches on the current page are shown, with counts scoped to that page. Uses the composite (flattened) cache for full stitches so only the topmost visible colour per cell is counted. The toggle is hidden in view mode and when page mode is not active.
- 4bbe7cb: Close the test coverage gap: add 350 unit/widget tests and 4 integration smoke tests across T1–T5.

  **T1** – File format round-trip: v2 `.stitches` full round-trip, compressed/uncompressed paths, unknown-YAML-key safety, legacy v1 fixture

  **T2** – EditorNotifier core: all stitch types, erase modes, layer CRUD, mode switching, undo/redo (200-step cap), thread management, progress marking, metadata

  **T3** – EditorNotifier remainder: snippet CRUD/resize/transform/palettes, selection/copy/paste, `saveSelectionAsSnippet`; session service save/restore; progress log edge cases

  **T4** – Pure-Dart services: `color_space`, `dashed_line`, `stitch_geometry`, `snippet_palette_resolver`, `page_layout`, `stitch_renderer`, `SpriteImporter`; widget smoke tests for six screens

  **T5** – Integration tests: four end-to-end flows (draw→save→reload, copy→paste→undo, progress→save→reload, snippet round-trip) using real disk I/O; CI workflow added at `.github/workflows/test.yml`

  All 350 `flutter test` tests pass in ~6 s. Integration tests run separately: `flutter test integration_test/ -d macos`.

## 0.7.0

### Patch Changes

- 0c19d73: Fix "select all visible layers" copy picking up stitch from occluded/transparent layers and missing stitches from the topmost visible layer.

  **Before:** canvas-mode copy iterated every visible layer independently, so cells covered by multiple layers produced duplicate stitches in the clipboard (lower-layer stitches that are visually hidden behind upper layers were included), and layers with `opacity: 0` but `visible: true` were incorrectly included too.

  **After:** `copySelection` and the `selectedStitches` getter now use the compositor's `dedupedNonBack` + `backstitches` result — the same deduplicated, opacity-aware stitch list that drives canvas rendering. One stitch per occupied cell (topmost visible normal-blend opaque layer wins), all visible backstitches included, opacity-zero layers naturally excluded. Falls back to the previous raw-layer iteration when the composite cache is absent.

## 0.6.0

### Minor Changes

- b5330a1: Use distinct icon for B&W toggle in stitch mode (`invert_colors`) vs realistic toggle in edit/view mode (`grid_view`). Default to B&W mode when entering stitch mode.
- 357fd67: Add colour list sort options to the sidebar. Threads can now be sorted by colour ID (DMC/Anchor) or by stitch count. In stitch mode, a toggle allows pushing fully-completed colours to the bottom of the list. Both preferences persist across sessions.
- f6e12b8: update navigation: quit to home = x + warning, exit stitch or edit mode = <- (back arrow)
- 13842c6: Internal refactor: structural splits to make large files more navigable.

  - New `lib/widgets/canvas_viewport.dart` — `CanvasViewport` value type encapsulating pan/zoom/cell-size math (screen↔canvas↔cell transforms, viewport culling, focal-point zoom). Replaces inline transform math in `pattern_canvas.dart` and `canvas_painter.dart`.
  - `EditorState` extracted from `lib/providers/editor/editor_provider.dart` into its own `editor_state.dart` part file (~340 lines moved out, main provider drops from ~990 → ~660 lines).
  - `lib/services/pdf_service.dart` (1923 lines) split into 5 focused part files under `lib/services/pdf/`: `pdf_chart.dart`, `pdf_color_table.dart`, `pdf_title_page.dart`, `pdf_markdown.dart`, `pdf_helpers.dart`. `PdfService` class now ~365 lines containing only orchestration (`buildPdfBytes`, `exportPattern`) plus the test helper.

  Pure refactor — no behaviour changes.

- 1ecdece: Internal refactor: extract dialog helpers and remove confirm/input boilerplate.

  - New `lib/widgets/dialogs/confirm_dialog.dart` — `confirmDestructive()` helper consolidating 6 inline AlertDialog destructive prompts (delete file/folder/layer-group/palette, clear progress, clear recent).
  - New `lib/widgets/dialogs/input_dialog.dart` — `inputDialog()` helper consolidating 3 single-text-field rename prompts (file/folder/snippet), with an `allowEmpty` flag preserving the snippet "leave empty for no name" behaviour.
  - New `lib/widgets/dialogs/dmc_picker_dialog.dart` — extracted shared `DmcPickerDialog` widget, de-duplicating two of three local copies (palettes panel + snippet dialogs).
  - Removed `docs/refactor-plan.md` — multi-phase refactor tracker is now obsolete.

  The phase-3 `StitchRenderer` abstraction was investigated and intentionally skipped: the three rendering sites share switch structure but differ on graphics API, coordinate system, and detail level — an interface would formalize the relationship without removing code.

  Pure refactor — no behaviour changes.

- 31ae406: Remove realistic stitch rendering from canvas — always render blocks. Rename `blockMode` to `colourMode` (B&W default in stitch mode, colour toggle on). Add "Realistic stitches" checkbox to PDF/PNG export dialog. Improve realistic rendering with lens-shaped threads (thicker in middle) and thinner backstitches.
- 2ea2c1b: Add StitchOps: in-depth stitching progress analytics

  A new **StitchOps** screen gives you detailed insight into your stitching progress, accessible via the chart icon in the toolbar (view mode and stitch mode).

  **Per-pattern stats**

  - Overview: completed / total / remaining stitch count with a progress bar, started date, and last-active date
  - Velocity: stitches completed today, this week, this month, and this year
  - ETA: estimated completion date based on your recent 14-day rate, plus average stitches per active day
  - Daily bar chart: last 60 days of per-day stitch counts with month labels
  - Cumulative line chart: overall progress curve over the lifetime of the project
  - Activity heatmap: 16-week GitHub-style contribution grid
  - Thread breakdown: per-DMC-colour progress bars and counts, sorted by size
  - Interactive hover tooltips on all charts (desktop/mouse)

  **Workspace stats**
  A second chart icon appears in the workspace toolbar when no file is open. It scans every `.stitches` file in the workspace (local or Google Drive) and shows a combined view across all patterns:

  - Total patterns, how many are complete, overall stitch count and completion percentage
  - Combined velocity (today / week / month / year) across all patterns
  - Current and longest stitching streak 🔥
  - Daily bar chart, cumulative line chart, and activity heatmap — aggregated across every pattern
  - Per-pattern list sorted by recent activity, with individual progress bars
  - **Pattern filter**: tap the filter icon to show checkboxes on each pattern row; toggle individual patterns in or out to focus the aggregate stats on a specific subset. "Select all / Select none" for quick bulk changes.
  - Google Drive workspaces cache downloaded files on first open — subsequent loads are instant

  **How progress history is tracked**
  Each time you mark stitches done, the app records a daily high-watermark entry (date + cumulative stitch count) in the pattern file. The log lives outside the undo stack, so undoing stitches never erases your history. The log is stripped when exporting or sharing a pattern so personal stitching history stays private.

- 018f046: Remove block mode from stitch mode and clean up colouring/styling in focus mode

### Patch Changes

- cc979d8: Fix canvas interaction bugs: grid lines fade out smoothly at low zoom (raised thresholds + alpha ramp), move YAML serialization to isolate so auto-save no longer blocks stitch marking, widen double-click window to 500ms, and add backstitch chain mode (Ctrl on desktop, toggle button on touch).
- 84ff3e4: Fix issue where deselection by clicking would also mark stitch on canvas.
- 3af1b18: Fix copy-paste functionality with view mode and other documents.
- 45a3f70: Bump `file_picker` from 11.0.1 to 11.0.2

  A package that allows you to use a native file explorer to pick single or multiple absolute file paths, with extension filtering support.

- 104cdb0: fix issue where layers don't merge correctly after changing layer and layer group visibility.
- 84a4900: Use the cross-stitch term "Frog" instead of "Unmark" for undoing completed stitches. "Frogging" is the widely used community term for ripping out stitches, so this makes the UI feel more natural to stitchers.
- abaf7ae: ensure pan and zoom gestures don't mark stitches as done in stitche mode.
- a1c8782: Internal refactor: extract shared utilities to reduce duplication.

  - New `lib/services/color_space.dart` consolidates 3 copies of CIE Lab conversion + ΔE distance, plus a `nearestLabIndex` helper.
  - New `lib/services/dashed_line.dart` consolidates 3 copies of dashed-line drawing into a Flutter-free segment iterator.
  - New `lib/models/stitch_geometry.dart` consolidates the duplicated `stitchXY` helper.
  - `canvas_painter.dart` block-mode rendering: collapsed two ~70-line stitch→rect switches into a single `_stitchToBlockRect` helper.

  Pure refactor — no behaviour changes.

- a1ba698: fix remaining stitch counts when marking stitches as done.
- ff6b0f7: ensure drive option is always available even when logged out when clicking "open" on home page.
- ea90b72: Fix several issues with the snippet editor and tighten up the title bar across all three editors.

  **Snippet editor — now renders as an editor instead of a viewer.** The snippet editor wraps itself in a fresh `ProviderScope`, so it inherited `loadPattern`'s default `AppMode.view` — which hid the toolbar and swapped the right sidebar to the Colours-only stitch layout. It now calls `setMode(AppMode.edit)` after load so the toolbar and Palettes/Colours tabs render, and the block-mode toggle has moved from `actions` into the title row (flush against the name) to match the main/workspace editors.

  **Slot-aligned palette symbols and stitch counts.** Symbols belong to the _slot_, not the thread, so every palette shares the primary palette's symbols at each slot index. Switching palettes in the snippet editor now only changes colours, not symbols — and stitch counts are remapped slot-by-slot so secondary palettes show identical numbers to the primary. A new `syncPaletteSymbolsToPrimary` helper is wired into palette init, add-palette, and swap-thread-colour so the invariant holds across all edit paths.

  **`replaceThread` drift fixed.** When the snippet-editor Colours panel swaps a DMC on the primary palette, the change is now mirrored into `snippetPalettes[0]` and the (preserved) slot symbol is fanned back out to every secondary palette. Pattern, primary, and secondaries stay aligned mid-session instead of waiting for save to re-sync.

  **Title bar polish across all three editors.** The pattern-name title in the main and workspace editors is now clamped to 280px with `TextOverflow.ellipsis`, so long names can't push the block-mode button off-screen. The snippet editor's name is a borderless always-on `TextField` (no more tap-to-edit `InkWell`), auto-sized to the text with the same 280px cap. A fixed 8×8 dirty-dot slot at the start of the snippet title row fades in/out without shifting the row, and the Save button is disabled when the snippet has no unsaved changes.

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
