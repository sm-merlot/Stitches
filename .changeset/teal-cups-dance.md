---
"stitches": patch
---

Close the test coverage gap: add 350 unit/widget tests and 4 integration smoke tests across T1–T5.

**T1** – File format round-trip: v2 `.stitches` full round-trip, compressed/uncompressed paths, unknown-YAML-key safety, legacy v1 fixture

**T2** – EditorNotifier core: all stitch types, erase modes, layer CRUD, mode switching, undo/redo (200-step cap), thread management, progress marking, metadata

**T3** – EditorNotifier remainder: snippet CRUD/resize/transform/palettes, selection/copy/paste, `saveSelectionAsSnippet`; session service save/restore; progress log edge cases

**T4** – Pure-Dart services: `color_space`, `dashed_line`, `stitch_geometry`, `snippet_palette_resolver`, `page_layout`, `stitch_renderer`, `SpriteImporter`; widget smoke tests for six screens

**T5** – Integration tests: four end-to-end flows (draw→save→reload, copy→paste→undo, progress→save→reload, snippet round-trip) using real disk I/O; CI workflow added at `.github/workflows/test.yml`

All 350 `flutter test` tests pass in ~6 s. Integration tests run separately: `flutter test integration_test/ -d macos`.

