# Share / Export Redesign

**Date:** 2026-04-04
**Status:** Approved, awaiting implementation
**Depends on:** Three-Mode Architecture (Share lives in View mode)
**Related:** File Format v2 (progress stripping on share)

---

## Problem

The current export surface is fragmented: "Export PDF" is buried in the ⋮ overflow menu, there is no PNG export, and there is no way to share files directly to other apps or people. Each new format would require a new menu item. The UX also doesn't distinguish between *persisting your work* (Save As) and *distributing your output* (Share).

---

## Goals

- One clear place to distribute a pattern in any format: Share button
- Save As upgrades to support all formats (`.stitches`, PDF, PNG) — desktop export path
- Platform-appropriate delivery: share sheet on mobile/macOS, file picker on Windows
- Remove "Export PDF" from the ⋮ menu once these flows cover it
- PNG export that matches the PDF "realistic" title page image

---

## Platform Behaviour

| | iOS / Android | macOS | Windows |
|---|---|---|---|
| **Share button** | ✓ AppBar (View mode) | ✓ AppBar (View mode) | — |
| **Share action** | OS share sheet (`share_plus`) | macOS share picker (NSSharingService via `share_plus`) | — |
| **Save As** | ✓ existing file picker / Drive | ✓ format picker → file picker | ✓ format picker → file picker |
| **Export PDF (⋮ menu)** | Removed | Removed | Removed |

---

## Share Button

### Placement
- AppBar in **View mode only** (per three-mode architecture spec)
- Not shown in Edit mode or Stitch mode
- Platform-conditional: iOS, Android, macOS only (not rendered on Windows)

### Format picker
Tapping Share opens a bottom sheet (mobile) or dialog (desktop) with three options:

1. **Pattern file** (`.stitches`) — the working file
   - Includes `stitching.pageMode` config
   - Strips `stitching.progress` by default
   - Option: "Include progress" toggle (useful for handing off a partially-done piece)
2. **PDF** — full pattern PDF, identical to current "Export PDF"
3. **PNG overview** — realistic line-art render (see PNG Export section below)

On selection, the file is generated, then passed to the platform share mechanism.

---

## Save As Upgrade

Save As gains the same format picker on macOS and Windows:

1. **Pattern file** (`.stitches`) → existing file picker (unchanged behaviour)
2. **PDF** → generate PDF, then save dialog
3. **PNG overview** → generate PNG, then save dialog

On mobile (iOS/Android), Save As is unchanged — users use the Share button for PDF and PNG.

---

## PNG Export

### Output
Replicates the PDF "realistic" title page image:
- Aida background colour
- All stitches as diagonal line-art (same stitch-type rendering as PDF)
- Backstitch segments
- Black border
- No grid, no symbols, no page numbers

### Sizing
Fixed px-per-stitch cell size of **20 px/cell** (default). Output dimensions scale with pattern size — a 100×80 pattern produces a 2000×1600 px image. This gives predictable, proportional output at reasonable quality.

### Rendering pipeline

New service: `lib/services/png_export_service.dart`

```
PngExportService.export(pattern)
  → StitchCompositor.compute(pattern)        // flatten layers → nonBack + backstitches
  → PictureRecorder + Canvas (dart:ui)       // offscreen render
  → _drawAidaBackground()
  → for each stitch in nonBack: _drawStitch()
  → for each segment in backstitches: _drawBackstitch()
  → _drawBorder()
  → image.toByteData(ImageByteFormat.png)
  → Uint8List
```

**Rendering reference** (mirrors `pdf_service.dart` logic, adapted for Flutter canvas API):

| Aspect | PDF (`PdfGraphics`) | PNG (`dart:ui Canvas`) |
|---|---|---|
| Coordinate origin | Bottom-left, y-up | Top-left, y-down |
| Row formula | `gy = originY + (rows - row - 1) * cs` | `gy = row * cs` (no flip needed) |
| Stroke width | `max(0.3, cs * 0.12)` | `max(0.5, cs * 0.12)` |
| Backstitch width | 1.5× stroke width | 1.5× stroke width |
| Colour source | `threadMap` + `blendedColors` | Same — from `StitchCompositor` |

**Stitch types** (same logic as `_drawRealisticStitch()`):
- `FullStitch` → two crossing diagonals (X)
- `HalfStitch(isForward: true)` → `/` diagonal
- `HalfStitch(isForward: false)` → `\` diagonal
- `QuarterStitch` / `QuarterCrossStitch` → half-sized diagonal in target quadrant
- `HalfCrossStitch` → two half-sized diagonals in target half-cell
- `BackStitch` → handled separately as thick line segment

---

## Removing "Export PDF"

Once Share and Save As are upgraded, "Export PDF" is removed from the ⋮ overflow menu on all platforms. PDF export is fully covered by:
- Share button → PDF (iOS/Android/macOS)
- Save As → PDF (macOS/Windows)

---

## Implementation

### New files

**`lib/services/png_export_service.dart`**
- `Future<Uint8List> export(CrossStitchPattern pattern, {double cellSize = 20.0})`
- Uses `dart:ui` `PictureRecorder`, no Flutter widget tree involvement
- Self-contained — no platform channels needed

**`lib/widgets/share_format_picker.dart`**
- Bottom sheet (mobile) / dialog (desktop) with format options
- Progress strip toggle when `.stitches` is selected
- Returns chosen `ShareFormat` enum value + options
- Shared by both Share button and Save As upgrade

### Files to change

**`pubspec.yaml`**
- Add `share_plus` if not already present

**`lib/screens/editor_screen.dart`** / **`lib/screens/workspace_screen.dart`**
- Add Share button to View mode AppBar (platform-conditional: not Windows)
- Wire Share button → `ShareFormatPicker` → generate → `share_plus`
- Upgrade Save As action → `ShareFormatPicker` → generate → file picker
- Remove "Export PDF" from ⋮ overflow menu

**`lib/services/pdf_service.dart`**
- No changes needed — called as-is by the new flows

---

## Testing

- iOS/Android: Share → PDF → share sheet appears with PDF
- iOS/Android: Share → PNG → share sheet appears with PNG
- iOS/Android: Share → `.stitches` → progress stripped by default; progress included when toggled
- macOS: Share → format picker → macOS share picker appears
- macOS: Save As → PDF → save dialog → file written
- macOS: Save As → PNG → save dialog → file written
- Windows: Save As → PNG → save dialog → file written
- Windows: confirm no Share button in AppBar
- PNG output: visually matches PDF title page realistic image
- PNG output: 100×80 pattern → 2000×1600 px image at default cell size
- "Export PDF" absent from ⋮ menu on all platforms after implementation
