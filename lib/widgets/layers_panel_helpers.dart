part of 'layers_panel.dart';

// ─── Flat item types ───────────────────────────────────────────────────────────

sealed class _FlatItem {
  const _FlatItem();
}

class _FlatGroupHeader extends _FlatItem {
  final LayerGroup group;
  final int layerItemIdx;
  const _FlatGroupHeader(this.group, this.layerItemIdx);
}

class _FlatLayer extends _FlatItem {
  final Layer layer;
  final String? groupId;
  final int? groupLayerIdx; // index in group.layers (null if top-level)
  final int layerItemIdx;   // index of the owning LayerItem in layerItems
  const _FlatLayer(this.layer,
      {required this.groupId,
      required this.groupLayerIdx,
      required this.layerItemIdx});
}

// ─── Enums ─────────────────────────────────────────────────────────────────────

enum _LayerAction { rename, duplicate, mergeDown, delete }

enum _GroupAction { rename, addLayer, toggleLock, ungroup, delete }

// ─── Flat list helpers ─────────────────────────────────────────────────────────

/// Builds a flat ordered list of displayable items (top → bottom in the panel).
List<_FlatItem> _buildFlatItems(List<LayerItem> layerItems) {
  final result = <_FlatItem>[];
  // layerItems[last] = topmost, iterate top-to-bottom.
  for (int i = layerItems.length - 1; i >= 0; i--) {
    final item = layerItems[i];
    if (item is LayerLeaf) {
      result.add(_FlatLayer(item.layer,
          groupId: null, groupLayerIdx: null, layerItemIdx: i));
    } else if (item is LayerGroup) {
      result.add(_FlatGroupHeader(item, i));
      if (!item.collapsed) {
        // group.layers[last] = topmost within group.
        for (int j = item.layers.length - 1; j >= 0; j--) {
          result.add(_FlatLayer(item.layers[j],
              groupId: item.id, groupLayerIdx: j, layerItemIdx: i));
        }
      }
    }
  }
  return result;
}

void _onFlatReorder(
    int oldVisual,
    int newVisual,
    List<LayerItem> layerItems,
    EditorNotifier notifier) {
  final flatItems = _buildFlatItems(layerItems);
  if (oldVisual == newVisual || oldVisual >= flatItems.length) return;

  final movedItem = flatItems[oldVisual];

  // Flutter's ReorderableListView passes newIndex as a position in the
  // *original* list, not the post-removal list. Clamp it to the reduced
  // list length to handle "drop past end" without index-out-of-bounds.
  final flatAfterRemoval = List<_FlatItem>.from(flatItems)..removeAt(oldVisual);
  final clampedNew = newVisual.clamp(0, flatAfterRemoval.length);

  final prevFlatItem =
      clampedNew > 0 ? flatAfterRemoval[clampedNew - 1] : null;
  final nextFlatItem =
      clampedNew < flatAfterRemoval.length ? flatAfterRemoval[clampedNew] : null;

  if (movedItem is _FlatGroupHeader) {
    // Move a collapsed group to a new top-level position.
    final groupId = movedItem.group.id;
    final oldIdx =
        layerItems.indexWhere((i) => i is LayerGroup && i.id == groupId);
    final newIdx = _countLayerItemsBelow(flatAfterRemoval, clampedNew);
    if (oldIdx >= 0 && oldIdx != newIdx) {
      notifier.reorderTopLevel(oldIdx, newIdx);
    }
    return;
  }

  final fl = movedItem as _FlatLayer;
  final layerId = fl.layer.id;

  // Destination: immediately after a group header.
  // Expanded group → insert at top of the group.
  // Collapsed group → insert as top-level below the group.
  if (prevFlatItem is _FlatGroupHeader) {
    if (!prevFlatItem.group.collapsed) {
      notifier.moveLayerIntoGroupBelow(layerId, prevFlatItem.group.id, null);
    } else {
      notifier.moveLayerToTopLevelBelow(layerId, prevFlatItem.group.id);
    }
    return;
  }

  // Destination: between two layers in the same group → within-group insert.
  if (prevFlatItem is _FlatLayer &&
      prevFlatItem.groupId != null &&
      nextFlatItem is _FlatLayer &&
      nextFlatItem.groupId == prevFlatItem.groupId) {
    notifier.moveLayerIntoGroupBelow(
        layerId, prevFlatItem.groupId!, prevFlatItem.layer.id);
    return;
  }

  // Otherwise → top-level insertion below prevFlatItem.
  final prevTopLevelId = _prevTopLevelId(prevFlatItem);
  notifier.moveLayerToTopLevelBelow(layerId, prevTopLevelId);
}

/// Number of distinct LayerItems that are visually BELOW [newVisual] in
/// [flatAfterRemoval]. Used to compute the insertion index for [reorderTopLevel].
int _countLayerItemsBelow(List<_FlatItem> flatAfterRemoval, int newVisual) {
  final seen = <String>{};
  for (int i = newVisual; i < flatAfterRemoval.length; i++) {
    final item = flatAfterRemoval[i];
    if (item is _FlatGroupHeader) {
      seen.add(item.group.id);
    } else if (item is _FlatLayer) {
      seen.add(item.groupId ?? item.layer.id);
    }
  }
  return seen.length;
}

/// Returns the ID of the top-level LayerItem that is just above the insertion
/// point (group ID, or leaf layer ID). Null means the insertion is at the top.
String? _prevTopLevelId(_FlatItem? prevFlatItem) {
  if (prevFlatItem == null) return null;
  if (prevFlatItem is _FlatGroupHeader) return prevFlatItem.group.id;
  if (prevFlatItem is _FlatLayer) {
    return prevFlatItem.groupId ?? prevFlatItem.layer.id;
  }
  return null;
}

