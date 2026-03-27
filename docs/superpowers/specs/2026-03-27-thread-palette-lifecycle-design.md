# Thread Palette Lifecycle & Symbol Stability

**Date:** 2026-03-27
**Status:** Approved

## Overview

Three related problems are fixed in a single coherent design:

1. **Auto-pruning** — threads are removed from `pattern.threads` automatically when the last stitch using them is erased across all layers, rather than accumulating as dead entries.
2. **Palette is read-only** — threads are added to the palette only when the first stitch using that colour is placed, not when a colour is selected in the picker.
3. **Stable composite symbols** — composite thread symbols (produced by layer-blending) are persisted to the `.stitchx` file so they survive save/reload cycles and do not change between sessions.

A bonus fix extends the symbol pool from 63 to ~180 symbols using additional UTF-8 characters.

---

## Section 1: Thread Lifecycle

### Adding threads

`addThread()` is removed from `EditorNotifier`. Threads enter `pattern.threads` via exactly two paths:

- **`addStitch()`** — before placing a stitch, checks if `selectedThreadId` exists in `pattern.threads`. If not, looks the DMC code up in the colour database, assigns a fresh globally-unique symbol (not used by any pattern thread or composite symbol), and appends the thread to `pattern.threads` before placing the stitch.
- **`pasteStitches()`** — same check, applied to each clipboard thread not already in the palette.

### Removing threads

A new internal helper:

```dart
CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern)
```

Collects all `threadId` values referenced across every layer's stitches, then returns a copy of `pattern` with `threads` filtered to only those present in the used set. Called at the end of every stitch-removing operation:

- `removeStitchesAt()`
- `deleteSelection()`
- `resizeAida()` (crop path)

Not needed after `undo()` / `redo()` — these restore full pattern snapshots that already contain the correct thread list for that point in history.

`removeThread()` is kept for the explicit "remove colour" action in the palette UI (destructive, user-initiated).

### Colour picker

`ColorPickerScreen` in "add colour" mode (`replacingThreadId == null`) now calls `notifier.setSelectedThread(dmcCode)` only — it does not call `addThread`. The two branches in `_onThreadSelected` ("already in palette" and "new colour") collapse into one: always `setSelectedThread`. The picker title changes from "Add Colour" to "Select Colour".

The DMC code does not need to be in `pattern.threads` to be selected. The palette list simply won't show it until the first stitch is placed.

---

## Section 2: Composite Symbol Registry

### Model change

`CrossStitchPattern` gains a new field:

```dart
final Map<String, String> compositeSymbols; // dmcCode → symbol
```

Defaults to `const {}`. Added to `copyWith` with `_sentinel` pattern (nullable override).

### Serialisation

Written to YAML as a top-level block, only when non-empty:

```yaml
compositeSymbols:
  "3865": "X"
  "ECRU": "+"
```

Parsed in `fromYaml` with graceful fallback to `{}` for older files.

### Symbol assignment in `refreshCompositeCache()`

`used` is seeded with symbols from both `pattern.threads` AND `pattern.compositeSymbols.values`. For each composite DMC code:

1. DMC code is in `pattern.threads` → inherit its symbol (unchanged)
2. DMC code is in `pattern.compositeSymbols` → use stored symbol
3. Otherwise → assign `_nextSymbol(used)`, add to `used`

After building the cache, `refreshCompositeCache()` writes an updated `compositeSymbols` map back into `state.pattern`, containing **only** the DMC codes currently in the cache (stale entries are dropped). This keeps the registry minimal and self-consistent.

### Collision healing on load

If (due to file corruption or manual edit) a `compositeSymbols` entry collides with a `pattern.threads` symbol, `refreshCompositeCache()` detects this (the composite symbol will already be in `used` when seeded from pattern threads) and reassigns a fresh symbol, then persists the correction.

### Manual symbol override for composites

A new method `changeCompositeSymbol(String dmcCode, String symbol)` on `EditorNotifier`:
- Validates the symbol is not already used by any pattern thread or other composite entry
- If invalid, returns without applying (caller shows an error)
- If valid, writes directly to `pattern.compositeSymbols` and immediately calls `refreshCompositeCache()` so the palette updates in place

---

## Section 3: Palette UI

### No add button

The "+" add-colour button is removed from the palette. The palette is a read-only display of colours in use.

### Symbol editing

- Pattern threads: existing `changeThreadSymbol()` tap-to-edit flow, unchanged.
- Composite threads (canvas mode): tapping the symbol invokes `changeCompositeSymbol()`. The symbol picker validates uniqueness against all pattern thread symbols and all other composite symbols before applying. Shows an inline error if the symbol is already taken.

### Remove colour

The per-thread remove (×) action is kept — it is a deliberate destructive action (removes thread and all its stitches from all layers) so remains user-initiated.

---

## Section 4: Error Handling & Edge Cases

| Scenario | Behaviour |
|---|---|
| Undo after auto-prune | Snapshot restored with thread + stitches intact — no special handling needed |
| `replaceThread` merge (target already in palette) | After remap, `_pruneUnusedThreads` removes the now-unreferenced source thread. Target keeps its symbol. |
| Composite symbol collision on load | `refreshCompositeCache()` self-heals by reassigning and persisting |
| All stitches erased | All threads pruned, palette empty, `compositeSymbols` cleaned to `{}`. First new stitch re-bootstraps cleanly. |
| Symbol pool exhaustion | `_nextSymbol` returns `''`; thread stored with empty symbol; canvas skips rendering the symbol (existing behaviour). |

---

## Section 5: Extended Symbol Pool

`kPatternSymbols` in `lib/data/symbols.dart` is extended from 63 to ~180 symbols. Additions:

```dart
// Lowercase (visually distinct from uppercase counterparts)
'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
'k', 'm', 'n', 'p', 'q', 'r', 's', 'u', 'v', 'w', 'x', 'y', 'z',

// Greek (recognisable at small cell sizes)
'α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'λ', 'μ',
'ξ', 'π', 'ρ', 'σ', 'τ', 'φ', 'χ', 'ψ', 'ω',

// Playing card suits
'♠', '♣', '♥', '♦',

// Arrows
'↑', '↓', '→', '←', '↗', '↘', '↙', '↖', '↔', '↕',

// Circled operators
'⊕', '⊖', '⊗', '⊙', '⊚',

// More filled/outline shapes
'▶', '◀', '▸', '◂', '⬡', '⬢', '⬤', '⬥',
'▪', '▫', '▴', '▾', '◉', '◎',

// Stars / snowflakes
'✦', '✧', '✩', '✪', '✫', '✬', '✭', '✮', '✯', '✰',

// Dingbats / marks
'✓', '✗', '✚', '✜', '✝',

// Misc punctuation / currency / special
'§', '¶', '°', '±', '×', '÷', '€', '£', '¥', '¢',
'©', '®', '™', '¿', '¡',
```

Omitted: `l`, `o`, `t` (too similar to `1`, `0`, `+`) and Greek `ι`, `ν`, `υ`, `κ` (too similar to Latin at small sizes).

---

## Files Affected

| File | Change |
|---|---|
| `lib/data/symbols.dart` | Extend `kPatternSymbols` |
| `lib/models/pattern.dart` | Add `compositeSymbols` field, `copyWith`, `fromYaml`, serialisation |
| `lib/services/file_service.dart` | Write `compositeSymbols` block in `toYamlString` |
| `lib/providers/editor_provider.dart` | Remove `addThread`, add `_pruneUnusedThreads`, update `addStitch`/`pasteStitches`, update `refreshCompositeCache`, add `changeCompositeSymbol` |
| `lib/screens/color_picker_screen.dart` | Collapse `_onThreadSelected` to always call `setSelectedThread` only |
| `lib/widgets/editor_toolbar.dart` | Remove "+" button; add composite symbol tap-to-edit in canvas mode |
