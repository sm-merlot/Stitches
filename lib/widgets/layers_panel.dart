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
                // Displayed top-to-bottom: visually topmost item first.
                // layerItems[last] = top, layerItems[0] = bottom.
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    onReorder: (vOld, vNew) {
                      final count = layerItems.length;
                      final lOld = count - 1 - vOld;
                      final lNew = count - 1 - vNew;
                      if (lOld != lNew) {
                        notifier.reorderTopLevel(lOld, lNew);
                      }
                    },
                    itemCount: layerItems.length,
                    itemBuilder: (context, visualIndex) {
                      // Visual index 0 = topmost item (layerItems.last)
                      final layerIndex = layerItems.length - 1 - visualIndex;
                      final item = layerItems[layerIndex];

                      final dragHandle = ReorderableDragStartListener(
                        index: visualIndex,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      );

                      if (item is LayerLeaf) {
                        final layer = item.layer;
                        return _LayerRow(
                          key: ValueKey(layer.id),
                          layer: layer,
                          indent: 0,
                          isActive: layer.id == state.activeLayerId,
                          isBottom: layerIndex == 0,
                          isOnly: totalLayerCount == 1,
                          groupId: null,
                          onTap: () => notifier.setActiveLayer(layer.id),
                          onToggleVisible: () =>
                              notifier.toggleLayerVisible(layer.id),
                          onOpacityChanged: (v) =>
                              notifier.setLayerOpacity(layer.id, v),
                          onRename: (name) =>
                              notifier.renameLayer(layer.id, name),
                          onMoveUp: layerIndex < layerItems.length - 1
                              ? () => notifier.moveLayer(layer.id, 1)
                              : null,
                          onMoveDown: layerIndex > 0
                              ? () => notifier.moveLayer(layer.id, -1)
                              : null,
                          onDuplicate: () =>
                              notifier.duplicateLayer(layer.id),
                          onMergeDown: layerIndex > 0
                              ? () => notifier.mergeLayers(layer.id)
                              : null,
                          onMoveOutOfGroup: null,
                          onDelete: totalLayerCount > 1
                              ? () => notifier.deleteLayer(layer.id)
                              : null,
                          dragHandle: dragHandle,
                        );
                      } else {
                        final group = item as LayerGroup;
                        return _GroupRow(
                          key: ValueKey(group.id),
                          group: group,
                          state: state,
                          notifier: notifier,
                          totalLayerCount: totalLayerCount,
                          dragHandle: dragHandle,
                        );
                      }
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

// ─── Group row ─────────────────────────────────────────────────────────────────

class _GroupRow extends StatefulWidget {
  final LayerGroup group;
  final EditorState state;
  final EditorNotifier notifier;
  final int totalLayerCount;
  final Widget dragHandle;

  const _GroupRow({
    required super.key,
    required this.group,
    required this.state,
    required this.notifier,
    required this.totalLayerCount,
    required this.dragHandle,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
            'This will delete "${widget.group.name}" and all ${widget.group.layers.length} layer(s) inside it.'),
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
    final layers = group.layers;
    final notifier = widget.notifier;
    final state = widget.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Group header row ───────────────────────────────────────────────
        Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          padding: const EdgeInsets.fromLTRB(6, 3, 2, 3),
          child: Row(
            children: [
              widget.dragHandle,
              const SizedBox(width: 2),
              // Collapse chevron
              GestureDetector(
                onTap: () => notifier.toggleGroupCollapsed(group.id),
                child: Icon(
                  group.collapsed
                      ? Icons.chevron_right
                      : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 2),
              // Eye toggle (group master visibility)
              GestureDetector(
                onTap: () => notifier.toggleGroupVisible(group.id),
                child: Icon(
                  group.groupVisible
                      ? Icons.visibility
                      : Icons.visibility_off,
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
                      // Set active to a layer inside this group so addLayer
                      // inserts within the group (per EditorNotifier.addLayer logic).
                      if (layers.isNotEmpty) {
                        notifier.setActiveLayer(layers.last.id);
                      }
                      notifier.addLayer();
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
                  _groupMenuItem(_GroupAction.ungroup, Icons.folder_open_outlined,
                      'Ungroup'),
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
        ),
        // ── Group's layers (hidden when collapsed) ─────────────────────────
        if (!group.collapsed)
          for (int i = layers.length - 1; i >= 0; i--)
            _LayerRow(
              key: ValueKey(layers[i].id),
              layer: layers[i],
              indent: 12,
              isActive: layers[i].id == state.activeLayerId,
              isBottom: false,
              isOnly: widget.totalLayerCount == 1,
              groupId: group.id,
              onTap: () => notifier.setActiveLayer(layers[i].id),
              onToggleVisible: () =>
                  notifier.toggleLayerVisible(layers[i].id),
              onOpacityChanged: (v) =>
                  notifier.setLayerOpacity(layers[i].id, v),
              onRename: (name) => notifier.renameLayer(layers[i].id, name),
              onMoveUp: i < layers.length - 1
                  ? () => notifier.reorderWithinGroup(
                      group.id, i, i + 1)
                  : null,
              onMoveDown: i > 0
                  ? () => notifier.reorderWithinGroup(
                      group.id, i, i - 1)
                  : null,
              onDuplicate: () => notifier.duplicateLayer(layers[i].id),
              onMergeDown: i > 0
                  ? () => notifier.mergeLayers(layers[i].id)
                  : null,
              onMoveOutOfGroup: () => notifier.moveLayerOutOfGroup(
                  layers[i].id, group.id),
              onDelete: widget.totalLayerCount > 1
                  ? () => notifier.deleteLayer(layers[i].id)
                  : null,
              dragHandle: null,
            ),
      ],
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
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDuplicate;
  final VoidCallback? onMergeDown;
  final VoidCallback? onMoveOutOfGroup;
  final VoidCallback? onDelete;
  final Widget? dragHandle;

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
    this.onMoveUp,
    this.onMoveDown,
    required this.onDuplicate,
    this.onMergeDown,
    this.onMoveOutOfGroup,
    this.onDelete,
    this.dragHandle,
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
  }) {
    final effectiveColor = enabled ? color : null;
    return PopupMenuItem<_LayerAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: effectiveColor ??
                  (enabled ? null : Colors.grey)),
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
                if (widget.dragHandle != null) widget.dragHandle!,
                if (widget.dragHandle != null) const SizedBox(width: 2),
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
                      case _LayerAction.moveUp:
                        widget.onMoveUp?.call();
                      case _LayerAction.moveDown:
                        widget.onMoveDown?.call();
                      case _LayerAction.duplicate:
                        widget.onDuplicate();
                      case _LayerAction.mergeDown:
                        widget.onMergeDown?.call();
                      case _LayerAction.moveOutOfGroup:
                        widget.onMoveOutOfGroup?.call();
                      case _LayerAction.delete:
                        widget.onDelete?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    _menuItem(
                        _LayerAction.rename, Icons.edit_outlined, 'Rename'),
                    _menuItem(
                      _LayerAction.moveUp,
                      Icons.arrow_upward,
                      'Move Up',
                      enabled: widget.onMoveUp != null,
                    ),
                    _menuItem(
                      _LayerAction.moveDown,
                      Icons.arrow_downward,
                      'Move Down',
                      enabled: widget.onMoveDown != null,
                    ),
                    _menuItem(
                        _LayerAction.duplicate, Icons.copy_outlined, 'Duplicate'),
                    _menuItem(
                      _LayerAction.mergeDown,
                      Icons.merge_type,
                      'Merge Down',
                      enabled: widget.onMergeDown != null,
                    ),
                    if (inGroup)
                      _menuItem(
                        _LayerAction.moveOutOfGroup,
                        Icons.drive_file_move_outlined,
                        'Move Out of Group',
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

enum _LayerAction {
  rename,
  moveUp,
  moveDown,
  duplicate,
  mergeDown,
  moveOutOfGroup,
  delete
}

enum _GroupAction { rename, addLayer, ungroup, delete }
