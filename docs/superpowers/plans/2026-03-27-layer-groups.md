# Layer Groups Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add collapsible named layer groups to the layers panel, where groups and ungrouped layers can be interleaved in any order (Photoshop-style).

**Architecture:** Replace `CrossStitchPattern.layers: List<Layer>` with `layerItems: List<LayerItem>`, where `LayerItem` is a sealed class (`LayerLeaf` or `LayerGroup`). A computed `layers` getter flattens all items for backward-compatible rendering — zero changes to canvas, colour picker, flood fill, stitch demo, or PDF scanner. The layers panel is rewritten to render group headers with collapse/expand.

**Tech Stack:** Flutter/Dart 3.11, flutter_riverpod ^2.5.1, uuid ^4.4.0

---

### Task 1: LayerItem model

**Goal:** Create `lib/models/layer_item.dart` with the sealed class hierarchy.

**Files:**
- Create: `lib/models/layer_item.dart`

**Acceptance Criteria:**
- [ ] `LayerItem` is a sealed class with two subtypes: `LayerLeaf` and `LayerGroup`
- [ ] `LayerLeaf` wraps a single `Layer` with `copyWith`
- [ ] `LayerGroup` has `id`, `name`, `collapsed`, `groupVisible`, `layers: List<Layer>` with `copyWith` and a `create` factory
- [ ] `flutter analyze` reports no issues

**Verify:** `flutter analyze lib/models/layer_item.dart` → no issues

**Steps:**

- [ ] **Step 1: Create `lib/models/layer_item.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'layer.dart';

@immutable
sealed class LayerItem {}

@immutable
class LayerLeaf extends LayerItem {
  final Layer layer;

  const LayerLeaf({required this.layer});

  LayerLeaf copyWith({Layer? layer}) =>
      LayerLeaf(layer: layer ?? this.layer);
}

@immutable
class LayerGroup extends LayerItem {
  final String id;
  final String name;
  final bool collapsed;
  final bool groupVisible;
  final List<Layer> layers;

  const LayerGroup({
    required this.id,
    required this.name,
    this.collapsed = false,
    this.groupVisible = true,
    required this.layers,
  });

  factory LayerGroup.create({required String name, required Layer initialLayer}) {
    return LayerGroup(
      id: const Uuid().v4(),
      name: name,
      layers: [initialLayer],
    );
  }

  LayerGroup copyWith({
    String? name,
    bool? collapsed,
    bool? groupVisible,
    List<Layer>? layers,
  }) =>
      LayerGroup(
        id: id,
        name: name ?? this.name,
        collapsed: collapsed ?? this.collapsed,
        groupVisible: groupVisible ?? this.groupVisible,
        layers: layers ?? this.layers,
      );
}
```

- [ ] **Step 2: Analyze and commit**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/models/layer_item.dart
git add lib/models/layer_item.dart
git commit -m "feat: add LayerItem sealed class (LayerLeaf, LayerGroup)"
```

---

### Task 2: CrossStitchPattern + serialization

**Goal:** Replace the stored `layers` field with `layerItems`, add the flattening `layers` getter and `mapLayers` helper, update YAML read/write, and fix `format_service.dart`.

**Files:**
- Modify: `lib/models/pattern.dart`
- Modify: `lib/services/file_service.dart`
- Modify: `lib/services/format_service.dart`

**Acceptance Criteria:**
- [ ] `CrossStitchPattern` stores `List<LayerItem> layerItems`; `layers` is a computed getter
- [ ] `groupVisible = false` on a group forces its layers to `visible: false` in the getter
- [ ] `mapLayers(fn)` applies a transform to every layer across all items (used by provider helpers)
- [ ] Old `.stitchx` files with `layers:` key load as all-`LayerLeaf` — no data loss
- [ ] Saved files write `layerItems:` with `type: layer` / `type: group` tags
- [ ] `format_service.dart` produces `layerItems:` with a `LayerLeaf`

**Verify:** Open an existing `.stitchx` file — layers appear in panel, drawing works

**Steps:**

- [ ] **Step 1: Update `lib/models/pattern.dart`**

Add `import 'layer_item.dart';`. Replace the `List<Layer> layers` field and update constructor, `empty`, `copyWith`, `fromYaml`. Add `layers` getter and `mapLayers`.

Key changes:

```dart
// Field (replaces List<Layer> layers):
final List<LayerItem> layerItems;

// Computed getter — used by all rendering/drawing code unchanged:
List<Layer> get layers => layerItems.expand((item) => switch (item) {
  LayerLeaf(:final layer) => [layer],
  LayerGroup(:final groupVisible, :final layers) => groupVisible
      ? layers
      : layers.map((l) => l.copyWith(visible: false)).toList(),
}).toList();

// Helper used by _updateLayer and _patternWithAllLayersTransformed:
CrossStitchPattern mapLayers(Layer Function(Layer) fn) => copyWith(
  layerItems: layerItems.map((item) => switch (item) {
    LayerLeaf(:final layer) => LayerLeaf(layer: fn(layer)),
    LayerGroup() => (item as LayerGroup).copyWith(
        layers: item.layers.map(fn).toList()),
  }).toList(),
);

// empty factory:
factory CrossStitchPattern.empty({String name = 'New Pattern', int width = 30, int height = 30}) {
  final defaultLayer = Layer.create(name: 'Layer 1');
  return CrossStitchPattern(
    name: name, width: width, height: height,
    threads: const [Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black')],
    layerItems: [LayerLeaf(layer: defaultLayer)],
    editorSelectedThreadId: '310',
    editorActiveLayerId: defaultLayer.id,
  );
}

// copyWith: replace List<Layer>? layers with List<LayerItem>? layerItems
```

`fromYaml` — replace the layers/stitches migration block:

```dart
final layerItemsYaml = yaml['layerItems'] as List?;
final layersYaml     = yaml['layers'] as List?;
final stitchesYaml   = yaml['stitches'] as List?;

final List<LayerItem> layerItems;
if (layerItemsYaml != null) {
  layerItems = layerItemsYaml.map((raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    if (m['type'] == 'group') {
      return LayerGroup(
        id: m['id'] as String,
        name: m['name'] as String,
        collapsed: m['collapsed'] as bool? ?? false,
        groupVisible: m['groupVisible'] as bool? ?? true,
        layers: (m['layers'] as List?)
                ?.map((l) => Layer.fromYaml(Map<String, dynamic>.from(l as Map)))
                .toList() ?? [],
      );
    }
    return LayerLeaf(layer: Layer.fromYaml(m));
  }).toList();
} else if (layersYaml != null) {
  layerItems = layersYaml
      .map((l) => LayerLeaf(
          layer: Layer.fromYaml(Map<String, dynamic>.from(l as Map))))
      .toList();
} else {
  final stitches = stitchesYaml
          ?.map((s) => Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
          .toList() ?? [];
  layerItems = [
    LayerLeaf(layer: Layer(
      id: const Uuid().v4(), name: 'Layer 1',
      visible: true, opacity: 1.0, stitches: stitches,
    )),
  ];
}
```

Also remove the now-unused `stitches` getter if it only existed for migration (check if any call sites remain outside tests).

- [ ] **Step 2: Update `lib/services/file_service.dart`**

Add `import '../models/layer_item.dart';`.

Replace the `layers:` write block in `toYamlString`:

```dart
buf.writeln('layerItems:');
for (final item in pattern.layerItems) {
  switch (item) {
    case LayerLeaf(:final layer):
      buf.writeln('  - type: layer');
      buf.writeln('    id: ${_yamlStr(layer.id)}');
      buf.writeln('    name: ${_yamlStr(layer.name)}');
      buf.writeln('    visible: ${layer.visible}');
      buf.writeln('    opacity: ${layer.opacity.toStringAsFixed(3)}');
      buf.writeln('    stitches:');
      for (final s in layer.stitches) {
        _writeStitch(buf, s, indent: '      ');
      }
    case LayerGroup():
      buf.writeln('  - type: group');
      buf.writeln('    id: ${_yamlStr(item.id)}');
      buf.writeln('    name: ${_yamlStr(item.name)}');
      buf.writeln('    collapsed: ${item.collapsed}');
      buf.writeln('    groupVisible: ${item.groupVisible}');
      buf.writeln('    layers:');
      for (final layer in item.layers) {
        _writeLayer(buf, layer, listIndent: '      ');
      }
  }
}
```

Update `_writeLayer` to take a `listIndent` parameter (the `  ` before the `-`):

```dart
static void _writeLayer(StringBuffer buf, Layer layer, {String listIndent = '  '}) {
  final f = '$listIndent  '; // field continuation indent
  buf.writeln('$listIndent- id: ${_yamlStr(layer.id)}');
  buf.writeln('${f}name: ${_yamlStr(layer.name)}');
  buf.writeln('${f}visible: ${layer.visible}');
  buf.writeln('${f}opacity: ${layer.opacity.toStringAsFixed(3)}');
  buf.writeln('${f}stitches:');
  for (final s in layer.stitches) {
    _writeStitch(buf, s, indent: '$f  ');
  }
}
```

- [ ] **Step 3: Update `lib/services/format_service.dart`**

Add `import '../models/layer_item.dart';`. Replace `layers: [Layer(...)]` with `layerItems: [LayerLeaf(layer: Layer(...))]`.

- [ ] **Step 4: Analyze, hot-restart, verify, commit**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze
```

Hot-restart the app. Open an existing `.stitchx` file. Verify layers appear. Draw a stitch — should work.

```bash
git add lib/models/pattern.dart lib/services/file_service.dart lib/services/format_service.dart
git commit -m "feat: pattern uses layerItems; layers getter flattens for rendering compat"
```

---

### Task 3: EditorProvider layer + group operations

**Goal:** Update all layer operations to work through `layerItems`, and add all group operations.

**Files:**
- Modify: `lib/providers/editor_provider.dart`

**Acceptance Criteria:**
- [ ] All existing layer operations (add, delete, rename, move, toggle visible, set opacity, duplicate, merge) work correctly
- [ ] `addLayer` inserts inside the active group when the active layer is grouped
- [ ] All group operations work: `addGroup`, `deleteGroup`, `renameGroup`, `toggleGroupVisible`, `toggleGroupCollapsed`, `ungroupGroup`, `moveLayerToGroup`, `moveLayerOutOfGroup`, `reorderTopLevel`, `reorderWithinGroup`
- [ ] `flutter analyze` passes

**Verify:** Hot-restart — create layers, delete, move, merge, opacity sliders — all work as before

**Steps:**

- [ ] **Step 1: Add `import '../models/layer_item.dart';` at top of file**

- [ ] **Step 2: Update `_updateLayer` to use `mapLayers`**

```dart
CrossStitchPattern _updateLayer(
    CrossStitchPattern pattern, String id, Layer Function(Layer) update) {
  return pattern.mapLayers((l) => l.id == id ? update(l) : l);
}
```

- [ ] **Step 3: Update `_patternWithAllLayersTransformed`**

```dart
CrossStitchPattern _patternWithAllLayersTransformed(
    CrossStitchPattern pattern, List<Stitch> Function(List<Stitch>) transform) {
  return pattern.mapLayers((l) => l.copyWith(stitches: transform(l.stitches)));
}
```

- [ ] **Step 4: Add private helper methods**

```dart
/// Returns the [LayerGroup] containing [layerId], or null if ungrouped.
LayerGroup? _groupContaining(String layerId) {
  for (final item in state.pattern.layerItems) {
    if (item is LayerGroup && item.layers.any((l) => l.id == layerId)) {
      return item;
    }
  }
  return null;
}

/// Removes [layerId] from wherever it lives in [items].
/// Returns (newItems, removedLayer). removedLayer is null if not found.
(List<LayerItem>, Layer?) _removeLayer(List<LayerItem> items, String layerId) {
  Layer? removed;
  final result = <LayerItem>[];
  for (final item in items) {
    switch (item) {
      case LayerLeaf(:final layer):
        if (layer.id == layerId) {
          removed = layer;
        } else {
          result.add(item);
        }
      case LayerGroup():
        final group = item as LayerGroup;
        final idx = group.layers.indexWhere((l) => l.id == layerId);
        if (idx != -1) {
          removed = group.layers[idx];
          result.add(group.copyWith(
            layers: [...group.layers]..removeAt(idx),
          ));
        } else {
          result.add(item);
        }
    }
  }
  return (result, removed);
}

/// Inserts [newLayer] immediately above [aboveLayerId] in [items].
/// layerItems are stored bottom-to-top; "above" = higher index.
/// Falls back to appending at the end (top) if [aboveLayerId] not found.
List<LayerItem> _insertLayerAbove(
    List<LayerItem> items, String aboveLayerId, Layer newLayer) {
  for (int i = 0; i < items.length; i++) {
    switch (items[i]) {
      case LayerLeaf(:final layer):
        if (layer.id == aboveLayerId) {
          return [...items]..insert(i + 1, LayerLeaf(layer: newLayer));
        }
      case LayerGroup():
        final group = items[i] as LayerGroup;
        final idx = group.layers.indexWhere((l) => l.id == aboveLayerId);
        if (idx != -1) {
          return [...items]..[i] = group.copyWith(
            layers: [...group.layers]..insert(idx + 1, newLayer),
          );
        }
    }
  }
  return [...items, LayerLeaf(layer: newLayer)];
}
```

- [ ] **Step 5: Rewrite `addLayer`**

```dart
void addLayer() {
  final newLayer = Layer.create(
      name: 'Layer ${state.pattern.layers.length + 1}');
  final newItems = _insertLayerAbove(
      state.pattern.layerItems, state.activeLayerId, newLayer);
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    activeLayerId: newLayer.id,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 6: Rewrite `deleteLayer`**

```dart
void deleteLayer(String id) {
  if (state.pattern.layers.length <= 1) return;
  final (newItems, _) = _removeLayer(state.pattern.layerItems, id);
  String newActiveId = state.activeLayerId;
  if (newActiveId == id) {
    final remaining = newItems.expand((item) => switch (item) {
      LayerLeaf(:final layer) => [layer],
      LayerGroup(:final layers) => layers,
    }).toList();
    final visible = remaining.where((l) => l.visible);
    newActiveId = visible.isNotEmpty
        ? visible.last.id
        : (remaining.isNotEmpty ? remaining.last.id : '');
  }
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    activeLayerId: newActiveId,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 7: Rewrite `moveLayer`**

Moves within the same container (within-group or top-level ungrouped). `delta = +1` toward top.

```dart
void moveLayer(String id, int delta) {
  final items = state.pattern.layerItems;
  List<LayerItem> newItems;
  final group = _groupContaining(id);
  if (group != null) {
    final layers = [...group.layers];
    final idx = layers.indexWhere((l) => l.id == id);
    final newIdx = (idx + delta).clamp(0, layers.length - 1);
    if (newIdx == idx) return;
    final layer = layers.removeAt(idx);
    layers.insert(newIdx, layer);
    newItems = items.map((item) =>
        item is LayerGroup && item.id == group.id
            ? item.copyWith(layers: layers)
            : item).toList();
  } else {
    final mutable = [...items];
    final idx = mutable.indexWhere(
        (item) => item is LayerLeaf && item.layer.id == id);
    if (idx == -1) return;
    final newIdx = (idx + delta).clamp(0, mutable.length - 1);
    if (newIdx == idx) return;
    final item = mutable.removeAt(idx);
    mutable.insert(newIdx, item);
    newItems = mutable;
  }
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
  if (state.showCompositeThreads) refreshCompositeCache();
}
```

- [ ] **Step 8: Rewrite `duplicateLayer`**

```dart
void duplicateLayer(String id) {
  final src = state.pattern.layers.firstWhere((l) => l.id == id);
  final duplicate = Layer(
    id: const Uuid().v4(),
    name: '${src.name} copy',
    visible: src.visible,
    opacity: src.opacity,
    stitches: List<Stitch>.from(src.stitches),
  );
  final newItems =
      _insertLayerAbove(state.pattern.layerItems, id, duplicate);
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    activeLayerId: duplicate.id,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 9: Rewrite `mergeLayers`**

Merges within the same container. Disabled at the bottom of any container (enforced in UI).

```dart
void mergeLayers(String topId) {
  final items = state.pattern.layerItems;
  List<LayerItem> newItems;
  String newActiveId = state.activeLayerId;
  final group = _groupContaining(topId);

  if (group != null) {
    final layers = group.layers;
    final topIdx = layers.indexWhere((l) => l.id == topId);
    if (topIdx <= 0) return;
    final belowIdx = topIdx - 1;
    var merged = [...layers[belowIdx].stitches];
    for (final s in layers[topIdx].stitches) {
      merged = _stitchesWithAdded(merged, s);
    }
    final newGroupLayers = [...layers]
      ..[belowIdx] = layers[belowIdx].copyWith(stitches: merged)
      ..removeAt(topIdx);
    if (state.activeLayerId == topId) newActiveId = newGroupLayers[belowIdx].id;
    newItems = items.map((item) =>
        item is LayerGroup && item.id == group.id
            ? item.copyWith(layers: newGroupLayers)
            : item).toList();
  } else {
    // Top-level: only merge between adjacent LayerLeaf items
    final topIdx = items.indexWhere(
        (item) => item is LayerLeaf && item.layer.id == topId);
    if (topIdx <= 0) return;
    int belowIdx = topIdx - 1;
    while (belowIdx >= 0 && items[belowIdx] is! LayerLeaf) belowIdx--;
    if (belowIdx < 0) return;
    final topLayer = (items[topIdx] as LayerLeaf).layer;
    final belowLayer = (items[belowIdx] as LayerLeaf).layer;
    var merged = [...belowLayer.stitches];
    for (final s in topLayer.stitches) merged = _stitchesWithAdded(merged, s);
    newItems = [...items]
      ..[belowIdx] = LayerLeaf(layer: belowLayer.copyWith(stitches: merged))
      ..removeAt(topIdx);
    if (state.activeLayerId == topId) {
      newActiveId = (newItems[belowIdx] as LayerLeaf).layer.id;
    }
  }

  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    activeLayerId: newActiveId,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}
```

- [ ] **Step 10: Add group operations**

```dart
// ─── Group management ──────────────────────────────────────────────────────

void addGroup() {
  final newLayer = Layer.create(
      name: 'Layer ${state.pattern.layers.length + 1}');
  final groupCount = state.pattern.layerItems.whereType<LayerGroup>().length;
  final newGroup = LayerGroup.create(
      name: 'Group ${groupCount + 1}', initialLayer: newLayer);
  // Append at end = topmost position in panel
  state = state.copyWith(
    pattern: state.pattern.copyWith(
        layerItems: [...state.pattern.layerItems, newGroup]),
    activeLayerId: newLayer.id,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

/// Warning dialog is shown by the UI before calling this.
void deleteGroup(String groupId) {
  final group = state.pattern.layerItems
      .whereType<LayerGroup>()
      .firstWhere((g) => g.id == groupId);
  final newItems = state.pattern.layerItems
      .where((item) => !(item is LayerGroup && item.id == groupId))
      .toList();
  String newActiveId = state.activeLayerId;
  if (group.layers.any((l) => l.id == state.activeLayerId)) {
    final remaining = newItems.expand((item) => switch (item) {
      LayerLeaf(:final layer) => [layer],
      LayerGroup(:final layers) => layers,
    }).toList();
    newActiveId = remaining.isNotEmpty ? remaining.last.id : '';
  }
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    activeLayerId: newActiveId,
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
    compositeThreadCache: null,
  );
}

void renameGroup(String groupId, String name) {
  final newItems = state.pattern.layerItems.map((item) =>
      item is LayerGroup && item.id == groupId
          ? item.copyWith(name: name)
          : item).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    isDirty: true,
  );
}

void toggleGroupVisible(String groupId) {
  final newItems = state.pattern.layerItems.map((item) =>
      item is LayerGroup && item.id == groupId
          ? item.copyWith(groupVisible: !item.groupVisible)
          : item).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    isDirty: true,
    compositeThreadCache: null,
  );
  if (state.showCompositeThreads) refreshCompositeCache();
}

void toggleGroupCollapsed(String groupId) {
  final newItems = state.pattern.layerItems.map((item) =>
      item is LayerGroup && item.id == groupId
          ? item.copyWith(collapsed: !item.collapsed)
          : item).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    isDirty: true,
  );
}

void ungroupGroup(String groupId) {
  final newItems = <LayerItem>[];
  for (final item in state.pattern.layerItems) {
    if (item is LayerGroup && item.id == groupId) {
      newItems.addAll(item.layers.map((l) => LayerLeaf(layer: l)));
    } else {
      newItems.add(item);
    }
  }
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}

void moveLayerToGroup(String layerId, String groupId) {
  final (itemsWithout, removed) = _removeLayer(state.pattern.layerItems, layerId);
  if (removed == null) return;
  final newItems = itemsWithout.map((item) =>
      item is LayerGroup && item.id == groupId
          ? item.copyWith(layers: [...item.layers, removed])
          : item).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}

void moveLayerOutOfGroup(String layerId, String groupId) {
  final (itemsWithout, removed) = _removeLayer(state.pattern.layerItems, layerId);
  if (removed == null) return;
  final groupIdx = itemsWithout.indexWhere(
      (item) => item is LayerGroup && item.id == groupId);
  final insertIdx = groupIdx == -1 ? itemsWithout.length : groupIdx + 1;
  final newItems = [...itemsWithout]..insert(insertIdx, LayerLeaf(layer: removed));
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}

/// Called by the panel's top-level ReorderableListView.
/// [oldVisual]/[newVisual] are visual indices (0 = topmost in panel = layerItems.last).
void reorderTopLevel(int oldVisual, int newVisual) {
  final count = state.pattern.layerItems.length;
  final fromIdx = count - 1 - oldVisual;
  int toIdx = count - 1 - newVisual;
  if (newVisual > oldVisual) toIdx += 1;
  if (fromIdx == toIdx) return;
  final items = [...state.pattern.layerItems];
  final item = items.removeAt(fromIdx);
  items.insert(toIdx.clamp(0, items.length), item);
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: items),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}

/// Called by the panel's per-group ReorderableListView.
/// [oldVisual]/[newVisual] are visual indices within the group (0 = topmost = group.layers.last).
void reorderWithinGroup(String groupId, int oldVisual, int newVisual) {
  final group = state.pattern.layerItems
      .whereType<LayerGroup>()
      .firstWhere((g) => g.id == groupId);
  final count = group.layers.length;
  final fromIdx = count - 1 - oldVisual;
  int toIdx = count - 1 - newVisual;
  if (newVisual > oldVisual) toIdx += 1;
  if (fromIdx == toIdx) return;
  final layers = [...group.layers];
  final layer = layers.removeAt(fromIdx);
  layers.insert(toIdx.clamp(0, layers.length), layer);
  final newItems = state.pattern.layerItems.map((item) =>
      item is LayerGroup && item.id == groupId
          ? item.copyWith(layers: layers)
          : item).toList();
  state = state.copyWith(
    pattern: state.pattern.copyWith(layerItems: newItems),
    undoStack: _buildUndoStack(),
    isDirty: true,
    redoStack: [],
  );
}
```

- [ ] **Step 11: Check for leftover `copyWith(layers:)` call sites**

```bash
grep -n "copyWith(layers:" lib/providers/editor_provider.dart
```

Any remaining occurrences are from call sites not yet updated. For each one, convert using the helpers above or `copyWith(layerItems:)`.

- [ ] **Step 12: Analyze, verify, commit**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze
```

Hot-restart. Verify: add layers, delete, move up/down, duplicate, merge, opacity slider — all work as before.

```bash
git add lib/providers/editor_provider.dart
git commit -m "feat: update EditorNotifier for layerItems; add group operations"
```

---

### Task 4: Layers panel UI

**Goal:** Rewrite `LayersPanel` to render groups (with collapse/expand) and ungrouped layers, with a "New Group" button.

**Files:**
- Modify: `lib/widgets/layers_panel.dart`

**Acceptance Criteria:**
- [ ] Group rows show: drag handle, chevron, eye, name (double-tap to rename), ⋮ menu
- [ ] Layers inside a collapsed group are not shown
- [ ] Layers inside a group are indented 12px left
- [ ] "New Group" button (`Icons.create_new_folder_outlined`) in panel header works
- [ ] Deleting a group shows a confirmation dialog before calling `notifier.deleteGroup`
- [ ] "Move out of group" appears in grouped layer ⋮ menu
- [ ] Ungrouped layers behave identically to before
- [ ] `isBottom` / `onMergeDown` correctly reflects bottom of each container

**Verify:** Run app — create a group, collapse it, toggle visibility, ungroup, delete with confirmation

**Steps:**

- [ ] **Step 1: Add `import '../models/layer_item.dart';` to `layers_panel.dart`**

- [ ] **Step 2: Update `_LayersPanelState.build` to iterate `layerItems`**

Replace the `ReorderableListView.builder` driven by `layers` with one driven by a flattened display list built from `layerItems`:

```dart
// Build the flat ordered display list (topmost item first = panel visual order)
// sealed type to carry display context
final displayItems = <({Object item, String? groupId})>[];
for (final layerItem in state.pattern.layerItems.reversed) {
  switch (layerItem) {
    case LayerGroup():
      displayItems.add((item: layerItem, groupId: null));
      if (!layerItem.collapsed) {
        for (final layer in layerItem.layers.reversed) {
          displayItems.add((item: layer, groupId: layerItem.id));
        }
      }
    case LayerLeaf(:final layer):
      displayItems.add((item: layer, groupId: null));
  }
}
```

Use `ReorderableListView.builder` over `displayItems`. In `onReorder`, determine whether dragging a group row, a grouped layer row, or an ungrouped layer row, and call the appropriate notifier method.

**Reorder logic:**

```dart
onReorder: (oldIndex, newIndex) {
  final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
  final moving = displayItems[oldIndex];
  final target = adjusted < displayItems.length ? displayItems[adjusted] : null;

  if (moving.item is LayerGroup || (moving.item is Layer && moving.groupId == null)) {
    // Top-level item: count its top-level visual index
    int topLevelOld = 0;
    int topLevelNew = 0;
    int topIdx = 0;
    for (int i = 0; i < displayItems.length; i++) {
      final d = displayItems[i];
      if (d.item is LayerGroup || (d.item is Layer && d.groupId == null)) {
        if (i == oldIndex) topLevelOld = topIdx;
        if (i == adjusted) topLevelNew = topIdx;
        topIdx++;
      }
    }
    notifier.reorderTopLevel(topLevelOld, topLevelNew);
  } else if (moving.item is Layer && moving.groupId != null) {
    final groupId = moving.groupId!;
    // Check if target is outside the group → move out
    if (target == null || target.groupId != groupId) {
      notifier.moveLayerOutOfGroup((moving.item as Layer).id, groupId);
    } else {
      // Reorder within group — compute group-relative indices
      int groupOld = 0, groupNew = 0, gIdx = 0;
      for (int i = 0; i < displayItems.length; i++) {
        if (displayItems[i].groupId == groupId) {
          if (i == oldIndex) groupOld = gIdx;
          if (i == adjusted) groupNew = gIdx;
          gIdx++;
        }
      }
      notifier.reorderWithinGroup(groupId, groupOld, groupNew);
    }
  }
},
```

- [ ] **Step 3: Implement `_GroupRow` widget**

Create a new `_GroupRow` stateful widget (alongside `_LayerRow`):

```dart
enum _GroupAction { rename, addLayer, ungroup, delete }

class _GroupRow extends StatefulWidget {
  final LayerGroup group;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onToggleVisible;
  final VoidCallback onAddLayer;
  final VoidCallback onUngroup;
  final VoidCallback onDeleteGroup;
  final ValueChanged<String> onRename;
  final Widget? dragHandle;
  const _GroupRow({
    required super.key,
    required this.group,
    required this.onToggleCollapsed,
    required this.onToggleVisible,
    required this.onAddLayer,
    required this.onUngroup,
    required this.onDeleteGroup,
    required this.onRename,
    this.dragHandle,
  });
  @override State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  bool _renaming = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.group.name);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  void _startRename() { _ctrl.text = widget.group.name; setState(() => _renaming = true); }
  void _commitRename() {
    final n = _ctrl.text.trim();
    if (n.isNotEmpty) widget.onRename(n);
    setState(() => _renaming = false);
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text(
            'Delete "${widget.group.name}" and all ${widget.group.layers.length} '
            'layer(s) inside? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(context); widget.onDeleteGroup(); },
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
      child: Row(children: [
        if (widget.dragHandle != null) ...[widget.dragHandle!, const SizedBox(width: 2)],
        // Collapse chevron
        GestureDetector(
          onTap: widget.onToggleCollapsed,
          child: Icon(
            group.collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 2),
        // Eye (master visibility)
        GestureDetector(
          onTap: widget.onToggleVisible,
          child: Icon(
            group.groupVisible ? Icons.visibility : Icons.visibility_off,
            size: 16,
            color: group.groupVisible
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(width: 4),
        // Group name
        Expanded(
          child: _renaming
              ? TextField(
                  controller: _ctrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _commitRename(),
                  onEditingComplete: _commitRename,
                )
              : GestureDetector(
                  onDoubleTap: _startRename,
                  child: Text(group.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: group.groupVisible
                          ? null
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
        // ⋮ menu
        PopupMenuButton<_GroupAction>(
          padding: EdgeInsets.zero,
          iconSize: 16,
          tooltip: 'Group options',
          onSelected: (action) {
            switch (action) {
              case _GroupAction.rename: _startRename();
              case _GroupAction.addLayer: widget.onAddLayer();
              case _GroupAction.ungroup: widget.onUngroup();
              case _GroupAction.delete: _confirmDelete(context);
            }
          },
          itemBuilder: (_) => [
            _groupMenuItem(_GroupAction.rename, Icons.edit_outlined, 'Rename'),
            _groupMenuItem(_GroupAction.addLayer, Icons.add, 'Add Layer'),
            _groupMenuItem(_GroupAction.ungroup, Icons.layers_clear_outlined, 'Ungroup'),
            const PopupMenuDivider(),
            _groupMenuItem(_GroupAction.delete, Icons.delete_outline, 'Delete Group', color: Colors.red.shade600),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<_GroupAction> _groupMenuItem(_GroupAction v, IconData icon, String label, {Color? color}) =>
      PopupMenuItem<_GroupAction>(
        value: v,
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ]),
      );
}
```

- [ ] **Step 4: Update `_LayerRow` to accept indent and "Move out of group"**

Add `indent` parameter to `_LayerRow` (default `0.0`). Wrap the row content in `Padding(padding: EdgeInsets.only(left: indent))`.

Add `onMoveOutOfGroup: VoidCallback?` parameter. When non-null, add "Move Out of Group" to the ⋮ menu (between Duplicate and Merge Down).

- [ ] **Step 5: Wire group rows in the `itemBuilder`**

In `ReorderableListView.builder`, for each entry in `displayItems`:

```dart
itemBuilder: (context, visualIndex) {
  final entry = displayItems[visualIndex];
  if (entry.item is LayerGroup) {
    final group = entry.item as LayerGroup;
    return _GroupRow(
      key: ValueKey('group_${group.id}'),
      group: group,
      onToggleCollapsed: () => notifier.toggleGroupCollapsed(group.id),
      onToggleVisible: () => notifier.toggleGroupVisible(group.id),
      onAddLayer: () {
        notifier.setActiveLayer(group.layers.last.id); // activate bottom layer in group
        notifier.addLayer();
      },
      onUngroup: () => notifier.ungroupGroup(group.id),
      onDeleteGroup: () => notifier.deleteGroup(group.id),
      onRename: (name) => notifier.renameGroup(group.id, name),
      dragHandle: ReorderableDragStartListener(
        index: visualIndex,
        child: MouseRegion(cursor: SystemMouseCursors.grab,
          child: Icon(Icons.drag_handle, size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
      ),
    );
  }

  // Layer row (grouped or ungrouped)
  final layer = entry.item as Layer;
  final groupId = entry.groupId;
  final isGrouped = groupId != null;

  // Determine container for isBottom / onMergeDown
  final containerLayers = isGrouped
      ? (state.pattern.layerItems
          .whereType<LayerGroup>()
          .firstWhere((g) => g.id == groupId)).layers
      : state.pattern.layerItems
          .whereType<LayerLeaf>()
          .map((lf) => lf.layer)
          .toList();
  final layerIdx = containerLayers.indexWhere((l) => l.id == layer.id);
  final isBottom = layerIdx == 0;
  final isOnly = containerLayers.length == 1 && !isGrouped
      ? state.pattern.layers.length == 1
      : containerLayers.length == 1;

  return _LayerRow(
    key: ValueKey(layer.id),
    layer: layer,
    indent: isGrouped ? 12.0 : 0.0,
    isActive: layer.id == state.activeLayerId,
    isBottom: isBottom,
    isOnly: isOnly && state.pattern.layers.length == 1,
    onTap: () => notifier.setActiveLayer(layer.id),
    onToggleVisible: () => notifier.toggleLayerVisible(layer.id),
    onOpacityChanged: (v) => notifier.setLayerOpacity(layer.id, v),
    onRename: (name) => notifier.renameLayer(layer.id, name),
    onMoveUp: layerIdx < containerLayers.length - 1
        ? () => notifier.moveLayer(layer.id, 1) : null,
    onMoveDown: layerIdx > 0
        ? () => notifier.moveLayer(layer.id, -1) : null,
    onDuplicate: () => notifier.duplicateLayer(layer.id),
    onMergeDown: !isBottom ? () => notifier.mergeLayers(layer.id) : null,
    onDelete: state.pattern.layers.length > 1
        ? () => notifier.deleteLayer(layer.id) : null,
    onMoveOutOfGroup: isGrouped
        ? () => notifier.moveLayerOutOfGroup(layer.id, groupId!) : null,
    dragHandle: ReorderableDragStartListener(
      index: visualIndex,
      child: MouseRegion(cursor: SystemMouseCursors.grab,
        child: Icon(Icons.drag_handle, size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
    ),
  );
},
```

- [ ] **Step 6: Add "New Group" button to panel header**

```dart
IconButton(
  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
  tooltip: 'New group',
  padding: EdgeInsets.zero,
  visualDensity: VisualDensity.compact,
  onPressed: notifier.addGroup,
),
```

Place it after the existing `Icons.add` button.

- [ ] **Step 7: Analyze, run app, verify all group operations**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze
```

Manually test:
1. Single layer — panel looks identical to before
2. Tap "New group" → group header + one layer inside
3. Collapse group → layers hidden
4. Toggle group eye → layers hidden on canvas
5. Double-tap group name → rename inline
6. Layer ⋮ → "Move Out of Group" → layer becomes ungrouped
7. Group ⋮ → "Add Layer" → new layer inside group
8. Group ⋮ → "Ungroup" → layers appear ungrouped in place
9. Group ⋮ → "Delete Group" → confirmation dialog → confirm → group + layers gone
10. Drag group → reorders in panel
11. Drag layer within group → reorders within group
12. Save and reload — groups persist

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/layers_panel.dart
git commit -m "feat: layer groups panel UI — collapse, visibility, reorder, group management"
```
