---
"stitches": minor
---

## Time tracking in StitchOps

Track how long you spend stitching, right inside StitchOps.

### Timer

A **Timer** button appears in the stitch-mode right sidebar (below Mark and StitchDemo). Tap it to start a session; the button counts up live (`MM:SS` / `HH:MM:SS`) and turns highlighted while running. Tap again to stop — the elapsed time is saved to that day's log entry automatically.

The timer survives device sleep and app kills: the session start time is persisted to `SharedPreferences` and restored on next launch. Sessions older than 24 hours are discarded as stale.

### Time section in StitchOps

A new **Time** card appears in StitchOps whenever any stitching has been logged:

- **Total** — all recorded stitching time across the project's lifetime
- **Today** / **Week** — rolling totals
- **Stitches / hour** — overall efficiency derived from logged time

### Manual time adjustment

A pencil icon in the Time card header opens the **Edit time history** dialog. Every day with stitching activity is listed (newest first, with Today always at the top), each with editable **h** and **m** fields. Only changed entries are saved on confirm. Useful for correcting sessions where the timer was left running, or for retroactively logging time for days the timer wasn't used.

StitchOps updates immediately after saving — no need to close and reopen the dialog.

### Persistence

Time is stored as a `minutes:` field on each `progressLog` entry in the `.stitches` file. Existing files load fine; the field is omitted when zero.

