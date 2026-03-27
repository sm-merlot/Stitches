# Snippet Multi-Palette System — Design Spec

**Date:** 2026-03-26
**Status:** Approved

---

## Overview

Multiple colour palettes per snippet, selectable at any time. The sprite importer is extended with a palette-strip selection workflow and simplified to crop-only mode.

The main canvas is unaffected by this feature.

---

## Data Model

### New `SnippetPalette` class (`lib/models/snippet_palette.dart`)

```dart
class SnippetPalette {
  final String id;             // UUID v4
  final String name;           // "Palette 1", "Winter", "Summer", etc.
  final List<Thread> threads;  // ordered — index position = slot
}
```

### `Snippet` changes

```dart
class Snippet {
  final String id;
  final String name;
  final int width;
  final int height;
  final List<Stitch> stitches;   // unchanged — always reference base thread IDs
  final List<SnippetPalette> palettes;  // NEW — at least one entry always
  final int activePaletteIndex;         // NEW — persisted; defaults to 0
  // List<Thread> threads REMOVED — replaced by palettes[0].threads
}
```

**`Snippet.threads` getter (for backward compatibility in rendering code):**
```dart
List<Thread> get threads => palettes[0].threads;
```

### Slot mapping

- `palettes[0]` = the **primary palette** (defines the slot order)
- `palettes[n].threads[i]` replaces `palettes[0].threads[i]` when palette `n` is active
- Rendering builds a `Map<String, Thread>` from the active palette: `{ baseThreadId: replacementThread }`
- All palettes must have the same slot count (enforced at creation)

### File format

```yaml
snippets:
  - id: "abc-123"
    name: "Hero sprite"
    width: 16
    height: 16
    activePalette: 1
    stitches: [...]
    palettes:
      - id: "pal-001"
        name: "Palette 1"
        threads: [{dmcCode: "948", ...}, {dmcCode: "798", ...}]
      - id: "pal-002"
        name: "Winter"
        threads: [{dmcCode: "3743", ...}, {dmcCode: "932", ...}]
```

### Migration (backward compatibility)

If a snippet has no `palettes:` key, its existing `threads:` list becomes `palettes[0]` named "Palette 1" with `activePalette: 0`. Fully non-breaking.

### Delete rules

- Any palette can be deleted as long as ≥ 2 remain
- No special protection on the first palette
- If palette 0 (primary) is deleted, palette 1 becomes the new primary (slot definitions shift; stitch thread IDs are unchanged since they were always base-relative)
- When only 1 palette remains, the delete button is hidden/disabled
- "Last palette cannot be deleted" is a UI constraint only (no data model enforcement needed)

---

## Snippet Panel UI

**Palette switcher dots** (replaces existing dots below thumbnails):
- Shown only when `snippet.palettes.length > 1`
- One dot per palette; filled/highlighted = active palette
- Tap a dot to switch active palette — thumbnail re-renders immediately
- More than 6 palettes: show `"2/7"` style counter instead of individual dots

**⋮ menu addition:** "Manage palettes…" — opens palette manager in the snippet editor.

---

## Snippet Editor UI

**AppBar addition:** palette icon button (always visible when a snippet is open).

Tapping opens the **Palette Manager** bottom sheet:
- Lists all palettes with swatch rows
- Active palette highlighted with filled indicator dot
- Tap any palette row to switch active palette (canvas re-renders live)
- Inline rename (tap-to-edit on the name)
- × delete button per palette (hidden when only 1 remains)
- Drag to reorder
- **"+ Add new palette…"** button at the bottom

**"+ Add new palette…" → Add Palette dialog:**

A modal dialog with:
1. **Name field** — free text, e.g. "Summer"
2. **Mapping table** — one row per slot (derived from `palettes[0].threads`):
   - Left column: original thread swatch + "DMC XXXX — Name"
   - Arrow →
   - Right column: "Pick colour…" button (opens existing `ColorPickerScreen`); shows chosen colour once set
3. **Progress counter** — "X / N done"; turns green when all slots filled
4. **"Add palette" confirm button** — disabled until all slots filled AND name is non-empty
5. **Cancel** — dismisses with no changes

**Behaviour notes:**
- Any original colour can be mapped to the same replacement as another (many-to-one allowed)
- Tapping a filled slot re-opens `ColorPickerScreen` to change it
- On confirm: new `SnippetPalette` appended to `snippet.palettes`; `activePaletteIndex` set to new palette

**Context distinction from sprite importer:**
- In the snippet editor, adding a palette always **appends** — existing palettes are preserved
- There is no "auto-default" placeholder in the editor context; all palettes are real

---

## Sprite Importer Redesign (`sprite_sheet_screen.dart`)

### Remove tile mode

The fixed tile grid (Tile / Crop segmented button) is removed. **Only crop mode exists.**

### Interaction model

**Crop is always active** — no mode button. The user draws a freehand crop on the image at any time.

After a crop is drawn:
- An **auto "Default" palette** appears in the controls panel (greyed out, labelled "auto")
- It shows the DMC colours detected in the crop region as swatches
- An **"Add palette strip" button** appears below it

**"Add palette strip" mode:**
- Tapping the button enters palette-strip-drawing mode
- The sprite dims; the palette strip being drawn is highlighted
- A **"✕ Cancel palette selection"** button appears — cancels and returns to idle crop mode
- User draws a region around a horizontal OR vertical row of colour swatches
- On release, the strip region has draggable corner handles for adjustment
- The app detects colour squares in the strip by scanning for contiguous same-colour blocks along the primary axis; ordered left-to-right (horizontal) or top-to-bottom (vertical)
- All palettes for a given sprite must use the same orientation as Palette 1. Orientation (horizontal vs vertical) is auto-detected from the first strip's aspect ratio. If a subsequent strip has a different aspect ratio, a warning is shown: "This strip looks vertical but Palette 1 was horizontal — continue?" — the user can proceed or cancel
- The strip becomes "Palette 1" and **replaces** the auto-default placeholder (the first real palette defines the slots)
- Each subsequent strip adds "Palette 2", "Palette 3", etc.

**Auto-association:** new palette strip matched to Palette 1 positionally (same index = same slot). If the colour count doesn't match Palette 1, a **manual override dialog** is shown — a reorderable list where the user drags colours from the new strip to match slots from Palette 1.

**Re-cropping warning:** if the user attempts to move/resize the sprite crop after palette strips have been defined, a warning banner appears: "Moving the crop will clear your palette selections. [Proceed] [✕]"

**Corner handles:** both the sprite crop box and each palette strip box have draggable corner handles for resizing. The boxes themselves are also draggable (not just by corners).

### Controls panel (right sidebar)

- **Palettes section:** lists auto-default (greyed) or confirmed palettes with swatches; × to remove each (Palette 1 cannot be removed while others exist — removing it would clear all palettes and revert to auto-default)
- **"Add palette strip" / "Draw another palette strip"** CTA
- **Simplify palette slider** — unchanged from current behaviour
- **Snippet name field** + **"Add to Snippets"** button (disabled until crop is non-empty)
- **"Change image"** button (top right of AppBar area)
- **"Close"** button replacing the current "Done" label

### Preview panel (bottom)

A preview panel shows the current crop rendered as a pixelated snippet preview:
- Tabs: one per palette (auto-default shown as "Default" tab; no tab until a strip is added)
- Clicking a tab switches the preview to show that palette's colours applied
- A slot-mapping column to the right of the preview grid shows `[swatch] → [swatch] DMC XXX → DMC YYY` for the active palette tab
- Preview updates live as the crop region or palette strips are adjusted

### Import result

When "Add to Snippets" is tapped:
- `SpriteImporter.importRegion` runs as before for the crop
- All defined palette strips are also processed via `SpriteImporter.importRegion` (or a lighter colour-only pass)
- The resulting `Snippet` is created with `palettes` populated: one entry per confirmed strip (Palette 1, Palette 2, …); the auto-default is discarded
- If no strips were defined, the snippet is created with a single palette derived from the crop colours (same as current behaviour)
- `activePaletteIndex` defaults to 0

---

## Rendering with active palette

In `SnippetThumbnail`, `CanvasStaticPainter` (when rendering snippet paste ghosts), and anywhere snippets are drawn:

```dart
Thread resolveThread(Snippet snippet, String baseThreadId) {
  final palette = snippet.palettes[snippet.activePaletteIndex];
  final baseIndex = snippet.palettes[0].threads
      .indexWhere((t) => t.dmcCode == baseThreadId);
  if (baseIndex == -1 || baseIndex >= palette.threads.length) {
    return snippet.palettes[0].threads
        .firstWhere((t) => t.dmcCode == baseThreadId);
  }
  return palette.threads[baseIndex];
}
```

This lookup is O(n) on palette size; cached as a `Map<String, Thread>` per render pass.

---

## Files Affected

| File | Change |
|------|--------|
| `lib/models/snippet_palette.dart` | **New** |
| `lib/models/snippet.dart` | Add `palettes`, `activePaletteIndex`; remove raw `threads` field (add getter) |
| `lib/providers/editor_provider.dart` | Add palette management methods; `activePaletteIndex` switching |
| `lib/services/file_service.dart` | Serialise/deserialise `palettes` and `activePalette`; migration for old `threads` key |
| `lib/screens/sprite_sheet_screen.dart` | Full redesign — remove tile mode, add palette strip tool, preview panel |
| `lib/widgets/sprite_sheet_painter.dart` | Update for crop-only mode + palette strip overlays |
| `lib/services/sprite_importer.dart` | Add palette strip colour detection; multi-palette import result |
| `lib/widgets/snippets_panel.dart` | Palette dot switcher; "Manage palettes…" menu item |
| `lib/widgets/snippet_thumbnail.dart` | Render with active palette applied |
| `lib/screens/snippet_editor_screen.dart` | Add palette icon button in AppBar; palette manager sheet; add-palette dialog |
