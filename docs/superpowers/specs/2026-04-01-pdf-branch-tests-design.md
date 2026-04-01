# PDF Branch Tests — Design Spec
_2026-04-01_

## Context

Branch `scme0/feature/pdf-improvements` introduced substantial pure-logic changes with no unit test coverage. This spec describes tests to be added before the branch is merged.

---

## Production changes required

Two private statics need `@visibleForTesting` so tests can call the real code:

| Symbol | Location |
|---|---|
| `PdfService._compositeNonBack` | `lib/services/pdf_service.dart` |
| `PdfService._buildPdfSymbolMap` | `lib/services/pdf_service.dart` |
| `EditorNotifier._assignSymbols` | `lib/providers/editor/editor_provider.dart` |

---

## Test files and cases

### Commit 1 — `test/symbols_test.dart` (new)

Tests `symbolIsVisible`, `symbolIsPdfUnsupported`, and `symbolSimilarityGroup` from `lib/data/symbols.dart`.

**symbolIsVisible**
- empty string → false
- plain space → false
- NBSP (U+00A0) → false
- zero-width space (U+200B) → false
- BOM (U+FEFF) → false
- ASCII letter 'A' → true
- digit '3' → true
- geometric shape '■' → true
- Greek 'α' → true
- string of only invisible chars → false

**symbolIsPdfUnsupported**
- '↑' (arrow) → true
- '⊕' (circled plus) → true
- '✝' (cross mark) → true
- 'A' → false
- '■' → false

**symbolSimilarityGroup**
- 'O' and '0' in same group
- 'I' and '1' in same group
- '●' and '◉' in same group
- 'A' not in any group → -1
- two similar symbols both return the same non-negative index

---

### Commit 2 — `test/skein_calculator_test.dart` (new)

Tests `calculateSkeins` from `lib/services/skein_calculator.dart`. Pure math — expected values hand-calculated from the formula.

- single full stitch, 14-count, 2 strands → 1 skein (minimum)
- zero stitches → 1 skein (minimum enforced)
- large stitch count (e.g. 500 full stitches, 14-count, 2 strands) → correct ceil
- backstitch-only thread → 1+ skeins based on Euclidean cell-unit length
- mixed cross + backstitch → combined thread usage
- higher aida count (18 vs 14), same stitches → fewer skeins
- more strands → more thread used → more skeins
- thread absent from both maps → 1 skein

---

### Commit 3 — `test/pdf_logic_test.dart` (new)

Tests `PdfService._buildPdfSymbolMap` and `PdfService._compositeNonBack` (both exposed via `@visibleForTesting`).

**_buildPdfSymbolMap**
- visible, supported symbol → included in map
- invisible symbol (empty string) → excluded
- PDF-unsupported symbol ('↑') → excluded
- mix of valid/invalid threads → only valid ones appear
- duplicate dmcCode → last wins (Map semantics)

**_compositeNonBack**
- single visible layer, single FullStitch → passes through; no blended colour entry
- hidden layer stitches are ignored
- BackStitch in layer is excluded from nonBack result
- two layers, same cell, Normal blend at full opacity → top stitch wins for symbol identity
- two layers, same cell, Add blend → bottom stitch identity used; blendedColors entry present
- non-FullStitch types (HalfStitch, QuarterStitch) go into otherNonBack, not deduplicated
- thread missing from threadMap → cell skipped entirely
- two different cells, no overlap → both stitches in result, no blended colours

---

### Commit 4 — additions to `test/models_and_logic_test.dart`

**CrossStitchPattern metadata YAML round-trip**
- `description` survives toYaml/fromYaml
- `copyright` survives toYaml/fromYaml
- `materialsSuggestions` (list of `{aidaCount, strands}`) survives round-trip
- null metadata fields are omitted from YAML output
- empty `materialsSuggestions` list omitted from YAML

**_assignSymbols (via @visibleForTesting)**
- thread with valid visible symbol keeps it unchanged
- thread with empty symbol gets auto-assigned from kPatternSymbols
- thread with PDF-unsupported symbol ('↑') gets reassigned
- two threads without symbols get distinct symbols
- `existingSymbols` param blocks those symbols from assignment
- composite symbols passed via `existingSymbols` are not reused for layer threads

---

## Commit order

| # | Commit message | Files |
|---|---|---|
| 1 | `test: symbol visibility and PDF-unsupported filtering` | `test/symbols_test.dart` |
| 2 | `test: skein calculator` | `test/skein_calculator_test.dart` |
| 3 | `test(pdf): compositing and symbol map logic` | `lib/services/pdf_service.dart` (annotations), `test/pdf_logic_test.dart` |
| 4 | `test: pattern metadata YAML round-trip and _assignSymbols` | `lib/providers/editor/editor_provider.dart` (annotation), `test/models_and_logic_test.dart` |
