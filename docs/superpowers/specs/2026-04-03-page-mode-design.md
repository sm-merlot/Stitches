# Page Mode — Design Spec

**Date:** 2026-04-03
**Branch:** `scme0/feature/page-mode` (off main)

## Overview

Stitch mode gains an optional "page mode" that splits a pattern into pages of a configurable size (stitches × stitches). The user navigates one page at a time, with the canvas auto-fitting to each page. Pages can have "fuzzy edges" — rather than a hard straight line at the boundary, each row/column near the boundary terminates at a natural colour change or a seeded pseudo-random offset, so there's no visible stitch-line when working a page at a time.

---

## Data Model

### `PageConfig` (persisted with pattern)

```dart
class PageConfig {
  final bool enabled;
  final int pageWidth;   // stitches across per page
  final int pageHeight;  // stitches down per page
  final int fuzzyAmount; // 0–3 stitches
}
```

Serialised to YAML under a `pageMode:` key in the `.stitches` file. `currentPage` is **not** persisted — always starts at 0.

### `PageLayout` (computed, not persisted)

Derived from `PageConfig` + pattern dimensions when config changes or the pattern is edited. Stored in `EditorState` and reused until invalidated.

Fields:
- `pagesAcross`, `pagesDown`, `totalPages`
- Fuzzy offsets: `Map<boundaryIndex, Map<rowOrCol, int>>` — one offset per row/column crossing each boundary

**Fuzzy offset computation per row/column at a boundary:**
1. Inspect the stitches within `±fuzzyAmount` cells of the boundary on both sides
2. If a **colour change** occurs in that zone, snap the boundary to the nearest colour change to the nominal edge — this prevents tiny slivers of a single colour appearing on a page
3. If no colour change exists in the zone, use a seeded pseudo-random offset in `[-fuzzyAmount, +fuzzyAmount]`
4. Seed: hash of `patternWidth + patternHeight + pageWidth + pageHeight + boundaryIndex`; recomputed only when the pattern is edited or config changes

### `PageModeState`

Added to `EditorState`:

```dart
class PageModeState {
  final PageConfig config;
  final int currentPage;       // session only
  final PageLayout? layout;    // computed lazily, null until first access
}
```

---

## Canvas Rendering

`CanvasStaticPainter` receives `PageModeState?`. When page mode is active:

- Each stitch is checked against the current page's fuzzy boundaries from `PageLayout`
- Only stitches that fall within the current page are painted — no dimming, clean page
- Grid lines and labels are also clipped to the current page region
- The aida background fills the full widget to avoid layout jumps during navigation
- The existing `RepaintBoundary` wrapping the static layer means page navigation repaints only the static layer

When `currentPage` changes, `EditorNotifier._fitToPage(int page)` computes the `panOffset` and `scale` needed to centre and fill the current page in the viewport (same logic as pattern open auto-fit), then updates state. Navigation plays a brief animated transition to the new pan/zoom.

---

## Navigation

Available in stitch mode when page mode is enabled:

| Input | Action |
|---|---|
| Prev/Next arrow overlay buttons (canvas edges) | Navigate one page |
| Swipe left/right (mobile) | Navigate one page |
| Left/Right arrow keys (desktop) | Navigate one page |
| Tap page indicator (`3 / 12`) | Open page grid |
| Page grid (modal bottom sheet) | Jump to any page |

**Page grid:** renders all pages as thumbnails in a grid using the same `SnippetThumbnail`-style painter, tappable to jump directly to a page.

**Page indicator:** centred text at the bottom of the canvas showing `currentPage + 1 / totalPages`, tappable.

---

## Config UI

A **Page Mode icon button** is added to the app bar in stitch mode. The icon is highlighted when page mode is enabled.

Tapping opens a dialog:

| Control | Detail |
|---|---|
| Enable toggle | Turns page mode on/off |
| Page Width | Integer field (stitches across); defaults to half pattern width |
| Page Height | Integer field (stitches down); defaults to half pattern height |
| Edge fuzziness | Slider 0–3 stitches; 0 = flat edge, 3 = maximum fuzz |

On confirm: config is saved to the pattern, `currentPage` resets to 0, `PageLayout` is recomputed, canvas fits to page 0.

---

## Persistence

- `PageConfig` (enabled, pageWidth, pageHeight, fuzzyAmount) — saved in `.stitches` YAML
- `currentPage` — session only, always opens at page 0
- `PageLayout` — never persisted, always recomputed

---

## Files Affected

```
lib/
  models/
    page_config.dart          NEW — PageConfig value object
    page_layout.dart          NEW — PageLayout + fuzzy offset computation (takes PageConfig + pattern stitch data)
  providers/editor/
    editor_provider.dart      add PageModeState to EditorState
    editor_provider_drawing.dart  add _fitToPage(), page navigation methods
  widgets/
    pattern_canvas.dart       pass PageModeState to painters; nav chrome overlay
    canvas_painter.dart       clip stitches/grid to current page
    page_grid_sheet.dart      NEW — modal bottom sheet page grid
  screens/
    editor_screen.dart        add page mode icon button to stitch mode app bar
  services/
    file_service.dart         serialise/deserialise PageConfig in YAML
```

---

## Out of Scope

- Per-page notes or annotations
- Printing pages (covered by PDF export feature)
- Page mode in design mode
