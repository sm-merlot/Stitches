# Test Coverage Spec

> Closing the testing gap called out in `README.md` (Engineering backlog) and
> `docs/road-to-v1.md` (Quality & Testing). Living document — update as
> phases land.

## Goal

Reach a confidence level where v1.0.0 ships without obvious editor regressions
and where future refactors can be made with a fast safety net. **Not** 100%
coverage — that's a treadmill. Aim for high coverage on the parts that change
often or break loudly, light coverage on the parts that rarely change.

The yardstick: a contributor (or me, six months from now) should be able to
make a non-trivial change to drawing, layers, snippets, or file format and
trust `flutter test` to catch the obvious mistakes before manual smoke
testing.

## Baseline (current)

Existing test files under `test/` (~2,750 lines total):

| File | What it covers |
|---|---|
| `models_and_logic_test.dart` (632) | `Stitch` types, `Layer`, `CrossStitchPattern`, `Thread`, `PatternProgress`, basic equality / copyWith / serialization |
| `stitch_planner_test.dart` (1117) | Stitch ordering, front/back alternation, planner heuristics |
| `stitch_compositor_test.dart` (223) | Composite-thread blending, layer opacity / blend modes |
| `pdf_logic_test.dart` (234) | Symbol filtering, PDF-unsupported symbol skip |
| `skein_calculator_test.dart` (149) | Stitch-count → skein conversion |
| `materials_list_test.dart` (114) | Materials list aggregation |
| `dmc_migration_test.dart` (149) | Legacy palette migration |
| `symbols_test.dart` (117) | Symbol pool stability |
| `widget_test.dart` (21) | Stub — app launches |

What this means: **pure model and pure-Dart service logic is well covered**.
**Anything stateful, async, or UI-facing is not.**

Since these tests were written, significant features have landed that are not yet covered: three-mode architecture (view/edit/stitch), file format v2 with progress tracking, StitchOps aggregation, B&W stitch rendering, page mode, unified share/export, and the full `EditorNotifier` refactor into five mixins.

## Coverage gaps by priority

### Priority 1 — central state and persistence

The single biggest risk surface. These are the things that, if they break,
silently corrupt user data or wreck the editor experience.

**P1.1 — `EditorNotifier` (`lib/providers/editor/`)**

The Riverpod notifier with five mixins (drawing, layers, progress, snippets,
selection) and ~660 lines of orchestration. Currently zero tests. Should
cover (including new three-mode and progress-tracking behaviour):

- Drawing each stitch type onto a fresh pattern; verify the resulting
  `Layer.stitches` set
- Erase modes: single cell, N×N box, fill-erase
- Tool / mode switching keeps state coherent (no orphaned selection on tool
  change, no clipboard leak between modes)
- Layer CRUD (add / delete / reorder / show-hide / lock / blend mode change),
  with the active-layer pointer staying valid after deletions
- Selection: rubber-band → copy → paste round-trip, including across pattern
  switches via clipboard preservation
- Mode switching: view → edit → stitch → view; verify state resets correctly
- Undo / redo across drawing, palette changes, and progress edits — all the
  way to the 200-step cap and back
- Snippet CRUD: save selection as snippet, paste snippet, resize, transform,
  delete; multi-palette palette swapping
- Progress mode: mark region done / not done, page completion tracking
- File-lifecycle helpers: open → dirty → save resets `isDirty`, pristine
  loaded files start clean

Approach: spin up a `ProviderContainer` in each test, override the file
service / drive provider with fakes, drive the notifier directly, assert on
`container.read(editorProvider)`. No widgets, no `await tester.pump()`.

Rough size: 600–900 lines of tests. Big up-front investment, biggest payoff.

**P1.2 — File format round-trip (`format_service.dart` + `file_service.dart`)**

Currently the only thing standing between users and silent data loss. File format is now v2, adding progress tracking fields. Should cover:

- Round-trip: build a pattern with every stitch type, every layer feature,
  multiple snippets, multiple palettes per snippet, progress data, progress log → serialize
  → deserialize → assert structural equality
- Compressed and uncompressed format paths
- Backwards compatibility: load older `.stitches` fixtures committed under
  `test/fixtures/` and assert they parse without loss
- Forward compatibility: unknown YAML keys are preserved or safely ignored,
  not erased

Rough size: 250–400 lines + a handful of fixture files.

**P1.3 — `EditorSessionService`**

Per-device session state (tool, view position, active layer) lives outside
the file. Should cover save/restore round-trip and graceful handling of
corrupt session data.

Rough size: 80–150 lines.

**P1.4 — Progress log and StitchOps aggregation**

The `ProgressLogEntry` model, `logCountAsOf`, `_aggregateStats`, and `_summarisePattern` are pure-Dart functions with meaningful edge cases (frogging, same-day high-watermark, empty log, all patterns excluded). Should cover:

- `logCountAsOf` with empty log, single entry, mid-range query, after-last query
- Daily delta computation when stitchCount goes up and down (frogging scenario)
- Streak calculation: gap in activity breaks streak, today counts, multi-day
- `_aggregateStats` with zero patterns, one pattern, patterns with no log entries

Rough size: 150–250 lines. Pure Dart — no fakes needed.

### Priority 2 — pure-Dart services without I/O

These are easy to test (no Flutter, no async, no fakes needed) and are called
from hot paths.

- **`color_space.dart`** — sRGB↔Lab round-trip within ε, ΔE ordering matches
  expected pairs, `nearestLabIndex` returns the right index for known cases
- **`dashed_line.dart`** — segment iterator yields the expected count and
  positions for known inputs (line lengths matching exact dash counts, lines
  shorter than one dash, zero-length)
- **`stitch_geometry.dart`** — `stitchXY` returns `null` only for backstitch
- **`snippet_palette_resolver.dart`** — positional slot mapping behaves
  consistently when threads are added/removed
- **`page_layout.dart`** — page tile generation for representative pattern
  sizes, edge cases (1×1, exactly one page, off-by-one boundary)
- **`sprite_importer.dart`** — palette simplification merges expected
  colours, region matching produces deterministic output for a fixture image
- **`stitch_renderer.dart`** — fractional cell-region helper (if added per
  the phase 3 follow-up note)
- **`progress_log.dart`** — `logCountAsOf`, daily delta computation, streak calculation (see P1.4 below)
- **`page_layout.dart`** — page tile generation now used in stitch-mode page view as well as PDF export

Rough size: 400–600 lines across ~7 files.

### Priority 3 — widget smoke tests for critical screens

Not exhaustive — just enough to catch render-time crashes and broken
provider wiring. One test per screen, asserting it builds and key widgets are
present:

- `editor_screen` — opens with empty pattern, toolbar present, sidebar
  present, mode switch works
- `home_screen` — recent list renders, empty state renders
- `workspace_screen` — folder tree renders with a fake folder contents
  provider
- `snippet_editor_screen` — opens with a fixture snippet
- `color_picker_screen` — DMC list renders, search filters
- `pattern_info_dialog`, `resize_canvas_dialog`, `new_pattern_dialog` —
  dialogs build and validate input
- `stitch_ops_screen` — renders with a fixture pattern that has a progress log; charts appear when data is present, empty-state message when not
- `stitch_ops_workspace_screen` — renders loading state, then stats view with filter toggle; toggling a pattern updates the displayed counts

Approach: use `pumpWidget` with `ProviderScope` overrides for any service
the screen reads. No real navigation, no real I/O.

Rough size: 400–700 lines across ~10 screens.

### Priority 4 — integration smoke tests

A small handful of end-to-end flows running in a real Flutter test harness
(`integration_test/`), gated to desktop CI:

1. Create new pattern → draw stitches → save → reopen → verify stitches
2. Open pattern → make a selection → copy → paste at offset → undo → verify
3. Open pattern → enter stitch mode → mark a region done → exit → re-enter
   → verify progress preserved
4. Snippet round-trip: create snippet → save pattern → reopen → paste
   snippet → verify

These are slow and brittle by nature; keep the count low. They exist to
catch wiring bugs that pass unit + widget tests.

Rough size: 4 tests, ~150–250 lines each.

## What is intentionally **out of scope**

- **Google Drive integration** — too much auth surface and rate-limit risk
  for unit tests; rely on manual smoke testing pre-release. A fake
  `GoogleDriveService` for use in editor provider tests is in scope (P1.1),
  but tests against real Drive APIs are not.
- **PDF export visual diffing** — `flutter_test` can't render the PDF
  package's output. PDF logic tests cover the data plumbing; visual checks
  remain manual.
- **PDF scanner** — beta feature, redesign not yet started. Add tests after the redesign lands.
- **Stitch demo** — beta feature; planner already has heavy unit tests, the
  rest is animation timing.
- **Apple Pencil / touch gesture handling** — can't realistically be tested
  without a device; the gesture detector logic is small and stable.
- **100 % line coverage** — explicitly not a goal.

## Approach & conventions

- **Test framework**: `flutter_test` for everything except integration (which
  uses `integration_test`).
- **State testing**: `ProviderContainer` directly, not widgets, for provider
  unit tests. Drive mutations through the notifier API; assert on
  `container.read(...)`.
- **Fakes over mocks**: write small handwritten fakes (`FakeFileService`,
  `FakeDriveService`) instead of using `mockito` / `mocktail`. Less ceremony,
  fewer broken tests on refactors.
- **Fixtures**: commit small `.stitches` files (and image fixtures for the
  sprite importer / grid scanner) under `test/fixtures/`. Keep them small —
  ideally under 1 KB each — and document what each one represents.
- **No `setUpAll` shared mutable state** — each test builds its own
  container. Slow tests are better than flaky ones.
- **CI**: existing `flutter test` invocation already runs in pre-commit /
  manual; add `integration_test` to the v1 release checklist (not pre-commit
  — too slow).

## Phasing

The work breaks into roughly four PRs, each landable independently.

| Phase | Scope | Approx size |
|---|---|---|
| **T1** | P1.2 file-format round-trip + fixtures | small (~300 lines) |
| **T2** | P1.1 EditorNotifier core (drawing, layers, undo/redo) | large (~600 lines) |
| **T3** | P1.1 remainder (snippets, selection, progress) + P1.3 session | medium (~400 lines) |
| **T4** | P2 pure-Dart services + P3 widget smoke tests | medium (~500 lines) |
| **T5** | P4 integration smoke tests + CI wiring | small (~250 lines) |

T1 first because format round-trip is the cheapest insurance against the
worst kind of bug. T2 next because the editor provider is where every
future change lands.

## Definition of done

This spec is satisfied — and the README "Engineering" item + road-to-v1
"Quality & Testing" item can be ticked off — when:

- All five phases above are merged
- `flutter test` runtime stays under ~30 s on a dev machine (excluding
  integration)
- The five "Priority 1" subsystems each have at least one test file with
  meaningful behaviour assertions (not just construction smoke)
- A documented fixture set lives under `test/fixtures/`
- Integration tests pass on at least one desktop platform in CI

Visual / manual checks (PDF export rendering, real Drive sync, on-device
gesture handling) remain part of the release checklist — not blocked by this
spec.
