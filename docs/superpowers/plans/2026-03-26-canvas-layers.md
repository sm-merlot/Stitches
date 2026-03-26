# Canvas Layers Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add named, reorderable layers to the main canvas, each with per-layer visibility and opacity, with full undo support and a right-side layers panel visible in both EditorScreen and WorkspaceScreen.

**Architecture:** A new `Layer` model wraps each layer's stitch list; `CrossStitchPattern.layers` replaces `CrossStitchPattern.stitches`; a migration in `fromYaml` wraps old `stitches:` files into a single "Layer 1" transparently. `EditorState` gains `activeLayerId` and a lazy composite-thread cache; all draw/erase/fill operations are scoped to the active layer's stitch list only.

**Tech Stack:** Flutter 3.41.4, Dart, flutter_riverpod ^2.5.1 (Notifier/NotifierProvider, no codegen), yaml ^3.1.2, uuid ^4.4.0

---

## Dependency Order

Tasks must be completed in order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10. Each task depends on all previous tasks completing successfully.

---

### Task 1: `Layer` model

**Goal:** Create an immutable `Layer` model with full YAML round-trip serialization.

**Files:**
- Create: `lib/models/layer.dart`

**Acceptance Criteria:**
- [ ] `Layer` is a `@immutable` class with `id`, `name`, `visible`, `opacity`, `stitches`
- [ ] `copyWith` handles all nullable fields using sentinel pattern
- [ ] `toYaml()` produces a `Map<String, dynamic>` matching the spec's YAML schema
- [ ] `Layer.fromYaml()` parses a map back to a `Layer`
- [ ] `flutter analyze` → no issues

**Verify:** Run `flutter analyze`. Open `lib/models/layer.dart` and visually confirm fields, constructors, and YAML methods.

**Steps:**

- [ ] **Step 1: Create `lib/models/layer.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'stitch.dart';

@immutable
class Layer {
  final String id;
  final String name;
  final bool visible;
  final double opacity;
  final List<Stitch> stitches;

  const Layer({
    required this.id,
    required this.name,
    required this.visible,
    required this.opacity,
    required this.stitches,
  });

  factory Layer.create({String? name}) {
    return Layer(
      id: const Uuid().v4(),
      name: name ?? 'Layer 1',
      visible: true,
      opacity: 1.0,
      stitches: const [],
    );
  }

  Layer copyWith({
    String? name,
    bool? visible,
    double? opacity,
    List<Stitch>? stitches,
  }) {
    return Layer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      stitches: stitches ?? this.stitches,
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      };

  factory Layer.fromYaml(Map<String, dynamic> yaml) {
    return Layer(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      visible: yaml['visible'] as bool? ?? true,
      opacity: (yaml['opacity'] as num?)?.toDouble() ?? 1.0,
      stitches: (yaml['stitches'] as List?)
              ?.map((s) => Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [],
    );
  }
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/models/layer.dart
git commit -m "feat: add Layer model with YAML serialization"
```

---

### Task 2: `CrossStitchPattern` — replace `stitches` with `layers`

**Goal:** Migrate `CrossStitchPattern` from a flat `stitches` list to a `layers` list, with `editorActiveLayerId` persisted in the `editor:` block, and a `stitches` getter for backward compat.

**Files:**
- Modify: `lib/models/pattern.dart`

**Acceptance Criteria:**
- [ ] `pattern.layers` is a `List<Layer>` (ordered bottom-to-top)
- [ ] `pattern.editorActiveLayerId` is a `String?`
- [ ] `pattern.stitches` getter returns the union of all layer stitch lists (backward compat for code not yet updated)
- [ ] `CrossStitchPattern.empty()` creates a single "Layer 1" with DMC 310 seeded
- [ ] `CrossStitchPattern.fromYaml()` migrates old `stitches:` files into a single layer
- [ ] `flutter analyze` → no issues

**Verify:** Run `flutter analyze`. Open an existing `.stitchx` file in the app (it will fail to compile until file_service is updated in Task 3, so just verify the model compiles).

**Steps:**

- [ ] **Step 1: Update `lib/models/pattern.dart`**

Replace the entire file content:

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'layer.dart';
import 'snippet.dart';
import 'stitch.dart';
import 'thread.dart';

class CrossStitchPattern {
  final String name;
  final int width;
  final int height;
  final List<Thread> threads;
  final List<Layer> layers;
  final Color aidaColor;

  /// Last-saved editor state — which thread was active.
  final String? editorSelectedThreadId;

  /// Last-saved editor state — which tool was active (DrawingTool.name).
  final String? editorTool;

  /// Last-saved editor state — whether stitch mode was active.
  final bool editorStitchMode;

  /// Last-saved editor state — which layer was active.
  final String? editorActiveLayerId;

  /// Path to a reference image overlay (persisted with the file).
  final String? referenceImagePath;

  /// Opacity of the reference image overlay (0.0–1.0).
  final double referenceOpacity;

  /// Saved snippets belonging to this pattern.
  final List<Snippet> snippets;

  const CrossStitchPattern({
    required this.name,
    required this.width,
    required this.height,
    required this.threads,
    required this.layers,
    this.aidaColor = Colors.white,
    this.editorSelectedThreadId,
    this.editorTool,
    this.editorStitchMode = false,
    this.editorActiveLayerId,
    this.referenceImagePath,
    this.referenceOpacity = 0.5,
    this.snippets = const [],
  });

  /// Flat union of all stitches across all layers. Used for backward-compat
  /// call sites that haven't been migrated to layer-aware access yet.
  List<Stitch> get stitches =>
      layers.expand((l) => l.stitches).toList();

  factory CrossStitchPattern.empty({
    String name = 'New Pattern',
    int width = 30,
    int height = 30,
  }) {
    final defaultLayer = Layer.create(name: 'Layer 1');
    return CrossStitchPattern(
      name: name,
      width: width,
      height: height,
      threads: const [
        Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black'),
      ],
      layers: [defaultLayer],
      editorSelectedThreadId: '310',
      editorActiveLayerId: defaultLayer.id,
    );
  }

  CrossStitchPattern copyWith({
    String? name,
    int? width,
    int? height,
    List<Thread>? threads,
    List<Layer>? layers,
    Color? aidaColor,
    Object? editorSelectedThreadId = _sentinel,
    Object? editorTool = _sentinel,
    bool? editorStitchMode,
    Object? editorActiveLayerId = _sentinel,
    Object? referenceImagePath = _sentinel,
    double? referenceOpacity,
    List<Snippet>? snippets,
  }) {
    return CrossStitchPattern(
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      threads: threads ?? this.threads,
      layers: layers ?? this.layers,
      aidaColor: aidaColor ?? this.aidaColor,
      editorSelectedThreadId: editorSelectedThreadId == _sentinel
          ? this.editorSelectedThreadId
          : editorSelectedThreadId as String?,
      editorTool: editorTool == _sentinel
          ? this.editorTool
          : editorTool as String?,
      editorStitchMode: editorStitchMode ?? this.editorStitchMode,
      editorActiveLayerId: editorActiveLayerId == _sentinel
          ? this.editorActiveLayerId
          : editorActiveLayerId as String?,
      referenceImagePath: referenceImagePath == _sentinel
          ? this.referenceImagePath
          : referenceImagePath as String?,
      referenceOpacity: referenceOpacity ?? this.referenceOpacity,
      snippets: snippets ?? this.snippets,
    );
  }

  static const _sentinel = Object();

  Thread? threadByCode(String dmcCode) {
    return threads.where((t) => t.dmcCode == dmcCode).firstOrNull;
  }

  /// Hex string representation of [aidaColor], e.g. `'#FFFFFF'`.
  String get aidaColorHex {
    final argb = aidaColor.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color _parseHex(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    return Color(int.parse('FF$h', radix: 16));
  }

  factory CrossStitchPattern.fromYaml(Map<String, dynamic> yaml) {
    final editor = yaml['editor'] as Map?;
    final aidaHex = yaml['aidaColor'] as String?;

    // ── Layer migration ──────────────────────────────────────────────────────
    // New format: 'layers:' key present.
    // Old format: 'stitches:' key only → wrap in a single Layer named "Layer 1".
    final layersYaml = yaml['layers'] as List?;
    final stitchesYaml = yaml['stitches'] as List?;

    final List<Layer> layers;
    if (layersYaml != null) {
      layers = layersYaml
          .map((l) => Layer.fromYaml(Map<String, dynamic>.from(l as Map)))
          .toList();
    } else {
      // Migration: old flat stitches → single layer
      final stitches = stitchesYaml
              ?.map((s) =>
                  Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [];
      layers = [
        Layer(
          id: const Uuid().v4(),
          name: 'Layer 1',
          visible: true,
          opacity: 1.0,
          stitches: stitches,
        ),
      ];
    }

    return CrossStitchPattern(
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      aidaColor: aidaHex != null ? _parseHex(aidaHex) : Colors.white,
      editorSelectedThreadId: editor?['selectedThread'] as String?,
      editorTool: editor?['tool'] as String?,
      editorStitchMode: editor?['stitchMode'] as bool? ?? false,
      editorActiveLayerId: editor?['activeLayer'] as String?,
      referenceImagePath: yaml['overlay']?['imagePath'] as String?,
      referenceOpacity:
          (yaml['overlay']?['opacity'] as num?)?.toDouble() ?? 0.5,
      threads: (yaml['threads'] as List?)
              ?.map((t) =>
                  Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
      layers: layers,
      snippets: (yaml['snippets'] as List?)
              ?.map((s) =>
                  Snippet.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [],
    );
  }
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/models/pattern.dart
git commit -m "feat: replace CrossStitchPattern.stitches with layers list, add migration"
```

---

### Task 3: `file_service.dart` — serialize layers and migrate old format

**Goal:** Update `FileService.toYamlString` to write `layers:` instead of `stitches:`, serialize `editorActiveLayerId` in the `editor:` block, and add a `_writeLayer` helper.

**Files:**
- Modify: `lib/services/file_service.dart`

**Acceptance Criteria:**
- [ ] New files save with `layers:` key (not `stitches:`)
- [ ] Each layer serializes `id`, `name`, `visible`, `opacity`, and its `stitches:`
- [ ] `editor:` block includes `activeLayer:` when non-null
- [ ] Old `.stitchx` files (with flat `stitches:`) load correctly via the migration in Task 2
- [ ] `flutter analyze` → no issues

**Verify:** Run `flutter analyze`. Create a new pattern, add some stitches, save, then open the saved file in a text editor and confirm the `layers:` structure is present.

**Steps:**

- [ ] **Step 1: Update `lib/services/file_service.dart`**

In `toYamlString`, replace the `stitches:` block and update the `editor:` block. The full updated `toYamlString` and helper:

```dart
static String toYamlString(CrossStitchPattern pattern) {
  final buf = StringBuffer();
  buf.writeln('name: ${_yamlStr(pattern.name)}');
  buf.writeln('width: ${pattern.width}');
  buf.writeln('height: ${pattern.height}');
  buf.writeln('aidaColor: ${_yamlStr(pattern.aidaColorHex)}');

  if (pattern.editorSelectedThreadId != null ||
      pattern.editorTool != null ||
      pattern.editorStitchMode ||
      pattern.editorActiveLayerId != null) {
    buf.writeln('editor:');
    if (pattern.editorSelectedThreadId != null) {
      buf.writeln(
          '  selectedThread: ${_yamlStr(pattern.editorSelectedThreadId!)}');
    }
    if (pattern.editorTool != null) {
      buf.writeln('  tool: ${pattern.editorTool!}');
    }
    if (pattern.editorStitchMode) {
      buf.writeln('  stitchMode: true');
    }
    if (pattern.editorActiveLayerId != null) {
      buf.writeln('  activeLayer: ${_yamlStr(pattern.editorActiveLayerId!)}');
    }
  }

  if (pattern.referenceImagePath != null) {
    buf.writeln('overlay:');
    buf.writeln('  imagePath: ${_yamlStr(pattern.referenceImagePath!)}');
    buf.writeln('  opacity: ${pattern.referenceOpacity.toStringAsFixed(2)}');
  }

  buf.writeln('threads:');
  for (final t in pattern.threads) {
    final m = t.toYaml();
    buf.writeln('  - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
    buf.writeln('    color: ${_yamlStr(m['color'] as String)}');
    buf.writeln('    name: ${_yamlStr(m['name'] as String)}');
    buf.writeln('    symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}');
  }

  buf.writeln('layers:');
  for (final layer in pattern.layers) {
    _writeLayer(buf, layer);
  }

  if (pattern.snippets.isNotEmpty) {
    buf.writeln('snippets:');
    for (final snippet in pattern.snippets) {
      _writeSnippet(buf, snippet);
    }
  }

  return buf.toString();
}

static void _writeLayer(StringBuffer buf, layer) {
  buf.writeln('  - id: ${_yamlStr(layer.id)}');
  buf.writeln('    name: ${_yamlStr(layer.name)}');
  buf.writeln('    visible: ${layer.visible}');
  buf.writeln('    opacity: ${layer.opacity.toStringAsFixed(3)}');
  buf.writeln('    stitches:');
  for (final s in layer.stitches) {
    _writeStitch(buf, s, indent: '      ');
  }
}
```

Note: The existing `_writeSnippet` and `_writeStitch` methods remain unchanged. The import at the top needs `import '../models/layer.dart';` added.

Full diff summary for `lib/services/file_service.dart`:
1. Add `import '../models/layer.dart';` after the existing imports.
2. Replace the `toYamlString` method body entirely with the code above.
3. Add the `_writeLayer` static method after `_writeStitch`.
4. Remove the old `buf.writeln('stitches:');` loop (now replaced by the layers loop).

- [ ] **Step 2: Apply the changes**

Open `/Users/scottmerchant/dev/stitchx/lib/services/file_service.dart` and apply:

a) Add import after `import '../models/snippet.dart';`:
```dart
import '../models/layer.dart';
```

b) Replace the entire `toYamlString` method (lines 119–169) with:
```dart
static String toYamlString(CrossStitchPattern pattern) {
  final buf = StringBuffer();
  buf.writeln('name: ${_yamlStr(pattern.name)}');
  buf.writeln('width: ${pattern.width}');
  buf.writeln('height: ${pattern.height}');
  buf.writeln('aidaColor: ${_yamlStr(pattern.aidaColorHex)}');

  if (pattern.editorSelectedThreadId != null ||
      pattern.editorTool != null ||
      pattern.editorStitchMode ||
      pattern.editorActiveLayerId != null) {
    buf.writeln('editor:');
    if (pattern.editorSelectedThreadId != null) {
      buf.writeln(
          '  selectedThread: ${_yamlStr(pattern.editorSelectedThreadId!)}');
    }
    if (pattern.editorTool != null) {
      buf.writeln('  tool: ${pattern.editorTool!}');
    }
    if (pattern.editorStitchMode) {
      buf.writeln('  stitchMode: true');
    }
    if (pattern.editorActiveLayerId != null) {
      buf.writeln('  activeLayer: ${_yamlStr(pattern.editorActiveLayerId!)}');
    }
  }

  if (pattern.referenceImagePath != null) {
    buf.writeln('overlay:');
    buf.writeln('  imagePath: ${_yamlStr(pattern.referenceImagePath!)}');
    buf.writeln('  opacity: ${pattern.referenceOpacity.toStringAsFixed(2)}');
  }

  buf.writeln('threads:');
  for (final t in pattern.threads) {
    final m = t.toYaml();
    buf.writeln('  - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
    buf.writeln('    color: ${_yamlStr(m['color'] as String)}');
    buf.writeln('    name: ${_yamlStr(m['name'] as String)}');
    buf.writeln('    symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}');
  }

  buf.writeln('layers:');
  for (final layer in pattern.layers) {
    _writeLayer(buf, layer);
  }

  if (pattern.snippets.isNotEmpty) {
    buf.writeln('snippets:');
    for (final snippet in pattern.snippets) {
      _writeSnippet(buf, snippet);
    }
  }

  return buf.toString();
}
```

c) Add after the existing `_writeStitch` method:
```dart
static void _writeLayer(StringBuffer buf, Layer layer) {
  buf.writeln('  - id: ${_yamlStr(layer.id)}');
  buf.writeln('    name: ${_yamlStr(layer.name)}');
  buf.writeln('    visible: ${layer.visible}');
  buf.writeln('    opacity: ${layer.opacity.toStringAsFixed(3)}');
  buf.writeln('    stitches:');
  for (final s in layer.stitches) {
    _writeStitch(buf, s, indent: '      ');
  }
}
```

- [ ] **Step 3: Commit**
```bash
git add lib/services/file_service.dart
git commit -m "feat: serialize layers in file_service, include activeLayer in editor block"
```

---

### Task 4: `EditorState` — add layer fields

**Goal:** Add `activeLayerId`, `showCompositeThreads`, and `compositeThreadCache` to `EditorState`; remove `pasteOpacity`; add convenience getters.

**Files:**
- Modify: `lib/providers/editor_provider.dart`

**Acceptance Criteria:**
- [ ] `EditorState` has `activeLayerId`, `showCompositeThreads`, `compositeThreadCache`
- [ ] `EditorState.pasteOpacity` field is removed
- [ ] `activeLayer` getter returns the layer matching `activeLayerId`
- [ ] `visibleLayers` getter returns all visible layers
- [ ] `patternForSave` includes `editorActiveLayerId`
- [ ] `copyWith` handles all new fields (sentinel for nullable)
- [ ] `flutter analyze` → no issues

**Verify:** `flutter analyze` after changes.

**Steps:**

- [ ] **Step 1: Update `EditorState` class fields**

In the `EditorState` class (around line 43), add after the `clipboardFromSnippet` field and remove `pasteOpacity`:

Remove this field:
```dart
/// Opacity applied when stamping paste contents (0.0–1.0). At < 1.0 each
/// stitch colour is blended with the background via CIE Lab nearest-DMC lookup.
final double pasteOpacity;
```

Add these fields (after `clipboardFromSnippet`):
```dart
// ── Layers ────────────────────────────────────────────────────────────────
/// The layer that drawing operations target.
final String activeLayerId;
/// When true, the toolbar palette shows composite (blended) threads for all
/// visible layers. When false, shows only the active layer's threads.
final bool showCompositeThreads;
/// Lazily computed composite thread map: cell key '${x},${y}' → nearest DMC
/// Thread after blending all visible layers. Null means cache is stale.
final Map<String, Thread>? compositeThreadCache;
```

- [ ] **Step 2: Update the constructor**

In the `const EditorState({...})` constructor, remove `this.pasteOpacity = 1.0,` and add:
```dart
this.activeLayerId = '',
this.showCompositeThreads = false,
this.compositeThreadCache,
```

Remove from the constructor body (initializers list): `_redoStack = redoStack;` remains unchanged.

- [ ] **Step 3: Add getters to `EditorState`**

After `bool get canRedo => _redoStack.isNotEmpty;`, add:
```dart
/// The layer currently targeted by drawing operations.
/// Falls back to first layer if activeLayerId is not found.
Layer get activeLayer {
  return pattern.layers.firstWhere(
    (l) => l.id == activeLayerId,
    orElse: () => pattern.layers.first,
  );
}

/// All layers that have visibility enabled.
Iterable<Layer> get visibleLayers => pattern.layers.where((l) => l.visible);
```

- [ ] **Step 4: Update `patternForSave` getter**

Replace the existing `patternForSave` getter:
```dart
CrossStitchPattern get patternForSave => pattern.copyWith(
      editorSelectedThreadId: selectedThreadId,
      editorTool: currentTool.name,
      editorStitchMode: stitchMode,
      editorActiveLayerId: activeLayerId.isEmpty ? null : activeLayerId,
    );
```

- [ ] **Step 5: Update `selectedStitches` getter**

The existing getter references `pattern.stitches` which now returns a union via the getter — it still works. But update it to operate on the active layer only:
```dart
/// Stitches in the current selectionRect, scoped to the active layer.
List<Stitch> get selectedStitches {
  final rect = selectionRect;
  if (rect == null) return [];
  return activeLayer.stitches
      .where((s) => EditorState.isStitchInRect(s, rect))
      .toList();
}
```

- [ ] **Step 6: Update `copyWith` method**

In the `EditorState copyWith({...})` signature, remove `double? pasteOpacity,` and add:
```dart
String? activeLayerId,
bool? showCompositeThreads,
Object? compositeThreadCache = _sentinel,
```

In the `return EditorState(...)` body, remove `pasteOpacity: pasteOpacity ?? this.pasteOpacity,` and add:
```dart
activeLayerId: activeLayerId ?? this.activeLayerId,
showCompositeThreads: showCompositeThreads ?? this.showCompositeThreads,
compositeThreadCache: compositeThreadCache == _sentinel
    ? this.compositeThreadCache
    : compositeThreadCache as Map<String, Thread>?,
```

- [ ] **Step 7: Add `import` for Layer model**

At the top of `editor_provider.dart`, add:
```dart
import '../models/layer.dart';
```

- [ ] **Step 8: Commit**
```bash
git add lib/providers/editor_provider.dart
git commit -m "feat: add layer fields to EditorState, remove pasteOpacity"
```

---

### Task 5: `EditorNotifier` — layer management methods + scoped drawing

**Goal:** Add all layer management methods to `EditorNotifier`; scope all drawing, erasing, and flood fill to the active layer; remove paste opacity logic; fix `loadPattern` to initialize `activeLayerId`.

**Files:**
- Modify: `lib/providers/editor_provider.dart`

**Acceptance Criteria:**
- [ ] `loadPattern` sets `activeLayerId` from `pattern.editorActiveLayerId` or defaults to first layer's id
- [ ] `addStitch` writes to the active layer's stitch list only
- [ ] `removeStitchesAt` operates on the active layer only
- [ ] `floodFill` operates on the active layer only
- [ ] `commitPaste` pastes onto the active layer (no opacity blending)
- [ ] `copySelection` reads from the active layer only
- [ ] `moveSelection` / `deleteSelection` operate on the active layer only
- [ ] `resizePattern` shifts stitches in all layers
- [ ] `removeThread` removes stitches from all layers
- [ ] `replaceThread` remaps stitches in all layers
- [ ] All 9 layer management methods are present and functional
- [ ] `_pushUndo` helper method exists (or inline undo stack building is used consistently)
- [ ] `flutter analyze` → no issues

**Verify:** `flutter analyze`. Then run the app, open a file, draw stitches on Layer 1, add a new layer, draw on it — verify stitches go onto the correct layer.

**Steps:**

- [ ] **Step 1: Update `loadPattern` in `EditorNotifier`**

In the existing `loadPattern` method, after `final withSymbols = ...` and before `state = EditorState(...)`, compute the active layer:
```dart
// Restore active layer, falling back to first layer's id
final layerIds = withSymbols.layers.map((l) => l.id).toSet();
final restoredLayerId = (pattern.editorActiveLayerId != null &&
        layerIds.contains(pattern.editorActiveLayerId))
    ? pattern.editorActiveLayerId!
    : (withSymbols.layers.isNotEmpty ? withSymbols.layers.first.id : '');
```

In the `state = EditorState(...)` call, add `activeLayerId: restoredLayerId,`.

- [ ] **Step 2: Update `newPattern` to set `activeLayerId`**

In `newPattern`:
```dart
void newPattern(CrossStitchPattern pattern) {
  final threads = _assignSymbols(pattern.threads);
  final seeded = pattern.copyWith(threads: threads);

  state = EditorState(
    pattern: seeded,
    selectedThreadId: threads.first.dmcCode,
    recentThreadIds: [threads.first.dmcCode],
    isFileOpen: true,
    activeLayerId: seeded.layers.isNotEmpty ? seeded.layers.first.id : '',
  );
}
```

- [ ] **Step 3: Add `_layerHelper` and scope `addStitch` to active layer**

Add a private helper method after the existing `_isInBounds` method:
```dart
/// Returns a copy of [pattern] with [updater] applied to the layer matching [layerId].
/// Returns the pattern unchanged if the layer is not found.
CrossStitchPattern _updateLayer(
    CrossStitchPattern pattern, String layerId, Layer Function(Layer) updater) {
  final idx = pattern.layers.indexWhere((l) => l.id == layerId);
  if (idx == -1) return pattern;
  final updated = List<Layer>.from(pattern.layers);
  updated[idx] = updater(updated[idx]);
  return pattern.copyWith(layers: updated);
}
```

Replace the existing `addStitch` method:
```dart
void addStitch(Stitch stitch) {
  final layerId = state.activeLayerId;
  final layerIdx = state.pattern.layers.indexWhere((l) => l.id == layerId);
  if (layerIdx == -1) return;

  final layer = state.pattern.layers[layerIdx];
  final alreadyExists =
      layer.stitches.any((s) => s == stitch && s.threadId == stitch.threadId);
  if (alreadyExists) return;

  final newStitches = _stitchesWithAdded(layer.stitches, stitch);
  final newPattern = _updateLayer(
      state.pattern, layerId, (l) => l.copyWith(stitches: newStitches));
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 4: Scope `removeStitchesAt` to active layer**

Replace the existing `removeStitchesAt` method:
```dart
void removeStitchesAt(int x, int y) {
  final layerId = state.activeLayerId;
  final layer = state.pattern.layers.firstWhere(
    (l) => l.id == layerId,
    orElse: () => state.pattern.layers.first,
  );
  bool hit(Stitch s) => _stitchAtCell(s, x, y) || _backstitchInCell(s, x, y);
  if (!layer.stitches.any(hit)) return;

  final newStitches = layer.stitches.where((s) => !hit(s)).toList();
  final newPattern = _updateLayer(
      state.pattern, layerId, (l) => l.copyWith(stitches: newStitches));
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 5: Scope `floodFill` to active layer**

Replace the existing `floodFill` method. Key changes: use `layer.stitches` instead of `p.stitches`, and write back to the layer:
```dart
void floodFill(int startX, int startY, {required bool erase}) {
  final p = state.pattern;
  if (startX < 0 || startX >= p.width || startY < 0 || startY >= p.height) return;

  final layerId = state.activeLayerId;
  final layerIdx = p.layers.indexWhere((l) => l.id == layerId);
  if (layerIdx == -1) return;
  final layer = p.layers[layerIdx];

  String? seedThreadId;
  for (final s in layer.stitches) {
    if (s is FullStitch && s.x == startX && s.y == startY) {
      seedThreadId = s.threadId;
      break;
    }
  }

  if (erase && seedThreadId == null) return;
  final fillThreadId = state.selectedThreadId;
  if (!erase && fillThreadId == null) return;
  if (!erase && seedThreadId == fillThreadId) return;

  final Map<int, String> occupied = {};
  for (final s in layer.stitches) {
    if (s is FullStitch) occupied[s.x * 100000 + s.y] = s.threadId;
  }

  int key(int x, int y) => x * 100000 + y;
  bool matches(int x, int y) => occupied[key(x, y)] == seedThreadId;

  final visited = <int>{};
  final queue = <(int, int)>[(startX, startY)];
  visited.add(key(startX, startY));
  final toChange = <(int, int)>[];

  while (queue.isNotEmpty) {
    final (cx, cy) = queue.removeAt(0);
    toChange.add((cx, cy));
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx < 0 || nx >= p.width || ny < 0 || ny >= p.height) continue;
        final k = key(nx, ny);
        if (visited.contains(k)) continue;
        visited.add(k);
        if (matches(nx, ny)) queue.add((nx, ny));
      }
    }
  }

  if (toChange.isEmpty) return;

  List<Stitch> newStitches = [...layer.stitches];
  if (erase) {
    final removeKeys = toChange.map((c) => key(c.$1, c.$2)).toSet();
    newStitches = newStitches.where((s) {
      if (s is! FullStitch) return true;
      return !removeKeys.contains(key(s.x, s.y));
    }).toList();
  } else {
    final changeKeys = toChange.map((c) => key(c.$1, c.$2)).toSet();
    newStitches = newStitches.where((s) {
      if (s is! FullStitch) return true;
      return !changeKeys.contains(key(s.x, s.y));
    }).toList();
    for (final (cx, cy) in toChange) {
      newStitches.add(FullStitch(x: cx, y: cy, threadId: fillThreadId!));
    }
  }

  final newPattern =
      _updateLayer(p, layerId, (l) => l.copyWith(stitches: newStitches));
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 6: Scope `copySelection`, `deleteSelection`, `moveSelection` to active layer**

Replace `copySelection`:
```dart
Future<void> copySelection() async {
  final rect = state.selectionRect;
  if (rect == null) return;
  final activeLayer = state.activeLayer;
  final inSel = activeLayer.stitches
      .where((s) => EditorState.isStitchInRect(s, rect))
      .toList();
  if (inSel.isEmpty) return;
  final clips = inSel
      .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
      .toList();
  final threadIds = clips.map((s) => s.threadId).toSet();
  final threads =
      state.pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
  await Clipboard.setData(ClipboardData(text: _serializeClipboard(threads, clips)));
  state = state.copyWith(
    clipboard: clips,
    clipboardThreads: threads,
    drawingMode: DrawingMode.paste,
    selectionRect: null,
    clipboardFromSnippet: false,
  );
}
```

Replace `deleteSelection`:
```dart
void deleteSelection() {
  final rect = state.selectionRect;
  if (rect == null) return;
  final layerId = state.activeLayerId;
  final layer = state.activeLayer;
  if (!layer.stitches.any((s) => EditorState.isStitchInRect(s, rect))) return;
  final remaining =
      layer.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
  final newPattern =
      _updateLayer(state.pattern, layerId, (l) => l.copyWith(stitches: remaining));
  state = state.copyWith(
    pattern: newPattern,
    selectionRect: null,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

Replace `moveSelection`:
```dart
void moveSelection(int dx, int dy) {
  final rect = state.selectionRect;
  if (rect == null) return;
  final maxX = state.pattern.width;
  final maxY = state.pattern.height;
  final layerId = state.activeLayerId;
  final layer = state.activeLayer;
  final inSel = layer.stitches
      .where((s) => EditorState.isStitchInRect(s, rect))
      .toList();
  if (inSel.isEmpty) return;
  var remaining =
      layer.stitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
  for (final s in inSel) {
    final moved = EditorState.offsetStitch(s, dx, dy);
    if (_isInBounds(moved, maxX, maxY)) {
      remaining = _stitchesWithAdded(remaining, moved);
    }
  }
  final newRect = Rect.fromLTWH(
    (rect.left + dx).clamp(0, maxX.toDouble()),
    (rect.top + dy).clamp(0, maxY.toDouble()),
    rect.width,
    rect.height,
  );
  final newPattern =
      _updateLayer(state.pattern, layerId, (l) => l.copyWith(stitches: remaining));
  state = state.copyWith(
    pattern: newPattern,
    selectionRect: newRect,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 7: Scope `commitPaste` to active layer (remove opacity logic)**

Replace the existing `commitPaste`:
```dart
/// Stamps the clipboard contents at offset [dx],[dy] onto the active layer.
/// Any clipboard threads not yet in the pattern are added automatically.
void commitPaste(int dx, int dy) {
  final clips = state.clipboard;
  if (clips == null || clips.isEmpty) return;
  final maxX = state.pattern.width;
  final maxY = state.pattern.height;
  final layerId = state.activeLayerId;
  final layer = state.activeLayer;

  // Add any clipboard threads not already in the pattern.
  var threads = [...state.pattern.threads];
  for (final ct in state.clipboardThreads ?? <Thread>[]) {
    if (!threads.any((t) => t.dmcCode == ct.dmcCode)) {
      threads.add(_resolveThreadSymbol(ct, threads));
    }
  }

  var stitches = [...layer.stitches];
  for (final s in clips) {
    final placed = EditorState.offsetStitch(s, dx, dy);
    if (!_isInBounds(placed, maxX, maxY)) continue;
    stitches = _stitchesWithAdded(stitches, placed);
  }

  final newPattern = _updateLayer(
    state.pattern.copyWith(threads: threads),
    layerId,
    (l) => l.copyWith(stitches: stitches),
  );
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

Remove `setPasteOpacity` method entirely. Remove `_blendedStitch` method entirely.

- [ ] **Step 8: Update `resizePattern` to operate on all layers**

Replace the existing `resizePattern`:
```dart
void resizePattern(int newWidth, int newHeight, int anchorX, int anchorY) {
  final old = state.pattern;
  final dx = (anchorX / 2.0 * (newWidth - old.width)).round();
  final dy = (anchorY / 2.0 * (newHeight - old.height)).round();

  bool inBounds(Stitch s) {
    final coords = EditorState.cellCoords(s);
    if (coords != null) {
      return coords.$1 >= 0 && coords.$1 < newWidth &&
          coords.$2 >= 0 && coords.$2 < newHeight;
    }
    final bs = s as BackStitch;
    return bs.x1 >= 0 && bs.x1 <= newWidth && bs.y1 >= 0 && bs.y1 <= newHeight &&
        bs.x2 >= 0 && bs.x2 <= newWidth && bs.y2 >= 0 && bs.y2 <= newHeight;
  }

  final newLayers = old.layers.map((layer) {
    final newStitches = layer.stitches
        .map((s) => EditorState.offsetStitch(s, dx, dy))
        .where(inBounds)
        .toList();
    return layer.copyWith(stitches: newStitches);
  }).toList();

  final newPattern = old.copyWith(
    width: newWidth,
    height: newHeight,
    layers: newLayers,
  );

  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    redoStack: [],
    isDirty: true,
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 9: Update `removeThread` and `replaceThread` to operate on all layers**

Replace `removeThread`:
```dart
void removeThread(String dmcCode) {
  final newThreads =
      state.pattern.threads.where((t) => t.dmcCode != dmcCode).toList();
  final newLayers = state.pattern.layers.map((layer) {
    return layer.copyWith(
      stitches: layer.stitches.where((s) => s.threadId != dmcCode).toList(),
    );
  }).toList();
  final newPattern =
      state.pattern.copyWith(threads: newThreads, layers: newLayers);
  final newSelectedId = state.selectedThreadId == dmcCode
      ? (newThreads.isNotEmpty ? newThreads.first.dmcCode : null)
      : state.selectedThreadId;
  state = state.copyWith(
    pattern: newPattern,
    selectedThreadId: newSelectedId,
    isDirty: true,
    compositeThreadCache: null,
  );
}
```

Replace `replaceThread` (key change: operate on all layers):
```dart
void replaceThread(String oldDmcCode, String newDmcCode, Color newColor, String newName) {
  if (oldDmcCode == newDmcCode) return;
  final oldThread =
      state.pattern.threads.where((t) => t.dmcCode == oldDmcCode).firstOrNull;
  if (oldThread == null) return;

  final newThread = Thread(
    dmcCode: newDmcCode,
    color: newColor,
    name: newName,
    symbol: oldThread.symbol,
  );

  final newLayers = state.pattern.layers.map((layer) {
    return layer.copyWith(
      stitches: layer.stitches
          .map((s) => s.threadId == oldDmcCode ? _withThreadId(s, newDmcCode) : s)
          .toList(),
    );
  }).toList();

  var threads = state.pattern.threads.toList();
  final oldIdx = threads.indexWhere((t) => t.dmcCode == oldDmcCode);
  final newExists = threads.any((t) => t.dmcCode == newDmcCode);
  if (newExists) {
    threads.removeAt(oldIdx);
  } else {
    threads[oldIdx] = newThread;
  }

  state = state.copyWith(
    pattern: state.pattern.copyWith(threads: threads, layers: newLayers),
    selectedThreadId:
        state.selectedThreadId == oldDmcCode ? newDmcCode : state.selectedThreadId,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 10: Add layer management methods**

Add these methods after the `replaceThread` method:
```dart
// ─── Layer management ──────────────────────────────────────────────────────

void addLayer() {
  final newLayer = Layer.create(name: 'Layer ${state.pattern.layers.length + 1}');
  // Insert above the active layer
  final activeIdx =
      state.pattern.layers.indexWhere((l) => l.id == state.activeLayerId);
  final insertIdx = activeIdx == -1 ? state.pattern.layers.length : activeIdx + 1;
  final newLayers = [...state.pattern.layers];
  newLayers.insert(insertIdx, newLayer);
  state = state.copyWith(
    pattern: state.pattern.copyWith(layers: newLayers),
    activeLayerId: newLayer.id,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

void deleteLayer(String id) {
  if (state.pattern.layers.length <= 1) return; // cannot delete last layer
  final newLayers = state.pattern.layers.where((l) => l.id != id).toList();
  // If we deleted the active layer, fall back to topmost visible or topmost
  String newActiveId = state.activeLayerId;
  if (newActiveId == id) {
    final visible = newLayers.where((l) => l.visible);
    newActiveId = visible.isNotEmpty
        ? visible.last.id
        : newLayers.last.id;
  }
  state = state.copyWith(
    pattern: state.pattern.copyWith(layers: newLayers),
    activeLayerId: newActiveId,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

void renameLayer(String id, String name) {
  final newPattern =
      _updateLayer(state.pattern, id, (l) => l.copyWith(name: name));
  state = state.copyWith(
    pattern: newPattern,
    isDirty: true,
  );
}

void toggleLayerVisible(String id) {
  final newPattern =
      _updateLayer(state.pattern, id, (l) => l.copyWith(visible: !l.visible));
  state = state.copyWith(
    pattern: newPattern,
    isDirty: true,
    compositeThreadCache: null,
  );
}

void setLayerOpacity(String id, double opacity) {
  final clamped = opacity.clamp(0.0, 1.0);
  final newPattern =
      _updateLayer(state.pattern, id, (l) => l.copyWith(opacity: clamped));
  state = state.copyWith(
    pattern: newPattern,
    isDirty: true,
    compositeThreadCache: null,
  );
}

/// [delta] = +1 moves layer up (toward top/front), -1 moves down (toward bottom/back).
void moveLayer(String id, int delta) {
  final layers = [...state.pattern.layers];
  final idx = layers.indexWhere((l) => l.id == id);
  if (idx == -1) return;
  final newIdx = (idx + delta).clamp(0, layers.length - 1);
  if (newIdx == idx) return;
  final layer = layers.removeAt(idx);
  layers.insert(newIdx, layer);
  state = state.copyWith(
    pattern: state.pattern.copyWith(layers: layers),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

void duplicateLayer(String id) {
  final src = state.pattern.layers.firstWhere((l) => l.id == id);
  final duplicate = Layer(
    id: const Uuid().v4(),
    name: '${src.name} copy',
    visible: src.visible,
    opacity: src.opacity,
    stitches: List<Stitch>.from(src.stitches),
  );
  final srcIdx = state.pattern.layers.indexWhere((l) => l.id == id);
  final newLayers = [...state.pattern.layers];
  newLayers.insert(srcIdx + 1, duplicate);
  state = state.copyWith(
    pattern: state.pattern.copyWith(layers: newLayers),
    activeLayerId: duplicate.id,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

/// Merges [topId]'s stitches into the layer directly below it.
void mergeLayers(String topId) {
  final layers = state.pattern.layers;
  final topIdx = layers.indexWhere((l) => l.id == topId);
  if (topIdx <= 0) return; // nothing below
  final belowIdx = topIdx - 1;
  final topLayer = layers[topIdx];
  final belowLayer = layers[belowIdx];

  var mergedStitches = [...belowLayer.stitches];
  for (final s in topLayer.stitches) {
    mergedStitches = _stitchesWithAdded(mergedStitches, s);
  }

  final newLayers = [...layers];
  newLayers[belowIdx] = belowLayer.copyWith(stitches: mergedStitches);
  newLayers.removeAt(topIdx);

  final newActiveId = state.activeLayerId == topId
      ? newLayers[belowIdx].id
      : state.activeLayerId;

  state = state.copyWith(
    pattern: state.pattern.copyWith(layers: newLayers),
    activeLayerId: newActiveId,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

void setActiveLayer(String id) {
  if (state.pattern.layers.any((l) => l.id == id)) {
    state = state.copyWith(activeLayerId: id);
  }
}

void setShowCompositeThreads(bool value) {
  state = state.copyWith(showCompositeThreads: value);
}
```

Add `import 'package:uuid/uuid.dart';` to the top of the file if not already present (it is already present from existing snippet code).

- [ ] **Step 11: Update `selectAll` to use pattern dimensions (unchanged)**

`selectAll` uses `state.pattern.width/height` which still works — no change needed.

- [ ] **Step 12: Remove leftover paste opacity references**

Search for `pasteOpacity` in `editor_provider.dart` and remove all remaining references (setPasteOpacity method, any remaining field references).

- [ ] **Step 13: Commit**
```bash
git add lib/providers/editor_provider.dart
git commit -m "feat: scope all drawing to active layer, add layer management methods, remove pasteOpacity"
```

---

### Task 6: `LayersPanel` widget

**Goal:** Build the full `LayersPanel` widget — a fixed 170dp right-side panel showing all layers with eye toggle, name, opacity slider, and a ⋮ menu per layer, plus a + button to add layers.

**Files:**
- Create: `lib/widgets/layers_panel.dart`

**Acceptance Criteria:**
- [ ] Panel shows all layers ordered top-to-bottom visually (topmost layer first in the list, matching Z-order: index 0 = bottom, displayed at bottom of list)
- [ ] Active layer is highlighted with a colored left border (left border faces canvas)
- [ ] Eye icon toggles visibility
- [ ] Double-tap on layer name opens an inline rename text field
- [ ] Opacity slider (0–100%) updates live
- [ ] ⋮ menu has: Rename, Move Up, Move Down, Duplicate, Merge Down (disabled for bottom layer), Delete (disabled if only 1 layer)
- [ ] + button adds a new layer
- [ ] `ReorderableListView` allows drag reorder (triggers `moveLayer` calls to rebuild state in the right order)
- [ ] Hidden in stitch mode (panel widget checks `stitchMode` and returns `SizedBox.shrink()`)
- [ ] `flutter analyze` → no issues

**Verify:** Run app, open pattern, observe layers panel on the right. Add layer, reorder, toggle visibility, set opacity, rename. All operations work without errors.

**Steps:**

- [ ] **Step 1: Create `lib/widgets/layers_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';

/// Fixed-width (170dp) right-side panel that lists the pattern's layers.
/// Visible only in design mode; returns [SizedBox.shrink] in stitch mode.
class LayersPanel extends ConsumerWidget {
  const LayersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    if (state.stitchMode || !state.isFileOpen) return const SizedBox.shrink();

    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final layers = state.pattern.layers;

    return SizedBox(
      width: 170,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            left: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
              child: Row(
                children: [
                  Text('Layers',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'New layer',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: notifier.addLayer,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Layer list ──────────────────────────────────────────────────
            // Displayed top-to-bottom: visually topmost layer first.
            // layers[last] = top, layers[0] = bottom.
            Expanded(
              child: ReorderableListView.builder(
                onReorder: (oldIndex, newIndex) {
                  // ReorderableListView gives visual indices (reversed from layer order).
                  final visualCount = layers.length;
                  // Visual index 0 = layers.last (topmost layer)
                  final fromLayerIdx = visualCount - 1 - oldIndex;
                  int toLayerIdx = visualCount - 1 - newIndex;
                  if (newIndex > oldIndex) toLayerIdx += 1;
                  // Move using delta
                  final delta = toLayerIdx - fromLayerIdx;
                  if (delta != 0) {
                    notifier.moveLayer(layers[fromLayerIdx].id, delta);
                  }
                },
                itemCount: layers.length,
                itemBuilder: (context, visualIndex) {
                  // Visual index 0 = topmost layer (layers.last)
                  final layerIndex = layers.length - 1 - visualIndex;
                  final layer = layers[layerIndex];
                  final isActive = layer.id == state.activeLayerId;
                  final isBottom = layerIndex == 0;
                  return _LayerRow(
                    key: ValueKey(layer.id),
                    layer: layer,
                    isActive: isActive,
                    isBottom: isBottom,
                    isOnly: layers.length == 1,
                    onTap: () => notifier.setActiveLayer(layer.id),
                    onToggleVisible: () => notifier.toggleLayerVisible(layer.id),
                    onOpacityChanged: (v) => notifier.setLayerOpacity(layer.id, v),
                    onRename: (name) => notifier.renameLayer(layer.id, name),
                    onMoveUp: layerIndex < layers.length - 1
                        ? () => notifier.moveLayer(layer.id, 1)
                        : null,
                    onMoveDown:
                        layerIndex > 0 ? () => notifier.moveLayer(layer.id, -1) : null,
                    onDuplicate: () => notifier.duplicateLayer(layer.id),
                    onMergeDown: !isBottom ? () => notifier.mergeLayers(layer.id) : null,
                    onDelete: layers.length > 1
                        ? () => notifier.deleteLayer(layer.id)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single layer row ──────────────────────────────────────────────────────────

class _LayerRow extends StatefulWidget {
  final layer;
  final bool isActive;
  final bool isBottom;
  final bool isOnly;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<String> onRename;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDuplicate;
  final VoidCallback? onMergeDown;
  final VoidCallback? onDelete;

  const _LayerRow({
    required super.key,
    required this.layer,
    required this.isActive,
    required this.isBottom,
    required this.isOnly,
    required this.onTap,
    required this.onToggleVisible,
    required this.onOpacityChanged,
    required this.onRename,
    this.onMoveUp,
    this.onMoveDown,
    required this.onDuplicate,
    this.onMergeDown,
    this.onDelete,
  });

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _renaming = false;
  late final TextEditingController _renameCtrl;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.layer.name);
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    super.dispose();
  }

  void _startRename() {
    _renameCtrl.text = widget.layer.name;
    setState(() => _renaming = true);
  }

  void _commitRename() {
    final name = _renameCtrl.text.trim();
    if (name.isNotEmpty) widget.onRename(name);
    setState(() => _renaming = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final layer = widget.layer;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : null,
          border: isActive
              ? Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                )
              : const Border(
                  left: BorderSide(color: Colors.transparent, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 4, 2, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Name row ──────────────────────────────────────────────────
            Row(
              children: [
                // Eye toggle
                GestureDetector(
                  onTap: widget.onToggleVisible,
                  child: Icon(
                    layer.visible ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: layer.visible
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 4),
                // Name (double-tap to rename)
                Expanded(
                  child: _renaming
                      ? TextField(
                          controller: _renameCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitRename(),
                          onEditingComplete: _commitRename,
                        )
                      : GestureDetector(
                          onDoubleTap: _startRename,
                          child: Text(
                            layer.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: layer.visible
                                  ? null
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
                // ⋮ menu
                PopupMenuButton<_LayerAction>(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'Layer options',
                  onSelected: (action) {
                    switch (action) {
                      case _LayerAction.rename:
                        _startRename();
                      case _LayerAction.moveUp:
                        widget.onMoveUp?.call();
                      case _LayerAction.moveDown:
                        widget.onMoveDown?.call();
                      case _LayerAction.duplicate:
                        widget.onDuplicate();
                      case _LayerAction.mergeDown:
                        widget.onMergeDown?.call();
                      case _LayerAction.delete:
                        widget.onDelete?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _LayerAction.rename,
                      child: Text('Rename', style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: _LayerAction.moveUp,
                      enabled: widget.onMoveUp != null,
                      child: const Text('Move Up', style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: _LayerAction.moveDown,
                      enabled: widget.onMoveDown != null,
                      child: const Text('Move Down',
                          style: TextStyle(fontSize: 13)),
                    ),
                    const PopupMenuItem(
                      value: _LayerAction.duplicate,
                      child: Text('Duplicate', style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: _LayerAction.mergeDown,
                      enabled: widget.onMergeDown != null,
                      child: const Text('Merge Down',
                          style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: _LayerAction.delete,
                      enabled: widget.onDelete != null,
                      child: Text(
                        'Delete Layer',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.onDelete != null
                              ? Colors.red.shade600
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // ── Opacity slider ─────────────────────────────────────────────
            Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      value: layer.opacity,
                      min: 0.0,
                      max: 1.0,
                      onChanged: widget.onOpacityChanged,
                    ),
                  ),
                ),
                Text(
                  '${(layer.opacity * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _LayerAction { rename, moveUp, moveDown, duplicate, mergeDown, delete }
```

- [ ] **Step 2: Commit**
```bash
git add lib/widgets/layers_panel.dart
git commit -m "feat: add LayersPanel widget with full layer management UI"
```

---

### Task 7: Add `LayersPanel` to `EditorScreen` and `WorkspaceScreen`

**Goal:** Add `LayersPanel` to the right side of both `EditorScreen` and `WorkspaceScreen` layouts; hide it in stitch mode (already handled by the widget).

**Files:**
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/workspace_screen.dart`

**Acceptance Criteria:**
- [ ] `EditorScreen` body wraps canvas+toolbar in a `Row` with `LayersPanel` on the right
- [ ] `WorkspaceScreen` body Row includes `LayersPanel` after the canvas `Expanded`
- [ ] Pattern Info dialog shows stitch count summed across all layers
- [ ] `flutter analyze` → no issues

**Verify:** Run app in standalone editor mode (EditorScreen). Layers panel appears on right. Open workspace (WorkspaceScreen) — layers panel appears on right of canvas.

**Steps:**

- [ ] **Step 1: Update `EditorScreen`**

In `lib/screens/editor_screen.dart`, add the import:
```dart
import '../widgets/layers_panel.dart';
```

In the `build` method, find the `body: Focus(...)` section. The current body is:
```dart
body: Focus(
  autofocus: true,
  onKeyEvent: handleKeys,
  child: Column(
    children: [
      if (!state.isNativeFormat) _ImportBanner(...),
      const Expanded(child: PatternCanvas()),
      const EditorToolbar(),
    ],
  ),
),
```

Wrap it to add the LayersPanel to the right:
```dart
body: Focus(
  autofocus: true,
  onKeyEvent: handleKeys,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Column(
          children: [
            if (!state.isNativeFormat)
              _ImportBanner(
                filePath: state.filePath!,
                onSaveAs: () => _saveAs(context, ref),
              ),
            const Expanded(child: PatternCanvas()),
            const EditorToolbar(),
          ],
        ),
      ),
      const LayersPanel(),
    ],
  ),
),
```

- [ ] **Step 2: Update Pattern Info stitch count in `EditorScreen`**

In `_showPatternInfo`, update the Stitches row to sum across all layers:
```dart
_InfoRow('Stitches',
    '${p.layers.fold(0, (sum, l) => sum + l.stitches.length)}'),
```

- [ ] **Step 3: Update `WorkspaceScreen`**

In `lib/screens/workspace_screen.dart`, add the import:
```dart
import '../widgets/layers_panel.dart';
```

Find the body `Row` widget (around line 1107). The current structure is:
```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    // Sidebar + draggable resize handle
    if (wsState.sidebarVisible) ...[
      SizedBox(width: wsState.sidebarWidth, child: const FileSidebar()),
      _ResizeDivider(...),
    ],
    // Editor, PDF viewer, image viewer, or empty state
    Expanded(
      child: openPdf != null ? ... : editorState.isFileOpen
          ? Focus(
              child: Column(children: [
                ...
                const Expanded(child: PatternCanvas()),
                const EditorToolbar(),
              ]),
            )
          : _EmptyState(...),
    ),
  ],
),
```

Add `LayersPanel` after the `Expanded(...)` in the Row's children:
```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (wsState.sidebarVisible) ...[
      SizedBox(width: wsState.sidebarWidth, child: const FileSidebar()),
      _ResizeDivider(
        onDrag: (delta) => ref
            .read(workspaceProvider.notifier)
            .setSidebarWidth(wsState.sidebarWidth + delta),
      ),
    ],
    Expanded(
      child: openPdf != null
          ? Focus(
              autofocus: true,
              onKeyEvent: handleKeys,
              child: PdfViewerPanel(key: _pdfPanelKey, path: openPdf.localPath),
            )
          : openImage != null
              ? Focus(
                  autofocus: true,
                  onKeyEvent: handleKeys,
                  child: ImageViewerPanel(path: openImage.localPath),
                )
              : editorState.isFileOpen
                  ? Focus(
                      autofocus: true,
                      onKeyEvent: handleKeys,
                      child: Column(
                        children: [
                          if (!editorState.isNativeFormat)
                            _ImportBanner(
                              filePath: editorState.filePath!,
                              onSaveAs: () => _saveAs(context),
                            ),
                          const Expanded(child: PatternCanvas()),
                          const EditorToolbar(),
                        ],
                      ),
                    )
                  : _EmptyState(
                      workspace: wsState.workspace,
                      onNewFile: () =>
                          _newFileInWorkspace(context, wsState.workspace),
                    ),
    ),
    // Layers panel — right side, always visible in design mode
    const LayersPanel(),
  ],
),
```

- [ ] **Step 4: Update Pattern Info stitch count in `WorkspaceScreen`**

Find `_showPatternInfo` (or the equivalent info dialog) in `WorkspaceScreen` and update the stitches row similarly:
```dart
_InfoRow('Stitches',
    '${p.layers.fold(0, (sum, l) => sum + l.stitches.length)}'),
```

- [ ] **Step 5: Commit**
```bash
git add lib/screens/editor_screen.dart lib/screens/workspace_screen.dart
git commit -m "feat: add LayersPanel to EditorScreen and WorkspaceScreen layouts"
```

---

### Task 8: Rendering — update `CanvasStaticPainter` for layers + overlay chip

**Goal:** Update `CanvasStaticPainter` to iterate layers bottom-to-top, applying `saveLayer`/`restore` for opacity; remove paste opacity ghost blending; add the "Drawing on: [name]" chip to `CanvasOverlayPainter`.

**Files:**
- Modify: `lib/widgets/canvas_painter.dart`

**Acceptance Criteria:**
- [ ] `CanvasStaticPainter` iterates `pattern.layers` bottom-to-top
- [ ] Layers with `opacity < 1.0` are rendered inside `canvas.saveLayer(...)`
- [ ] Invisible layers (`visible == false`) are skipped
- [ ] Ghost stitches in paste mode no longer use opacity blending (was driven by `pasteOpacity`)
- [ ] `CanvasOverlayPainter` shows a "Drawing on: [name]" chip in the bottom-left of the canvas when in design mode
- [ ] `shouldRepaint` in `CanvasStaticPainter` invalidates when layer list changes
- [ ] `flutter analyze` → no issues

**Verify:** Run app, open a pattern with 2 layers, set layer 1 opacity to 50% — observe semi-transparent rendering. Active layer chip appears in canvas bottom-left.

**Steps:**

- [ ] **Step 1: Update `CanvasStaticPainter` constructor and fields**

The current `CanvasStaticPainter` takes `CrossStitchPattern pattern` and reads `pattern.stitches` directly. Update it to use layers.

Current field:
```dart
late final Map<String, Thread> _threadMap = {
  for (final t in pattern.threads) t.dmcCode: t,
};
```
This is fine — keep it.

In the `paint` method, replace the stitches rendering section. Current code (around line 465):
```dart
if (blockMode || effectivePx < kBlockThreshold) {
  _drawStitchesAsBlocks(canvas, minCX, minCY, maxCX, maxCY);
} else {
  for (final stitch in pattern.stitches) {
    ...
  }
}
```

Replace it with a layer-iteration approach:
```dart
// ── Stitches — iterate layers bottom to top ──────────────────────────────
for (final layer in pattern.layers) {
  if (!layer.visible) continue;
  final needsOpacity = layer.opacity < 1.0;
  if (needsOpacity) {
    canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 255, 255, layer.opacity));
  }
  if (blockMode || effectivePx < kBlockThreshold) {
    _drawLayerStitchesAsBlocks(canvas, layer, minCX, minCY, maxCX, maxCY);
  } else {
    for (final stitch in layer.stitches) {
      if (stitch is BackStitch) continue;
      if (!_inCellRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
      final thread = _threadMap[stitch.threadId];
      if (thread == null) continue;
      final c = _resolveStitchColor(stitch.threadId, thread.color,
          isCrossStitch: true);
      if (c == null) continue;
      switch (stitch) {
        case FullStitch(:final x, :final y):
          _drawFullStitch(canvas, x, y, c);
        case HalfStitch(:final x, :final y, :final isForward):
          _drawHalfStitch(canvas, x, y, isForward, c);
        case QuarterStitch(:final x, :final y, :final quadrant):
          _drawQuarterStitch(canvas, x, y, quadrant, c);
        case HalfCrossStitch(:final x, :final y, :final half):
          _drawHalfCrossStitch(canvas, x, y, half, c);
        case QuarterCrossStitch(:final x, :final y, :final quadrant):
          _drawQuarterCrossStitch(canvas, x, y, quadrant, c);
        default:
          break;
      }
    }
  }
  if (needsOpacity) canvas.restore();
}
```

Also update the backstitches and symbols sections to iterate layers:
```dart
// ── Backstitches (all visible layers) ────────────────────────────────────
if (effectivePx >= kNoBackstitch) {
  for (final layer in pattern.layers) {
    if (!layer.visible) continue;
    for (final stitch in layer.stitches) {
      if (stitch is! BackStitch) continue;
      if (!_backstichInRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
      final thread = _threadMap[stitch.threadId];
      if (thread == null) continue;
      final c = _resolveStitchColor(stitch.threadId, thread.color,
          isCrossStitch: false);
      if (c != null) {
        _drawBackstitch(canvas, stitch.x1, stitch.y1, stitch.x2, stitch.y2, c);
      }
    }
  }
}

// ── Stitch symbols (all visible layers) ──────────────────────────────────
if (effectivePx >= 8 && (!blockMode || stitchMode)) {
  for (final layer in pattern.layers) {
    if (!layer.visible) continue;
    for (final stitch in layer.stitches) {
      if (stitch is BackStitch) continue;
      if (!_inCellRange(stitch, minCX, minCY, maxCX, maxCY)) continue;
      final thread = _threadMap[stitch.threadId];
      if (thread == null || thread.symbol.isEmpty) continue;
      final c = _resolveStitchColor(stitch.threadId, thread.color,
          isCrossStitch: true);
      if (c != null) _drawStitchSymbol(canvas, stitch, thread.symbol, c);
    }
  }
}
```

- [ ] **Step 2: Add `_drawLayerStitchesAsBlocks`**

The existing `_drawStitchesAsBlocks` method currently takes no layer param and iterates `pattern.stitches`. Add a new version that accepts a `Layer`:

Find the existing `_drawStitchesAsBlocks(Canvas canvas, int minX, int minY, int maxX, int maxY)` method and rename it `_drawLayerStitchesAsBlocks`, adding a `Layer layer` parameter, and replace `pattern.stitches` with `layer.stitches`:

```dart
void _drawLayerStitchesAsBlocks(
    Canvas canvas, Layer layer, int minX, int minY, int maxX, int maxY) {
  // Batch by colour to minimise Paint churn
  final byColor = <Color, List<Rect>>{};

  for (final stitch in layer.stitches) {
    if (stitch is BackStitch) continue;
    // ... (same logic as existing _drawStitchesAsBlocks, just using layer.stitches)
  }
  // ... draw batched rects
}
```

The exact implementation should mirror `_drawStitchesAsBlocks` exactly, just using `layer.stitches` instead of `pattern.stitches`. Copy the full body and change only the stitch source.

Also need to add `import '../models/layer.dart';` to `canvas_painter.dart`.

- [ ] **Step 3: Update `CanvasOverlayPainter` to show the active layer chip**

`CanvasOverlayPainter` needs two new fields: `activeLayerName` and `stitchMode`. Add them to the constructor.

In `PatternCanvas` (in `pattern_canvas.dart`), where `CanvasOverlayPainter` is constructed, pass:
- `activeLayerName: state.activeLayer.name`
- `stitchMode: state.stitchMode`

In the `CanvasOverlayPainter.paint` method, after all other drawing, add the chip rendering (in screen space, after `canvas.restore()`):
```dart
// ── Active layer chip ───────────────────────────────────────────────────
if (!stitchMode && activeLayerName != null) {
  _drawActiveLayerChip(canvas, size, activeLayerName!);
}
```

Add the helper:
```dart
void _drawActiveLayerChip(Canvas canvas, Size size, String layerName) {
  const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  const textStyle = TextStyle(
    fontSize: 11,
    color: Colors.white,
    fontWeight: FontWeight.w500,
  );
  final label = 'Drawing on: $layerName';
  final tp = TextPainter(
    text: TextSpan(text: label, style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  const left = 8.0;
  const bottom = 8.0;
  final chipRect = Rect.fromLTWH(
    left,
    size.height - bottom - tp.height - padding.vertical,
    tp.width + padding.horizontal,
    tp.height + padding.vertical,
  );

  canvas.drawRRect(
    RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
    Paint()..color = const Color(0xCC1A1A2E),
  );
  tp.paint(canvas,
      Offset(chipRect.left + padding.left, chipRect.top + padding.top));
}
```

- [ ] **Step 4: Update `shouldRepaint` in `CanvasStaticPainter`**

The existing `shouldRepaint` checks `old.pattern != pattern`. Since `CrossStitchPattern` uses structural equality via `copyWith`, the existing check works as long as the pattern reference changes — which it does on every layer mutation. No change needed here if the pattern reference updates on mutation.

- [ ] **Step 5: Remove paste opacity ghost blending**

In `CanvasOverlayPainter` (in `pattern_canvas.dart`), find where ghost stitches are drawn in paste mode. The `_drawGhostStitches` call likely passes `opacity: state.pasteOpacity`. Remove the opacity parameter — use `opacity: 1.0` or remove the named param entirely (the method defaults to 1.0).

- [ ] **Step 6: Commit**
```bash
git add lib/widgets/canvas_painter.dart lib/widgets/pattern_canvas.dart
git commit -m "feat: render layers bottom-to-top with saveLayer opacity, add active layer chip"
```

---

### Task 9: Composite thread computation

**Goal:** Implement the overlap-only composite thread computation and cache it on `EditorState`; add the palette toggle chip to the toolbar.

**Files:**
- Modify: `lib/providers/editor_provider.dart`
- Modify: `lib/widgets/editor_toolbar.dart`

**Acceptance Criteria:**
- [ ] `computeCompositeThreads(CrossStitchPattern)` function exists (top-level or static) returning `Map<String, Thread>`
- [ ] Single-layer cells use their source thread unchanged (regardless of layer opacity)
- [ ] Multi-layer cells blend colors bottom-to-top using `Color.lerp` with each layer's opacity, then snap to nearest DMC via `SpriteImporter.matchPixel`
- [ ] `compositeThreadCache` on `EditorState` is populated by `_refreshCompositeCache()` in `EditorNotifier`
- [ ] Toolbar shows a "Layer ↔ Canvas" toggle chip when `showCompositeThreads` can be set
- [ ] When in Canvas view, the toolbar palette list shows composite threads (read-only)
- [ ] When any layer has opacity < 1.0, an info chip appears in the toolbar with message "Opacity active — Canvas view shows resulting stitch colours"
- [ ] In stitch mode, `showCompositeThreads` is effectively always true
- [ ] `flutter analyze` → no issues

**Verify:** Create 2 layers with different thread colours on the same cell. Enable "Canvas view" in toolbar — palette shows blended thread. Stitch mode shows composite threads automatically.

**Steps:**

- [ ] **Step 1: Add `computeCompositeThreads` function**

Add this as a top-level function (or static method on `EditorNotifier`) in `editor_provider.dart`:

```dart
/// Computes composite threads for each cell that has stitches in multiple
/// visible layers. Single-layer cells use their source thread directly.
/// Returns a map from 'x,y' cell key to the composite [Thread].
Map<String, Thread> computeCompositeThreads(CrossStitchPattern pattern) {
  // Collect all visible FullStitch entries per cell, in layer order (bottom-to-top).
  final cellLayers = <String, List<({Layer layer, FullStitch stitch})>>{};
  for (final layer in pattern.layers) {
    if (!layer.visible) continue;
    for (final stitch in layer.stitches) {
      if (stitch is! FullStitch) continue;
      final key = '${stitch.x},${stitch.y}';
      (cellLayers[key] ??= []).add((layer: layer, stitch: stitch));
    }
  }

  final threadMap = <String, Thread>{
    for (final t in pattern.threads) t.dmcCode: t,
  };

  final result = <String, Thread>{};

  for (final entry in cellLayers.entries) {
    final hits = entry.value;
    if (hits.isEmpty) continue;

    if (hits.length == 1) {
      // Single layer: use source thread directly, ignore opacity for display
      final t = threadMap[hits.first.stitch.threadId];
      if (t != null) result[entry.key] = t;
      continue;
    }

    // Multiple layers: blend bottom-to-top using each layer's opacity.
    // Start with the bottom layer's colour.
    var blended = threadMap[hits.first.stitch.threadId]?.color;
    if (blended == null) continue;

    for (int i = 1; i < hits.length; i++) {
      final hit = hits[i];
      final layerColor = threadMap[hit.stitch.threadId]?.color;
      if (layerColor == null) continue;
      blended = Color.lerp(blended!, layerColor, hit.layer.opacity)!;
    }

    // Snap blended colour to nearest DMC via CIE Lab.
    final r = (blended.r * 255).round();
    final g = (blended.g * 255).round();
    final b = (blended.b * 255).round();
    final dmc = SpriteImporter.matchPixel(r, g, b, 255);
    if (dmc != null) {
      result[entry.key] = Thread(
        dmcCode: dmc.code,
        color: dmc.color,
        name: dmc.name,
      );
    }
  }

  return result;
}
```

- [ ] **Step 2: Add `_refreshCompositeCache` to `EditorNotifier`**

```dart
void refreshCompositeCache() {
  final cache = computeCompositeThreads(state.pattern);
  state = state.copyWith(compositeThreadCache: cache);
}
```

Call `refreshCompositeCache()` in `toggleStitchMode` when entering stitch mode:
```dart
void toggleStitchMode() {
  final entering = !state.stitchMode;
  state = state.copyWith(
    stitchMode: entering,
    drawingMode: entering ? DrawingMode.pan : DrawingMode.draw,
    selectionRect: null,
    backstitchStartPoint: null,
    showCompositeThreads: entering, // stitch mode always shows composite
  );
  if (entering) refreshCompositeCache();
  _autoSaveStitchMode();
}
```

- [ ] **Step 3: Add palette toggle to toolbar**

In `lib/widgets/editor_toolbar.dart`, in the design mode toolbar build, add after the thread palette section (before the right-side buttons):

```dart
// ── Palette view toggle ─────────────────────────────────────────────────
// Show "Layer ↔ Canvas" toggle when any layer has opacity < 1.0 in design mode
if (!state.stitchMode) ...[
  Builder(builder: (context) {
    final hasOpacity = state.pattern.layers
        .any((l) => l.visible && l.opacity < 0.99);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasOpacity) ...[
          vDivider,
          const SizedBox(width: 4),
          Tooltip(
            message:
                'Opacity active — Canvas view shows resulting stitch colours.',
            child: Icon(
              Icons.info_outline,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(width: 2),
        ChoiceChip(
          label: Text(
            state.showCompositeThreads ? 'Canvas' : 'Layer',
            style: const TextStyle(fontSize: 11),
          ),
          selected: state.showCompositeThreads,
          onSelected: (v) {
            notifier.setShowCompositeThreads(v);
            if (v) notifier.refreshCompositeCache();
          },
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ],
    );
  }),
],
```

The thread list in the toolbar should filter based on `showCompositeThreads`:

When `showCompositeThreads` is true: show the unique threads from `compositeThreadCache.values` (deduplicated by dmcCode, read-only, no select action).
When `showCompositeThreads` is false: show `state.pattern.threads` for the active layer (current behaviour — `state.pattern.threads` is the full palette across all layers; functionally acceptable for MVP since it was already the global palette).

For a clean implementation, wrap the thread list section in the toolbar in a conditional:
```dart
final displayThreads = state.showCompositeThreads
    ? (state.compositeThreadCache?.values
            .toList()
            .fold<List<Thread>>([], (acc, t) {
          if (!acc.any((e) => e.dmcCode == t.dmcCode)) acc.add(t);
          return acc;
        }) ??
        state.pattern.threads)
    : state.pattern.threads;
```
Use `displayThreads` instead of `state.pattern.threads` when building thread buttons.

- [ ] **Step 4: Commit**
```bash
git add lib/providers/editor_provider.dart lib/widgets/editor_toolbar.dart
git commit -m "feat: composite thread computation, palette Layer/Canvas toggle in toolbar"
```

---

### Task 10: Stitch mode — show composite threads; fix remaining `pattern.stitches` references

**Goal:** In stitch mode, the thread list and stitch count always use composite threads; fix all remaining call sites that still use `pattern.stitches` (the getter works but is now a union — verify correctness for each call site).

**Files:**
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/workspace_screen.dart`
- Modify: `lib/widgets/editor_toolbar.dart`
- Modify: `lib/services/file_service.dart` (OXS format export if applicable)

**Acceptance Criteria:**
- [ ] `_StitchPalettePanel` in `editor_screen.dart` shows composite threads in stitch mode
- [ ] The workspace equivalent stitch panel also shows composite threads
- [ ] `selectAll` in stitch mode selects the active layer (already handled — `selectAll` sets a Rect over the full canvas)
- [ ] `resizePattern` in `format_service.dart` / `FormatService` still works (it reads `pattern.stitches` getter, which returns the union — verify this is correct for export)
- [ ] `flutter analyze` → no issues

**Verify:** Enter stitch mode. Open the thread panel — it shows composite threads (blended). Exit stitch mode — thread panel reverts to source threads.

**Steps:**

- [ ] **Step 1: Update `_StitchPalettePanel` to show composite threads**

In `lib/screens/editor_screen.dart`, in `_StitchPalettePanel.build`:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(editorProvider);
  final useDmc = ref.watch(settingsProvider).useDmc;
  final theme = Theme.of(context);

  // In stitch mode, always show composite threads.
  // Ensure cache is fresh (it's populated on toggleStitchMode).
  final List<Thread> threads;
  if (state.stitchMode && state.compositeThreadCache != null) {
    final unique = <String, Thread>{};
    for (final t in state.compositeThreadCache!.values) {
      unique[t.dmcCode] = t;
    }
    // Also include source threads not in composite map (e.g. non-FullStitch threads)
    for (final t in state.pattern.threads) {
      unique.putIfAbsent(t.dmcCode, () => t);
    }
    threads = unique.values.toList();
  } else {
    threads = state.pattern.threads;
  }

  // ... rest of the build (use `threads` instead of `state.pattern.threads`)
}
```

- [ ] **Step 2: Check `format_service.dart` for `pattern.stitches` usage**

Open `lib/services/format_service.dart` and search for `.stitches`. The getter `pattern.stitches` returns the union of all layers, which is correct for export — no change needed.

- [ ] **Step 3: Check `stitch_planner.dart` and `stitch_renderer.dart`**

Open `lib/services/stitch_planner.dart` and `lib/services/stitch_renderer.dart`. Both likely use `pattern.stitches`. The getter returns the union — stitch planning over all layers is correct behaviour. No change needed.

- [ ] **Step 4: Final `flutter analyze` sweep**

Run `flutter analyze` and fix any remaining issues. Common issues to watch for:
- Calls to `state.pasteOpacity` anywhere — remove them
- Calls to `setPasteOpacity` anywhere (editor_toolbar.dart, pattern_canvas.dart) — remove them
- Any reference to `pattern.stitches` being assigned (it's now a getter, not a field) — update to use layers

- [ ] **Step 5: Final integration test**

Manual test steps:
1. Run `flutter run -d macos`
2. Create a new pattern
3. Draw stitches on Layer 1
4. Tap + in layers panel → Layer 2 added and activated
5. Draw stitches on Layer 2 in a different colour
6. Toggle Layer 2 visibility off → its stitches disappear
7. Set Layer 2 opacity to 50% → stitches show semi-transparent
8. Drag to reorder layers → Z-order changes
9. Merge layers → stitches combine
10. Save file → reopen → layers preserved with correct names and stitches
11. Open old `.stitchx` file (without `layers:` key) → loads into single "Layer 1"
12. Enter stitch mode → layers panel hides, composite thread list shows

- [ ] **Step 6: Commit**
```bash
git add -A
git commit -m "feat: stitch mode shows composite threads, fix remaining stitches references"
```
