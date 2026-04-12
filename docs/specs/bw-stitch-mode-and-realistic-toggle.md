# B&W Stitch Mode + Block Mode Default

## Context
Block mode (solid colour rectangles) is more useful than stitch-line mode for most workflows. The goals:
1. Make block mode the default, rename the opt-in toggle to "Realistic mode"
2. In stitch mode: unmarked stitches = **white fill + black symbol**, marked-done = **full colour block, no symbol**

This replaces the current "dimming overlay" approach where completed stitches get a 70% aida-colour overlay.

## Plan

### 1. Flip `blockMode` default to `true`

**Files:**
- `lib/providers/editor/editor_state.dart:104` — `this.blockMode = false` → `true`
- `lib/providers/editor/editor_provider.dart:106` — `bool blockMode = false` → `true`
- `lib/services/editor_session_service.dart:31` — constructor default `false` → `true`
- `lib/services/editor_session_service.dart:53` — `fromJson` fallback `?? false` → `?? true`
- `lib/models/pattern.dart:80` — constructor default `false` → `true`
- `lib/models/pattern.dart:346` — deserialization fallback `?? false` → `?? true`

Legacy detection in `editor_provider.dart:130-138`: The condition `pattern.editorBlockMode ||` detects non-default values. Since `true` is now the default, flip to `!pattern.editorBlockMode ||`.

### 2. Rename UI toggle to "Realistic mode"

3 files with identical IconButton pattern:
- `lib/screens/workspace_screen.dart` ~line 1290
- `lib/screens/editor_screen.dart` ~line 509
- `lib/screens/snippet_editor_screen.dart` ~line 538

Changes per button:
- Tooltip: `'Realistic mode: on'` / `'Realistic mode: off'`
- `isSelected`: flip to `!state.blockMode` (selected = realistic = NOT block)
- Style conditional: flip to `!state.blockMode`
- Method stays `toggleBlockMode()` (internal name doesn't matter)

### 3. B&W rendering in stitch mode (canvas_painter.dart)

#### 3a. Block rendering path (line 169-210)
When `stitchMode && (blockMode || effectivePx < kBlockThreshold)`:
- **Done cells**: render full-colour block (existing colour logic)
- **Undone cells**: render white block

Approach: in the block rect builder (`_getOrBuildBlockRects`), when `stitchMode`, substitute white for undone cells and keep colour for done cells. Add `progress` to cache invalidation.

#### 3b. Symbol rendering (line 248-286)
When `stitchMode && blockMode`:
- **Done cells**: skip symbol entirely
- **Undone cells**: draw symbol in black on white (no coloured background box)

Modify the symbol drawing section:
- After resolving the thread/symbol, check `progress.completedStitches.contains((x, y))`
- If done: skip
- If undone: call a simplified symbol draw — black text, no background box (the white block is already drawn)

#### 3c. Remove dimming overlay for block mode (lines 288-303)
Change to: `if (stitchMode && !blockMode && progress.completedStitches.isNotEmpty)`

In block mode, the B&W rendering handles done/undone distinction directly.

#### 3d. Backstitch done rendering (lines 232-236)
Backstitches are drawn outside the block/stitch-line branch (line 220). For B&W stitch mode, done backstitches could get the full-colour treatment instead of dimming, and undone backstitches could render in grey/light. Or keep existing behaviour for now since backstitches are secondary.

### 4. Cache invalidation
`_getOrBuildBlockRects` (line 538-555) caches block rects. For B&W mode, `progress` changes also need to invalidate the cache since progress affects block colours.

Add `progress` (or `progress.completedStitches.length` as a cheap proxy) to the cache key when `stitchMode` is true.

### 5. Snippet editor
`lib/widgets/snippets_panel.dart:115` reads `editorState.blockMode` and passes it as `initialBlockMode`. Since default is now `true`, this works without changes. The snippet editor screen's toggle button needs the same "Realistic mode" label flip.

## Files to modify
1. `lib/providers/editor/editor_state.dart` — default flip
2. `lib/providers/editor/editor_provider.dart` — default flip + legacy detection fix
3. `lib/services/editor_session_service.dart` — default flip
4. `lib/models/pattern.dart` — default flip
5. `lib/widgets/canvas_painter.dart` — B&W rendering logic (main work)
6. `lib/screens/workspace_screen.dart` — UI toggle rename
7. `lib/screens/editor_screen.dart` — UI toggle rename
8. `lib/screens/snippet_editor_screen.dart` — UI toggle rename

## Verification
- Open existing pattern → should render as blocks by default
- Toggle "Realistic mode" → should show stitch lines
- Enter stitch mode → unmarked stitches should be white with black symbol
- Mark a stitch done → should fill with full colour, symbol disappears
- Unmark → returns to white + black symbol
- Zoom out past threshold → still renders B&W blocks correctly
- Open snippet editor → block mode by default
