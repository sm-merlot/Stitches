# Refactor Plan — Reduce Duplication & Improve Maintainability

> Tracking doc for a multi-phase refactor of `lib/`. Each phase ships as its own
> branch + PR off `main`. This file is deleted in the final phase.

## Workflow

1. Create branch `refactor/phase-N-<slug>` off `main`
2. Implement the phase
3. Run `flutter analyze` + `flutter test` (export PATH for Homebrew Flutter)
4. Add a Changeset (`patch` for small fixes, `minor` for larger refactors)
5. Open PR, wait for manual test, merge
6. Repeat for next phase

## Phase 1 — Shared utilities (low risk, high payoff) ✅ in progress

Branch: `refactor/phase-1-shared-utils`
Bump: `patch` (pure extraction, one bug fix)

Scope (~440 lines of duplication consolidated):

- **#1 — CIE Lab colour conversion** (~80 lines, 3 sites)
  - Extract to `lib/services/color_space.dart`
  - Replace in:
    - `lib/widgets/canvas_painter_drawing_methods.dart:24` `_labDeltaE()`
    - `lib/services/sprite_importer.dart:46` `_rgbToLab()`
    - `lib/services/grid_cell_scanner.dart:248` `_rgbToLab()` + `_labDist()`

- **#2 — Dashed line drawing** (~90 lines, 3 sites)
  - Extract to `lib/services/canvas_utils.dart`
  - `gif_renderer.dart` uses `image` package — needs separate variant or
    raw-coordinate helper
  - Replace in:
    - `lib/widgets/stitch_demo_painter.dart:277` `_drawDashedLine()`
    - `lib/widgets/sprite_sheet_painter.dart:106` `_drawDashedRect()`
    - `lib/services/gif_renderer.dart:291` `_drawDashedLine()`

- **#3 — Block-mode stitch→Rect switch** (~130 lines, 2 sites in one file)
  - Extract `Rect? stitchToRect(Stitch, cellSize, ...)` helper
  - Replace switches in:
    - `lib/widgets/canvas_painter.dart:534` `_getOrBuildBlockRects()`
    - `lib/widgets/canvas_painter.dart:655` `_drawLayerBlocksWithPageFilter()`
  - **Bug fix:** `canvas_painter.dart:559` has `quarterCell = cellSize * 0.5`,
    should be `* 0.25`

- **#4 — Thread colour matching** (~40 lines core, 3 sites)
  - Extract to `lib/services/thread_matcher.dart`
  - `nearestThreadByRgb` and `nearestThreadByLab`
  - Replace in:
    - `lib/widgets/canvas_painter.dart:83` `_nearestThread()` (RGB)
    - `lib/services/sprite_importer.dart:72` `matchPixel()` (Lab)
    - `lib/services/grid_cell_scanner.dart:139` (Lab in isolate)

- **#5 / #7 — Stitch geometry helpers** (~90 lines, scattered)
  - Extract to `lib/models/stitch_geometry.dart`
  - Symbol/quadrant/half-orient centers from
    `lib/widgets/canvas_painter.dart:849`
  - Geometry helpers from `lib/providers/editor/editor_provider.dart:879+`
    (`_stitchXY`, `_stitchOnPage`)
  - Re-use from `lib/services/pdf_service.dart:438` for symbol placement
    (ensures PDF↔canvas symbol alignment)

## Phase 2 — Structural refactors (medium risk)

Branch: `refactor/phase-2-structure`
Bump: `minor`

- **#6 — Viewport class** (~60 lines)
  - New `lib/models/viewport.dart` encapsulating pan/zoom/cellSize/screenSize
  - `screenToCell` / `cellToScreen` / `isCellVisible` / `visibleCellRange`
  - Replace inline math in `pattern_canvas.dart:320` and
    `canvas_painter.dart:105` + `:731`
  - **Needs gesture regression testing** (pan, zoom, click-to-cell)

- **#11 — Extract `EditorState`** from `editor_provider.dart`
  - Move lines ~76–284 to `lib/providers/editor/editor_state.dart`
  - Drops main provider file from 997 → ~700 lines

- **#10 — Split `pdf_service.dart`** (1923 lines, biggest file in repo)
  - Natural splits: page layout, symbol drawing, legend/key, cover page
  - Likely target: `lib/services/pdf/` directory with focused files

## Phase 3 — Larger refactors (only if pain justifies)

Branch: `refactor/phase-3-abstractions`
Bump: `minor`

- **#9 — Abstract `StitchRenderer`** (~200 lines overlap)
  - Interface with `CanvasStitchRenderer` / `PdfStitchRenderer`
  - Unifies `pdf_service.dart`, `canvas_painter.dart`, `snippet_thumbnail.dart`
  - **Highest risk** — needs visual regression testing for PDF output

- **#8 — Dialog base classes** (~500 lines boilerplate across 12+ files)
  - `ConfirmDialog`, `InputDialog`, `SelectionDialog<T>` in
    `lib/widgets/dialogs/`
  - Refactor incrementally, starting with colour picker
  - Touches: `color_select_dialog.dart`, `editor_toolbar_palette_dialog.dart`,
    `snippet_editor_screen_dialogs.dart` (667 lines),
    `pattern_scan_review_screen.dart` (544 lines), and 8+ others

- **#12 — Hygiene pass**
  - `flutter analyze` for orphaned exports / dead code
  - **Delete this doc** as the final commit of phase 3

## Notes

- Project memory says project lives at `/Users/scottmerchant/dev/stitchx` but
  the actual path is `/Users/scottmerchant/dev/Stitches`. Memory should be
  updated.
- All Flutter commands need `export PATH="/opt/homebrew/bin:$PATH"` first.
