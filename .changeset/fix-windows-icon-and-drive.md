---
"stitches": patch
---

Fix Windows app icon and confirm Google Drive support on Windows

- Regenerate Windows app icon as a proper multi-size ICO (16, 24, 32, 48, 64, 128, 256 px) from the source PNG; previously the icon was incorrect
- Add Windows to `flutter_launcher_icons` config so future icon updates are applied automatically
- Google Drive sync confirmed working on Windows
