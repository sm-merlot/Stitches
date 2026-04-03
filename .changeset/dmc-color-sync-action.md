---
"stitches": patch
---

fix: DMC color list — auto-retire discontinued colors in monthly sync

The monthly GitHub Action that keeps the DMC color list current now automatically removes colors absent from the community source from `dmcColors` and adds placeholder entries to `dmcReplacements`. The resulting PR shows exactly what changed so you can fill in replacement codes before merging, or revert individual entries if the community source is wrong.

- Removes the AI/Anchor-code lookup from the script and workflow (can be done manually when reviewing the PR)
- Auto-migration at pattern load skips placeholder entries (empty replacement) until a confirmed replacement is filled in
- Discontinued codes removed from `dmcColors` in a previous step, plus 9 migration tests
