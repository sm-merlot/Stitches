---
"stitches": minor
---

Unified Share and Export with support for all four formats from a single entry point.

- Share button (iOS, Android, macOS) and Export button are now direct app bar actions — no overflow menu
- Both Share and Export support `.stitches`, `.oxs`, `.pdf`, and `.png`
- Export to Drive-backed files shows the Drive folder picker; includes a "Save to local storage" escape hatch
- Export to local files opens the native save dialog with the current file's folder pre-selected
- Non-native files (`.oxs`, etc.) open in read-only view mode with a "Convert to .stitches" banner; if the `.stitches` sibling already exists, shows "Open .stitches" instead
- App bar overflow menus removed — Reference Image and Resize Aida are direct icon buttons in Edit mode
