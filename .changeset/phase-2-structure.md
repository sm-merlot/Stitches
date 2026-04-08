---
"stitches": minor
---

Internal refactor: structural splits to make large files more navigable.

- New `lib/widgets/canvas_viewport.dart` — `CanvasViewport` value type encapsulating pan/zoom/cell-size math (screen↔canvas↔cell transforms, viewport culling, focal-point zoom). Replaces inline transform math in `pattern_canvas.dart` and `canvas_painter.dart`.
- `EditorState` extracted from `lib/providers/editor/editor_provider.dart` into its own `editor_state.dart` part file (~340 lines moved out, main provider drops from ~990 → ~660 lines).
- `lib/services/pdf_service.dart` (1923 lines) split into 5 focused part files under `lib/services/pdf/`: `pdf_chart.dart`, `pdf_color_table.dart`, `pdf_title_page.dart`, `pdf_markdown.dart`, `pdf_helpers.dart`. `PdfService` class now ~365 lines containing only orchestration (`buildPdfBytes`, `exportPattern`) plus the test helper.

Pure refactor — no behaviour changes.
