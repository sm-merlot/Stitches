---
"stitches": patch
---

Stitch mode focus: unfocused stitches show pale colour/symbol instead of flat grey

**Before:** Focusing a thread in stitch mode turned all other stitches to uniform grey with no symbols — losing context about surrounding pattern.

**After:** Unfocused stitches retain their identity:
- **Done + unfocused:** pale version of actual thread colour (hue preserved, desaturated + lightened)
- **Undone + unfocused:** pale greyscale with semi-transparent symbol still visible
- **Focused stitches:** unchanged (same as before)

Applies to both cross-stitches (via RenderCache) and backstitches (via painter).

Colour helpers added: `_paleColor` (HSL desat+lighten), `_paleGreyscale` (greyscale at alpha 128).
Removed unused `_muteColor` and `_greyColor` from both files.
