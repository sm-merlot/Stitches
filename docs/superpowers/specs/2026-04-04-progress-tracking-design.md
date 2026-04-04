# Progress Tracking Design

**Date:** 2026-04-04
**Status:** Approved, awaiting implementation
**Depends on:** File Format v2, Three-Mode Architecture

---

## Goal

Allow users to mark stitches as physically done while stitching, track progress per page and per colour, and celebrate completion milestones.

---

## Data Model

### `PatternProgress` (new model)

```dart
class PatternProgress {
  /// Cells the user has physically stitched. Stored as (x, y) pairs.
  final Set<(int, int)> completedStitches;

  /// Page indices (0-based) marked as fully done.
  /// A page auto-completes when its last stitch is marked done.
  /// Can also be manually toggled.
  final Set<int> completedPages;

  static const PatternProgress empty = PatternProgress(
    completedStitches: {},
    completedPages: {},
  );
}
```

Serialised under `stitching.progress:` in the v2 file format (see File Format v2 spec).

`PatternProgress` is carried in `EditorState` and mutated through `EditorNotifier`.

---

## Interactions (Stitch mode only)

### Tap → single stitch done/undone
Tap a cell to toggle it between done and not done. If the cell contains a stitch, it is marked complete. Tapping a completed stitch un-marks it (undo-friendly).

### Drag → region select → mark done
Click/touch and drag to rubber-band a region. On release, a bottom sheet or inline action bar appears with "Mark done" (and "Cancel"). All stitches within the region are marked done. Does not un-mark already-completed stitches within the region.

### Double-tap → flood fill by colour
Double-tap a stitch to mark all connected stitches of the same colour as done (flood fill). "Connected" means orthogonally reachable cells of the same thread, not the entire colour across the whole pattern. This prevents accidentally marking all instances of a colour done when only a local area is finished.

---

## Auto-completion

### Colour completion
After every mark-done action, check whether all stitches of each affected thread colour across the entire pattern are now in `completedStitches`. If so:
- Show a toast: **"DMC 321 complete ✅"**
- Mark the colour as done in the colour list

### Page completion
After every mark-done action, check whether all stitches on the current page are now in `completedStitches`. If so:
- Auto-add the page index to `completedPages`
- Show a subtle page-done indicator on the page nav overlay

Pages can also be manually toggled done/undone via a long-press on the page indicator or via the page grid sheet.

---

## Visual Representation

### Done stitches in Stitch mode
Completed stitches are rendered with reduced opacity (e.g. 30% of their normal colour) so the remaining work is visually prominent. The aida background shows through more strongly on completed cells.

### Colour list (Stitch mode)
Each colour entry shows:
- Colour swatch + thread name
- Done count / total count (e.g. "47 / 120")
- Progress bar or pill
- ✅ badge when all stitches of that colour are done

### Page navigation overlay
Page indicator shows a ✓ on completed pages. The page grid sheet (tap page indicator) shows done/incomplete status per page tile.

### Overall progress
View mode shows a summary progress bar or percentage in the pattern overview. Not shown in Edit mode.

---

## Colour List — Stitch Mode Ordering

The colour list in Stitch mode is sorted differently from View mode:

1. In-progress colours first (started but not done)
2. Not-started colours next (sorted by stitch count descending — most work first)
3. Completed colours last (greyed out, collapsible)

---

## Undo / Redo

Progress marking is undoable via the standard undo stack. Marking a stitch done or flood-filling a region pushes an undo entry. This allows accidental taps to be undone without losing other progress.

---

## Sharing

When sharing a `.stitches` file:
- Default: progress is stripped (recipient starts fresh)
- Option: "Include progress" — useful when handing off a partially-done piece

This is handled in the share/export flow (see Share/Export redesign spec).

---

## Implementation

### New files

**`lib/models/pattern_progress.dart`**
- `PatternProgress` model
- `fromYaml()` / `toYaml()`
- Helper methods: `isStitchDone(x, y)`, `isPageDone(pageIndex)`, `isColourDone(threadId, allStitches)`

### Files to change

**`lib/providers/editor/editor_provider.dart`**
- Add `progress: PatternProgress` to `EditorState`
- `loadPattern()` reads progress from file (or uses `PatternProgress.empty`)
- `savePattern()` writes progress to file

**New mixin: `lib/providers/editor/editor_provider_progress.dart`**
- `toggleStitchDone(int x, int y)` — toggle single cell
- `markRegionDone(Rect region)` — mark all stitches in region done
- `floodFillDone(int x, int y)` — flood fill connected same-colour stitches
- `togglePageDone(int pageIndex)` — manual page toggle
- `_checkColourCompletion(String threadId)` → triggers toast if complete
- `_checkPageCompletion(int pageIndex)` → auto-marks page done if all stitches done

**`lib/widgets/canvas_painter.dart`**
- `CanvasStaticPainter` gains `progress: PatternProgress`
- Done stitches rendered at reduced opacity in stitch mode

**`lib/widgets/pattern_canvas.dart`**
- Tap handler in stitch mode → `toggleStitchDone`
- Drag handler in stitch mode → region selection → `markRegionDone`
- Double-tap handler in stitch mode → `floodFillDone`

**`lib/widgets/editor_toolbar.dart` / colour list widget**
- Stitch mode colour list shows done/total counts and ✅ badges

**Page nav overlay (`pattern_canvas.dart`)**
- Page tiles show done indicator

### Toast notification

Use a lightweight overlay (e.g. `OverlayEntry` or a snackbar) shown briefly when a colour completes. Keep it non-blocking — it dismisses automatically after ~2 seconds.

---

## Testing

- Tap a stitch → confirm it appears done, progress saved to file
- Tap done stitch again → confirm it un-marks
- Drag region → confirm all stitches in region marked done
- Double-tap → confirm only connected same-colour stitches marked done (not whole-pattern flood)
- Mark last stitch of a colour → confirm toast appears with correct thread name
- Mark last stitch on a page → confirm page auto-completes
- Load file → confirm progress persists across sessions
- Share without progress → confirm recipient's file has no progress data
- Undo after marking done → confirm stitch un-marks
