# PDF Export Improvements — Design Spec
**Date:** 2026-04-01
**Branch:** scme0/feature/pdf-improvements (to be created)

---

## Overview

Four areas of improvement to the existing PDF export:
1. **Pattern metadata** — new optional fields on the pattern model, editable via Pattern Info screen
2. **PDF title page** — professional centred layout with metadata and materials tables
3. **Thread table** — two-column layout, pagination, symbol column header fix, visible-layers-only
4. **Bug fixes** — `_ascii()` replacement, en-dash in chart subtitles, symbol rendering on grid pages

Plus: extract skein calculation into a shared utility used by both the materials list dialog and the PDF.

---

## 1. Data Model — `CrossStitchPattern`

### New optional fields

```dart
final String? designer;
final String? description;
final String? difficulty;
final String? estimatedHours;   // free text, e.g. "6–8 hours"
final String? copyright;
final List<({int aidaCount, int strands})> materialsSuggestions; // max 3, default []
```

### Serialisation (YAML)

All fields are optional. Absent = null / empty list. Keys:
- `designer`, `description`, `difficulty`, `estimatedHours`, `copyright`
- `materialsSuggestions`: list of maps `{aidaCount: 14, strands: 2}`

`copyWith`, `fromYaml`, and `toYaml` updated accordingly.

---

## 2. Pattern Info Screen

### Behaviour

The existing read-only `AlertDialog` gains an in-place edit/view toggle.

**View mode** (default):
- Title row: "Pattern Info" + pencil `IconButton` (top-right)
- Existing rows: Name, Size, Threads, Stitches (canvas), Stitches (all layers), File — unchanged
- New rows (shown only when non-null/non-empty): Designer, Description, Difficulty, Est. time, Copyright
- Materials suggestions shown as a compact read-only list: "14-count · 2 strands", etc.

**Edit mode** (pencil tapped):
- Title row: "Edit Pattern" + Save `IconButton` (checkmark) + Cancel `IconButton` (X)
- Name → `TextFormField`
- Designer, Description, Difficulty, Est. time, Copyright → `TextFormField` each
- Difficulty has three quick-option chips below it: **Beginner** / **Intermediate** / **Advanced** — tapping fills the field
- Materials suggestions → compact editable list:
  - Each row: aida count `DropdownButton` ([11,14,16,18,28,32]) + strands `DropdownButton` ([1–6]) + delete `IconButton`
  - "Add suggestion" button (hidden when 3 suggestions already exist)
- Size, Threads, Stitches, File → remain read-only labels
- Save calls `editorProvider.notifier.updatePatternMetadata(...)`, returns to view mode
- Cancel discards all in-progress edits, returns to view mode

**Layout:**
- Wide screens (shortestSide ≥ 600): scrollable `AlertDialog`, `SingleChildScrollView` wrapping content
- Narrow screens: full-screen `MaterialPageRoute` with same content

### Provider change

Add to `EditorNotifier` (in `editor_provider_drawing.dart`):
```dart
void updatePatternMetadata({
  String? name,
  String? designer,
  String? description,
  String? difficulty,
  String? estimatedHours,
  String? copyright,
  List<({int aidaCount, int strands})>? materialsSuggestions,
})
```

---

## 3. Shared Skein Calculator

Extract to `lib/services/skein_calculator.dart`:

```dart
/// Returns the number of skeins required for [dmcCode].
/// [crossEquiv] = cross-stitch equivalents map (FullStitch=1.0, Half=0.5, etc.)
/// [backCells] = backstitch Euclidean cell-unit length map
int calculateSkeins({
  required String dmcCode,
  required Map<String, double> crossEquiv,
  required Map<String, double> backCells,
  required int aidaCount,
  required int strands,
})
```

Constants (currently duplicated in `materials_list_screen.dart`):
- `dmcSkeinMetres = 8.0`
- `dmcTotalStrands = 6`
- `wasteFactor = 1.3`

**Consumers updated:**
- `materials_list_screen.dart` — remove local `_skeins()` and constants, use shared function
- `pdf_service.dart` — use shared function for materials section

---

## 4. PDF Title Page

### Layout (top to bottom)

```
[margin top]
  Pattern name          — large (18pt) bold, CENTRED
  "W × H stitches · Page 1 of N"  — 9pt grey, centred

  [gap]

  Pattern preview       — centred, fills majority of vertical space
                          shrinks slightly when metadata block is present

  [metadata block — rendered only if ≥ 1 field is set]
    Aida colour swatch + label     — small swatch (14×14pt) + colour name
    Designer: <value>              — bold label + value, one line
    Difficulty: <value>            — bold label + value, one line
    Est. time: <value>             — bold label + value, one line
    <Description paragraph>        — full width, wrapped
    <Copyright>                    — small (7pt) italic text

[footer]
```

No separator rule between subtitle and preview.
Metadata block sits between preview bottom edge and footer.
Preview height = `availableH - metadataBlockH` (metadata block height estimated before drawing).

---

## 5. Thread Tables

### Two-column layout logic

```
rowsPerCol = floor((usableH - headerH - footerH - sectionHeadH - tableHeadH) / rowH)

if threads.length <= rowsPerCol:
    → single-column, one page (current behaviour)
else:
    → two-column mode
    rowsPerPage = rowsPerCol   (each column holds rowsPerCol rows)
    threadsPerPage = rowsPerCol * 2

    for each page:
        remaining = threads not yet placed
        if remaining <= rowsPerCol:
            → render as single column (last page rule)
        else:
            → render two columns, each with its own header row
            left column: threads[0..rowsPerCol-1]
            right column: threads[rowsPerCol..min(threadsPerPage, remaining)-1]
```

Each column is `(usableW - gutterW) / 2` wide, with `gutterW = 12pt` between columns.
Column widths: swatch(22) + dmc(44) + name(flexible) + count(60).
Both columns share the same proportions.

### Symbol column header

Pass empty string `''` for the symbol/colour column header (currently `'Symbol'` / `'Colour'`).
The swatch makes it self-explanatory.

### Visible layers only

Replace `pattern.stitches` with a filtered collection built from `pattern.layers` (which already applies group/layer visibility flags). Thread list derived from the same filtered stitch set — threads with zero stitches on the visible canvas are excluded.

---

## 6. PDF Materials Section

Rendered after the last thread table page. Appended to the same page if `y` position allows (≥ 120pt remaining); otherwise starts a new page.

Only rendered when `pattern.materialsSuggestions.isNotEmpty`.

### Aida size sub-table

Columns: `[Aida Colour | <aidaCount1>-count | <aidaCount2>-count | ...]`

One data row showing:
- Col 0: Colour swatch + `aidaColorLabel()` name (reusing shared function)
- Col N: `"W.W × H.H cm (W.W × H.H in)"` — min fabric size for that aida count (pattern dimensions ÷ aidaCount × 2.54 + 10cm border each side)

### Skeins sub-table

Columns: `[DMC/Anchor | Name | <aidaCount1>/<strands1> | <aidaCount2>/<strands2> | ...]`

- DMC vs Anchor column header and codes follow the existing `useAnchorColours` app setting
- One row per thread on the visible canvas
- Skein count = combined cross + backstitch (using shared `calculateSkeins`)
- Threads sorted by numeric DMC code (same as materials list dialog)

---

## 7. Bug Fixes

### `_ascii()` strips instead of replacing

```dart
// Before:
static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

// After:
static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
```

### En-dash in chart page subtitles

```dart
// Before:
'Cols ${startX + 1}\u2013$endX, Rows ${startY + 1}\u2013$endY'

// After:
'Cols ${startX + 1}-$endX, Rows ${startY + 1}-$endY'
```

### Symbol rendering on grid pages

Current guard: `if (subSize >= 6)` where `subSize = cellSize` for full/half stitches.
Bug: at typical export cell sizes (4–8pt), symbols are suppressed or rendered at 3.5pt minimum — too small to read, or not rendered at all.

Fix: lower threshold to `>= 4pt` and ensure the minimum font size produces a legible symbol. Investigate whether the symbol coordinate calculation places text outside the cell bounds at small sizes.

---

## 8. Files Affected

| File | Change |
|------|--------|
| `lib/models/pattern.dart` | Add 6 new fields + serialisation |
| `lib/services/skein_calculator.dart` | **New** — shared skein calculation |
| `lib/services/pdf_service.dart` | All PDF improvements + bug fixes |
| `lib/screens/materials_list_screen.dart` | Use shared skein calculator |
| `lib/screens/editor_screen.dart` | Update `_showPatternInfo` |
| `lib/screens/workspace_screen.dart` | Update `_showPatternInfo` |
| `lib/providers/editor/editor_provider_drawing.dart` | Add `updatePatternMetadata` |
| `lib/providers/settings_provider.dart` | Read `useAnchorColours` in PDF (already exists) |

---

## Out of Scope

- Landscape PDF orientation
- Custom font embedding (non-ASCII character support beyond stripping)
- Per-layer PDF export
- PDF password protection
