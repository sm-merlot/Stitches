# Editor, Stitch Mode & Snippet Editor Redesign

**Date:** 2026-03-28
**Scope:** Main editor, stitch mode, and snippet editor backlog items

---

## Overview

Four discrete chunks of work that address overlapping backlog items across all three editing contexts. The central change is replacing the ad-hoc palette modal/drawer system with a persistent, collapsible right sidebar. The remaining chunks clean up tools and add flip/rotate capabilities.

---

## Chunk A — Right Sidebar Redesign

### Current state

| Context | Right side | Palette access |
|---|---|---|
| Main editor — design | Layers panel (always visible) | Modal dialog, toolbar button |
| Main editor — stitch | Empty (layers hidden) | Right-side drawer (on demand) |
| Snippet editor | Nothing | Bottom sheet (`_PaletteManagerSheet`) |

### New state

A single collapsible right sidebar replaces all of the above. Its tab structure varies by context:

| Context | Tabs |
|---|---|
| Main editor — design | `Layers` \| `Colours` |
| Main editor — stitch | `Colours` only (no tab bar) |
| Snippet editor | `Palettes` \| `Colours` |

The sidebar is collapsible (persisted in SharedPreferences) — a chevron button collapses it to a thin strip for more canvas space. Width is drag-to-resize, same as the current layers panel.

**Removed as redundant:**
- Palette modal dialog + toolbar palette button (design mode)
- Stitch mode right-side end drawer
- `_PaletteManagerSheet` bottom sheet in snippet editor
- Focus thread swatches row in stitch mode toolbar
- View mode buttons (Show all / Hide backstitches / Grey stitches) in stitch mode toolbar
- Demo button in stitch mode toolbar

---

### A1 — Layers tab (main editor design mode only)

Identical to the current layers panel — no functional changes. Layer groups, reorder, visibility, opacity, rename, merge, delete. Just moved into the tab system.

---

### A2 — Palettes tab (snippet editor only)

Replaces `_PaletteManagerSheet`. Manages the list of palettes a snippet has:

- Scrollable list of palettes; tap to activate
- Active palette: highlighted with primary-colour left border
- Drag to reorder
- Double-tap name to rename inline
- Delete button per row (disabled when only one palette)
- "Add palette…" button at bottom → opens `_AddPaletteDialog` as before

---

### A3 — Colours panel

Two variants depending on context.

#### Design mode variant (main editor only)

Simpler — palette management, not view control.

- Thread list: colour swatch + symbol, DMC/Anchor code, name, stitch count
- Tap a thread to set it as the active drawing thread
- Layer/Canvas toggle (currently in toolbar) moves here — controls whether the list shows the active layer's threads only or the blended composite view
- No filter controls, no demo button

**Note:** Quick swatches in the toolbar stay — they serve a different purpose (rapid recent-thread switching without looking at the sidebar).

#### Stitch mode / Snippet editor variant (richer)

**Header row (always visible at top of panel):**
```
[ 〇 Backstitch ]  [ 〇 Grey ]  │  [ ▶ Demo ]
```
- Backstitch toggle: hides/shows backstitch stitches (replaces stitch mode toolbar "Hide backstitches")
- Grey stitches toggle: dims non-focused stitches (replaces stitch mode toolbar "Grey stitches")
- Divider
- Demo button: launches `StitchDemoScreen` (replaces stitch mode toolbar demo button)
- "Show all" is implicit: both toggles off = default visible state

**Thread list:**
- Colour swatch with symbol overlay, DMC/Anchor code, name, stitch count
- Tap a thread to toggle focus (highlighted border when focused, others dimmed on canvas)
- Multiple threads can be focused simultaneously
- Stitch mode: shows composite canvas colours only — threads in hidden layers or merged layers are excluded
- Snippet editor: shows threads in the currently active palette

---

### A4 — Stitch mode toolbar cleanup

After the sidebar takes over view controls and pan mode is removed (Chunk B), the stitch mode toolbar simplifies to:

**Kept:**
- Select mode button [S]

**Removed:**
- Pan mode button (Chunk B)
- Focus thread swatches row (→ Colours panel)
- View mode buttons: Show all / Hide backstitches / Grey stitches (→ Colours panel header)
- Demo button (→ Colours panel header)

The stitch mode toolbar becomes very minimal — essentially just the Select mode button plus any future additions.

---

## Chunk B — Pan Mode Removal

### Design mode
- Remove the Pan tool button from the design mode toolbar
- `DrawingMode.pan` stays in the enum — Space-bar hold-to-pan still uses it internally, it just isn't a selectable persistent mode
- Panning: middle-click drag, two-finger drag, Space held down (all already work)

### Stitch mode
- Remove Pan button from stitch mode toolbar (see A4 above)
- Stitch mode already defaults to pan behaviour when no tool is active; two-finger and middle-click pan always work

### Keyboard shortcut
- Remove `P` as a keyboard shortcut for pan mode (or remap Space-hold behaviour if needed)
- Update keyboard shortcuts dialog

---

## Chunk C — Flip & Rotate

Three distinct contexts; same four operations in each: **Flip Horizontal**, **Flip Vertical**, **Rotate 90° CW**, **Rotate 90° CCW**.

Keyboard shortcuts (consistent across all contexts):
- Flip H: `Cmd+Shift+H` (or `Ctrl+Shift+H` on Windows/Linux)
- Flip V: `Cmd+Shift+V`
- Rotate CW: `Cmd+Shift+]`
- Rotate CCW: `Cmd+Shift+[`

---

### C1 — Selection flip/rotate (main canvas + snippet canvas)

- Available when: select mode is active AND a region has been selected
- Toolbar: flip/rotate buttons appear alongside existing copy / delete / save-as-snippet buttons
- Operation: transforms stitch positions within the selected bounding box, in place
- Pushes to undo stack as a single operation
- After transform, selection rect updates to match

---

### C2 — Paste mode flip/rotate (main canvas + snippet canvas)

- Available when: in paste mode (clipboard ghost is visible)
- Toolbar: flip/rotate buttons appear alongside the cancel button
- Operation: transforms the in-memory clipboard data; ghost preview updates immediately
- No undo needed for the transform itself — only the eventual stamp is undoable
- Allows the user to orient the paste content before committing

---

### C3 — Whole-canvas flip/rotate (snippet editor only)

- Available always in the snippet editor toolbar (not context-dependent)
- Separate button group from C1/C2 — always visible, not hidden behind a selection state
- **Flip**: reflects all stitch positions, canvas dimensions unchanged
- **Rotate 90°**: transforms all stitch positions AND swaps canvas width ↔ height (e.g. 16×8 becomes 8×16)
- Pushes to undo stack
- Positioned in the snippet editor toolbar in a dedicated section (left side, near other canvas-level controls)

---

### C4 — Remove from snippet ⋮ menu (SnippetsPanel)

- Remove the existing flip/rotate options from the snippet card context menu in `SnippetsPanel`
- These operations now live exclusively in the snippet editor

---

## Chunk D — Small Cleanups

### D1 — Remove opacity-layers info icon/tooltip
- Remove the info icon and tooltip next to the Canvas/Layer toggle in the toolbar
- The toggle itself moves to the Colours panel (see A3), so this resolves naturally

### D2 — Prevent accidental stitch moves in stitch mode
- Currently, dragging a selection in stitch mode can accidentally move stitches
- In stitch mode, drag on a selection should pan the canvas, not move stitches
- Selection in stitch mode is read-only: copy/paste/move operations disabled
- Only focus-toggling (tap) is active in stitch mode

### D3 — Hide irrelevant chrome in snippet editor
- Canvas/Layer mode toggle: hidden (snippets have no layers; this moves to Colours panel anyway per A3, where it won't be rendered in snippet context)
- "Drawing on layer X" canvas overlay chip: hidden in snippet editor (pass `activeLayerName: null` or suppress via existing `stitchMode` flag)
- Both are already prop-controlled; small conditional changes

### D4 — Unsaved changes warning in snippet editor
- Detect dirty state: compare canvas stitch data at session start vs. current
- On close attempt (back button, X, navigate away): if dirty, show confirmation dialog
  - "Discard changes?" with Cancel / Discard actions
- No autosave — snippet editor is always explicit save-on-pop

---

## What stays the same

- Layers panel functionality (just rehoused in a tab)
- Quick swatches in the design mode toolbar
- Active thread swatch + DMC code in the design mode toolbar
- Undo/Redo buttons in the design mode toolbar
- Aida colour button in the design mode toolbar
- All keyboard shortcuts not explicitly changed above
- Canvas/Layer toggle logic — just moves from toolbar to Colours panel
- `DrawingMode` enum values (pan stays, just not toolbar-selectable)

---

## Open questions

None — all design decisions resolved in conversation.
