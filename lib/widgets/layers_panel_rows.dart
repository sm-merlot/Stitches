part of 'layers_panel.dart';

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
  final ValueChanged<LayerBlendMode> onBlendModeChanged;
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
    required this.onBlendModeChanged,
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
            // ── Opacity slider + blend mode ────────────────────────────────
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
                      divisions: 20,
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
                const SizedBox(width: 4),
                DropdownButton<LayerBlendMode>(
                  value: layer.blendMode,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: LayerBlendMode.values
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.displayName),
                          ))
                      .toList(),
                  onChanged: (m) {
                    if (m != null) widget.onBlendModeChanged(m);
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
