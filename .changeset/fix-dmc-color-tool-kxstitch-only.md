---
"stitches": patch
---

Fix DMC colour update tool to use KXStitch as sole source

Removes the cheshire137/cross-stitch-color-conversion JSON as the primary
source and replaces the dual-source (primary + supplementary) logic with a
single KXStitch XML fetch. The KXStitch dataset covers all ~489 DMC colours
including the newer 01–35 range that the previous primary source omitted.

