---
"stitches": patch
---

Internal refactor: extract shared utilities to reduce duplication.

- New `lib/services/color_space.dart` consolidates 3 copies of CIE Lab conversion + ΔE distance, plus a `nearestLabIndex` helper.
- New `lib/services/dashed_line.dart` consolidates 3 copies of dashed-line drawing into a Flutter-free segment iterator.
- New `lib/models/stitch_geometry.dart` consolidates the duplicated `stitchXY` helper.
- `canvas_painter.dart` block-mode rendering: collapsed two ~70-line stitch→rect switches into a single `_stitchToBlockRect` helper.

Pure refactor — no behaviour changes.
