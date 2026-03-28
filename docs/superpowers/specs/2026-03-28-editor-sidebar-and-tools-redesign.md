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

| Context | Tabs | Colours panel variant |
|---|---|---|
| Main editor — design | `Layers` \| `Colours` | Simple (tap = set active colour) |
| Main editor — stitch | `Colours` only (no tab bar) | Rich (focus, filters, demo) |
| Snippet editor | `Palettes` \| `Colours` | Simple (tap = set active colour) |

Snippet editor has no stitch mode — it is always in design/drawing mode.

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

Replaces `_PaletteManagerSheet`. Manages the list of palettes a snippet has.

#### Palette data model

Palette 1 (index 0) is the **primary palette** — stitches are always stored using its DMC codes internally. All other palettes are display remappings: when palette N is active, each stitch's primary-palette DMC code is resolved to its slot index, then palette N's colour for that slot is used for rendering and drawing. This means drawing on any palette always stores the primary palette's equivalent colour — switching back to palette 1 always renders consistently.

Reordering palettes is not supported — the cosmetic benefit doesn't justify the complexity, and the primary palette's position (index 0) is load-bearing.

#### Palette list UI

- Scrollable list of palettes; tap to activate
- Active palette: highlighted with primary-colour left border
- Double-tap name to rename inline
- Delete button per row (disabled when only one palette)
- "Add palette…" button at bottom → opens `_AddPaletteDialog` as before

#### Editing colours in existing palettes

Each palette row is expandable to show its colour slots. Tap any slot to replace its colour via the DMC picker — this updates only that slot in that palette. Other palettes are unaffected.

#### Adding new colours

New colours are added **implicitly** when the user stitches a colour not currently in any palette slot. The new colour is added as a new slot to **all palettes simultaneously**, defaulting to the same colour in every palette. The user then edits individual palettes via the slot editor above to set their alternate colourway for that slot.

There is no manual "add colour" button — the draw-to-add flow is the only path.

#### Duplicate slot conflict

A conflict occurs when a newly added slot's default colour is already used by a different slot in an existing palette. Example:

| Palette | Slot A | Slot B | Slot C | Slot D (new) |
|---|---|---|---|---|
| 1 | Blue | Red | Orange | Purple |
| 2 | Purple | Pink | Green | Purple ← duplicate |

Palette 2 now has Purple in both Slot A and Slot D. Since slot resolution uses the first match, **Slot D is unreachable for drawing while Palette 2 is active** — any Purple stitch will always resolve to Slot A.

Duplicate slots are flagged with an amber warning indicator on the affected row in the Palettes tab. The warning message reads: *"Same colour as Slot A — this slot can't be drawn on Palette 2 until it's given a unique colour."*

The warning is informational, not blocking. The user resolves it by editing Slot D in Palette 2 to a different colour.

#### Model integrity on load

When loading a snippet, validate that all palettes have the same number of slots. If any palette has fewer slots than the primary palette (e.g. from file corruption), pad the short palette by copying the primary palette's colour for the missing slots. Log a warning but do not error.

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

#### Stitch mode variant (main editor stitch mode only)

**Header row (always visible at top of panel):**
```
┌─ Stitch Focus: ──────────┐
│  [ ✕ Cross ]  [ ╱ Back ] │  [ ▶ Demo ]
└──────────────────────────┘
```

- **Cross**: focus on cross stitches — hides backstitches, normal stitches shown in colour (icon: filled ✕)
- **Back**: focus on backstitches — greys normal stitches, backstitches shown in colour (icon: diagonal stroke)
- The two buttons are grouped in a bordered container labelled "Stitch Focus:" making their shared purpose clear
- Demo sits outside the border — it is a different class of action (launches a screen) not a view filter

Toggles behave like a radio group that can be fully off — at most one active at a time:
- Tapping an inactive toggle enables it and disables the other
- Tapping the active toggle disables it (both off)

**What each toggle does:**

| State | Normal stitches | Backstitches |
|---|---|---|
| None | Colour | Colour |
| Cross | Colour | Hidden |
| Back | Grey | Colour |

The intent: *Cross* lets you focus on normal stitches; *Back* lets you focus on backstitches.

**Colour focus** (tap a thread row to toggle):
- Tap to focus a colour; tap again to unfocus; only one colour focused at a time
- Toggles and focus compose:

| State | Normal stitches | Backstitches |
|---|---|---|
| Focus only | Focused: colour / Others: grey | Focused: colour / Others: grey |
| Focus + Backstitch off | Focused: colour / Others: grey | Hidden |
| Focus + Grey | Grey | Focused: colour / Others: grey |

- Demo button: launches `StitchDemoScreen` (replaces stitch mode toolbar demo button)
- Thread list shows composite canvas colours only — threads in hidden or merged layers excluded

#### Design mode and snippet editor variant (simpler)

- Thread list: colour swatch + symbol, DMC/Anchor code, name, stitch count
- Tap a thread to set it as the active drawing colour
- No filter toggles, no focus mode, no demo button
- Design mode: shows active layer's threads or composite (controlled by Layer/Canvas toggle, which moves here from the toolbar)
- Snippet editor: shows threads in the currently active palette

---

### A4 — Stitch mode toolbar removal

The stitch mode toolbar is removed entirely. Every item either moves to the sidebar or becomes redundant:

- Pan mode button → removed (Chunk B; panning via two-finger/middle-click)
- Focus thread swatches row → Colours panel
- View mode buttons (Show all / Hide backstitches / Grey stitches) → Colours panel header (Cross/Back toggles)
- Demo button → Colours panel header

Select mode is always-on in stitch mode — there is nothing to toggle, so no button is needed. The toolbar widget is not rendered at all in stitch mode.

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
