---
"stitches": minor
---

Add global settings access and Google Drive sign-out safety

- **Settings access**: settings icon added to workspace and editor AppBars; `Ctrl+,` shortcut on Windows/Linux; macOS app menu gains Preferences… item (`Cmd+,`) with full standard menu items
- **Drive sign-out**: signing out automatically closes any open Drive workspace or file, pops to home, and shows a snackbar
- **Drive revocation**: mid-session token revocation shows a blocking dialog over the open workspace (keeping it loaded); "Sign in again" transitions to a spinner and re-auths inline; on success the folder listing and open file are refreshed automatically; Cancel/Dismiss closes the workspace and returns to home
- **Sign-in cancel**: a Cancel button appears next to the spinner in Settings during OAuth so users can abort a stuck sign-in flow
- **Recent items**: Drive recent items already grey out and disable tap when signed out or signed in as a different account — this now also triggers correctly when a session expires mid-use
