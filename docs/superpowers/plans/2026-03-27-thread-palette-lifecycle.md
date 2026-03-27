# Thread Palette Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the thread palette a read-only mirror of canvas usage — threads auto-enter on first stitch, auto-leave when last stitch is erased, and composite thread symbols are stable across save/reload.

**Architecture:** Four cooperating changes: (1) extended symbol pool in `symbols.dart`; (2) `compositeSymbols` registry persisted in the pattern model; (3) thread lifecycle logic centralised in `EditorNotifier` (`addStitch` auto-registers, stitch-removal methods call `_pruneUnusedThreads`); (4) UI removes the "Add colour" affordance and the colour picker collapses to a pure selector.

**Tech Stack:** Flutter/Dart, Riverpod `Notifier`, YAML serialisation via `file_service.dart`, `kPatternSymbols` pool in `symbols.dart`.

---

### Task 1: Extend symbol pool

**Goal:** Add ~117 new UTF-8 symbols to `kPatternSymbols`, bringing the pool from 63 to ~180.

**Files:**
- Modify: `lib/data/symbols.dart`

**Acceptance Criteria:**
- [ ] `kPatternSymbols` contains all existing symbols plus the new additions
- [ ] No duplicate symbols in the list
- [ ] `flutter test` passes

**Verify:** `cd /Users/scottmerchant/dev/stitchx && export PATH="/opt/homebrew/bin:$PATH" && flutter test` → All tests pass

**Steps:**

- [ ] **Step 1: Replace the contents of `lib/data/symbols.dart`**

```dart
/// Ordered pool of symbols available for thread identification in patterns.
const kPatternSymbols = [
  // Uppercase Latin
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
  'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
  'U', 'V', 'W', 'X', 'Y', 'Z',
  // Digits
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  // ASCII punctuation / operators
  '+', '-', '/', '|', '#', '@', '\$', '%', '&', '~',
  '!', '?', '<', '>', '=', '^', '*',
  // Filled / outline geometric shapes
  '■', '●', '▲', '▼', '◆', '★', '○', '□', '△', '◇',
  // Lowercase Latin (visually distinct from uppercase)
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
  'k', 'm', 'n', 'p', 'q', 'r', 's', 'u', 'v', 'w', 'x', 'y', 'z',
  // Greek (recognisable at small cell sizes)
  'α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'λ', 'μ',
  'ξ', 'π', 'ρ', 'σ', 'τ', 'φ', 'χ', 'ψ', 'ω',
  // Playing card suits
  '♠', '♣', '♥', '♦',
  // Arrows
  '↑', '↓', '→', '←', '↗', '↘', '↙', '↖', '↔', '↕',
  // Circled operators
  '⊕', '⊖', '⊗', '⊙', '⊚',
  // More filled / outline shapes
  '▶', '◀', '▸', '◂', '⬡', '⬢', '⬤', '⬥',
  '▪', '▫', '▴', '▾', '◉', '◎',
  // Stars / snowflakes
  '✦', '✧', '✩', '✪', '✫', '✬', '✭', '✮', '✯', '✰',
  // Dingbats / marks
  '✓', '✗', '✚', '✜', '✝',
  // Misc punctuation / currency / special
  '§', '¶', '°', '±', '×', '÷', '€', '£', '¥', '¢',
  '©', '®', '™', '¿', '¡',
];
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/symbols.dart
git commit -m "feat: extend symbol pool to ~180 UTF-8 symbols"
```

---

### Task 2: Add `compositeSymbols` registry to pattern model and serialisation

**Goal:** `CrossStitchPattern` gains a `compositeSymbols: Map<String, String>` field (dmcCode → symbol) that is persisted to and restored from the `.stitchx` YAML file.

**Files:**
- Modify: `lib/models/pattern.dart`
- Modify: `lib/services/file_service.dart`

**Acceptance Criteria:**
- [ ] `CrossStitchPattern` has `compositeSymbols` field defaulting to `const {}`
- [ ] `copyWith` supports nullable override with sentinel
- [ ] `fromYaml` reads `compositeSymbols:` key, falls back to `{}` when absent
- [ ] `toYamlString` writes `compositeSymbols:` block only when non-empty
- [ ] `flutter test` passes

**Verify:** `cd /Users/scottmerchant/dev/stitchx && export PATH="/opt/homebrew/bin:$PATH" && flutter test` → All tests pass

**Steps:**

- [ ] **Step 1: Add field to `CrossStitchPattern`**

In `lib/models/pattern.dart`, add the field after `snippets`:

```dart
/// Stable symbol assignments for composite (blended) thread colours.
/// Maps dmcCode → symbol. Persisted so symbols survive save/reload.
final Map<String, String> compositeSymbols;
```

Update the constructor to include it:

```dart
const CrossStitchPattern({
  // ... existing params ...
  this.compositeSymbols = const {},
});
```

- [ ] **Step 2: Update `copyWith`**

Add the parameter and body:

```dart
CrossStitchPattern copyWith({
  // ... existing params ...
  Object? compositeSymbols = _sentinel,
}) {
  return CrossStitchPattern(
    // ... existing fields ...
    compositeSymbols: compositeSymbols == _sentinel
        ? this.compositeSymbols
        : compositeSymbols as Map<String, String>,
  );
}
```

- [ ] **Step 3: Update `fromYaml`**

Inside `CrossStitchPattern.fromYaml`, after the snippets parse, add:

```dart
compositeSymbols: () {
  final raw = yaml['compositeSymbols'];
  if (raw == null) return const <String, String>{};
  return Map<String, String>.from(raw as Map);
}(),
```

Pass it into the `return CrossStitchPattern(...)` call.

- [ ] **Step 4: Update `toYamlString` in `file_service.dart`**

After the snippets block write, add:

```dart
if (pattern.compositeSymbols.isNotEmpty) {
  buf.writeln('compositeSymbols:');
  for (final entry in pattern.compositeSymbols.entries) {
    buf.writeln('  ${_yamlStr(entry.key)}: ${_yamlStr(entry.value)}');
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add lib/models/pattern.dart lib/services/file_service.dart
git commit -m "feat: add compositeSymbols registry to pattern model and YAML serialisation"
```

---

### Task 3: Thread auto-register on stitch placement, auto-prune on stitch removal

**Goal:** Threads enter `pattern.threads` automatically when the first stitch using them is placed, and are removed automatically when the last stitch using them is erased across all layers. `addThread()` is removed.

**Files:**
- Modify: `lib/providers/editor_provider.dart`
- Modify: `lib/data/dmc_colors.dart` (no change needed — `dmcColorByCode` already exported)

**Acceptance Criteria:**
- [ ] `addThread()` method no longer exists on `EditorNotifier`
- [ ] `addStitch()` auto-adds the thread to `pattern.threads` (with unique symbol) if not already present
- [ ] `pasteStitches()` auto-adds missing clipboard threads (with unique symbols, respecting `compositeSymbols`)
- [ ] `removeStitchesAt()`, `deleteSelection()`, `resizePattern()`, `removeBackstitchAt()` all call `_pruneUnusedThreads` after modifying stitches
- [ ] `pickColorAtCell()` no longer adds composite thread to `pattern.threads` — it only calls `setSelectedThread`
- [ ] `EditorState.selectedThread` falls back to the DMC database when `selectedThreadId` is not in `pattern.threads`
- [ ] `flutter test` passes

**Verify:** `cd /Users/scottmerchant/dev/stitchx && export PATH="/opt/homebrew/bin:$PATH" && flutter test` → All tests pass

**Steps:**

- [ ] **Step 1: Add `_allUsedSymbols` helper and update `_resolveThreadSymbol`**

Add this helper method to `EditorNotifier`:

```dart
/// All symbols currently reserved in the pattern (both palette threads
/// and the composite symbol registry). Used to guarantee uniqueness
/// when auto-assigning a symbol to a new thread.
Set<String> _allUsedSymbols([CrossStitchPattern? pattern]) {
  final p = pattern ?? state.pattern;
  return {
    for (final t in p.threads) if (t.symbol.isNotEmpty) t.symbol,
    ...p.compositeSymbols.values.where((s) => s.isNotEmpty),
  };
}
```

Update the existing `_resolveThreadSymbol` to seed from `_allUsedSymbols` instead of just `existingThreads`:

```dart
Thread _resolveThreadSymbol(Thread thread, List<Thread> existingThreads) {
  final usedSymbols = {
    ...existingThreads.map((t) => t.symbol).where((s) => s.isNotEmpty),
    ...state.pattern.compositeSymbols.values.where((s) => s.isNotEmpty),
  };
  if (thread.symbol.isEmpty || usedSymbols.contains(thread.symbol)) {
    return thread.copyWith(symbol: _nextSymbol(usedSymbols));
  }
  return thread;
}
```

- [ ] **Step 2: Add `_pruneUnusedThreads` helper**

```dart
/// Removes any threads from [pattern.threads] that are no longer referenced
/// by any stitch across all layers.
CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern) {
  final used = <String>{};
  for (final layer in pattern.layers) {
    for (final stitch in layer.stitches) {
      final id = switch (stitch) {
        FullStitch(:final threadId) => threadId,
        HalfStitch(:final threadId) => threadId,
        HalfCrossStitch(:final threadId) => threadId,
        QuarterStitch(:final threadId) => threadId,
        QuarterCrossStitch(:final threadId) => threadId,
        BackStitch(:final threadId) => threadId,
        _ => null,
      };
      if (id != null) used.add(id);
    }
  }
  final pruned = pattern.threads.where((t) => used.contains(t.dmcCode)).toList();
  if (pruned.length == pattern.threads.length) return pattern;
  return pattern.copyWith(threads: pruned);
}
```

- [ ] **Step 3: Update `addStitch` to auto-register thread**

Replace the body of `addStitch`:

```dart
void addStitch(Stitch stitch) {
  // Skip if identical stitch already exists.
  final alreadyExists = state.activeLayer.stitches
      .any((s) => s == stitch && s.threadId == stitch.threadId);
  if (alreadyExists) return;

  // Auto-register thread into palette if this is its first stitch.
  var pattern = state.pattern;
  final threadId = stitch.threadId;
  if (!pattern.threads.any((t) => t.dmcCode == threadId)) {
    final dmc = dmcColorByCode(threadId);
    if (dmc != null) {
      final usedSymbols = _allUsedSymbols(pattern);
      final newThread = Thread(
        dmcCode: dmc.code,
        color: dmc.color,
        name: dmc.name,
        symbol: _nextSymbol(usedSymbols),
      );
      pattern = pattern.copyWith(threads: [...pattern.threads, newThread]);
    }
  }

  final newStitches = _stitchesWithAdded(state.activeLayer.stitches, stitch);
  final newPattern = _patternWithActiveLayerStitches(pattern, newStitches);
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}
```

- [ ] **Step 4: Update `pasteStitches` to use `_allUsedSymbols`**

In `pasteStitches`, the existing clipboard-thread-adding loop uses `_resolveThreadSymbol(ct, threads)`. Since `_resolveThreadSymbol` now already reads `compositeSymbols` from `state.pattern`, this will automatically be correct. No code change needed in the loop itself — but verify the loop reads:

```dart
for (final ct in state.clipboardThreads ?? <Thread>[]) {
  if (!threads.any((t) => t.dmcCode == ct.dmcCode)) {
    threads.add(_resolveThreadSymbol(ct, threads));
  }
}
```

This is already correct after Step 1's `_resolveThreadSymbol` update.

- [ ] **Step 5: Add `_pruneUnusedThreads` call to stitch-removing methods**

In `removeStitchesAt`, update the state assignment:

```dart
void removeStitchesAt(int x, int y) {
  bool hit(Stitch s) => _stitchAtCell(s, x, y) || _backstitchInCell(s, x, y);
  if (!state.activeLayer.stitches.any(hit)) return;

  final newStitches =
      state.activeLayer.stitches.where((s) => !hit(s)).toList();
  final newPattern = _pruneUnusedThreads(
      _patternWithActiveLayerStitches(state.pattern, newStitches));
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}
```

In `deleteSelection`, update the pattern assignment:

```dart
final newPattern = _pruneUnusedThreads(
    _patternWithActiveLayerStitches(state.pattern, remaining));
```

In `resizePattern`, update the pattern assignment:

```dart
final newPattern = _pruneUnusedThreads(_patternWithAllLayersTransformed(
  old.copyWith(width: newWidth, height: newHeight),
  (stitches) => stitches
      .map((s) => EditorState.offsetStitch(s, dx, dy))
      .where(inBounds)
      .toList(),
));
```

In `removeBackstitchAt`, update the pattern assignment:

```dart
final newPattern = _pruneUnusedThreads(
    _patternWithActiveLayerStitches(state.pattern, newStitches));
```

- [ ] **Step 6: Update `pickColorAtCell` — remove palette mutation**

In `pickColorAtCell`, find the multi-layer composite block (around line 537). Replace:

```dart
// Ensure the composite thread is in the palette (with a symbol), then select it.
var pattern = s.pattern;
if (!threadMap.containsKey(dmc.code)) {
  final newThread = _resolveThreadSymbol(
    Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name),
    pattern.threads,
  );
  pattern = pattern.copyWith(threads: [...pattern.threads, newThread]);
}
select(dmc.code, pattern);
```

With:

```dart
// Just select the composite DMC code — the thread auto-registers when
// the first stitch is placed via addStitch().
select(dmc.code);
```

- [ ] **Step 7: Update `EditorState.selectedThread` to fall back to DMC database**

In `EditorState`, update the `selectedThread` getter so the toolbar can display a pending colour that hasn't been palette-registered yet:

```dart
Thread? get selectedThread {
  if (selectedThreadId == null) return null;
  final inPalette = pattern.threadByCode(selectedThreadId!);
  if (inPalette != null) return inPalette;
  // Not yet in palette (selected but no stitch placed yet) — look up in DMC db.
  final dmc = dmcColorByCode(selectedThreadId!);
  if (dmc == null) return null;
  return Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
}
```

Note: `dmcColorByCode` is imported from `lib/data/dmc_colors.dart`. Add the import to `editor_provider.dart` if not already present.

- [ ] **Step 8: Remove `addThread` method**

Delete the entire `addThread` method (lines ~788–802). Confirm no other callers remain after `color_picker_screen.dart` is updated in Task 5.

- [ ] **Step 9: Commit**

```bash
git add lib/providers/editor_provider.dart
git commit -m "feat: auto-register threads on first stitch, auto-prune on last erase"
```

---

### Task 4: Composite symbol registry in `refreshCompositeCache` + `changeCompositeSymbol`

**Goal:** `refreshCompositeCache` reads from and writes back to `pattern.compositeSymbols` so symbols are stable across rebuilds. A new `changeCompositeSymbol` method lets users manually override a composite symbol.

**Files:**
- Modify: `lib/providers/editor_provider.dart`

**Acceptance Criteria:**
- [ ] `refreshCompositeCache` seeds `used` from both `pattern.threads` symbols and `pattern.compositeSymbols.values`
- [ ] Existing composite DMC codes in `pattern.compositeSymbols` reuse their stored symbol
- [ ] After rebuild, `pattern.compositeSymbols` is updated to contain only current composite DMC codes
- [ ] `changeCompositeSymbol(String dmcCode, String symbol)` rejects symbols already in use and immediately rebuilds the cache
- [ ] `flutter test` passes

**Verify:** `cd /Users/scottmerchant/dev/stitchx && export PATH="/opt/homebrew/bin:$PATH" && flutter test` → All tests pass

**Steps:**

- [ ] **Step 1: Rewrite `refreshCompositeCache`**

Replace the existing `refreshCompositeCache` method body:

```dart
void refreshCompositeCache() {
  final raw = computeCompositeThreads(state.pattern);

  final patternMap = <String, Thread>{
    for (final t in state.pattern.threads) t.dmcCode: t,
  };

  // Seed used symbols from both palette threads and the existing composite registry.
  // This guarantees no new assignment can collide with either source.
  final used = _allUsedSymbols();

  // Build updated composite registry containing only currently-active composites.
  final newRegistry = <String, String>{};

  final resolved = raw.map((cell, thread) {
    // 1. DMC code is a pattern thread — inherit its symbol.
    final existing = patternMap[thread.dmcCode];
    if (existing != null && existing.symbol.isNotEmpty) {
      newRegistry[thread.dmcCode] = existing.symbol;
      return MapEntry(cell, existing);
    }

    // 2. DMC code has a stored composite symbol — reuse it.
    final stored = state.pattern.compositeSymbols[thread.dmcCode];
    if (stored != null && stored.isNotEmpty && !used.contains(stored)) {
      used.add(stored);
      newRegistry[thread.dmcCode] = stored;
      return MapEntry(cell, thread.copyWith(symbol: stored));
    }
    if (stored != null && stored.isNotEmpty) {
      // stored symbol is already used by a pattern thread — reassign.
    }

    // 3. Assign a fresh symbol.
    final sym = _nextSymbol(used);
    if (sym.isNotEmpty) used.add(sym);
    if (sym.isNotEmpty) newRegistry[thread.dmcCode] = sym;
    return MapEntry(cell, thread.copyWith(symbol: sym));
  });

  // Write updated registry back to pattern so it persists on next save.
  state = state.copyWith(
    compositeThreadCache: resolved,
    pattern: state.pattern.copyWith(compositeSymbols: newRegistry),
    isDirty: true,
  );
}
```

- [ ] **Step 2: Add `changeCompositeSymbol`**

```dart
/// Manually overrides the symbol for a composite (blended) thread.
/// Rejects the symbol if it is already used by any pattern thread or
/// other composite entry, then immediately rebuilds the composite cache.
///
/// Returns true if applied, false if rejected (symbol already taken).
bool changeCompositeSymbol(String dmcCode, String symbol) {
  final usedByOthers = {
    for (final t in state.pattern.threads)
      if (t.symbol.isNotEmpty) t.symbol,
    for (final entry in state.pattern.compositeSymbols.entries)
      if (entry.key != dmcCode && entry.value.isNotEmpty) entry.value,
  };
  if (usedByOthers.contains(symbol)) return false;

  final newRegistry = Map<String, String>.from(state.pattern.compositeSymbols)
    ..[dmcCode] = symbol;
  state = state.copyWith(
    pattern: state.pattern.copyWith(compositeSymbols: newRegistry),
  );
  refreshCompositeCache();
  return true;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/providers/editor_provider.dart
git commit -m "feat: persist composite symbols across cache rebuilds, add changeCompositeSymbol"
```

---

### Task 5: Colour picker collapses to selector; palette removes "Add colour" row

**Goal:** `ColorPickerScreen` in non-replace mode now calls `setSelectedThread` only. The `_PaletteDialog` "Add colour…" list tile is removed.

**Files:**
- Modify: `lib/screens/color_picker_screen.dart`
- Modify: `lib/widgets/editor_toolbar.dart`

**Acceptance Criteria:**
- [ ] Selecting a colour in the picker (non-replace mode) calls `setSelectedThread` regardless of whether the colour is already in the palette
- [ ] The `_PaletteDialog` no longer has an "Add colour…" row at the bottom
- [ ] The picker title reads "Select Colour" in non-replace mode
- [ ] `flutter test` passes

**Verify:** `cd /Users/scottmerchant/dev/stitchx && export PATH="/opt/homebrew/bin:$PATH" && flutter test` → All tests pass

**Steps:**

- [ ] **Step 1: Collapse `_onThreadSelected` in `color_picker_screen.dart`**

Find the `_onThreadSelected` callback (around line 80–106). Replace the entire non-replace branch so both cases call `setSelectedThread`:

```dart
// Normal mode — select thread (auto-registered into palette on first stitch).
notifier.setSelectedThread(dmcColor.code);
Navigator.of(context).pop();
```

The full updated method:

```dart
void _onThreadSelected(DmcColor dmcColor) {
  final notifier = ref.read(editorProvider.notifier);

  // Replace mode — remap all stitches to the new colour.
  if (widget.replacingThreadId != null) {
    final replacingId = widget.replacingThreadId!;
    notifier.replaceThread(
      replacingId,
      dmcColor.code,
      dmcColor.color,
      dmcColor.name,
    );
    Navigator.of(context).pop();
    return;
  }

  // Select mode — set as active colour; palette entry created on first stitch.
  notifier.setSelectedThread(dmcColor.code);
  Navigator.of(context).pop();
}
```

- [ ] **Step 2: Update picker title**

In the `AppBar` title of `ColorPickerScreen.build`, change:

```dart
title: Text(widget.replacingThreadId != null
    ? 'Replace Colour'
    : 'Select Colour'),   // was 'Add Colour' or similar
```

- [ ] **Step 3: Remove "Add colour…" row from `_PaletteDialog`**

In `editor_toolbar.dart`, find the `_PaletteDialog.build` method. Delete these lines (around line 673–680):

```dart
const Divider(height: 1),
// Add colour — opens picker on top without closing this dialog
ListTile(
  dense: true,
  leading: const Icon(Icons.add, size: 20),
  title: const Text('Add colour…'),
  onTap: () => showColorPicker(context),
),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/color_picker_screen.dart lib/widgets/editor_toolbar.dart
git commit -m "feat: palette read-only — colour picker collapses to selector, remove add-colour row"
```

---

### Task 6: Symbol picker uniqueness validation for both thread types

**Goal:** The symbol picker validates that the chosen symbol is not already used by any other thread (pattern or composite) before applying. Composite threads in canvas mode get a tappable symbol cell that calls `changeCompositeSymbol`.

**Files:**
- Modify: `lib/widgets/editor_toolbar.dart`

**Acceptance Criteria:**
- [ ] Selecting an already-taken symbol in the picker for a pattern thread shows a `SnackBar` error and does not apply the change
- [ ] Tapping a composite thread's symbol swatch in canvas mode opens the symbol picker
- [ ] Selecting an already-taken symbol for a composite thread shows a `SnackBar` error and does not apply
- [ ] `flutter test` passes

**Verify:** `cd /Users/scottmerchant/dev/stitchx && export PATH="/opt/homebrew/bin:$PATH" && flutter test` → All tests pass

**Steps:**

- [ ] **Step 1: Add uniqueness validation to `_showSymbolPicker` for pattern threads**

In `_PaletteDialog._showSymbolPicker`, update `onSelect` to validate before applying:

```dart
void _showSymbolPicker(BuildContext context, WidgetRef ref, Thread t) {
  showDialog<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _SymbolPickerDialog(
        thread: t,
        onSelect: (s) {
          final state = ref.read(editorProvider);
          final takenByOther = state.pattern.threads
              .any((other) => other.dmcCode != t.dmcCode && other.symbol == s)
              || state.pattern.compositeSymbols.entries
              .any((e) => e.value == s);
          if (takenByOther) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("'$s' is already used by another thread")),
            );
            return;
          }
          ref.read(editorProvider.notifier).changeThreadSymbol(t.dmcCode, s);
          Navigator.of(context).pop();
        },
      ),
    ),
  );
}
```

- [ ] **Step 2: Add composite symbol tap in canvas mode**

In `_PaletteDialog.build`, the `displayThreads` list in canvas mode comes from `compositeThreadCache`. Add a helper method for composite symbol picking alongside `_showSymbolPicker`:

```dart
void _showCompositeSymbolPicker(BuildContext context, WidgetRef ref, Thread t) {
  showDialog<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _SymbolPickerDialog(
        thread: t,
        onSelect: (s) {
          final applied =
              ref.read(editorProvider.notifier).changeCompositeSymbol(t.dmcCode, s);
          Navigator.of(context).pop();
          if (!applied) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("'$s' is already used by another thread")),
            );
          }
        },
      ),
    ),
  );
}
```

- [ ] **Step 3: Wire composite symbol tap into the palette list tile**

In `_PaletteDialog.build`, the `ListTile` symbol tap currently always calls `_showSymbolPicker`. Update to branch on whether we are in composite mode:

```dart
onTap: () {
  if (state.showCompositeThreads) {
    _showCompositeSymbolPicker(context, ref, t);
  } else {
    _showSymbolPicker(context, ref, t);
  }
},
```

Apply this to both the `leading: GestureDetector` and the `Tooltip` > `GestureDetector` in the trailing row that triggers the symbol picker.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/editor_toolbar.dart
git commit -m "feat: symbol picker validates uniqueness; composite threads get tappable symbol in canvas mode"
```
