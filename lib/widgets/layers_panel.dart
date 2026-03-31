import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_item.dart';
import '../providers/editor/editor_provider.dart';

part 'layers_panel_helpers.dart';
part 'layers_panel_rows.dart';

/// The inner content of the layers panel (header + list).
/// Used by [LayersPanel] and directly by [RightSidebar].
class LayersPanelBody extends ConsumerWidget {
  const LayersPanelBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final layerItems = state.pattern.layerItems;
    final totalLayerCount = state.pattern.layers.length;

    // Build flat display list (top to bottom, mirroring panel order).
    final flatItems = _buildFlatItems(layerItems);

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              itemCount: flatItems.length + 1, // +1 for add-buttons row
              itemBuilder: (context, index) {
                // Last item: add-buttons row (not draggable).
                if (index == flatItems.length) {
                  return Padding(
                    key: const ValueKey('__add_buttons__'),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('Layer', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          ),
                          onPressed: notifier.addLayer,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.create_new_folder_outlined, size: 15),
                          label: const Text('Group', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          ),
                          onPressed: notifier.addGroup,
                        ),
                      ],
                    ),
                  );
                }

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
                      group.layers.any((l) => l.id == state.activeLayerId);
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
                  onToggleLocked: () =>
                      notifier.toggleLayerLocked(layer.id),
                  onOpacityChanged: (v) =>
                      notifier.setLayerOpacity(layer.id, v),
                  onBlendModeChanged: (m) =>
                      notifier.setLayerBlendMode(layer.id, m),
                  onRename: (name) => notifier.renameLayer(layer.id, name),
                  onDuplicate: () => notifier.duplicateLayer(layer.id),
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
    );
  }
}

/// Resizable right-side panel that lists the pattern's layers.
/// Visible only in design mode; returns [SizedBox.shrink] in stitch mode.
/// When the right sidebar is used, [LayersPanelBody] is hosted there directly
/// and this standalone widget is not shown.
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

    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag-to-resize handle on the left edge of the panel
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _width =
                    (_width - details.delta.dx).clamp(_minWidth, _maxWidth);
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
          child: const LayersPanelBody(),
        ),
      ],
    );
  }
}
