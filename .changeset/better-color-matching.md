---
"stitches": minor
---

Improve DMC colour matching accuracy with CIEDE2000

Replaces the CIE-76 squared-Euclidean distance used throughout the sprite importer with CIEDE2000 (Sharma, Wu & Dalal 2004), the current industry standard for perceptual colour difference. CIEDE2000 corrects known weaknesses in CIE-76, particularly for blues/violets, dark colours, and near-neutrals — all common in pixel-art palettes.

Changes:
- `matchPixel`, the palette-merge step, `renderCropWithPalette`, and `_importRegionRestrictedFromRaw` all now use CIEDE2000.
- Added a per-RGB match cache to `SpriteImporter`; sprite art typically reuses a tiny set of colours, so CIEDE2000's extra trig cost is paid once per unique colour rather than per pixel.
- Fixed a silent bug in `renderCropWithPalette` and `_importRegionRestrictedFromRaw` where the drop threshold was compared against a squared CIE-76 value (`30² = 900`) rather than the intended linear 30-unit distance. This is now a direct CIEDE2000 comparison against `30.0`.
- Replaced single-midline palette strip scanning with full-block column/row averaging. Each slot's representative colour is the average of all pixels in the corresponding column (horizontal strip) or row (vertical strip), making detection robust against JPEG artefacts and anti-aliased edges.
- Removed `_quantizeColor` (16-step grid snap). Grid-boundary artefacts caused incorrect block splits when a colour straddled a step boundary.
- Strip block-boundary detection now uses CIE-76 Lab distance (threshold 15 ΔE) instead of sRGB Euclidean, consistent with the rest of the pipeline.

