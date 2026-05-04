---
"stitches": minor
---

Step 19: Object-aware page boundary algorithm (v2 band-local pipeline)

- `PageConfig.tolerance` default changed from 4 → 5; backward-compatible YAML migration reads legacy `fuzzyAmount` key
- `PageLayout` boundary algorithm replaced with v2 band-local pipeline:
  - Phase 1: Extract ±tolerance band around each nominal boundary
  - Phase 2: 8-directional flood-fill detects local objects within band
  - Phase 3: Object classification (keepWhole / keepLeft / keepRight / tooBig) with keep-whole enforcement
  - Phase 4: Anchor detection at colour transitions weighted by adjacent cluster size, with continuity tie-breaking; linear interpolation + deterministic fuzz between anchors
  - Phase 5: Fragment reclamation pulls stranded small objects back to their majority side
  - Corner connectivity post-pass removes cells disconnected from page interior
- Object classification distinguishes one-sided band extension (keepLeft/keepRight) from both-sided (tooBig), protecting real object edges even when the object extends beyond the band on one side
- Smoothing removed — interpolation constrains steps to ±2; keep-whole jumps are intentional
- `_isQualifyingCut` removed from anchor detection — keep-whole + reclamation handles object integrity
- Page mode dialog: tolerance slider replaced with "Fuzzy edges" on/off switch (tolerance=5 when on, 0 when off)
- Visual diagnostic test added for real-pattern boundary verification
