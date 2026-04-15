---
"stitches": minor
---

Add StitchOps: in-depth stitching progress analytics

A new **StitchOps** screen gives you detailed insight into your stitching progress, accessible via the chart icon in the toolbar (view mode and stitch mode).

**Per-pattern stats**
- Overview: completed / total / remaining stitch count with a progress bar, started date, and last-active date
- Velocity: stitches completed today, this week, this month, and this year
- ETA: estimated completion date based on your recent 14-day rate, plus average stitches per active day
- Daily bar chart: last 60 days of per-day stitch counts with month labels
- Cumulative line chart: overall progress curve over the lifetime of the project
- Activity heatmap: 16-week GitHub-style contribution grid
- Thread breakdown: per-DMC-colour progress bars and counts, sorted by size
- Interactive hover tooltips on all charts (desktop/mouse)

**Workspace stats**
A second chart icon appears in the workspace toolbar when no file is open. It scans every `.stitches` file in the workspace (local or Google Drive) and shows a combined view across all patterns:
- Total patterns, how many are complete, overall stitch count and completion percentage
- Combined velocity (today / week / month / year) across all patterns
- Current and longest stitching streak 🔥
- Daily bar chart, cumulative line chart, and activity heatmap — aggregated across every pattern
- Per-pattern list sorted by recent activity, with individual progress bars
- **Pattern filter**: tap the filter icon to show checkboxes on each pattern row; toggle individual patterns in or out to focus the aggregate stats on a specific subset. "Select all / Select none" for quick bulk changes.
- Google Drive workspaces cache downloaded files on first open — subsequent loads are instant

**How progress history is tracked**
Each time you mark stitches done, the app records a daily high-watermark entry (date + cumulative stitch count) in the pattern file. The log lives outside the undo stack, so undoing stitches never erases your history. The log is stripped when exporting or sharing a pattern so personal stitching history stays private.
