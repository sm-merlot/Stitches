---
"stitches": minor
---

Step 19: Object-aware page boundary algorithm

- `PageConfig.fuzzyAmount` replaced by `PageConfig.tolerance` (default 4); backward-compatible YAML migration reads legacy `fuzzyAmount` key
- `PageLayout` boundary algorithm replaced with four-phase object-aware DP:
  - Phase 1: 8-directional flood-fill groups same-colour stitches into objects
  - Phase 2: Union-find merges objects within 1-cell gap into super-groups
  - Phase 3: Super-groups with ≤ tolerance minority cells → kept whole on majority page
  - Phase 4: Smooth-edge DP produces globally smooth per-row offsets (±2 max step between rows)
- Eliminates jagged "teeth" at page boundaries caused by independent per-row snapping
- Single `tolerance` parameter replaces `fuzzyAmount`; controls both object bleed threshold and max DP edge shift
- Page mode dialog slider renamed "Boundary flexibility", range 0–8
- `file_service.dart` writes `tolerance:` YAML key
