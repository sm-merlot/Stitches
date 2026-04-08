---
"stitches": minor
---

Internal refactor: extract dialog helpers and remove confirm/input boilerplate.

- New `lib/widgets/dialogs/confirm_dialog.dart` — `confirmDestructive()` helper consolidating 6 inline AlertDialog destructive prompts (delete file/folder/layer-group/palette, clear progress, clear recent).
- New `lib/widgets/dialogs/input_dialog.dart` — `inputDialog()` helper consolidating 3 single-text-field rename prompts (file/folder/snippet), with an `allowEmpty` flag preserving the snippet "leave empty for no name" behaviour.
- New `lib/widgets/dialogs/dmc_picker_dialog.dart` — extracted shared `DmcPickerDialog` widget, de-duplicating two of three local copies (palettes panel + snippet dialogs).
- Removed `docs/refactor-plan.md` — multi-phase refactor tracker is now obsolete.

The phase-3 `StitchRenderer` abstraction was investigated and intentionally skipped: the three rendering sites share switch structure but differ on graphics API, coordinate system, and detail level — an interface would formalize the relationship without removing code.

Pure refactor — no behaviour changes.
