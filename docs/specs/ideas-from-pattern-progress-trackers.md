# Ideas from pattern progress trackers (Pattern Keeper, Markup RX-P)

These apps are built specifically for scanning pdfs and then tracking progress while you work through the pattern. They offer much deeper features than what Stitches currently offers.

1. PDF Import is much more powerful (see [pdf-import-research](./pdf-import-research.md))
    - Pattern Keeper uses specifically formatted PDFs which a lot of pattern markers use. We should support importing AND exporting PDFs in this format.
    - Markup RX-P uses Rasta image scanning so is a bit like what we have but it seems like it might be better in some ways, worse in others. Needs more research.
    - Still not great/non-existent backstitch and partial stitch support.
2. Both seem to follow the pattern of: initially Black & White w/ symbols, then as you mark cells off, they turn into the solid colour of the stitch.
   - This is nice because it shows you the pattern filling in as you complete it.
   - I think we should add this as a separate mode so people can choose what they prefer.
3. Ability to park stitches on a cell.
   - This is a common technique where stitchers will thread a colour in a corner of one cell, while they complete other colours.
4. Use the term "Frog" for "Unmark" a stitch.
   - Common term in cross-stitching.
5. More visual-first home screen so you can see what charts you have (big chart previews, less lists etc).
   - Not sure exactly how to wrangle this but it needs some thought.
6. Pages can be as they are in the PDF, or one single page.
   - I think we should offer something similar for scanned patterns. Also offer manually adjustable patterns and fuzzy edges as we do now.
7. Key view.
   - View the original Key from the PDF...
   - Solid maybe for this one.
   - It depends if we can get good back stitch and partial stitch support on import.
8. Rescan/adjust grid for scan etc.
   - This might be useful if the initial scan wasn't fully correct.
   - Have to think about how to manage this, if they also have made edits.
9. More progress stats — **mostly done via StitchOps** (branch `claude/add-stitch-stats-fgQj3`):
   - ✅ Stitches today / this week / this month / this year (velocity card)
   - ✅ History of daily stitches (60-day bar chart, 16-week activity heatmap)
   - ✅ Averages — avg stitches per active day in ETA card
   - ✅ Estimates — ETA based on 14-day rate, shown on cumulative chart
   - ✅ Total days stitching / streaks (current streak + longest streak)
   - ✅ Graphs — daily bar, cumulative line, activity heatmap; all with hover tooltips
   - ✅ Analytics — workspace StitchOps aggregates all patterns; filter to compare subsets
   - ❌ Timer (how much time spent stitching) — not yet implemented
10. Generally lets review how we mark stitches compared to other apps.
    - I feel like what we have is a bit more intuitive out the gate.
    - But they have a "select all colour" button which feels not super useful but I'm not sure.
    - wondering if a long-press for some extra options might be a good idea?
11. Colour list sort options:
    - by colour id
    - by number of stitches
    - complete colours last

