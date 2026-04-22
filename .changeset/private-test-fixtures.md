---
"stitches": patch
---

Add real-world PDF parse integration test sourced from private fixtures repo.

A new CI job (`integration-test`) clones `stitches-test-fixtures` (private) and runs `pk_real_pdf_parse_test` against actual PatternKeeper PDFs to guard against regressions in the Tier-1 text-layer parser. Fixture path resolution updated across existing tests to use the shared `TestFixtures` helper.
