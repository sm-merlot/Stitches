# Ideas from pattern progress trackers (Pattern Keeper, Markup RX-P)

These apps are built specifically for scanning pdfs and then tracking progress while you work through the pattern. They offer much deeper features than what Stitches currently offers.

1. PDF Import is much more powerful (see [pdf-import-research](./pdf-import-research.md))
    - Pattern Keeper uses specifically formatted PDFs which a lot of pattern markers use. We should support importing AND exporting PDFs in this format.
    - Markup RX-P uses Rasta image scanning so is a bit like what we have but it seems like it might be better in some ways, worse in others. Needs more research.
    - Still not great/non-existent backstitch and partial stitch support.

2. ✅ **DONE** — Both apps follow the pattern of: initially Black & White w/ symbols, then as you mark cells off, they turn into the solid colour of the stitch. Implemented in B&W stitch mode (#53); "realistic mode" canvas view removed (#54) in favour of this cleaner approach.

3. Ability to park stitches on a cell.
   - This is a common technique where stitchers will thread a colour in a corner of one cell, while they complete other colours.

4. ✅ **DONE** — Use the term "Frog" for "Unmark" a stitch. Implemented in #51.

5. ✅ **DONE** — More visual-first home screen. Implemented in #40: pattern thumbnails, unified pickers, workspace improvements.

6. ✅ **DONE** — Pages can be as they are in the PDF, or one single page. Page mode in stitch view implemented in #34.

7. Key view.
   - View the original Key from the PDF.
   - Depends on getting good backstitch and partial stitch support on import.

8. Rescan/adjust grid for scan etc.
   - This might be useful if the initial scan wasn't fully correct.
   - Have to think about how to manage this if they also have made edits.

9. ✅ **DONE** — More progress stats, via StitchOps (#64):
   - ✅ Stitches today / this week / this month / this year (velocity card)
   - ✅ History of daily stitches (60-day bar chart, 16-week activity heatmap)
   - ✅ Averages — avg stitches per active day in ETA card
   - ✅ Estimates — ETA based on 14-day rate, shown on cumulative chart
   - ✅ Total days stitching / streaks (current streak + longest streak)
   - ✅ Graphs — daily bar, cumulative line, activity heatmap; all with hover tooltips
   - ✅ Analytics — workspace StitchOps aggregates all patterns; filter to compare subsets
   - ❌ Timer (how much time spent stitching) — not yet implemented

10. Generally let's review how we mark stitches compared to other apps.
    - I feel like what we have is a bit more intuitive out the gate.
    - They have a "select all colour" button which feels not super useful but I'm not sure.
    - Wondering if a long-press for some extra options might be a good idea?

11. ✅ **DONE** — Colour list sort options. Implemented in #52: sort by colour ID, by stitch count, or completed colours last.
