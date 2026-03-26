# Snippet Multi-Palette Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multiple colour palettes per snippet so users can switch between colour variants at any time; extend the sprite importer to define palettes from colour strips on the sheet image.

**Architecture:** A new `SnippetPalette` model replaces the raw `threads` list on `Snippet`; `palettes[0]` defines the canonical slot order; alternate palettes map slots positionally to replacement threads. A `resolveThread()` helper is used everywhere a snippet's thread colours are needed. The sprite importer gains a palette-strip workflow and is simplified to crop-only mode.

**Tech Stack:** Flutter 3.41.4, Dart, flutter_riverpod ^2.5.1 (Notifier/NotifierProvider, no codegen), yaml ^3.1.2, uuid ^4.4.0

---

## Dependency Order

Tasks must be completed in order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10. Each task depends on all previous tasks completing successfully.

---

### Task 1: `SnippetPalette` model

**Goal:** Create an immutable `SnippetPalette` model with full YAML round-trip serialization.

**Files:**
- Create: `lib/models/snippet_palette.dart`

**Acceptance Criteria:**
- [ ] `SnippetPalette` is a `@immutable` class with `id`, `name`, `threads`
- [ ] `copyWith` covers all fields
- [ ] `toYaml()` matches the spec's YAML schema
- [ ] `SnippetPalette.fromYaml()` round-trips correctly
- [ ] `flutter analyze` → no issues

**Verify:** `flutter analyze`. No errors.

**Steps:**

- [ ] **Step 1: Create `lib/models/snippet_palette.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'thread.dart';

@immutable
class SnippetPalette {
  final String id;
  final String name;
  /// Ordered thread list — index position defines the "slot".
  final List<Thread> threads;

  const SnippetPalette({
    required this.id,
    required this.name,
    required this.threads,
  });

  factory SnippetPalette.create({
    String? name,
    List<Thread> threads = const [],
  }) {
    return SnippetPalette(
      id: const Uuid().v4(),
      name: name ?? 'Palette 1',
      threads: threads,
    );
  }

  SnippetPalette copyWith({
    String? name,
    List<Thread>? threads,
  }) {
    return SnippetPalette(
      id: id,
      name: name ?? this.name,
      threads: threads ?? this.threads,
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'threads': threads.map((t) => t.toYaml()).toList(),
      };

  factory SnippetPalette.fromYaml(Map<String, dynamic> yaml) {
    return SnippetPalette(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      threads: (yaml['threads'] as List?)
              ?.map((t) =>
                  Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
    );
  }
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/models/snippet_palette.dart
git commit -m "feat: add SnippetPalette model with YAML serialization"
```

---

### Task 2: `Snippet` model — add palettes, migration

**Goal:** Update `Snippet` to hold `List<SnippetPalette>` and `activePaletteIndex`; add a `threads` getter for backward compatibility; remove the raw `threads` field; add migration in `fromYaml`.

**Files:**
- Modify: `lib/models/snippet.dart`

**Acceptance Criteria:**
- [ ] `Snippet.palettes` is `List<SnippetPalette>` (always at least 1 entry)
- [ ] `Snippet.activePaletteIndex` is `int` (defaults to 0)
- [ ] `Snippet.threads` getter returns `palettes[0].threads`
- [ ] `Snippet.create()` wraps provided `threads` in a `SnippetPalette`
- [ ] `Snippet.fromYaml()` migrates old `threads:` format to `palettes[0]`
- [ ] `Snippet.toYaml()` writes `palettes:` and `activePalette:` (not `threads:`)
- [ ] `Snippet.copyWith` accepts `palettes` and `activePaletteIndex`
- [ ] `flutter analyze` → no issues

**Verify:** `flutter analyze`. No errors.

**Steps:**

- [ ] **Step 1: Rewrite `lib/models/snippet.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'snippet_palette.dart';
import 'stitch.dart';
import 'thread.dart';

@immutable
class Snippet {
  final String id;
  final String name;
  final int width;
  final int height;
  final List<Stitch> stitches;
  final List<SnippetPalette> palettes;
  final int activePaletteIndex;

  const Snippet({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.stitches,
    required this.palettes,
    this.activePaletteIndex = 0,
  });

  /// Backward-compatible getter: returns the primary palette's thread list.
  List<Thread> get threads => palettes.isNotEmpty ? palettes[0].threads : const [];

  factory Snippet.create({
    required String name,
    required int width,
    required int height,
    List<Thread> threads = const [],
    List<Stitch> stitches = const [],
  }) {
    return Snippet(
      id: const Uuid().v4(),
      name: name,
      width: width,
      height: height,
      stitches: stitches,
      palettes: [
        SnippetPalette.create(name: 'Palette 1', threads: threads),
      ],
      activePaletteIndex: 0,
    );
  }

  Snippet copyWith({
    String? name,
    int? width,
    int? height,
    List<Stitch>? stitches,
    List<SnippetPalette>? palettes,
    int? activePaletteIndex,
  }) {
    return Snippet(
      id: id,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      stitches: stitches ?? this.stitches,
      palettes: palettes ?? this.palettes,
      activePaletteIndex: activePaletteIndex ?? this.activePaletteIndex,
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'activePalette': activePaletteIndex,
        'stitches': stitches.map((s) => s.toYaml()).toList(),
        'palettes': palettes.map((p) => p.toYaml()).toList(),
      };

  factory Snippet.fromYaml(Map<String, dynamic> yaml) {
    // ── Palette migration ──────────────────────────────────────────────────
    // New format: 'palettes:' key present.
    // Old format: 'threads:' key only → wrap in a single SnippetPalette.
    final palettesYaml = yaml['palettes'] as List?;
    final threadsYaml = yaml['threads'] as List?;

    final List<SnippetPalette> palettes;
    if (palettesYaml != null) {
      palettes = palettesYaml
          .map((p) =>
              SnippetPalette.fromYaml(Map<String, dynamic>.from(p as Map)))
          .toList();
    } else {
      final threads = threadsYaml
              ?.map((t) =>
                  Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          <Thread>[];
      palettes = [
        SnippetPalette(
          id: const Uuid().v4(),
          name: 'Palette 1',
          threads: threads,
        ),
      ];
    }

    // Ensure at least 1 palette
    final safePalettes =
        palettes.isNotEmpty ? palettes : [SnippetPalette.create()];

    return Snippet(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      activePaletteIndex: (yaml['activePalette'] as int?) ?? 0,
      stitches: (yaml['stitches'] as List?)
              ?.map((s) =>
                  Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [],
      palettes: safePalettes,
    );
  }
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/models/snippet.dart
git commit -m "feat: add multi-palette support to Snippet model, migrate threads to palettes"
```

---

### Task 3: `file_service.dart` — serialize snippet palettes

**Goal:** Update `_writeSnippet` in `FileService` to write `palettes:` and `activePalette:` instead of `threads:`.

**Files:**
- Modify: `lib/services/file_service.dart`

**Acceptance Criteria:**
- [ ] `_writeSnippet` writes `activePalette:` integer and a `palettes:` list
- [ ] Each palette entry writes `id:`, `name:`, and a `threads:` list
- [ ] Old files (without `palettes:`) load via the migration in Task 2
- [ ] `flutter analyze` → no issues

**Verify:** Create a snippet, save the pattern, open the `.stitchx` file in a text editor, confirm `palettes:` is present inside the snippet entry.

**Steps:**

- [ ] **Step 1: Update `_writeSnippet` in `lib/services/file_service.dart`**

Add `import '../models/snippet_palette.dart';` at the top if needed (it may not be needed since `Snippet` already exports via its model — but add it to be explicit).

Replace the existing `_writeSnippet` method:

```dart
static void _writeSnippet(StringBuffer buf, Snippet snippet) {
  buf.writeln('  - id: ${_yamlStr(snippet.id)}');
  buf.writeln('    name: ${_yamlStr(snippet.name)}');
  buf.writeln('    width: ${snippet.width}');
  buf.writeln('    height: ${snippet.height}');
  buf.writeln('    activePalette: ${snippet.activePaletteIndex}');
  buf.writeln('    palettes:');
  for (final palette in snippet.palettes) {
    buf.writeln('      - id: ${_yamlStr(palette.id)}');
    buf.writeln('        name: ${_yamlStr(palette.name)}');
    buf.writeln('        threads:');
    for (final t in palette.threads) {
      final m = t.toYaml();
      buf.writeln('          - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
      buf.writeln('            color: ${_yamlStr(m['color'] as String)}');
      buf.writeln('            name: ${_yamlStr(m['name'] as String)}');
      buf.writeln('            symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}');
    }
  }
  buf.writeln('    stitches:');
  for (final s in snippet.stitches) {
    _writeStitch(buf, s, indent: '      ');
  }
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/services/file_service.dart
git commit -m "feat: serialize snippet palettes in file_service"
```

---

### Task 4: `EditorNotifier` — snippet palette management methods

**Goal:** Add all palette management methods for snippets to `EditorNotifier`.

**Files:**
- Modify: `lib/providers/editor_provider.dart`

**Acceptance Criteria:**
- [ ] `setSnippetActivePalette(snippetId, index)` updates `activePaletteIndex` and marks dirty
- [ ] `addSnippetPalette(snippetId, palette)` appends a palette and sets it active
- [ ] `deleteSnippetPalette(snippetId, paletteId)` removes palette (only if ≥2 remain); adjusts `activePaletteIndex` if needed
- [ ] `renameSnippetPalette(snippetId, paletteId, name)` renames
- [ ] `reorderSnippetPalette(snippetId, oldIndex, newIndex)` moves a palette in the list
- [ ] All methods push undo stack
- [ ] `flutter analyze` → no issues

**Verify:** `flutter analyze`. No errors.

**Steps:**

- [ ] **Step 1: Add palette management methods to `EditorNotifier`**

Add these methods at the end of `EditorNotifier`, after the existing snippet methods (`addSnippet`, `updateSnippet`, etc.):

```dart
// ─── Snippet palette management ───────────────────────────────────────────

void setSnippetActivePalette(String snippetId, int index) {
  final snippets = state.pattern.snippets.map((s) {
    if (s.id != snippetId) return s;
    final clamped = index.clamp(0, s.palettes.length - 1);
    return s.copyWith(activePaletteIndex: clamped);
  }).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(snippets: snippets),
    isDirty: true,
  );
}

void addSnippetPalette(String snippetId, SnippetPalette palette) {
  final snippets = state.pattern.snippets.map((s) {
    if (s.id != snippetId) return s;
    final newPalettes = [...s.palettes, palette];
    return s.copyWith(
      palettes: newPalettes,
      activePaletteIndex: newPalettes.length - 1,
    );
  }).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(snippets: snippets),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}

void deleteSnippetPalette(String snippetId, String paletteId) {
  final snippets = state.pattern.snippets.map((s) {
    if (s.id != snippetId) return s;
    if (s.palettes.length <= 1) return s; // cannot delete last palette
    final newPalettes = s.palettes.where((p) => p.id != paletteId).toList();
    // If palette 0 is removed, slot definitions come from the new palettes[0].
    // activePaletteIndex may need adjustment.
    final newActiveIdx =
        s.activePaletteIndex.clamp(0, newPalettes.length - 1);
    return s.copyWith(
      palettes: newPalettes,
      activePaletteIndex: newActiveIdx,
    );
  }).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(snippets: snippets),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}

void renameSnippetPalette(String snippetId, String paletteId, String name) {
  final snippets = state.pattern.snippets.map((s) {
    if (s.id != snippetId) return s;
    final newPalettes = s.palettes.map((p) {
      if (p.id != paletteId) return p;
      return p.copyWith(name: name);
    }).toList();
    return s.copyWith(palettes: newPalettes);
  }).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(snippets: snippets),
    isDirty: true,
  );
}

void reorderSnippetPalette(String snippetId, int oldIndex, int newIndex) {
  final snippets = state.pattern.snippets.map((s) {
    if (s.id != snippetId) return s;
    final palettes = [...s.palettes];
    if (oldIndex < 0 || oldIndex >= palettes.length) return s;
    final palette = palettes.removeAt(oldIndex);
    final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    palettes.insert(insertIdx.clamp(0, palettes.length), palette);
    // Adjust active index to follow the moved item if it was active.
    int newActive = s.activePaletteIndex;
    if (s.activePaletteIndex == oldIndex) {
      newActive = insertIdx.clamp(0, palettes.length - 1);
    }
    return s.copyWith(palettes: palettes, activePaletteIndex: newActive);
  }).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(snippets: snippets),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}
```

Add `import '../models/snippet_palette.dart';` to the top of `editor_provider.dart`.

- [ ] **Step 2: Commit**
```bash
git add lib/providers/editor_provider.dart
git commit -m "feat: add snippet palette management methods to EditorNotifier"
```

---

### Task 5: `resolveThread` helper and `SnippetThumbnail` update

**Goal:** Implement the `resolveThread` lookup function; update `SnippetThumbnail` to render with the active palette applied.

**Files:**
- Create: `lib/models/snippet_palette_resolver.dart`
- Modify: `lib/widgets/snippet_thumbnail.dart`

**Acceptance Criteria:**
- [ ] `resolveThread(Snippet, String baseThreadId)` returns the correct `Thread` from the active palette
- [ ] Falls back to palette 0 if active palette index is out of range or base thread not found
- [ ] `SnippetThumbnail` paints stitches using the active palette colours
- [ ] Switching `activePaletteIndex` causes the thumbnail to re-render with different colours
- [ ] `flutter analyze` → no issues

**Verify:** Create a snippet, add two palettes with different colours, switch between palettes in the panel — thumbnails update immediately.

**Steps:**

- [ ] **Step 1: Create `lib/models/snippet_palette_resolver.dart`**

```dart
import 'snippet.dart';
import 'thread.dart';

/// Resolves the display [Thread] for a given [baseThreadId] in [snippet],
/// applying the currently active palette's colour mapping.
///
/// Slot mapping: palettes[0] defines canonical slot order.
/// palettes[n].threads[i] replaces palettes[0].threads[i] when palette n is active.
///
/// Falls back to palettes[0] if:
/// - activePaletteIndex is 0 or out of range
/// - baseThreadId not found in palette 0
/// - active palette has fewer slots than the base index
Thread resolveThread(Snippet snippet, String baseThreadId) {
  if (snippet.palettes.isEmpty) {
    // Degenerate case — should never happen in valid data.
    return Thread(
      dmcCode: baseThreadId,
      color: const Color(0xFF000000),
      name: baseThreadId,
    );
  }

  final primary = snippet.palettes[0];
  final baseIndex = primary.threads.indexWhere((t) => t.dmcCode == baseThreadId);

  if (baseIndex == -1) {
    // Thread not found in primary palette — return first thread as fallback.
    return primary.threads.isNotEmpty
        ? primary.threads.first
        : Thread(
            dmcCode: baseThreadId,
            color: const Color(0xFF000000),
            name: baseThreadId,
          );
  }

  final activeIdx = snippet.activePaletteIndex;
  // Index 0 is always the primary palette.
  if (activeIdx == 0 || activeIdx >= snippet.palettes.length) {
    return primary.threads[baseIndex];
  }

  final activePalette = snippet.palettes[activeIdx];
  if (baseIndex >= activePalette.threads.length) {
    // Active palette has fewer slots — fall back to primary.
    return primary.threads[baseIndex];
  }

  return activePalette.threads[baseIndex];
}
```

Note: needs `import 'package:flutter/material.dart' show Color;` at the top.

- [ ] **Step 2: Update `lib/widgets/snippet_thumbnail.dart`**

Open `snippet_thumbnail.dart` and find where thread colours are looked up during painting. Everywhere the thumbnail uses `snippet.threads.firstWhere(...)` or builds a thread map, replace with `resolveThread`:

```dart
import '../models/snippet_palette_resolver.dart';

// In the painter's paint method, build the colour map using resolveThread:
final colorMap = <String, Color>{};
for (final stitch in snippet.stitches) {
  if (!colorMap.containsKey(stitch.threadId)) {
    final thread = resolveThread(snippet, stitch.threadId);
    colorMap[stitch.threadId] = thread.color;
  }
}
// Then use colorMap[stitch.threadId] when drawing each stitch.
```

The full thumbnail paint logic likely already has a thread map — just change how it's populated.

- [ ] **Step 3: Commit**
```bash
git add lib/models/snippet_palette_resolver.dart lib/widgets/snippet_thumbnail.dart
git commit -m "feat: add resolveThread helper, update SnippetThumbnail to use active palette"
```

---

### Task 6: Snippet panel — palette dot switcher and "Manage palettes" menu item

**Goal:** Add palette dot indicators below snippet thumbnails in `SnippetsPanel`; add "Manage palettes…" to the snippet ⋮ menu.

**Files:**
- Modify: `lib/widgets/snippets_panel.dart`

**Acceptance Criteria:**
- [ ] Palette dots appear below thumbnails only when `snippet.palettes.length > 1`
- [ ] Dots are filled for active palette, hollow for others
- [ ] Tapping a dot calls `setSnippetActivePalette` and thumbnail re-renders
- [ ] More than 6 palettes: shows `"${active + 1}/${total}"` text instead of dots
- [ ] ⋮ menu has a "Manage palettes…" item that opens the snippet editor (palette manager view)
- [ ] `flutter analyze` → no issues

**Verify:** Create a snippet with 2 palettes, close and reopen the snippets panel. Dots appear. Tap a dot — thumbnail changes colour.

**Steps:**

- [ ] **Step 1: Update `_SnippetCard` in `lib/widgets/snippets_panel.dart`**

Find the `_SnippetCard` widget (or the grid item builder). Add palette dots below the thumbnail:

```dart
// Inside the snippet card Column (below SnippetThumbnail):
if (snippet.palettes.length > 1) ...[
  const SizedBox(height: 4),
  _PaletteDots(snippet: snippet, onSwitch: (idx) {
    ref.read(editorProvider.notifier)
        .setSnippetActivePalette(snippet.id, idx);
  }),
],
```

Add the `_PaletteDots` widget:

```dart
class _PaletteDots extends ConsumerWidget {
  final Snippet snippet;
  final ValueChanged<int> onSwitch;

  const _PaletteDots({required this.snippet, required this.onSwitch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = snippet.palettes.length;
    final active = snippet.activePaletteIndex.clamp(0, count - 1);

    // More than 6 palettes: show counter text
    if (count > 6) {
      return Text(
        '${active + 1}/$count',
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return GestureDetector(
          onTap: () => onSwitch(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
```

- [ ] **Step 2: Update `_showOptions` to add "Manage palettes…" menu item**

Find the `_showOptions` method in `SnippetsPanel`. Add a "Manage palettes…" option that opens `SnippetEditorScreen` and navigates directly to the palette manager:

```dart
void _showOptions(BuildContext context, WidgetRef ref, Snippet snippet) {
  // ... existing options (rename, edit, delete)
  // Add:
  ListTile(
    leading: const Icon(Icons.palette_outlined),
    title: const Text('Manage palettes…'),
    onTap: () {
      Navigator.of(context).pop(); // close bottom sheet options
      _openEditor(context, ref, snippet, openPaletteManager: true);
    },
  ),
}
```

Update `_openEditor` to accept `openPaletteManager: bool = false` and pass it through to `SnippetEditorScreen`.

- [ ] **Step 3: Commit**
```bash
git add lib/widgets/snippets_panel.dart
git commit -m "feat: add palette dot switcher to snippets panel, manage palettes menu item"
```

---

### Task 7: Snippet editor — palette manager bottom sheet and add-palette dialog

**Goal:** Add a palette icon button to the `SnippetEditorScreen` AppBar; implement the Palette Manager bottom sheet (list with rename/delete/reorder/switch); implement the Add Palette dialog (per-slot colour picker).

**Files:**
- Modify: `lib/screens/snippet_editor_screen.dart`

**Acceptance Criteria:**
- [ ] AppBar has a palette icon button (always visible when a snippet is open)
- [ ] Tapping opens `_PaletteManagerSheet` bottom sheet
- [ ] Sheet lists all palettes; active one has a filled dot indicator
- [ ] Tapping a palette row switches the active palette (canvas re-renders live)
- [ ] Inline tap-to-edit renames a palette
- [ ] × delete button on each palette row (hidden when only 1 remains)
- [ ] Drag to reorder via `ReorderableListView`
- [ ] "Add new palette…" button at bottom opens `_AddPaletteDialog`
- [ ] `_AddPaletteDialog` shows mapping table (one row per slot in palette 0), each with a colour picker button
- [ ] Progress counter shows X/N done
- [ ] "Add palette" confirm disabled until all slots filled and name non-empty
- [ ] On confirm: calls `addSnippetPalette` on the notifier (inside the `ProviderScope` override)
- [ ] `flutter analyze` → no issues

**Verify:** Open a snippet editor. Tap the palette icon. Add a new palette, fill all slots, confirm. Switch between palettes via the manager — canvas updates live.

**Steps:**

- [ ] **Step 1: Add the palette button to the `_SnippetEditorBodyState` AppBar**

Find the `Scaffold(appBar: AppBar(...))` in `_SnippetEditorBodyState`. Add a palette `IconButton` to the AppBar actions:

```dart
actions: [
  // ... existing actions ...
  IconButton(
    icon: const Icon(Icons.palette_outlined),
    tooltip: 'Manage palettes',
    onPressed: () => _openPaletteManager(context),
  ),
  // ... save button, etc. ...
],
```

- [ ] **Step 2: Add `_openPaletteManager` method**

```dart
void _openPaletteManager(BuildContext context) {
  // The snippet lives on editorProvider's pattern as a single-snippet pattern.
  // We operate directly on the local editorProvider (ProviderScope-overridden).
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return ProviderScope(
        // Share the same overridden editorProvider
        parent: ProviderScope.containerOf(context),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => _PaletteManagerSheet(
            scrollController: scrollCtrl,
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 3: Implement `_PaletteManagerSheet`**

Add this class to `snippet_editor_screen.dart`:

```dart
class _PaletteManagerSheet extends ConsumerWidget {
  final ScrollController scrollController;
  const _PaletteManagerSheet({required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    // The snippet editor loads the snippet as the entire pattern. Its "palettes"
    // are on the pattern itself via the SnippetEditorScreen's special handling.
    // We need to get palettes from the loaded pattern.
    // In snippet editor, the snippet data is loaded via loadPattern — the palettes
    // must be accessible. We store palettes in EditorState.snippetPalettes (see
    // Step 4 note). For now, access via the pattern's metadata approach.
    //
    // Practical approach: the snippet editor passes the snippet to the body,
    // which stores it. We access it via ref to the parent notifier or
    // via a local field on the state.
    //
    // Since SnippetEditorScreen uses a ProviderScope override, and the snippet
    // is loaded as a CrossStitchPattern (without palettes on the pattern itself),
    // we need a mechanism to store snippet palettes in EditorState during snippet
    // editing. The cleanest approach: add a `snippetPalettes` field to EditorState
    // (List<SnippetPalette>, session-only), populated when loadPattern is called
    // in the snippet editor context.
    //
    // See Step 4 for the EditorState addition.

    final palettes = state.snippetPalettes;
    final activeIdx = state.snippetActivePaletteIndex;
    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Text('Palettes', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: scrollController,
            onReorder: (oldIdx, newIdx) {
              notifier.reorderSnippetPaletteLocal(oldIdx, newIdx);
            },
            itemCount: palettes.length,
            itemBuilder: (ctx, i) {
              final palette = palettes[i];
              final isActive = i == activeIdx;
              return _PaletteRow(
                key: ValueKey(palette.id),
                palette: palette,
                isActive: isActive,
                canDelete: palettes.length > 1,
                onTap: () => notifier.setSnippetActivePaletteLocal(i),
                onRename: (name) =>
                    notifier.renameSnippetPaletteLocal(palette.id, name),
                onDelete: () =>
                    notifier.deleteSnippetPaletteLocal(palette.id),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.tonal(
            onPressed: () async {
              final newPalette = await showDialog<SnippetPalette>(
                context: context,
                builder: (_) => _AddPaletteDialog(
                  basePalette: palettes.isNotEmpty ? palettes[0] : null,
                ),
              );
              if (newPalette != null) {
                notifier.addSnippetPaletteLocal(newPalette);
              }
            },
            child: const Text('+ Add new palette…'),
          ),
        ),
      ],
    );
  }
}
```

**Important note on "local" methods:** The snippet editor uses a `ProviderScope` override, so the `editorProvider` there is a fresh instance. The snippet palettes aren't on the main pattern — they need to be stored in the snippet editor's local EditorState. Add the following fields to `EditorState` (session-only, not persisted):

```dart
// ── Snippet editor palette state (session-only) ───────────────────────────
/// Palettes for the snippet currently being edited in SnippetEditorScreen.
final List<SnippetPalette> snippetPalettes;
/// Active palette index for the snippet currently being edited.
final int snippetActivePaletteIndex;
```

With corresponding `copyWith` fields, defaults to `const []` and `0`.

Add corresponding "local" methods to `EditorNotifier`:
```dart
void setSnippetActivePaletteLocal(int index) {
  state = state.copyWith(snippetActivePaletteIndex: index);
}

void addSnippetPaletteLocal(SnippetPalette palette) {
  final newPalettes = [...state.snippetPalettes, palette];
  state = state.copyWith(
    snippetPalettes: newPalettes,
    snippetActivePaletteIndex: newPalettes.length - 1,
  );
}

void deleteSnippetPaletteLocal(String paletteId) {
  if (state.snippetPalettes.length <= 1) return;
  final newPalettes =
      state.snippetPalettes.where((p) => p.id != paletteId).toList();
  final newActive =
      state.snippetActivePaletteIndex.clamp(0, newPalettes.length - 1);
  state = state.copyWith(
    snippetPalettes: newPalettes,
    snippetActivePaletteIndex: newActive,
  );
}

void renameSnippetPaletteLocal(String paletteId, String name) {
  final newPalettes = state.snippetPalettes.map((p) {
    return p.id == paletteId ? p.copyWith(name: name) : p;
  }).toList();
  state = state.copyWith(snippetPalettes: newPalettes);
}

void reorderSnippetPaletteLocal(int oldIndex, int newIndex) {
  final palettes = [...state.snippetPalettes];
  final palette = palettes.removeAt(oldIndex);
  final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
  palettes.insert(insertIdx.clamp(0, palettes.length), palette);
  int newActive = state.snippetActivePaletteIndex;
  if (state.snippetActivePaletteIndex == oldIndex) {
    newActive = insertIdx.clamp(0, palettes.length - 1);
  }
  state = state.copyWith(snippetPalettes: palettes, snippetActivePaletteIndex: newActive);
}
```

In `_SnippetEditorBodyState.initState`, after `loadPattern`, initialize `snippetPalettes` from the existing snippet:
```dart
// After loadPattern in initState postFrameCallback:
if (s != null) {
  ref.read(editorProvider.notifier).state =
      ref.read(editorProvider).copyWith(
        snippetPalettes: s.palettes,
        snippetActivePaletteIndex: s.activePaletteIndex,
      );
} else {
  // New snippet: initialize with one empty palette
  ref.read(editorProvider.notifier).state =
      ref.read(editorProvider).copyWith(
        snippetPalettes: [SnippetPalette.create(name: 'Palette 1')],
        snippetActivePaletteIndex: 0,
      );
}
```

When `_saveSnippet` is called (the method that pops with the result), build the `Snippet` using `state.snippetPalettes`:
```dart
Snippet _buildResult() {
  final state = ref.read(editorProvider);
  return Snippet(
    id: widget.snippet?.id ?? const Uuid().v4(),
    name: _nameController.text.trim(),
    width: _canvasW,
    height: _canvasH,
    stitches: state.pattern.stitches,
    palettes: state.snippetPalettes.isNotEmpty
        ? state.snippetPalettes
        : [SnippetPalette.create(
            name: 'Palette 1',
            threads: state.pattern.threads,
          )],
    activePaletteIndex: state.snippetActivePaletteIndex,
  );
}
```

- [ ] **Step 4: Implement `_PaletteRow`**

```dart
class _PaletteRow extends StatefulWidget {
  final SnippetPalette palette;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onTap;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  const _PaletteRow({
    required super.key,
    required this.palette,
    required this.isActive,
    required this.canDelete,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends State<_PaletteRow> {
  bool _editing = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.palette.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: widget.onTap,
      leading: Icon(
        widget.isActive ? Icons.circle : Icons.circle_outlined,
        size: 14,
        color: widget.isActive ? theme.colorScheme.primary : null,
      ),
      title: _editing
          ? TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.isNotEmpty) widget.onRename(trimmed);
                setState(() => _editing = false);
              },
            )
          : GestureDetector(
              onTap: () => setState(() => _editing = true),
              child: Text(widget.palette.name,
                  style: const TextStyle(fontSize: 14)),
            ),
      // Swatch row
      subtitle: widget.palette.threads.isEmpty
          ? null
          : Wrap(
              spacing: 3,
              runSpacing: 3,
              children: widget.palette.threads.take(12).map((t) {
                return Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: t.color,
                    border: Border.all(
                        color: Colors.grey.shade400, width: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }).toList(),
            ),
      trailing: widget.canDelete
          ? IconButton(
              icon: const Icon(Icons.close, size: 16),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: widget.onDelete,
            )
          : null,
    );
  }
}
```

- [ ] **Step 5: Implement `_AddPaletteDialog`**

```dart
class _AddPaletteDialog extends ConsumerStatefulWidget {
  final SnippetPalette? basePalette;
  const _AddPaletteDialog({this.basePalette});

  @override
  ConsumerState<_AddPaletteDialog> createState() => _AddPaletteDialogState();
}

class _AddPaletteDialogState extends ConsumerState<_AddPaletteDialog> {
  late final TextEditingController _nameCtrl;
  // Maps slot index → chosen Thread
  final Map<int, Thread> _slotThreads = {};

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _slotCount => widget.basePalette?.threads.length ?? 0;

  bool get _canConfirm =>
      _nameCtrl.text.trim().isNotEmpty &&
      _slotThreads.length == _slotCount;

  Future<void> _pickColour(int slotIdx) async {
    final result = await Navigator.of(context).push<Thread>(
      MaterialPageRoute(
        builder: (_) => ColorPickerScreen(
          existingThreads: ref.read(editorProvider).pattern.threads,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result != null) {
      setState(() => _slotThreads[slotIdx] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = widget.basePalette?.threads ?? [];

    return AlertDialog(
      title: const Text('Add New Palette'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name field
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Palette name',
                hintText: 'e.g. Winter, Summer…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            // Progress
            Text(
              '${_slotThreads.length} / $_slotCount slots filled',
              style: TextStyle(
                fontSize: 12,
                color: _slotThreads.length == _slotCount
                    ? Colors.green.shade700
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            // Slot mapping table
            if (slots.isEmpty)
              const Text(
                  'No slots in primary palette. Add threads to the snippet first.')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: slots.length,
                  itemBuilder: (_, i) {
                    final base = slots[i];
                    final chosen = _slotThreads[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // Original swatch
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: base.color,
                              border: Border.all(
                                  color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'DMC ${base.dmcCode} – ${base.name}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 14),
                          const SizedBox(width: 6),
                          // Chosen colour button
                          GestureDetector(
                            onTap: () => _pickColour(i),
                            child: Container(
                              width: 60,
                              height: 28,
                              decoration: BoxDecoration(
                                color: chosen?.color ?? Colors.grey.shade200,
                                border: Border.all(
                                    color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                chosen != null
                                    ? 'DMC ${chosen.dmcCode}'
                                    : 'Pick…',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: chosen != null
                                      ? (chosen.color.computeLuminance() > 0.4
                                          ? Colors.black
                                          : Colors.white)
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canConfirm
              ? () {
                  final threads = List.generate(
                    _slotCount,
                    (i) => _slotThreads[i]!,
                  );
                  final palette = SnippetPalette(
                    id: const Uuid().v4(),
                    name: _nameCtrl.text.trim(),
                    threads: threads,
                  );
                  Navigator.of(context).pop(palette);
                }
              : null,
          child: const Text('Add palette'),
        ),
      ],
    );
  }
}
```

Add required imports to `snippet_editor_screen.dart`:
```dart
import '../models/snippet_palette.dart';
import '../screens/color_picker_screen.dart';
import 'package:uuid/uuid.dart';
```

- [ ] **Step 6: Commit**
```bash
git add lib/screens/snippet_editor_screen.dart lib/providers/editor_provider.dart
git commit -m "feat: add palette manager sheet and add-palette dialog to snippet editor"
```

---

### Task 8: Sprite importer redesign — remove tile mode, add palette-strip UI

**Goal:** Redesign `SpriteSheetScreen` to crop-only mode with palette strip drawing, controls panel updates, and preview panel.

**Files:**
- Modify: `lib/screens/sprite_sheet_screen.dart`

**Acceptance Criteria:**
- [ ] Tile mode / segmented button removed
- [ ] Crop is always active; no mode switch
- [ ] After crop is drawn, an "auto" palette section appears in controls panel showing detected DMC swatches
- [ ] "Add palette strip" button enters strip-drawing mode
- [ ] In strip mode, the screen dims and a "✕ Cancel palette selection" button appears
- [ ] Strip region can be drawn and has draggable corner handles
- [ ] Re-cropping after strips are defined shows a warning banner
- [ ] Controls panel has: palette list, simplify slider, snippet name, "Add to Snippets" (disabled until crop non-empty), "Change image" in AppBar
- [ ] Preview panel (bottom, tabbed by palette) shows pixelated snippet preview
- [ ] Done button label is "Close" (spec improvement #12)
- [ ] `flutter analyze` → no issues

**Verify:** Open sprite importer. Load an image. Draw a crop. Observe auto palette. Draw a palette strip. Observe strip region. Add to snippets — snippet is created with palettes.

**Steps:**

- [ ] **Step 1: Restructure `_SpriteSheetScreenState` fields**

Remove tile-mode fields:
```dart
// Remove:
SpriteMode _mode = SpriteMode.tile;
int _tileSize = 16;
int? _selTileX;
int? _selTileY;
```

Add palette-strip fields:
```dart
// Crop (always active)
Offset? _cropStart;
Offset? _cropEnd;

// Palette strips
enum _StripDrawState { idle, drawing, adjusting }
_StripDrawState _stripState = _StripDrawState.idle;
Offset? _stripStart;
Offset? _stripEnd;
// List of confirmed strips in image coordinates
final List<Rect> _confirmedStrips = [];
// Corner handle being dragged: (0=TL,1=TR,2=BL,3=BR) or null
int? _draggingStripCorner;
int? _draggingStripIndex; // which confirmed strip
// Re-crop warning
bool _showRecropWarning = false;
```

- [ ] **Step 2: Rebuild the gesture handling**

The existing gesture code handles single-finger drag for crop draw and two-finger pinch for pan/zoom. Remove tile-specific logic. Update crop drag to:
1. Check if `_confirmedStrips.isNotEmpty` and the crop is being resized → show `_showRecropWarning = true`, don't proceed unless user confirms.
2. In strip-drawing mode (`_stripState == _StripDrawState.drawing`): drag creates `_stripStart` / `_stripEnd`.

For corner handle drag on confirmed strips: detect if pointer-down is within 12px of any confirmed strip's corner handle → set `_draggingStripCorner` and `_draggingStripIndex`.

- [ ] **Step 3: Rebuild the layout**

Replace the existing build method's body layout with:

```dart
// Overall structure:
Scaffold(
  appBar: AppBar(
    title: const Text('Sprite Importer'),
    actions: [
      // Change image button
      TextButton.icon(
        icon: const Icon(Icons.image_outlined, size: 16),
        label: const Text('Change image'),
        onPressed: _pickImage,
      ),
      // Close button (was "Done")
      TextButton(
        onPressed: () => Navigator.of(context).pop(_addedCount > 0),
        child: const Text('Close'),
      ),
    ],
  ),
  body: _image == null
      ? _buildNoPicState()
      : Column(
          children: [
            // Re-crop warning banner
            if (_showRecropWarning)
              _RecropWarningBanner(
                onProceed: () {
                  setState(() {
                    _confirmedStrips.clear();
                    _showRecropWarning = false;
                  });
                },
                onCancel: () => setState(() => _showRecropWarning = false),
              ),
            // Strip mode cancel banner
            if (_stripState == _StripDrawState.drawing)
              _StripCancelBanner(
                onCancel: () => setState(() {
                  _stripState = _StripDrawState.idle;
                  _stripStart = null;
                  _stripEnd = null;
                }),
              ),
            Expanded(
              child: Row(
                children: [
                  // Main canvas (left / Expanded)
                  Expanded(child: _buildCanvas()),
                  // Controls panel (right, ~240dp)
                  _buildControlsPanel(),
                ],
              ),
            ),
            // Preview panel (bottom, ~180dp)
            if (_hasCrop) _buildPreviewPanel(),
          ],
        ),
);
```

- [ ] **Step 4: Implement `_buildControlsPanel`**

```dart
Widget _buildControlsPanel() {
  return SizedBox(
    width: 240,
    child: Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── Palettes ────────────────────────────────────────────────────
          Text('Palettes', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_confirmedStrips.isEmpty) ...[
            // Auto-detected palette from crop (greyed, labelled "auto")
            if (_hasCrop) _buildAutopaletteTile(),
          ] else ...[
            for (int i = 0; i < _confirmedStrips.length; i++)
              _buildStripTile(i),
          ],
          const SizedBox(height: 8),
          // Add palette strip button
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(_confirmedStrips.isEmpty
                ? 'Add palette strip'
                : 'Draw another palette strip'),
            onPressed: _hasCrop
                ? () => setState(
                    () => _stripState = _StripDrawState.drawing)
                : null,
          ),
          const Divider(height: 24),
          // ── Simplify palette ──────────────────────────────────────────
          Text(
            'Simplify palette',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Slider(
            value: _mergeThreshold.toDouble(),
            min: 0,
            max: 50,
            divisions: 50,
            label: '$_mergeThreshold',
            onChanged: (v) => setState(() => _mergeThreshold = v.round()),
          ),
          const Divider(height: 24),
          // ── Snippet name ──────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Snippet name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          // ── Add to Snippets ───────────────────────────────────────────
          FilledButton(
            onPressed: _hasCrop && !_importing ? _importAndAdd : null,
            child: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Add to Snippets'),
          ),
          if (_addedCount > 0) ...[
            const SizedBox(height: 8),
            Text('$_addedCount added',
                style: TextStyle(
                    fontSize: 12, color: Colors.green.shade700)),
          ],
        ],
      ),
    ),
  );
}

bool get _hasCrop =>
    _cropStart != null &&
    _cropEnd != null &&
    (_cropEnd! - _cropStart!).distance > 4;
```

- [ ] **Step 5: Implement `_buildPreviewPanel`**

```dart
Widget _buildPreviewPanel() {
  // The number of palette tabs = confirmed strips count (or 1 if none = just "Default")
  final tabCount = _confirmedStrips.isEmpty ? 1 : _confirmedStrips.length;
  return SizedBox(
    height: 160,
    child: Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: DefaultTabController(
        length: tabCount,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _confirmedStrips.isEmpty
                  ? [const Tab(text: 'Default')]
                  : List.generate(
                      _confirmedStrips.length,
                      (i) => Tab(text: 'Palette ${i + 1}'),
                    ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Preview updates after import',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

Note: A full live preview is complex to implement. The MVP preview panel shows the tab structure and a placeholder. Full live rendering of the snippet preview (pixelated grid) can be a follow-up improvement.

- [ ] **Step 6: Commit**
```bash
git add lib/screens/sprite_sheet_screen.dart
git commit -m "feat: redesign sprite importer to crop-only mode with palette strip UI"
```

---

### Task 9: `SpriteImporter` service — palette strip colour detection and multi-palette import

**Goal:** Add `detectPaletteStrip` to `SpriteImporter`; update the import flow in `SpriteSheetScreen` to create snippets with multiple palettes.

**Files:**
- Modify: `lib/services/sprite_importer.dart`
- Modify: `lib/screens/sprite_sheet_screen.dart`

**Acceptance Criteria:**
- [ ] `SpriteImporter.detectPaletteStrip(image, region, horizontal)` returns an ordered `List<Color>` representing contiguous same-colour blocks
- [ ] `SpriteImporter.importRegionToSnippet(image, rect, name, mergeThreshold, paletteStrips)` returns a `Snippet` with palettes populated
- [ ] When no strips provided, returns snippet with single palette (current behaviour)
- [ ] When strips provided, each strip becomes a palette; slot count must match or a fallback is used
- [ ] `flutter analyze` → no issues

**Verify:** Open sprite importer, load image, draw crop and palette strip. Tap "Add to Snippets" — snippet is created with multiple palettes. Open snippets panel, switch dots — colours change.

**Steps:**

- [ ] **Step 1: Add `detectPaletteStrip` to `SpriteImporter`**

```dart
/// Detects ordered colour swatches from a strip region in the image.
/// Scans along the primary axis (horizontal: left-to-right; vertical: top-to-bottom),
/// groups contiguous pixels of the same dominant colour into blocks, and returns
/// one representative colour per block.
///
/// [region] is in image-pixel coordinates (not screen coordinates).
/// [horizontal] true = scan left-to-right; false = scan top-to-bottom.
static List<Color> detectPaletteStrip(
    img.Image image, Rect region, bool horizontal) {
  final x0 = region.left.round().clamp(0, image.width - 1);
  final y0 = region.top.round().clamp(0, image.height - 1);
  final x1 = region.right.round().clamp(0, image.width);
  final y1 = region.bottom.round().clamp(0, image.height);

  if (x1 <= x0 || y1 <= y0) return [];

  final colours = <Color>[];
  Color? lastColour;
  int consecutiveCount = 0;
  const minBlockWidth = 3; // minimum pixels to count as a colour block

  if (horizontal) {
    // Scan each column; take the median row as representative
    final midY = ((y0 + y1) / 2).round().clamp(y0, y1 - 1);
    for (int x = x0; x < x1; x++) {
      final pixel = image.getPixel(x, midY);
      final c = Color.fromARGB(
        pixel.a.toInt(),
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
      // Quantize to nearest 16 to group similar colours
      final quantized = _quantizeColor(c);
      if (lastColour == null || _colorDistance(quantized, lastColour!) > 20) {
        if (consecutiveCount >= minBlockWidth && lastColour != null) {
          colours.add(lastColour!);
        }
        lastColour = quantized;
        consecutiveCount = 1;
      } else {
        consecutiveCount++;
      }
    }
    if (consecutiveCount >= minBlockWidth && lastColour != null) {
      colours.add(lastColour!);
    }
  } else {
    // Scan each row; take the median column as representative
    final midX = ((x0 + x1) / 2).round().clamp(x0, x1 - 1);
    for (int y = y0; y < y1; y++) {
      final pixel = image.getPixel(midX, y);
      final c = Color.fromARGB(
        pixel.a.toInt(),
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
      final quantized = _quantizeColor(c);
      if (lastColour == null || _colorDistance(quantized, lastColour!) > 20) {
        if (consecutiveCount >= minBlockWidth && lastColour != null) {
          colours.add(lastColour!);
        }
        lastColour = quantized;
        consecutiveCount = 1;
      } else {
        consecutiveCount++;
      }
    }
    if (consecutiveCount >= minBlockWidth && lastColour != null) {
      colours.add(lastColour!);
    }
  }

  return colours;
}

static Color _quantizeColor(Color c) {
  int q(double v) => ((v * 255 / 16).round() * 16).clamp(0, 255);
  return Color.fromARGB(255, q(c.r), q(c.g), q(c.b));
}

static double _colorDistance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return sqrt(dr * dr + dg * dg + db * db);
}
```

- [ ] **Step 2: Add `importRegionToSnippet` multi-palette overload**

The existing `importRegion` method returns a `Snippet`. Add a new method that accepts strip colours:

```dart
/// Imports a region and creates a [Snippet] with multiple palettes.
///
/// [paletteStrips] is an ordered list of colour lists, one per palette strip.
/// Each inner list has the same length (slot count = palette 0 size).
/// If [paletteStrips] is empty, behaves like [importRegion] with a single palette.
static Future<Snippet> importRegionWithPalettes({
  required img.Image image,
  required Rect region,
  required String name,
  required int mergeThreshold,
  List<List<Color>> paletteStrips = const [],
}) async {
  // Step 1: Import the base crop to get stitches + primary palette
  final baseSnippet = await importRegion(
    image: image,
    region: region,
    name: name,
    mergeThreshold: mergeThreshold,
  );

  if (paletteStrips.isEmpty) {
    return baseSnippet;
  }

  // Step 2: The primary palette comes from the base import (palette 0 = auto)
  final primaryPalette = baseSnippet.palettes[0];
  final slotCount = primaryPalette.threads.length;

  // Step 3: Build additional palettes from strips
  final palettes = <SnippetPalette>[primaryPalette];

  for (int stripIdx = 0; stripIdx < paletteStrips.length; stripIdx++) {
    final stripColours = paletteStrips[stripIdx];
    final List<Thread> threads;

    if (stripColours.length == slotCount) {
      // Perfect match — map each strip colour to a DMC thread
      threads = stripColours.map((c) {
        final r = (c.r * 255).round();
        final g = (c.g * 255).round();
        final b = (c.b * 255).round();
        final dmc = matchPixel(r, g, b, 255);
        if (dmc != null) {
          return Thread(
              dmcCode: dmc.code, color: dmc.color, name: dmc.name);
        }
        // Fallback: use corresponding primary palette thread
        return primaryPalette.threads[stripColours.indexOf(c) % slotCount];
      }).toList();
    } else {
      // Slot count mismatch — use primary palette as fallback for this strip
      threads = List<Thread>.from(primaryPalette.threads);
    }

    palettes.add(SnippetPalette(
      id: const Uuid().v4(),
      name: 'Palette ${stripIdx + 1}',
      threads: threads,
    ));
  }

  return baseSnippet.copyWith(palettes: palettes);
}
```

Note: The existing `importRegion` method needs to be checked — it likely returns a `Snippet` built with `Snippet.create(...)` which now wraps threads in a palette. Verify it compiles correctly after the `Snippet` model change in Task 2.

- [ ] **Step 3: Update `_importAndAdd` in `SpriteSheetScreen`**

Replace the existing import-and-add logic:
```dart
Future<void> _importAndAdd() async {
  if (_image == null || !_hasCrop) return;
  setState(() => _importing = true);

  try {
    final cropRect = Rect.fromPoints(_cropStart!, _cropEnd!);

    // Detect palette strip colours if strips were drawn
    final List<List<Color>> paletteStripColours = [];
    for (final stripRect in _confirmedStrips) {
      final w = stripRect.width;
      final h = stripRect.height;
      final horizontal = w >= h;
      final colours = SpriteImporter.detectPaletteStrip(
          _image!, stripRect, horizontal);
      if (colours.isNotEmpty) paletteStripColours.add(colours);
    }

    final snippet = await SpriteImporter.importRegionWithPalettes(
      image: _image!,
      region: cropRect,
      name: _nameCtrl.text.trim().isEmpty ? 'Sprite' : _nameCtrl.text.trim(),
      mergeThreshold: _mergeThreshold,
      paletteStrips: paletteStripColours,
    );

    ref.read(editorProvider.notifier).addSnippet(snippet);
    setState(() {
      _addedCount++;
      _importing = false;
      _nameCtrl.text = 'Sprite ${_addedCount + 1}';
    });
  } catch (e) {
    setState(() => _importing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }
}
```

- [ ] **Step 4: Commit**
```bash
git add lib/services/sprite_importer.dart lib/screens/sprite_sheet_screen.dart
git commit -m "feat: palette strip detection in SpriteImporter, multi-palette import"
```

---

### Task 10: `SpriteSheetPainter` — update for crop-only + palette strip overlays

**Goal:** Remove tile mode from `SpriteSheetPainter`; add palette strip overlay painting with corner handles and dim effect.

**Files:**
- Modify: `lib/widgets/sprite_sheet_painter.dart`

**Acceptance Criteria:**
- [ ] `SpriteMode` enum and tile-mode fields removed (or `SpriteMode.tile` branch is dead code removed)
- [ ] New `paletteStrips` parameter renders each confirmed strip with a coloured border + label
- [ ] `isDrawingStrip` parameter + `stripDraftRect` renders the current in-progress strip with a dashed border
- [ ] When `isDrawingStrip` is true, an overlay dims the sprite image outside the strip
- [ ] Corner handles on the sprite crop and each strip rect (same handle style as existing crop handles)
- [ ] `shouldRepaint` covers new fields
- [ ] `flutter analyze` → no issues

**Verify:** Open sprite importer, draw a crop (border visible). Tap "Add palette strip", draw a strip — dashed in-progress border, then confirmed solid border with label "Palette 1".

**Steps:**

- [ ] **Step 1: Rewrite `lib/widgets/sprite_sheet_painter.dart`**

```dart
import 'dart:math';
import 'package:flutter/material.dart';

/// Paints the crop selection and optional palette strip overlays on the sprite sheet.
///
/// Transform: screen = image * zoom + pan
class SpriteSheetPainter extends CustomPainter {
  final Size imageSize;
  final double zoom;
  final Offset pan;

  /// Sprite crop region in image coordinates.
  final Rect? cropRect;

  /// Confirmed palette strip regions in image coordinates.
  final List<Rect> paletteStrips;

  /// In-progress strip being drawn (image coordinates).
  final Rect? stripDraftRect;

  /// Whether the user is currently in strip-drawing mode.
  final bool isDrawingStrip;

  const SpriteSheetPainter({
    required this.imageSize,
    required this.zoom,
    required this.pan,
    this.cropRect,
    this.paletteStrips = const [],
    this.stripDraftRect,
    this.isDrawingStrip = false,
  });

  Offset _toScreen(Offset imgPos) =>
      Offset(imgPos.dx * zoom + pan.dx, imgPos.dy * zoom + pan.dy);

  Rect _rectToScreen(Rect r) =>
      Rect.fromPoints(_toScreen(r.topLeft), _toScreen(r.bottomRight));

  @override
  void paint(Canvas canvas, Size size) {
    _paintCropOverlay(canvas, size);
    _paintPaletteStrips(canvas, size);
    if (isDrawingStrip && stripDraftRect != null) {
      _paintDraftStrip(canvas, stripDraftRect!);
    }
  }

  void _paintCropOverlay(Canvas canvas, Size size) {
    if (cropRect == null || cropRect!.isEmpty) return;
    final dispRect = _rectToScreen(cropRect!);

    // Dark mask outside crop selection
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRect(dispRect),
      ),
      Paint()
        ..color = Colors.black
            .withValues(alpha: isDrawingStrip ? 0.65 : 0.45)
        ..style = PaintingStyle.fill,
    );

    // Selection border
    canvas.drawRect(
      dispRect,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Corner handles
    _drawCornerHandles(canvas, dispRect, Colors.white);
  }

  void _paintPaletteStrips(Canvas canvas, Size size) {
    final colors = [
      Colors.amber,
      Colors.lightBlue,
      Colors.lightGreen,
      Colors.orange,
      Colors.purple,
    ];
    for (int i = 0; i < paletteStrips.length; i++) {
      final strip = paletteStrips[i];
      if (strip.isEmpty) continue;
      final dispRect = _rectToScreen(strip);
      final color = colors[i % colors.length];

      canvas.drawRect(
        dispRect,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        dispRect,
        Paint()
          ..color = color
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
      _drawCornerHandles(canvas, dispRect, color);

      // Label "P1", "P2", etc.
      final tp = TextPainter(
        text: TextSpan(
          text: 'P${i + 1}',
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, dispRect.topLeft + const Offset(4, 2));
    }
  }

  void _paintDraftStrip(Canvas canvas, Rect stripRect) {
    if (stripRect.isEmpty) return;
    final dispRect = _rectToScreen(stripRect);

    // Dashed border
    final path = Path()..addRect(dispRect);
    final dashPaint = Paint()
      ..color = Colors.amber
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..pathEffect = null; // Flutter canvas doesn't support path effects natively

    // Draw dashed rect manually
    _drawDashedRect(canvas, dispRect,
        Paint()..color = Colors.amber.withValues(alpha: 0.6));

    canvas.drawRect(
      dispRect,
      Paint()
        ..color = Colors.amber.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    final borders = [
      (rect.topLeft, rect.topRight),
      (rect.topRight, rect.bottomRight),
      (rect.bottomRight, rect.bottomLeft),
      (rect.bottomLeft, rect.topLeft),
    ];
    for (final (from, to) in borders) {
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.001) continue;
      final ux = dx / dist;
      final uy = dy / dist;
      var d = 0.0;
      var drawing = true;
      while (d < dist) {
        final segLen = min(drawing ? dashLen : gapLen, dist - d);
        if (drawing) {
          canvas.drawLine(
            Offset(from.dx + ux * d, from.dy + uy * d),
            Offset(from.dx + ux * (d + segLen), from.dy + uy * (d + segLen)),
            paint,
          );
        }
        d += segLen;
        drawing = !drawing;
      }
    }
  }

  void _drawCornerHandles(Canvas canvas, Rect rect, Color color) {
    const handleSize = 6.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handleSize, height: handleSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SpriteSheetPainter old) =>
      old.zoom != zoom ||
      old.pan != pan ||
      old.cropRect != cropRect ||
      old.paletteStrips.length != paletteStrips.length ||
      old.stripDraftRect != stripDraftRect ||
      old.isDrawingStrip != isDrawingStrip ||
      old.imageSize != imageSize;
}
```

Remove the `SpriteMode` enum from this file (and update all imports in `sprite_sheet_screen.dart` to no longer reference it).

- [ ] **Step 2: Update `SpriteSheetScreen` to pass the new painter parameters**

In `_buildCanvas()` in `sprite_sheet_screen.dart`, construct `SpriteSheetPainter` with the new signature:
```dart
SpriteSheetPainter(
  imageSize: Size(_image!.width.toDouble(), _image!.height.toDouble()),
  zoom: _zoom,
  pan: _pan,
  cropRect: _hasCrop
      ? Rect.fromPoints(_cropStart!, _cropEnd!)
      : null,
  paletteStrips: _confirmedStrips,
  stripDraftRect: _stripState != _StripDrawState.idle &&
          _stripStart != null &&
          _stripEnd != null
      ? Rect.fromPoints(_stripStart!, _stripEnd!)
      : null,
  isDrawingStrip: _stripState == _StripDrawState.drawing,
),
```

- [ ] **Step 3: Commit**
```bash
git add lib/widgets/sprite_sheet_painter.dart lib/screens/sprite_sheet_screen.dart
git commit -m "feat: update SpriteSheetPainter for crop-only + palette strip overlays"
```

---

## Final Integration

After all 10 tasks are complete, run a full manual integration test:

1. `flutter analyze` → zero issues
2. Run `flutter run -d macos`
3. Open an existing `.stitchx` file (old format, with flat `threads:` on snippets) — snippets load correctly, single palette shown
4. Open snippets panel — no palette dots (single palette)
5. Tap a snippet → enters paste mode (correct palette colours)
6. Open snippet editor → palette icon in AppBar visible
7. Tap palette icon → Palette Manager sheet opens, shows "Palette 1"
8. "Add new palette…" → fill all slots via colour picker → confirm → new palette added, active
9. Close snippet editor → panel shows palette dots below thumbnail
10. Tap each dot → thumbnail re-renders with different colours
11. Open sprite importer, load a sprite sheet image
12. Draw a crop region
13. Tap "Add palette strip" → strip-drawing mode starts
14. Draw a strip → confirmed as "P1" with amber border
15. "Add to Snippets" → snippet added with 2 palettes
16. Open snippets panel → snippet has palette dots
17. Save file → reopen → palettes preserved
