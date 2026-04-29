---
"stitches": minor
---

Step 12: Map threads, Cell class, O(1) lookups, undo.onChange

- `pattern.threads`: `List<Thread>` → `Map<String, Thread>` keyed by `dmcCode` — O(1) lookup replaces `.any()`/`.firstWhere()` scans throughout providers, widgets, services, and screens.
- `Cell` value class (`lib/models/cell.dart`) — canonical grid coordinate with `==`/`hashCode`; static `hitStitch`/`hitBox` consolidate duplicated `_hitCell`/`_hitBox` from edit controllers.
- `UndoManager.onChange` callback — eliminates separate `_syncUndoState()` calls after every `execute`/`undo`/`redo`.
- `Layer._cellIndex` — lazy `Map<String, List<Stitch>>` for O(1) `stitchesAt(x, y)` lookups; `@immutable`/`const` removed (cache field is non-final).
- Static YAML parsers: `Thread.mapFromYaml`, `Stitch.listFromYaml`, `Snippet.listFromYaml` — consolidate parse logic out of `pattern.dart`.
