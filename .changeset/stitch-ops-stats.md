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
- Thread breakdown: per-DMC-colour progress bars and counts, sorted by size

**Workspace stats**
A second chart icon appears in the workspace toolbar when no file is open. It scans every `.stitches` file in the workspace (local or Google Drive) and shows a combined view: total patterns, how many are complete, overall stitch count and completion percentage, combined velocity across all patterns, and a per-pattern list sorted by recent activity.

**How progress history is tracked**
Each time you mark stitches done, the app records a daily high-watermark entry (date + cumulative stitch count) in the pattern file. The log lives outside the undo stack, so undoing stitches never erases your history. The log is stripped when exporting or sharing a pattern so personal stitching history stays private.
