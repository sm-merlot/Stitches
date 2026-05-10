# Changelog

## 0.12.0

### Minor Changes

- a9aa943: Add global settings access and Google Drive sign-out safety

  - **Settings access**: settings icon added to workspace and editor AppBars; `Ctrl+,` shortcut on Windows/Linux; macOS app menu gains Preferences… item (`Cmd+,`) with full standard menu items
  - **Drive sign-out**: signing out automatically closes any open Drive workspace or file, pops to home, and shows a snackbar
  - **Drive revocation**: mid-session token revocation shows a blocking dialog over the open workspace (keeping it loaded); "Sign in again" transitions to a spinner and re-auths inline; on success the folder listing and open file are refreshed automatically; Cancel/Dismiss closes the workspace and returns to home
  - **Sign-in cancel**: a Cancel button appears next to the spinner in Settings during OAuth so users can abort a stuck sign-in flow
  - **Recent items**: Drive recent items already grey out and disable tap when signed out or signed in as a different account — this now also triggers correctly when a session expires mid-use

### Patch Changes

- 2a375a9: Fix page-mode bugs and middle-click marking; centralise mouse-button filtering

  - **Auto-select page**: opening stitch mode now lands on the first unfinished page (not marked done) instead of always defaulting to page 1
  - **Page colours default**: stitch-mode colour panel now defaults to "Page" filter instead of "All"; segment order swapped so Page is on the left and All on the right
  - **Top-row tap**: tapping or starting a selection in the top rows of a page-mode pattern now works correctly; the nav-zone guard is precise to each button's actual footprint rather than a blanket 56 px strip, so cells alongside or below nav arrows are no longer blocked
  - **Middle-click**: middle mouse button no longer marks stitches in stitch mode or draws in edit mode; the `kMiddleMouseButton` guard is now enforced once in `AidaWidget._onPointerDown` and removed from individual controllers (`EditController`, `SnippetEditController`, `StitchController`), eliminating a class of per-controller omission bugs

- f8829db: Fix selection drag starting new selection, and fix page colour done counts

  - **Selection**: clicking or dragging inside an existing selection now always starts a new rubber-band selection instead of entering move mode
  - **Page colours**: done stitch counts in the page-filtered colour panel now reflect only stitches on the current page, instead of showing global totals against page-scoped totals
  - **Refactor**: gesture recognition (tap, double-tap, drag) is now a shared `GestureHandler` layer; double-tap window reduced from 500 ms to 300 ms to match mobile standard

## 0.11.0

### Minor Changes

- 70a357e: Step 19: Object-aware page boundary algorithm (v2 band-local pipeline)

  - `PageConfig.tolerance` default changed from 4 → 5; backward-compatible YAML migration reads legacy `fuzzyAmount` key
  - `PageLayout` boundary algorithm replaced with v2 band-local pipeline:
    - Phase 1: Extract ±tolerance band around each nominal boundary
    - Phase 2: 8-directional flood-fill detects local objects within band
    - Phase 3: Object classification (keepWhole / keepLeft / keepRight / tooBig) with keep-whole enforcement
    - Phase 4: Anchor detection at colour transitions weighted by adjacent cluster size, with continuity tie-breaking; linear interpolation + deterministic fuzz between anchors
    - Phase 5: Fragment reclamation pulls stranded small objects back to their majority side
    - Corner connectivity post-pass removes cells disconnected from page interior
  - Object classification distinguishes one-sided band extension (keepLeft/keepRight) from both-sided (tooBig), protecting real object edges even when the object extends beyond the band on one side
  - Smoothing removed — interpolation constrains steps to ±2; keep-whole jumps are intentional
  - `_isQualifyingCut` removed from anchor detection — keep-whole + reclamation handles object integrity
  - Page mode dialog: tolerance slider replaced with "Fuzzy edges" on/off switch (tolerance=5 when on, 0 when off)
  - Visual diagnostic test added for real-pattern boundary verification

### Patch Changes

- 8f08856: Fix single-tap stitch unmark ignoring page boundaries

  - `toggleStitchDone` page-mode guard moved before the mark/unmark branch so it applies to both adding and removing completed stitches
  - Previously, tapping a completed stitch on a different page would incorrectly unmark it

## 0.10.0

### Minor Changes

- a62fc1a: Step 8: Introduce AidaWidget, replace PatternCanvas

  - `AidaWidget` (`lib/widgets/aida_widget.dart`) is the new canvas widget; owns viewport state, RenderCache, ZoomPanHandler, and mode controllers
  - `pattern_canvas.dart` reduced to a compat shim (`typedef PatternCanvas = AidaWidget`) for transition; deleted in step 9
  - `editor_canvas_area.dart` and `snippet_editor_screen.dart` updated to use `AidaWidget` directly
  - All `PatternCanvas` references in docstrings and comments updated across controllers, handlers, providers, and services

- 6a97ce4: Step 11: Command-based undo for draw operations

  - `AddStitchCommand`, `RemoveStitchesAtCommand`, `RemoveStitchesInBoxCommand` — concrete `Command` subclasses in `lib/utils/command.dart`; each captures pre-mutation state so `undo()` is an exact inverse without a full snapshot.
  - `addStitchRaw`, `removeStitchRaw`, `removeStitchesAtRaw`, `removeStitchesInBoxRaw` — raw draw variants on `EditorNotifier` that mutate state without pushing to the snapshot undo stack; called by `Command.execute()` and `Command.undo()`.
  - `EditController` and `SnippetEditController` `attachCanvas` now wrap `DrawHandler.onAddStitch`, `onRemoveAt`, and `onRemoveBox` in the appropriate `Command` and execute via `undoManager.execute(cmd)`.
  - Undo delegate — `EditorNotifier.registerUndoDelegate` / `unregisterUndoDelegate` / `updateControllerUndoState`: the active controller registers callbacks so `notifier.undo()` / `notifier.redo()` route through the controller's `UndoManager` before falling back to the snapshot stack.
  - `EditorState.controllerCanUndo` / `controllerCanRedo` — new bool fields; `canUndo` / `canRedo` getters now include them so the toolbar undo button reflects the live command stack.
  - `test/utils/command_test.dart` — 15 tests: execute/undo round-trips for all three command types; raw variants do not push to snapshot stack; delegate registration, routing, and reset.

- 831032a: PR7: Introduce mode controllers (EditController, StitchController), UndoManager + Command infrastructure

  - `Command` abstract class + `UndoManager` per editing context (edit, stitch, snippet editor)
  - `EditController` — ShortcutHandler for edit mode; owns all pattern-editing keyboard shortcuts
  - `StitchController` — ShortcutHandler for stitch mode; owns progress undo/redo, page navigation, mode-switch keys
  - `EditorScreen` converted from ConsumerWidget → ConsumerStatefulWidget for lifecycle hooks
  - `WorkspaceScreen` and `SnippetEditorScreen` migrated to push/pop controllers via ShortcutRouter
  - Removed `editor_key_handler.dart` and all `Focus(onKeyEvent: ...)` wrappers
  - 39 new unit tests for UndoManager, EditController, StitchController

- dd672bb: Step 10: Introduce SnippetEditController and CanvasEditController interface

  - `SnippetEditController` — distinct controller class for snippet canvas editing. No save/PDF-zoom/shortcuts-dialog callbacks; no stitchMode guard; owns an independent `UndoManager` instance isolated from the parent pattern undo stack.
  - `CanvasEditController` — abstract interface implemented by both `EditController` and `SnippetEditController`. `AidaWidget.editController` is now typed to the interface rather than the concrete class.
  - `SnippetEditView` now wires `SnippetEditController` instead of `EditController`.
  - `patchLayer` unit tests added to `StitchCompositorTest`.
  - `SnippetEditController` isolation tests verify independent `UndoManager`, absence of save/shortcuts shortcuts, and correct editing shortcut dispatch.

- 0ab1d66: Step 12: Map threads, Cell class, O(1) lookups, undo.onChange

  - `pattern.threads`: `List<Thread>` → `Map<String, Thread>` keyed by `dmcCode` — O(1) lookup replaces `.any()`/`.firstWhere()` scans throughout providers, widgets, services, and screens.
  - `Cell` value class (`lib/models/cell.dart`) — canonical grid coordinate with `==`/`hashCode`; static `hitStitch`/`hitBox` consolidate duplicated `_hitCell`/`_hitBox` from edit controllers.
  - `UndoManager.onChange` callback — eliminates separate `_syncUndoState()` calls after every `execute`/`undo`/`redo`.
  - `Layer._cellIndex` — lazy `Map<String, List<Stitch>>` for O(1) `stitchesAt(x, y)` lookups; `@immutable`/`const` removed (cache field is non-final).
  - Static YAML parsers: `Thread.mapFromYaml`, `Stitch.listFromYaml`, `Snippet.listFromYaml` — consolidate parse logic out of `pattern.dart`.

- fab1981: **Step 16 — Complete command-based undo + delete snapshot stack**

  All remaining mutation paths now route through `UndoManager` commands instead
  of the `EditorState` snapshot stacks. The snapshot fields are deleted.

  ### New / changed APIs

  - `UndoManager.replaceLast(cmd)` — replaces the top stack entry; used by
    `StitchController` to squash a single-tap + double-tap flood-fill into one
    undo step.
  - `ProgressSnapshotCommand` — lightweight command that stores only
    `PatternProgress` before/after (not the full pattern) and applies it via a
    provided callback, so `progressLog` is intentionally never rolled back.
  - `EditorNotifier.applyProgressSnapshot(progress)` — restores progress without
    touching `progressLog`; called by `ProgressSnapshotCommand`.
  - `registerUndoDelegate` gains `pushProgressSnapshot` — routes direct-UI
    progress mutations (`markRegion`, `clearProgress`) through the controller's
    `UndoManager`.

  ### Deleted

  - `EditorState._progressUndoStack` / `_progressRedoStack` and
    `canUndoProgress` / `canRedoProgress` getters.
  - `EditorNotifier.undoProgress()` / `redoProgress()`.
  - `EditorState.progressUndoStack` / `progressRedoStack` `copyWith` params.
  - Abstract `_buildUndoStack()` from all mixins.

  ### Behaviour changes

  - `StitchController` registers as undo delegate on `attachCanvas`; Cmd+Z in
    stitch mode undoes the most recent progress mark (toggle or region fill).
  - `EditController` and `SnippetEditController` wrap `deleteSelection`,
    `flipSelectionH/V`, `rotateSelectionCW` keyboard shortcuts with
    `PatternSnapshotCommand` so they are now undoable via Cmd+Z.
  - `SnippetEditController` wraps `onCommitPaste`, `onFloodFill`,
    `onMoveSelection` — previously these were not undo-able inside the snippet
    editor.

- 44dbf5f: Step 20: Stitch type refactor — toolbar consolidation + three-quarter stitch + overlap system

  - `ThreeQuarterStitch` — new stitch type: full diagonal + quarter diagonal to corner. Block mode: half-cell triangle. Realistic: two thread lines.
  - Removed single-diagonal quarter stitch; old `'quarter'` YAML entries silently dropped on load. Petit point (X in quarter cell) kept as `QuarterStitch` with YAML type `'quartercross'`.
  - Toolbar: 6 partial stitch buttons consolidated to 1 button with tap-to-open dropdown selector + dropdown arrow indicator. Keyboard shortcuts 2–6 unchanged.
  - `BlockShape` sealed class (`RectShape` / `PathShape`) replaces raw `Rect` in `RenderCache`. `HalfStitch` renders as thick diagonal parallelogram, `ThreeQuarterStitch` as filled triangle. `drawRect` GPU fast path preserved for rect-based stitch types.
  - `PartialSubTool` enum + `partialSubTool` field on `EditSessionState`. `DrawingTool` enum consolidated: `halfForward`/`halfBackward`/`halfCross`/`quarterDiag`/`quarterCross` replaced by single `partial` value. Session migration handles old tool names.
  - Overlap-aware stitch placement via `CellRegion` quadrant system. Non-overlapping partial stitches coexist in the same cell. Overlapping stitch replaces existing.
  - Cross-layer compositor: same regions → blend, partial overlap → top occludes, no overlap → both visible.

- f685554: Step 9: Introduce EditView, StitchView, SnippetEditView — each owning a single mode controller and its chrome

### Patch Changes

- a239fc1: Introduce CompositeLayer and stateful StitchCompositor

  Adds `CompositeStitch` and `CompositeLayer` types as the rendering-oriented
  output of layer compositing. `CompositeLayer.fullStitches` maps each occupied
  cell to a `CompositeStitch` carrying resolved colour, resolved thread, and an
  `isBlended` flag — no further layer logic required downstream.

  `StitchCompositor` is now instantiable: `StitchCompositor(pattern)` holds the
  pattern and lazily maintains a cached `CompositeLayer`. Incremental update
  methods `updateCell`, `updateCells`, `updateLayer`, and `rebuild` invalidate
  the cache; the next `compositeLayer` access rebuilds only what changed (full
  rebuild for now; cell-level invalidation follows in the RenderCache step).

  The static `compute()` and `computeLayer()` convenience helpers remain for
  services and tests that do not need the stateful API. `CompositeResult` is
  retained unchanged — `CompositeLayer.toCompositeResult()` bridges the two.

  10 new unit tests added covering `CompositeLayer` structure, `isBlended` flag
  accuracy, and the cache invalidation / lazy-rebuild contract.

- 0dc255a: Complete controller handler composition (PR 7a)

  `EditController` now owns `DrawHandler`, `SelectHandler`, `PasteHandler`, and
  `HoverHandler`; `StitchController` owns `ProgressHandler`, `PageNavHandler`,
  and `HoverHandler`. Both controllers expose an `attachCanvas(CanvasCallbacks)`
  / `detachCanvas()` lifecycle so `PatternCanvas` can inject view-level callbacks
  at mount time. `PatternCanvas` delegates all pointer events to the active
  controller and reads overlay state (hover cell, paste origin, selection rect)
  directly from controller-owned handlers.

- 63f52b2: Extract Draw, Select, Paste, Progress, PageNav, Hover handlers from PatternCanvas

  Introduces six handler classes that own the mutable gesture/interaction state
  previously scattered across `_PatternCanvasState`. Each handler receives
  injected callbacks for writes (no direct `EditorNotifier` access) and accepts
  `EditorState`/`CanvasViewport` as method parameters for reads — fully
  unit-testable without Riverpod.

  **`DrawHandler`** — stitch drawing and erasing. Owns `_fillFired` (per-tap
  flood-fill guard) and `_backstitchHoverPoint`. Handles all `DrawingTool` and
  `DrawingMode` dispatch including backstitch chain mode, layer-visibility
  warnings, and sub-cell quadrant/half detection.

  **`SelectHandler`** — rubber-band selection and selection-move. Owns anchor,
  drag rect, move delta, and hasDragged flag. Exposes static helpers
  `buildSelRect`, `cellInSelRect`, `toSelCell` used by the painter.

  **`PasteHandler`** — paste origin, Ctrl/Shift modifier tracking, ghost-stitch
  cache, and Shift edge-snapping. Ghost cache avoids re-allocating the offset
  list when `(dx,dy)` and clipboard identity are unchanged across builds.

  **`ProgressHandler`** — stitch-mode progress marking. Owns anchor, drag rect,
  double-click detection (DOWN-to-DOWN within 500 ms), and backstitch hit-test.
  Separate `onPointerMove` (screen-pixel threshold) and `onTouchMove` (rect-size
  threshold) mirror the original split for stylus/mouse vs touch.

  **`PageNavHandler`** — stateless const helper. `isNavZone` returns true when a
  screen position falls in an edge/corner guard zone used to suppress canvas
  input during page navigation.

  **`HoverHandler`** — mouse/stylus hover cell tracking. Discriminates device
  kinds so stylus-added events update the preview cell without clobbering the
  mouse position, and vice-versa.

  `PatternCanvas` wires each handler in `initState` with `EditorNotifier`
  methods as callbacks, and all event methods delegate to the appropriate
  handler. ~25 individual state fields and ~10 methods removed from
  `_PatternCanvasState`.

  48 new unit tests added covering all six handlers.

- 55bf621: Stitch mode focus: unfocused stitches show pale colour/symbol instead of flat grey

  **Before:** Focusing a thread in stitch mode turned all other stitches to uniform grey with no symbols — losing context about surrounding pattern.

  **After:** Unfocused stitches retain their identity:

  - **Done + unfocused:** pale version of actual thread colour (hue preserved, desaturated + lightened)
  - **Undone + unfocused:** pale greyscale with semi-transparent symbol still visible
  - **Focused stitches:** unchanged (same as before)

  Applies to both cross-stitches (via RenderCache) and backstitches (via painter).

  Colour helpers added: `_paleColor` (HSL desat+lighten), `_paleGreyscale` (greyscale at alpha 128).
  Removed unused `_muteColor` and `_greyColor` from both files.

- b1f3ca1: Fix various bugs with progress tracking
- 88ad015: Extract RenderCache and delete CompositeResult — painter receives pre-resolved data

  Introduces `RenderCache` and `RenderViewConfig`:

  - `RenderCache` owns `Map<Color, Map<cellKey, List<Rect>>>` — pre-resolved stitch
    block rects grouped by colour, with a reverse-index enabling O(1) cell removal.
    `version` counter replaces object-identity cache-key comparisons.
  - `RenderViewConfig` is an immutable value object capturing focus thread,
    stitch/back/cross mode, palette override, progress, and page config.

  `CanvasStaticPainter` gains a `renderCache` field and loses both static caches
  (`_blockRectsByLayer`, `_occlusionCache`) and all the domain helpers that fed
  them (`_resolveStitchColor`, `_applyPaletteOverride`, `_bwGreyscale`,
  `_muteColor`, `_greyColor`, `_nearestThread`, `_getOrBuildBlockRects`,
  `_drawLayerStitchesAsBlocks`, `_drawLayerBlocksWithPageFilter`,
  `_getOcclusionSets`). Block rendering is now a simple nested iteration of
  `renderCache.store`. Symbol rendering iterates `compositeLayer.fullStitches`
  and `otherStitches` (symbol-winner already applied by `StitchCompositor`) so
  occlusion sets are no longer needed.

  `PatternCanvas` owns the `RenderCache` and calls `_syncRenderCache` at the
  top of `build()` — rebuilding only when pattern/composite/view-config identity
  changes, not on pan/zoom. `rebuildViewConfig` is used for focus/mode changes
  (recolour only, no geometry recomputation).

  `CompositeResult` deleted in full — `StitchCompositor.compute()`,
  `CompositeLayer.toCompositeResult()`, and `StitchCompositor.compositeResult`
  are all removed. All callers now use `StitchCompositor.computeLayer()` and
  access `CompositeLayer` fields directly (`fullStitches`, `otherStitches`,
  `backstitches`, `crossStitchEquiv`, `backStitchEquiv`). Migrated files:
  `EditorState`, all `editor_provider_*` mixins, `canvas_painter.dart`,
  `pattern_canvas.dart`, `right_sidebar_colours_panel.dart`,
  `editor_toolbar_color_controls.dart`, `stitch_ops_screen.dart`,
  `materials_list_screen.dart`, `pdf_service.dart`, `png_export_service.dart`,
  `page_layout.dart`, and all affected tests.

  15 new unit tests added covering rebuild, incremental `updateCells`, focus
  greying, B&W stitch mode, version counter, and `RenderViewConfig` equality.
  All 480 tests pass.

- 399c667: Introduce ShortcutRouter — replace HardwareKeyboard handler in PatternCanvas

  Adds `ShortcutRouter` singleton + `ShortcutHandler` interface as global
  keyboard-shortcut infrastructure. No Flutter focus dependency — fires
  regardless of which widget has focus, resolving the focus-stealing issues
  with AppBar and dialogs.

  `PatternCanvas` now implements `ShortcutHandler` and pushes/pops itself
  on `ShortcutRouter` in `initState`/`dispose`, replacing the direct
  `HardwareKeyboard.instance.addHandler` call. The handler behaviour is
  unchanged: update `PasteHandler` Ctrl/Shift modifier state, return false
  (do not consume).

  `ShortcutRouter.init()` called once in `main()` after
  `WidgetsFlutterBinding.ensureInitialized()`.

  `ShortcutRouter.forTesting()` and `dispatchForTesting()` allow pure-Dart
  unit tests without the Flutter binding.

  8 new unit tests covering dispatch order, consume/propagate, push/pop,
  and empty-stack safety. All 601 tests pass.

- cc0abe5: Extract ZoomPanHandler into it's own class, to be used with new controllers in on-going refactor.
- 1144236: Step 14: Architecture thinning, dead code pass, O(1) pipeline bottleneck fixes

  **Dead code removed**

  - `lib/services/ai/` directory deleted — `ai_provider.dart` was an unreferenced duplicate of `ScannedThread`/`ScannedStitch`/`PatternScanResult` already in `lib/services/scan/scan_result.dart`
  - `changeThreadSymbol`, `removeThread` — 0 callers in production code
  - `transformSnippet`, `addSnippetPalette`, `deleteSnippetPalette`, `renameSnippetPalette`, `reorderSnippetPalette` — test-only or 0 callers; superseded by `*Local()` variants
  - `SnippetTransform` enum removed (no remaining callers)
  - Tests for all removed methods removed

  **Render pipeline: O(n) → O(1) hot-path fixes**

  - `StitchCompositor.patchLayer`: inner loop now calls `layer.stitchesAt(x, y)` (O(1) via `_cellIndex`) instead of scanning all of `layer.stitches`; `BackStitch` exclusion implicit since it has no `cellCoords`
  - `addStitch` / `addStitchRaw`: `alreadyExists` check uses `stitchesAt` — O(1) for the common case, O(n) fallback only for `BackStitch`
  - `removeStitchesAt` / `removeStitchesAtRaw`: early-return guard checks `stitchesAt(x,y).isEmpty` first; only scans for backstitch when cell is otherwise empty

  **`StitchCompositor.patchAffectedLayer` — new**

  - Patches only cells that a changed layer touches; used by `toggleLayerVisible` and `setLayerBlendMode`
  - Previously both called `refreshCompositeCache()` → `computeLayer()` = O(total_stitches)
  - Now O(cells_in_layer × avg_layers_per_cell) — effectively O(1) for sparse single-layer patterns

  **EditorState field audit**

  - Fields grouped and annotated by mode ownership (edit / stitch / snippet / view / render pipeline) to guide future per-mode state extraction

- 6b28457: Step 15: Layer Map primary storage + O(1) draw hot-path + CompositeLayer version counter

  **`Layer` data structure change**

  - Primary storage is now `Map<Cell, List<Stitch>> stitchesByCell` + `List<BackStitch> backstitches`
  - `List<Stitch> get stitches` is a computed getter (O(N)) for compatibility — serialisation, bulk transforms, non-hot-path code
  - `stitchesAt(int x, int y)` is always O(1) — no lazy rebuild, index exists from construction
  - Immutable update methods for snapshot-undo paths (paste, move, delete, etc.):
    - `withStitchAdded`, `withStitchReplaced`, `withStitchRemoved`, `withCellCleared` — O(N_cells) map copy
  - In-place mutation methods for 120 Hz draw hot-path (via UndoManager commands):
    - `addStitchInPlace`, `replaceStitchInPlace`, `removeStitchInPlace`, `clearCellInPlace` — O(1), zero map copy

  **Draw hot-path: O(N_stitches) → O(1)**

  - `addStitchRaw`: `addStitchInPlace` mutates map directly — no copy
  - `removeStitchRaw`: `removeStitchInPlace` — no copy
  - `removeStitchesAtRaw`: `clearCellInPlace` — no copy
  - `removeStitchesInBoxRaw`: `clearCellInPlace` per box cell — O(box²)
  - Safe because UndoManager commands reverse mutations exactly (add ↔ remove); snapshot undo always uses immutable methods that create new Layer instances

  **`CompositeLayer` version counter + in-place mutation**

  - `patchLayer`: mutates `old.fullStitches` in-place + bumps `version` — eliminates O(N_cells) `Map.from` copy
  - `patchCells(old, pattern, cells)`: new method for multi-cell patches (paste, etc.) — O(cells × layers_per_cell)
  - `patchAffectedLayer`: thin wrapper around `patchCells`, in-place mutation
  - `_syncRenderCache` detects changes via version counter instead of `identical()`

  **`toggleLayerVisible` / `setLayerBlendMode` → `patchAffectedLayer`**

  - Now that `patchAffectedLayer` is in-place (no Map.from copy), it's faster than `computeComposite` for visibility/blend toggles — resolves only cells the changed layer touches

  **`commitPaste` → `patchCells`**

  - Paste uses `patchCells(dirtyCells)` for incremental composite — only resolves pasted cells instead of full recompute

  **Rename: `computeLayer` → `computeComposite`**

  - Clearer name: computes composite from ALL visible layers, not a single layer

  **Controller hot-path fixes**

  - `EditController` / `SnippetEditController` `onAddStitch` and `onRemoveAt` callbacks use `stitchesAt` (O(1)) instead of `layer.stitches` getter (O(N) allocation)
  - `draw_handler._checkLayerWarning` uses `stitchesAt` (O(1))
  - `pickColorAtCell`, `floodFill`: use `stitchesAt` / `stitchesByCell` directly

  **Net effect on 256×224 pattern (~6 300 cells, ~19 000 stitches)**

  - Per draw event: 3×O(19k) → O(1) — zero list copies, zero map copies, zero index rebuilds
  - Visibility toggle: O(19k) full recompute → O(6.3k cells × ~1 layer) incremental
  - Paste 50 stitches: O(19k) full recompute → O(50 cells) incremental

- bff8f8a: **Step 17 — EditorState split into grouped value classes**

  The `EditorState` monolith's ~30 flat fields are now grouped into four
  dedicated value classes. No behaviour change — pure structural refactor.

  ### New types

  - `ViewState` — `panX`, `panY`, `scale` (replaces `viewPanX/Y/viewScale`)
  - `StitchSessionState` — `crossMode`, `backMode`, `focusThreadId`,
    `showPageColours`, `currentPage`, `pageLayout`, `pendingFitPage`,
    `progressRegion`
  - `EditSessionState` — `currentTool`, `drawingMode`, `backstitchStartPoint`,
    `backstitchChainMode`, `selectionRect`, `clipboard`, `clipboardThreads`,
    `clipboardFromSnippet`, `eraserSize`, `fillEraseActive`,
    `canvasSelectionMode`, `pendingCanvasWarning`, `referenceImage`,
    `referenceOpacity`, `referenceVisible`, `colourMode`
  - `SnippetEditorState` — `palettes`, `activePaletteIndex`

  ### EditorState API changes

  Flat fields replaced by grouped accessors:

  ```dart
  // Before
  state.viewPanX / state.currentPage / state.currentTool / state.snippetPalettes

  // After
  state.viewState.panX / state.stitchSession.currentPage
  state.editSession.currentTool / state.snippetEditorState.palettes
  ```

  `EditorState.copyWith` now accepts grouped params (`viewState:`,
  `stitchSession:`, `editSession:`, `snippetEditorState:`) instead of the
  individual flat params. `dirtyCellKeys` remains a flat field (moving it out
  requires a new provider↔widget communication channel — deferred).

- e40e8d0: **Step 18 — Polish, bug fixes, and stitch-mode architectural enforcement**

  ### Bug fixes

  - **Canvas blank after addGroup / layer ops** — all 13 layer-mutation methods
    now call `refreshCompositeCache()` immediately instead of setting
    `compositeLayer: null` and waiting for the next repaint.
  - **setLayerOpacity flash** — replaced `compositeLayer: null` + 150 ms debounce
    with `patchAffectedLayer()` for O(cells) incremental update; no more visible
    flash on every slider tick.
  - **Focus-mode mark/frog ignores composite stitches** — `markRegionDone`,
    `markRegionNotDone`, `floodFillDone`, and the sidebar mark/demo buttons now
    compare against `resolvedThread.dmcCode` from `compositeLayer` instead of
    raw `stitch.threadId`, so blended/composite cells respect the focus filter.
  - **Text field typing blocked in colour picker** — `FocusNode.context.widget`
    is a `Focus` widget (child of `EditableText`), not `EditableText` itself.
    Guard now uses `findAncestorStateOfType<EditableTextState>()` to walk the
    element tree correctly. Colour picker and DMC picker gain `autofocus: true`.
  - **Reference image visible in stitch mode** — painter now checks `!stitchMode`
    before drawing the overlay; reference image is edit-mode only.
  - **Aida colour removed from canvas** — canvas background is always white;
    aida colour moved to Pattern Info as metadata (still used in PDF / PNG
    export). Toolbar aida button removed.
  - **Drive Open modal hid Drive section on first render** — `build()` now
    returns `DriveState(isConfigured: _auth.isConfigured)` synchronously.
  - **Stitch demo used pattern aida colour** — demo background is always white
    (demo shows technique, not pattern colours).

  ### Architecture

  - **`StitchStateView` facade** — read-only projection of `EditorState` for
    stitch-mode code. Exposes `compositeLayer`, `stitchSession`, `progress`,
    `progressLog`, `threads`; deliberately omits `pattern.layers`. `ProgressMixin`
    reads exclusively through `_stitch: StitchStateView`; sidebar stitch-mode
    helpers (`_regionHasPageStitches`, `_isRegionAllDone`, `_buildTopThread`,
    `_stitchPool`) accept `StitchStateView` — raw layer access in stitch mode is
    now a compile error.
  - **`CompositeLayer` helpers** — `topThreadAt(Cell)` and `hasCrossStitchAt(Cell)`
    added for O(1) single-cell lookup used by toggle/flood-fill paths.

- 0216700: Consolidate stitch geometry into StitchGeometry extension on Stitch

  Adds `cellCoords`, `bounds`, `blockCells`, and `isInViewport` extension
  getters/methods, replacing 5 duplicate switch-based geometry helpers scattered
  across `canvas_painter`, `pattern_canvas`, `editor_state`, and two stitch ops
  screens. `EditorState.cellCoords` and `stitchXY` free function now delegate to
  the extension. 16 new unit tests added.

## 0.9.0

### Minor Changes

- 85219c7: Improve DMC colour matching accuracy with CIEDE2000

  Replaces the CIE-76 squared-Euclidean distance used throughout the sprite importer with CIEDE2000 (Sharma, Wu & Dalal 2004), the current industry standard for perceptual colour difference. CIEDE2000 corrects known weaknesses in CIE-76, particularly for blues/violets, dark colours, and near-neutrals — all common in pixel-art palettes.

  Changes:

  - `matchPixel`, the palette-merge step, `renderCropWithPalette`, and `_importRegionRestrictedFromRaw` all now use CIEDE2000.
  - Added a per-RGB match cache to `SpriteImporter`; sprite art typically reuses a tiny set of colours, so CIEDE2000's extra trig cost is paid once per unique colour rather than per pixel.
  - Fixed a silent bug in `renderCropWithPalette` and `_importRegionRestrictedFromRaw` where the drop threshold was compared against a squared CIE-76 value (`30² = 900`) rather than the intended linear 30-unit distance. This is now a direct CIEDE2000 comparison against `30.0`.
  - Replaced single-midline palette strip scanning with full-block column/row averaging. Each slot's representative colour is the average of all pixels in the corresponding column (horizontal strip) or row (vertical strip), making detection robust against JPEG artefacts and anti-aliased edges.
  - Removed `_quantizeColor` (16-step grid snap). Grid-boundary artefacts caused incorrect block splits when a colour straddled a step boundary.
  - Strip block-boundary detection now uses CIE-76 Lab distance (threshold 15 ΔE) instead of sRGB Euclidean, consistent with the rest of the pipeline.

### Patch Changes

- 0bc5aa9: Update DMC colour list from community source

  Synced against cheshire137/cross-stitch-color-conversion: 13 colours added, 441 hex/name values updated, 1 possibly retired (994 Aquamarine Very Light moved to dmcReplacements).

- ab31a6a: Update DMC colour list from KXStitch source

  Automated sync: 35 added, 453 updated, 2 possibly retired.

- 15a57be: Fix canvas not updating after drawing, snippet palette save, and symbol picker

  - Canvas now repaints immediately after every draw/erase/fill/paste/move/delete operation — previously required hiding and re-showing a layer to trigger a repaint
  - `loadSnippetToClipboard` auto-switches to edit mode so pasting a snippet from view mode works without a manual mode switch
  - Snippet palette colour changes now mark the editor dirty so they can be saved
  - Layer-thread symbol picker no longer allows picking a symbol already used by a composite (blended) thread
  - `newPattern` opens directly in edit/draw mode instead of view mode

- 8d976cc: Fix DMC colour update tool to use KXStitch as sole source

  Removes the cheshire137/cross-stitch-color-conversion JSON as the primary
  source and replaces the dual-source (primary + supplementary) logic with a
  single KXStitch XML fetch. The KXStitch dataset covers all ~489 DMC colours
  including the newer 01–35 range that the previous primary source omitted.

- 3881ed6: Fix thread colour mismatch when loading old files

  When a `.stitchx` file was saved before a DMC colour update, threads stored the outdated hex. Now `Thread.fromYaml` looks up the DMC code in the canonical colour table and uses the current hex — so existing stitches and newly drawn ones always match. Falls back to the saved hex for unknown/custom codes.

- b3aae41: Fix the case where there is a duplicate colour in a primary palette on import, causing issues with colours on secondary palettes.
- 0ea5b4f: Windows now registers the `.stitches` file association at launch — double-clicking a `.stitches` file in Explorer opens it directly in Stitches. No admin rights required (written to `HKCU`). Matches existing macOS/iOS/Android behaviour.

  Drag and drop a `.stitches` file onto the home screen to open it on macOS, Windows, and Linux.

## 0.8.0

### Minor Changes

- 2b8cdf2: Add PatternKeeper PDF import and export support.

  **Import (Tier-1 parser):** When opening a PDF in workspace scan mode, StitchX now tries a text-layer parse before falling back to the manual raster scan. PatternKeeper-format PDFs (and most PDFs produced by MacStitch, WinStitch, PCStitch) embed symbols as selectable TTF characters — the parser reads symbol positions and the legend table directly from the text layer with no user input required. Falls back automatically to the existing sample-one-cell raster scan for image-only PDFs.

  **Export:** A new "Also export PatternKeeper PDF" checkbox appears in the PDF export/share picker. When checked, a `_PatternKeeper.pdf` is generated alongside the standard PDF. The PatternKeeper-format PDF omits the title page (which PatternKeeper would misread as chart data), caps pages at 60 stitches, and renders the colour legend with `Symbol`/`Number` column headers and TTF symbol characters as selectable text — satisfying PatternKeeper's import requirements.

### Patch Changes

- 1bb5f79: Bump `googleapis_auth` from 2.0.0 to 2.3.0

  Obtain Access credentials for Google services using OAuth 2.0

- 926d3ff: Bump `wakelock_plus` from 1.5.1 to 1.5.2

  Plugin that allows you to keep the device screen awake, i.e. prevent the screen from sleeping on Android, iOS, macOS, Windows, Linux, and web.

- cf8c0eb: Add real-world PDF parse integration test sourced from private fixtures repo.

  A new CI job (`integration-test`) clones `stitches-test-fixtures` (private) and runs `pk_real_pdf_parse_test` against actual PatternKeeper PDFs to guard against regressions in the Tier-1 text-layer parser. Fixture path resolution updated across existing tests to use the shared `TestFixtures` helper.

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
