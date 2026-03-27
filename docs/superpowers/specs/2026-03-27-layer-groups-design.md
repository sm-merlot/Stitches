# Layer Groups Design

**Date:** 2026-03-27
**Status:** Approved

## Overview

Organise layers into collapsible named groups in the layers panel. Groups and ungrouped layers can be interleaved in any order (Photoshop-style). Groups have a master visibility override that hides all contained layers regardless of their individual visibility state.

---

## Model

### New file: `lib/models/layer_item.dart`

```dart
sealed class LayerItem {}

class LayerLeaf extends LayerItem {
  final Layer layer;
}

class LayerGroup extends LayerItem {
  final String id;
  final String name;
  final bool collapsed;     // persisted; whether group is folded in the panel
  final bool groupVisible;  // persisted; master visibility override
  final List<Layer> layers; // ordered top-to-bottom within the group
}
```

### `CrossStitchPattern` changes

- Add `List<LayerItem> layerItems` as the stored field
- Keep `List<Layer> get layers` as a computed getter that flattens `layerItems`, applying `groupVisible`:
  - `groupVisible = true` → include each layer with its own `visible` flag intact
  - `groupVisible = false` → include each layer with `visible` forced to `false`
- Remove the stored `List<Layer> layers` field

### `Layer` model

No changes. `Layer` remains the same immutable value object.

---

## YAML Serialization

### New format

```yaml
layerItems:
  - type: layer
    id: abc123
    name: Layer 1
    visible: true
    opacity: 1.0
    stitches: [...]
  - type: group
    id: grp456
    name: Flowers
    collapsed: false
    groupVisible: true
    layers:
      - id: def789
        name: Petals
        visible: true
        opacity: 1.0
        stitches: [...]
```

### Migration

Old files are migrated transparently on load:

| Old format | Migration |
|---|---|
| `layers:` key present | Each `Layer` wrapped in `LayerLeaf`; written back as `layerItems:` on next save |
| `stitches:` key only (pre-layers) | Existing migration produces one `Layer`, then wrapped in `LayerLeaf` |

No existing `.stitchx` files break.

---

## Layers Panel UI

### Group row

- Drag handle — reorders the group in the top-level panel list
- Collapse chevron (`▶`/`▼`) — toggles `collapsed`
- Eye icon — toggles `groupVisible` master override
- Group name — double-tap to rename
- `Icons.create_new_folder_outlined` button in panel header — creates a new group
- ⋮ menu: **Rename**, **Add Layer to Group**, **Ungroup** (dissolves group, layers become ungrouped in place), **Delete Group** (warning dialog — deletes group and all layers inside)

### Layer rows inside a group

- Same as current `_LayerRow` with 12px left indent
- Drag handle reorders within the group
- Can be dragged out of the group to become an ungrouped `LayerLeaf`

### Ungrouped layer row

- Same as current `_LayerRow`, no indent

### Panel header

- Existing `Icons.add` button — adds a new ungrouped layer at the top
- New `Icons.create_new_folder_outlined` button — adds a new group (with one new layer inside) at the top

### Reordering rules

| Drag action | Result |
|---|---|
| Drag a group | Moves group as a unit in the top-level order |
| Drag a layer within a group | Reorders within the group |
| Drag a layer out of a group | Layer becomes ungrouped, inserted at the drop position |
| Drag an ungrouped layer onto a group | Layer appended as last item in the group |

---

## EditorState & EditorNotifier

### EditorState

- `activeLayerId` unchanged — still a `Layer` id (works regardless of group membership)
- No new state fields; `collapsed`/`groupVisible` live in the model

### New notifier operations

| Method | Behaviour |
|---|---|
| `addGroup()` | Creates `LayerGroup` with one new layer inside; inserts at top of `layerItems`; new layer becomes active |
| `deleteGroup(groupId)` | Warning dialog, then removes group and all its layers; adjusts `activeLayerId` if needed |
| `renameGroup(groupId, name)` | Updates group name |
| `toggleGroupVisible(groupId)` | Flips `groupVisible` |
| `toggleGroupCollapsed(groupId)` | Flips `collapsed` |
| `ungroupGroup(groupId)` | Dissolves group; inserts its layers as `LayerLeaf` items in place |
| `moveLayerToGroup(layerId, groupId)` | Removes layer from current position; appends to group |
| `moveLayerOutOfGroup(layerId, groupId)` | Removes from group; inserts as `LayerLeaf` just below the group |
| `reorderTopLevel(oldIndex, newIndex)` | Moves a top-level item (group or ungrouped layer) |
| `reorderWithinGroup(groupId, oldIndex, newIndex)` | Moves a layer within a group |

### Existing operations unchanged

`addLayer`, `deleteLayer`, `renameLayer`, `moveLayer`, `toggleLayerVisible`, `setActiveLayer`, `duplicateLayer`, `mergeLayers` — all find layers by searching `layerItems` recursively. No signature changes.

`addLayer` — if the active layer is inside a group, the new layer is inserted inside that same group above the active layer. If the active layer is ungrouped, the new layer is inserted as an ungrouped `LayerLeaf` above it.

---

## Rendering

All rendering consumers (`CanvasStaticPainter`, colour picker, flood fill, stitch demo, PDF scanner, sprite importer) use `pattern.layers` — the flattened computed getter. **Zero changes required** in any rendering file.

The `groupVisible` override is applied in the getter, so group hiding is transparent to all consumers. Toggling `groupVisible` changes the `pattern` object identity, which triggers `shouldRepaint` normally.

---

## Files Changed

| File | Change |
|---|---|
| `lib/models/layer_item.dart` | **New** — `LayerItem`, `LayerLeaf`, `LayerGroup` |
| `lib/models/pattern.dart` | Replace `List<Layer> layers` field with `List<LayerItem> layerItems`; add `layers` computed getter; update `fromYaml`/`toYaml`/`copyWith` |
| `lib/widgets/layers_panel.dart` | Rewrite to render `LayerItem` list with group headers, indent, drag-out-of-group |
| `lib/providers/editor_provider.dart` | Add group operations; update existing layer ops to search `layerItems` recursively |
| `lib/services/format_service.dart` | Update layer construction to produce `LayerLeaf` items |
