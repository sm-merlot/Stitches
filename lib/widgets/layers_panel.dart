import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
import '../models/layer_item.dart';
import '../providers/editor/editor_provider.dart';

part 'layers_panel_helpers.dart';
part 'layers_panel_rows.dart';

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
