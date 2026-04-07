# Three-Mode Architecture Design

**Date:** 2026-04-04
**Status:** Approved, awaiting implementation
**Depends on:** File Format v2 (for pageMode relocation)
**Required by:** Progress Tracking

---

## Problem

The current two-mode design (Design ↔ Stitch) is showing strain. Stitch mode is simultaneously a reference viewer, a page navigator, a materials consultant, and a demo player. There is no clear "default" state — files open into the full editor, which is intimidating for users who just want to look at or share their pattern.

---

## Goals

- Three clearly purposeful modes: View (overview), Stitch (active stitching), Edit (pattern design)
- Files always open in View mode — safe, read-only, no accidental edits or progress marks
- Edit and Stitch are deliberate entries from View
- Each mode has a focused, coherent set of features

---

## Mode Definitions

### View mode (default)
Overview and planning. Read-only — no edits, no progress marking.

**Features:**
- Full pattern preview (colours, all layers visible)
- Colour list — see where each colour appears in the pattern
- Focus mode — highlight a single colour across the pattern
- Materials list (thread counts, shopping list)
- Pattern info (name, designer, dimensions, notes)
- Share / Export (`.stitches`, PDF, PNG overview)

**AppBar:** Pattern name + Share button + "Edit" button + "Stitch" button

---

### Edit mode
Full pattern editor. Identical in capability to the current design mode.

**Entry:** "Edit" button from View mode only.
**Exit:** "Finished" button — returns to View mode. Cannot jump directly to Stitch.

**Features:**
- All current editor functionality: drawing tools, layers, colour picker, snippets, sprite sheet importer
- Reference image overlay
- Block mode toggle
- Resize Aida
- Keyboard shortcuts

**AppBar:** "Finished" button prominently placed (replaces current stitch-mode toggle)

---

### Stitch mode
For active stitching sessions at the embroidery frame.

**Entry:** "Stitch" button from View mode only (not from Edit).
**Exit:** Back / exit button → returns to View mode.

**Features:**
- Page navigation (only available here — requires page mode config set in Edit)
- Progress tracking (tap/drag/flood-fill to mark stitches done) — see Progress Tracking spec
- Colour list — shows done/remaining counts per colour
- Focus mode — highlight a colour to find your next stitches
- Stitch demo
- Keep-screen-on toggle

**AppBar:** Exit button + page indicator (if page mode) + keep-screen-on toggle

---

## Mode Transitions

```
┌─────────────────────────────────────────────┐
│                                             │
│   Open file ──→ VIEW                        │
│                  │                          │
│          ┌───────┴───────┐                  │
│          ▼               ▼                  │
│         EDIT           STITCH               │
│          │               │                  │
│          └───────┬───────┘                  │
│                  ▼                          │
│                VIEW                         │
│                                             │
└─────────────────────────────────────────────┘
```

- **View → Edit:** "Edit" button
- **Edit → View:** "Finished" button (only exit from Edit)
- **View → Stitch:** "Stitch" button
- **Stitch → View:** back/exit button
- **Edit → Stitch:** not allowed (must finish editing first)
- **Stitch → Edit:** not allowed (must exit stitch mode first)

---

## Feature Distribution

| Feature | View | Stitch | Edit |
|---|:---:|:---:|:---:|
| Pattern overview | ✓ | | |
| Colour list | ✓ | ✓ | |
| Focus mode | ✓ | ✓ | |
| Materials list | ✓ | | |
| Pattern info | ✓ | | |
| Share / Export | ✓ | | |
| Page navigation | | ✓ | |
| Progress tracking | | ✓ | |
| Colour completion toast | | ✓ | |
| Stitch demo | | ✓ | |
| Keep-screen-on | | ✓ | |
| Drawing tools | | | ✓ |
| Layers | | | ✓ |
| Colour picker | | | ✓ |
| Snippets | | | ✓ |
| Sprite sheet importer | | | ✓ |
| Reference image | | | ✓ |
| Block mode | | | ✓ |
| Resize Aida | | | ✓ |
| Keyboard shortcuts | | | ✓ |

---

## State

Add `AppMode` enum to `EditorState`:

```dart
enum AppMode { view, stitch, edit }
```

Replace `EditorState.stitchMode: bool` with `EditorState.mode: AppMode`.

Computed helpers for existing consumers:
```dart
bool get stitchMode => mode == AppMode.stitch;
bool get editMode => mode == AppMode.edit;
```

---

## Implementation

### Files to change

**`lib/providers/editor/editor_provider.dart`**
- Replace `stitchMode: bool` with `mode: AppMode` in `EditorState`
- Add `setMode(AppMode)` to `EditorNotifier`
- Keep `bool get stitchMode` computed getter for backwards compatibility during migration

**`lib/screens/editor_screen.dart`**
- Currently handles both design and stitch modes
- Refactor AppBar to render per-mode actions
- "Edit" and "Stitch" buttons in view mode AppBar
- "Finished" button in edit mode AppBar
- Exit button in stitch mode AppBar

**`lib/screens/workspace_screen.dart`**
- Same AppBar refactor as editor_screen
- Page mode button moves from stitch-mode AppBar to Stitch mode only

**`lib/utils/editor_key_handler.dart`**
- Update mode checks from `state.stitchMode` to `state.mode`

### Workspace screen note
The workspace screen (desktop) has a file sidebar. In View and Edit modes the sidebar remains. In Stitch mode the sidebar should be hidden (full-screen stitching experience).

### Page mode config
Page mode is configured in Edit mode (not Stitch). The page config dialog (`page_mode_dialog.dart`) moves from the stitch-mode AppBar to the Edit mode overflow menu or toolbar. Stitch mode then reads and applies the config but does not expose settings controls.

---

## Testing

- Open any file → confirm it opens in View mode
- View → Edit → Finished → confirm returns to View
- View → Stitch → exit → confirm returns to View
- Confirm Edit → Stitch transition is not possible
- Confirm all features listed above appear in correct modes
- Confirm keyboard shortcut guard (`state.stitchMode`) works correctly post-migration
