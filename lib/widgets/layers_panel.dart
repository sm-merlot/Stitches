import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
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
                buildDefaultDragHandles: false,
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
                    dragHandle: ReorderableDragStartListener(
                      index: visualIndex,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(
                          Icons.drag_handle,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ),
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
  final Layer layer;
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
  final Widget? dragHandle;

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
                // Drag handle — leftmost, separated from ⋮ menu on the right
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
