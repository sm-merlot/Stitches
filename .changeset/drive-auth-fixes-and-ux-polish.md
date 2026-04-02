---
"stitches": minor
---

Google Drive auth overhaul and UX polish

- Migrate Google Sign-In to v7 SDK on iOS/Android; fix auth state bugs where sign-in button disappeared after sign-out, first sign-in attempt failed, and UI did not update after signing in via Settings
- Drive recent files now show a warning and are unclickable when not signed in or signed in as a different account
- Screen lock button in stitch mode redesigned as a visual toggle with lock/unlock icons and primary-colour fill when active; shows a brief toast on touch devices when toggled
- Fix spurious Google Drive uploads triggered by toggling stitch mode
- Fix legacy `.stitches` files with `editor:` YAML fields being re-saved unnecessarily on first open
- Remove block mode toggle from stitch mode AppBar on Android (was appearing on Android only, inconsistent with other platforms)
- Bump `share_plus` to v12, `google_sign_in` to v7, `font_awesome_flutter` to v11, `wakelock_plus` to v1.5, `package_info_plus` to v9; update Android AGP to 8.12.1 to match share_plus v12 requirements
