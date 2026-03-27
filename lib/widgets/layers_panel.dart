import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
import '../models/layer_item.dart';
import '../providers/editor_provider.dart';

/// Resizable right-side panel that lists the pattern's layers.
/// Visible only in design mode; returns [SizedBox.shrink] in stitch mode.
class LayersPanel extends ConsumerStatefulWidget {
  const LayersPanel({super.key});

  @override
  ConsumerState<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends ConsumerState<LayersPanel> {
  double _width = 170;
  static const double _minWidth = 140;
  static const double _maxWidth = 350;


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    if (state.stitchMode || !state.isFileOpen) return const SizedBox.shrink();

    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final layerItems = state.pattern.layerItems;
    final totalLayerCount = state.pattern.layers.length;

    // Build flat display list (top to bottom, mirroring panel order).
    final flatItems = _buildFlatItems(layerItems);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag-to-resize handle on the left edge of the panel
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _width = (_width - details.delta.dx).clamp(_minWidth, _maxWidth);
              });
            },
            child: Container(
              width: 5,
              color: Colors.transparent,
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.dividerColor,
              ),
            ),
          ),
        ),
        SizedBox(
          width: _width,
          child: Container(
            color: theme.colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
                  child: Row(
                    children: [
                      Text('Layers',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 18),
                        tooltip: 'New group',
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: notifier.addGroup,
                      ),
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
                // ── Layer list ───────────────────────────────────────────────
                // Flat list: groups and their layers are separate items.
                // Display order is top-to-bottom (topmost layer first).
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    onReorder: (oldVisual, newVisual) {
                      final currentLayerItems =
                          ref.read(editorProvider).pattern.layerItems;
                      _onFlatReorder(
                          oldVisual, newVisual, currentLayerItems, notifier);
                    },
                    itemCount: flatItems.length,
                    itemBuilder: (context, index) {
                      final flatItem = flatItems[index];

                      Widget dragHandle(bool enabled) => enabled
                          ? ReorderableDragStartListener(
                              index: index,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Icon(
                                  Icons.drag_handle,
                                  size: 16,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                            )
                          : SizedBox(
                              width: 16,
                              child: Icon(
                                Icons.drag_handle,
                                size: 16,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.15),
                              ),
                            );

                      if (flatItem is _FlatGroupHeader) {
                        final group = flatItem.group;
                        final activeInGroup = group.collapsed &&
                            group.layers.any(
                                (l) => l.id == state.activeLayerId);
                        final groupDragHandle = group.collapsed
                            ? dragHandle(true)
                            : GestureDetector(
                                onTap: () {
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(const SnackBar(
                                      content: Text(
                                          'Collapse the group first to drag it'),
                                      duration: Duration(seconds: 2),
                                    ));
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.forbidden,
                                  child: SizedBox(
                                    width: 16,
                                    child: Icon(
                                      Icons.drag_handle,
                                      size: 16,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.15),
                                    ),
                                  ),
                                ),
                              );
                        return _GroupRow(
                          key: ValueKey(group.id),
                          group: group,
                          notifier: notifier,
                          dragHandle: groupDragHandle,
                          hasActiveLayer: activeInGroup,
                        );
                      }

                      final fl = flatItem as _FlatLayer;
                      final layer = fl.layer;
                      final inGroup = fl.groupId != null;

                      // Merge-down: not available if it's the bottommost layer
                      // in its container (group or top-level), or the only layer.
                      final canMerge = totalLayerCount > 1 &&
                          (inGroup
                              ? fl.groupLayerIdx! > 0
                              : fl.layerItemIdx > 0 &&
                                  layerItems[fl.layerItemIdx - 1] is LayerLeaf);

                      return _LayerRow(
                        key: ValueKey(layer.id),
                        layer: layer,
                        indent: inGroup ? 12.0 : 0.0,
                        isActive: layer.id == state.activeLayerId,
                        isBottom: false,
                        isOnly: totalLayerCount == 1,
                        groupId: fl.groupId,
                        onTap: () => notifier.setActiveLayer(layer.id),
                        onToggleVisible: () =>
                            notifier.toggleLayerVisible(layer.id),
                        onOpacityChanged: (v) =>
                            notifier.setLayerOpacity(layer.id, v),
                        onRename: (name) =>
                            notifier.renameLayer(layer.id, name),
                        onDuplicate: () =>
                            notifier.duplicateLayer(layer.id),
                        onMergeDown: canMerge
                            ? () => notifier.mergeLayers(layer.id)
                            : null,
                        onDelete: totalLayerCount > 1
                            ? () => notifier.deleteLayer(layer.id)
                            : null,
                        dragHandle: dragHandle(true),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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

LayerGroup? _groupOf(List<LayerItem> layerItems, String groupId) {
  for (final item in layerItems) {
    if (item is LayerGroup && item.id == groupId) return item;
  }
  return null;
}

// ─── Group row (header only) ───────────────────────────────────────────────────

class _GroupRow extends StatefulWidget {
  final LayerGroup group;
  final EditorNotifier notifier;
  final Widget dragHandle;

  /// True when the group is collapsed and the active layer is inside it.
  final bool hasActiveLayer;

  const _GroupRow({
    required super.key,
    required this.group,
    required this.notifier,
    required this.dragHandle,
    required this.hasActiveLayer,
  });

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  bool _renaming = false;
  late final TextEditingController _renameCtrl;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.group.name);
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    super.dispose();
  }

  void _startRename() {
    _renameCtrl.text = widget.group.name;
    setState(() => _renaming = true);
  }

  void _commitRename() {
    final name = _renameCtrl.text.trim();
    if (name.isNotEmpty) widget.notifier.renameGroup(widget.group.id, name);
    setState(() => _renaming = false);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final group = widget.group;
    final layerCount = group.layers.length;
    final content = layerCount == 0
        ? 'This will delete the empty group "${group.name}".'
        : 'This will delete "${group.name}" and all $layerCount layer(s) inside it.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.notifier.deleteGroup(widget.group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final notifier = widget.notifier;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: widget.hasActiveLayer
            ? Border(
                left: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.fromLTRB(widget.hasActiveLayer ? 3 : 6, 3, 2, 3),
      child: Row(
        children: [
          widget.dragHandle,
          const SizedBox(width: 2),
          // Collapse chevron
          GestureDetector(
            onTap: () => notifier.toggleGroupCollapsed(group.id),
            child: Icon(
              group.collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 2),
          // Eye toggle (group master visibility)
          GestureDetector(
            onTap: () => notifier.toggleGroupVisible(group.id),
            child: Icon(
              group.groupVisible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: group.groupVisible
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 4),
          // Group name (double-tap to rename)
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
                      group.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: group.groupVisible
                            ? null
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
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
                case _GroupAction.rename:
                  _startRename();
                case _GroupAction.addLayer:
                  notifier.addLayerToGroup(group.id);
                case _GroupAction.ungroup:
                  notifier.ungroupGroup(group.id);
                case _GroupAction.delete:
                  _confirmDelete(context);
              }
            },
            itemBuilder: (_) => [
              _groupMenuItem(
                  _GroupAction.rename, Icons.edit_outlined, 'Rename'),
              _groupMenuItem(
                  _GroupAction.addLayer, Icons.add, 'Add Layer to Group'),
              _groupMenuItem(_GroupAction.ungroup,
                  Icons.folder_open_outlined, 'Ungroup'),
              _groupMenuItem(
                _GroupAction.delete,
                Icons.delete_outline,
                'Delete Group…',
                color: Colors.red.shade600,
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_GroupAction> _groupMenuItem(
    _GroupAction value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<_GroupAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

// ─── Single layer row ──────────────────────────────────────────────────────────

class _LayerRow extends StatefulWidget {
  final Layer layer;
  final double indent;
  final bool isActive;
  final bool isBottom;
  final bool isOnly;
  final String? groupId;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<String> onRename;
  final VoidCallback onDuplicate;
  final VoidCallback? onMergeDown;
  final VoidCallback? onDelete;
  final Widget dragHandle;

  const _LayerRow({
    required super.key,
    required this.layer,
    required this.indent,
    required this.isActive,
    required this.isBottom,
    required this.isOnly,
    required this.groupId,
    required this.onTap,
    required this.onToggleVisible,
    required this.onOpacityChanged,
    required this.onRename,
    required this.onDuplicate,
    this.onMergeDown,
    this.onDelete,
    required this.dragHandle,
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

  PopupMenuItem<_LayerAction> _menuItem(
    _LayerAction value,
    IconData icon,
    String label, {
    bool enabled = true,
    Color? color,
    double iconRotation = 0,
  }) {
    final effectiveColor = enabled ? color : null;
    Widget iconWidget = Icon(icon,
        size: 16, color: effectiveColor ?? (enabled ? null : Colors.grey));
    if (iconRotation != 0) {
      iconWidget = Transform.rotate(angle: iconRotation, child: iconWidget);
    }
    return PopupMenuItem<_LayerAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          iconWidget,
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(fontSize: 13, color: effectiveColor)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final layer = widget.layer;
    final inGroup = widget.groupId != null;

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
        padding: EdgeInsets.fromLTRB(6 + widget.indent, 4, 2, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Name row ──────────────────────────────────────────────────
            Row(
              children: [
                widget.dragHandle,
                const SizedBox(width: 2),
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
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
                      case _LayerAction.duplicate:
                        widget.onDuplicate();
                      case _LayerAction.mergeDown:
                        widget.onMergeDown?.call();
                      case _LayerAction.delete:
                        widget.onDelete?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    _menuItem(
                        _LayerAction.rename, Icons.edit_outlined, 'Rename'),
                    _menuItem(
                        _LayerAction.duplicate, Icons.copy_outlined, 'Duplicate'),
                    _menuItem(
                      _LayerAction.mergeDown,
                      Icons.merge_type,
                      'Merge Down',
                      enabled: widget.onMergeDown != null,
                      iconRotation: pi,
                    ),
                    _menuItem(
                      _LayerAction.delete,
                      Icons.delete_outline,
                      'Delete Layer',
                      enabled: widget.onDelete != null,
                      color: Colors.red.shade600,
                    ),
                  ],
                ),
              ],
            ),
            // ── Opacity slider ─────────────────────────────────────────────
            Row(
              children: [
                SizedBox(width: 20 + widget.indent),
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

enum _GroupAction { rename, addLayer, ungroup, delete }
