# Layers & Snippet Multi-Palette — Design Spec

**Date:** 2026-03-26
**Status:** Approved

---

## Overview

Two independent features designed in sequence. They share no data dependencies and can be implemented separately.

1. **Canvas Layers** — add named layers to the main canvas with per-layer visibility and opacity
2. **Snippet Multi-Palette System** — multiple colour palettes per snippet, selectable at any time; sprite importer extended to define palettes from colour strips on the sheet

---

## Feature 1: Canvas Layers

### Scope

- Main canvas only. Snippets have no layers.
- When a snippet is stamped/pasted, it lands on the **active layer**.
- Layers are hidden in **stitch mode** (the read-only follow-along view).

### Data Model

#### New `Layer` class (`lib/models/layer.dart`)

```dart
class Layer {
  final String id;       // UUID v4
  final String name;     // user-editable, e.g. "Background", "Layer 1"
  final bool visible;    // on/off toggle
  final double opacity;  // 0.0–1.0
  final List<Stitch> stitches;
}
```

#### `CrossStitchPattern` changes

- **Remove** `List<Stitch> stitches`
- **Add** `List<Layer> layers` — ordered bottom-to-top (index 0 = bottom)
- **Add** `String? editorActiveLayerId` — persisted in the `editor:` YAML block
- `List<Thread> threads` unchanged (global across all layers)

#### File format (`.stitchx` YAML)

```yaml
layers:
  - id: "uuid-1"
    name: "Background"
    visible: true
    opacity: 0.4
    stitches: [...]
  - id: "uuid-2"
    name: "Main design"
    visible: true
    opacity: 1.0
    stitches: [...]
editor:
  selectedThread: "310"
  activeLayer: "uuid-2"
  tool: "fullStitch"
  stitchMode: false
```

#### Migration (backward compatibility)

`CrossStitchPattern.fromYaml`:
- If `layers:` key present → parse normally
- If only `stitches:` key present (old format) → wrap in a single `Layer` named "Layer 1" with `visible: true, opacity: 1.0`
- Old files open without any user action; fully non-breaking

### UI: Layers Panel

**Placement:** Right-hand sidebar in both workspace (folder sidebar on left, layers on right, canvas in middle) and standalone editor (canvas fills left, layers on right).

**Always visible in design mode.** No collapse toggle. Width: ~170dp fixed.

**Layout per layer row:**
- Eye toggle button (filled green circle = visible, hollow grey = hidden)
- Layer name (double-tap to rename inline)
- ⋮ `PopupMenuButton`
- Inline opacity slider below the name row (only shown when layer is expanded or always inline — always inline for compactness)

**Active layer:** highlighted with a coloured right border + a "Drawing on: [name]" chip in the bottom-left of the canvas (overlay painter).

**⋮ menu per layer:**
- Rename
- Move up / Move down
- Duplicate
- Merge down (merges this layer's stitches into the layer below; disabled for bottom layer)
- Delete layer *(goes on the undo stack)*

**+ button** (top of panel header): adds a new empty layer above the active layer.

**Drag to reorder:** `ReorderableListView` — dragging changes Z-order. Reorder goes on undo stack.

**Layer border direction:** right border faces inward toward the canvas, natural from either side.

#### New widget: `LayersPanel` (`lib/widgets/layers_panel.dart`)

Self-contained `ConsumerWidget`. Reads `editorProvider` for layer list and active layer. Calls notifier methods for all mutations.

### `EditorScreen` / `WorkspaceScreen` layout

**Workspace:**
```
Row([
  FileSidebar (resizable, left),
  _ResizeDivider,
  Expanded(Column([canvas, EditorToolbar])),
  LayersPanel (fixed 170dp, right),
])
```

**Standalone editor:**
```
Row([
  Expanded(Column([canvas, EditorToolbar])),
  LayersPanel (fixed 170dp, right),
])
```

### `EditorState` changes

```dart
// New fields:
String activeLayerId;          // which layer drawing targets
bool showCompositeThreads;     // palette toggle: false = layer view, true = canvas view (session-only)
Map<String, Thread>? compositeThreadCache;  // lazily computed; null = needs recompute
```

**Getters to add:**
```dart
Layer get activeLayer => pattern.layers.firstWhere((l) => l.id == activeLayerId);
Iterable<Layer> get visibleLayers => pattern.layers.where((l) => l.visible);
```

### `EditorNotifier` changes

All drawing operations (`drawStitch`, `eraseStitch`, `floodFill`, `floodFillErase`, `pasteClipboard`) target `activeLayerId` — modification is scoped to that layer's stitch list only.

**New methods:**
```dart
void addLayer()
void deleteLayer(String id)          // goes on undo stack
void renameLayer(String id, String name)
void toggleLayerVisible(String id)
void setLayerOpacity(String id, double opacity)
void moveLayer(String id, int delta) // +1 = up, -1 = down
void duplicateLayer(String id)
void mergeLayers(String topId)       // merges topId into the layer below it
void setActiveLayer(String id)
```

All mutations that change `pattern.layers` push to the undo stack automatically (they snapshot the full `CrossStitchPattern` like all other edits).

**Explicit note on delete:** `deleteLayer` calls `_pushUndo()` before modifying, ensuring layer deletion is fully reversible via Cmd+Z.

**Active layer guard:** if `activeLayerId` refers to a deleted layer, fall back to the topmost visible layer (or the topmost layer if all are hidden).

### Selection behaviour

Rubber-band select, flood fill, erase, and draw all operate on the **active layer only**.

Future addition (not in scope): a "copy merged" function that copies visible stitches across all layers into the clipboard.

### Rendering (`canvas_painter.dart`)

`CanvasStaticPainter` iterates layers bottom-to-top:

```dart
for (final layer in pattern.layers) {
  if (!layer.visible) continue;
  if (layer.opacity < 1.0) {
    canvas.saveLayer(Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 255, 255, layer.opacity));
  }
  _drawLayerStitches(canvas, size, layer);
  if (layer.opacity < 1.0) canvas.restore();
}
```

`canvas.saveLayer` / `restore` handles opacity compositing natively — no custom blending needed.

**Cache invalidation:** static painter re-caches on any `layer.visible` or `layer.opacity` change, in addition to existing triggers. Active layer switch does not require static repaint (only the overlay chip updates).

### Opacity & composite thread colours

Layer opacity is a **design concept, not a stitching concept** — physical thread has no transparency. When any layer has opacity < 1.0, the visual colour of a cell is a blend of multiple layers, which may not correspond to any source thread. The app resolves this by computing a **composite thread** for each cell: blend all visible layers bottom-to-top at their opacities → nearest DMC via CIE Lab matching (same algorithm as `SpriteImporter.matchPixel`).

Two distinct thread lists exist at all times:

- **Source threads** — what's stored in each layer; what the user draws with
- **Composite threads** — nearest DMC for each cell after blending all visible layers; what the user actually needs to stitch

`pattern.threads` remains the union of all source threads across all layers (unchanged role — used for the drawing palette). Composite threads are computed lazily and cached until any layer changes.

#### Edit mode — palette toggle

The editor toolbar palette gains a small toggle chip with two states:

- **Layer** (default) — shows threads for the active layer only; this is the drawing palette. Tapping a colour draws with that source thread.
- **Canvas** — shows composite threads for the full visible canvas (read-only reference). No drawing action; purely informational.

When a layer has opacity < 1.0 and the user is in **Layer** view, a subtle indicator appears near the palette: *"Opacity active — Canvas view shows resulting stitch colours."* Tapping it switches to Canvas view.

#### Stitch mode

Layers panel is hidden entirely in stitch mode. Stitch mode **always shows composite threads** — the thread list, stitch count, and progress tracking all use the composite result. The user never has to toggle; stitch mode simply presents the correct "what to buy and stitch" view automatically.

#### Composite computation

```dart
// For each cell (x, y) in the canvas:
// 1. Start with aida background colour
// 2. For each visible layer, bottom to top:
//    - Find stitch at (x, y) in that layer (if any)
//    - Blend: result = Color.lerp(result, stitchColour, layer.opacity)
// 3. Match blended colour → nearest DMC via SpriteImporter._rgbToLab / CIE Lab distance
// 4. Build Map<(x,y), DmcCode> → group into composite thread list
```

Computation is O(width × height × layerCount) — fast for typical cross-stitch canvas sizes. Cached as `_compositeThreadCache` on `EditorState`; invalidated whenever any layer's stitches, visibility, or opacity changes.

---

## Feature 2: Snippet Multi-Palette System

### Scope

- Palettes belong to snippets, not the main canvas.
- The main canvas is unaffected.
- The sprite importer gains a palette-strip selection workflow.
- The snippet editor gains a palette manager with add/rename/delete/reorder.

### Data Model

#### New `SnippetPalette` class (`lib/models/snippet_palette.dart`)

```dart
class SnippetPalette {
  final String id;             // UUID v4
  final String name;           // "Palette 1", "Winter", "Summer", etc.
  final List<Thread> threads;  // ordered — index position = slot
}
```

#### `Snippet` changes

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

#### Slot mapping

- `palettes[0]` = the **primary palette** (defines the slot order)
- `palettes[n].threads[i]` replaces `palettes[0].threads[i]` when palette `n` is active
- Rendering builds a `Map<String, Thread>` from the active palette: `{ baseThreadId: replacementThread }`
- All palettes must have the same slot count (enforced at creation)

#### File format

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

#### Migration (backward compatibility)

If a snippet has no `palettes:` key, its existing `threads:` list becomes `palettes[0]` named "Palette 1" with `activePalette: 0`. Fully non-breaking.

#### Delete rules

- Any palette can be deleted as long as ≥ 2 remain
- No special protection on the first palette
- If palette 0 (primary) is deleted, palette 1 becomes the new primary (slot definitions shift; stitch thread IDs are unchanged since they were always base-relative)
- When only 1 palette remains, the delete button is hidden/disabled
- "Last palette cannot be deleted" is a UI constraint only (no data model enforcement needed)

### Snippet Panel UI

**Palette switcher dots** (replaces existing dots below thumbnails):
- Shown only when `snippet.palettes.length > 1`
- One dot per palette; filled/highlighted = active palette
- Tap a dot to switch active palette — thumbnail re-renders immediately
- More than 6 palettes: show `"2/7"` style counter instead of individual dots

**⋮ menu addition:** "Manage palettes…" — opens palette manager in the snippet editor.

### Snippet Editor UI

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

### Sprite Importer Redesign (`sprite_sheet_screen.dart`)

#### Remove tile mode

The fixed tile grid (Tile / Crop segmented button) is removed. **Only crop mode exists.**

#### Interaction model

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

#### Controls panel (right sidebar)

- **Palettes section:** lists auto-default (greyed) or confirmed palettes with swatches; × to remove each (Palette 1 cannot be removed while others exist — removing it would clear all palettes and revert to auto-default)
- **"Add palette strip" / "Draw another palette strip"** CTA
- **Simplify palette slider** — unchanged from current behaviour
- **Snippet name field** + **"Add to Snippets"** button (disabled until crop is non-empty)
- **"Change image"** button (top right of AppBar area)
- **"Close"** button replacing the current "Done" label

#### Preview panel (bottom)

A preview panel shows the current crop rendered as a pixelated snippet preview:
- Tabs: one per palette (auto-default shown as "Default" tab; no tab until a strip is added)
- Clicking a tab switches the preview to show that palette's colours applied
- A slot-mapping column to the right of the preview grid shows `[swatch] → [swatch] DMC XXX → DMC YYY` for the active palette tab
- Preview updates live as the crop region or palette strips are adjusted

#### Import result

When "Add to Snippets" is tapped:
- `SpriteImporter.importRegion` runs as before for the crop
- All defined palette strips are also processed via `SpriteImporter.importRegion` (or a lighter colour-only pass)
- The resulting `Snippet` is created with `palettes` populated: one entry per confirmed strip (Palette 1, Palette 2, …); the auto-default is discarded
- If no strips were defined, the snippet is created with a single palette derived from the crop colours (same as current behaviour)
- `activePaletteIndex` defaults to 0

### Rendering with active palette

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

## Shared Notes

- **"Done" → "Close"** on dismiss buttons throughout the app (logged as improvement #12). Applies to `SpriteSheetScreen` (confirmed) and any other screen using `Text('Done')` as a dismiss action.
- Both features are independent — either can be shipped without the other.
- Layer count and palette count are not capped (no artificial limits enforced).

---

## Files Affected

### Canvas Layers

| File | Change |
|------|--------|
| `lib/models/layer.dart` | **New** |
| `lib/models/pattern.dart` | Replace `stitches` with `layers`; add `editorActiveLayerId` |
| `lib/providers/editor_provider.dart` | Add `activeLayerId` to state; add layer management methods; scope all drawing to active layer |
| `lib/services/file_service.dart` | Serialise/deserialise `layers`; migration path for old `stitches` key |
| `lib/widgets/layers_panel.dart` | **New** |
| `lib/widgets/canvas_painter.dart` | Iterate layers bottom-to-top with `saveLayer`/`restore` for opacity |
| `lib/screens/editor_screen.dart` | Add `LayersPanel` to right of layout; update Pattern Info stitch count to sum across all layers |
| `lib/screens/workspace_screen.dart` | Add `LayersPanel` to right of layout |

### Snippet Multi-Palette

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
