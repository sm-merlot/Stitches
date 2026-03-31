# Materials List / Skein Calculator

**Date:** 2026-03-31
**Status:** Approved

## Overview

A materials list screen that calculates how many DMC thread skeins are needed for a pattern, accounting for the stitcher's preferred aida count and strand count. Opened from the stitch mode AppBar. Read-only in the app; exports a plain-text checklist via the platform share sheet.

---

## Trigger

A shopping-bag icon button added to the stitch mode AppBar actions, alongside the existing block mode toggle and stitch demo button.

---

## Presentation

| Platform | Form |
|---|---|
| macOS desktop | `showDialog` — fixed 480 pt wide, scrollable content |
| iPad (`shortestSide ≥ 600`) | `showDialog` — fixed 480 pt wide, scrollable content |
| Phone (iOS / Android) | Full-screen modal via `Navigator.push` + `MaterialPageRoute` |

Detection: `MediaQuery.of(context).size.shortestSide >= 600` → dialog, else full-screen.

---

## Layout

```
┌─────────────────────────────────────┐
│  Materials List             [Close] │
├─────────────────────────────────────┤
│  Aida count: [▼ 14]  Strands: [▼ 2] │
│  ▓ Aida: at least 27 × 22 cm        │
│          (10.6 × 8.7 in)        [ⓘ] │
├──────┬───────┬──────────────┬───────┤
│Swatch│  DMC  │     Name     │Skeins │
├──────┼───────┼──────────────┼───────┤
│  ██  │  310  │  Black       │   2   │
│  ██  │  321  │  Red - med   │   1   │
│  …   │  …    │  …           │  …    │
├─────────────────────────────────────┤
│  Total: 14 threads · 23 skeins      │
│                      [Share  ↗]     │
└─────────────────────────────────────┘
```

### Inputs

- **Aida count** — `DropdownButton` with values `[11, 14, 16, 18, 28, 32]`, default `14`. Local state, not persisted.
- **Strands** — `DropdownButton` with values `[1, 2, 3, 4, 5, 6]`, default `2`. Local state, not persisted.

### Aida size row

Displays the minimum aida fabric size needed, including a 5 cm border on each side for framing and mounting:

```
aidaWidthCm  = (pattern.width  / aidaCount) × 2.54 + 10
aidaHeightCm = (pattern.height / aidaCount) × 2.54 + 10
aidaWidthIn  = aidaWidthCm  / 2.54
aidaHeightIn = aidaHeightCm / 2.54
```

Shown as: `"at least 27.3 × 22.1 cm  (10.7 × 8.7 in)"`

A small colour swatch showing `pattern.aidaColor` precedes the text.

The **ⓘ** button uses Flutter's `Tooltip` widget with `triggerMode: TooltipTriggerMode.tap`. On desktop it shows on hover automatically; on touch it shows on tap. Tooltip text: *"Includes a 5 cm (2 in) border on each side for framing and mounting."*

### Thread table

Scrollable. One row per composite thread (same set shown in stitch mode colours panel — reads `compositeThreadCache`). Columns:

| Column | Width | Content |
|---|---|---|
| Swatch | 36 pt | Filled colour square with thread symbol overlaid (same rendering as stitch mode panel) |
| DMC | 52 pt | DMC code string |
| Name | flex | Thread name |
| Skeins | 52 pt | Skein count (see formula), right-aligned |

### Footer

`"Total: N threads · N skeins"` on the left. **Share** button (icon + label) on the right.

---

## Skein Calculation

All calculations are reactive — recomputed whenever aida count or strands change.

### Constants

```
DMC_SKEIN_METRES  = 8.0
DMC_TOTAL_STRANDS = 6
WASTE_FACTOR      = 1.3   // 30% for travel, finishing, mistakes
```

### Cross-stitch thread per stitch

```
cellMm              = 25.4 / aidaCount
metersPerFullStitch = strands × 4 × √2 × (cellMm / 1000) × WASTE_FACTOR
```

Partial stitches scale linearly (half = 0.5, quarter = 0.25). The `crossStitchEquiv` sum already stores fractional equivalents.

### Backstitch thread

Backstitch segments are measured as Euclidean cell-unit lengths (e.g. a one-cell horizontal = 1.0, a diagonal = √2):

```
metersPerBackCell = strands × 2 × (cellMm / 1000) × WASTE_FACTOR
```

### Usable metres per skein

Separating `strands` strands from a 6-strand skein:

```
usableMetresPerSkein = DMC_SKEIN_METRES × (DMC_TOTAL_STRANDS / strands)
```

### Skeins per thread

Cross-stitch and backstitch contributions are combined before rounding:

```
totalMetres = (crossEquiv × metersPerFullStitch)
            + (backCells  × metersPerBackCell)

skeins = max(1, ceil(totalMetres / usableMetresPerSkein))
```

Minimum 1 skein for any thread that has stitches.

---

## Share Text Format

Plain text shared via `share_plus` package (new dependency):

```
Materials List — {pattern.name}
{aidaCount}-count aida · {strands} strands
Aida: at least {W} × {H} cm ({W} × {H} in)

☐ {dmc}  {name}  {n} skein(s)
☐ ...

Total: {N} threads · {N} skeins
```

On iOS/Android: opens native share sheet.
On macOS: opens macOS share panel.

---

## Data Source

Reads from `EditorState` at the time the screen is opened (passed in as a constructor parameter — no live `ref.watch`). Uses:

- `state.compositeThreadCache` — the composite thread map (cell key → Thread) for thread identity and stitch counts
- `state.pattern.stitches` — for backstitch segment lengths (only visible-layer stitches, since `pattern.layers` applies group/layer visibility)
- `state.pattern.aidaColor`, `state.pattern.width`, `state.pattern.height`
- `state.pattern.threads` — for thread names (composite cache values may be synthetic blended threads without full names; fall back to pattern threads by dmcCode)

---

## New Files

| File | Purpose |
|---|---|
| `lib/screens/materials_list_screen.dart` | `MaterialsListScreen` widget (full-screen) and `showMaterialsListDialog` helper (dialog wrapper) |

No new models. No new providers. No persistence.

---

## New Dependency

```yaml
share_plus: ^11.0.0   # or latest compatible
```

---

## Out of Scope

- PNG export (deferred)
- Persisting aida count / strand count to the pattern file
- Per-thread "purchased" checkboxes
- Currency / cost estimation
