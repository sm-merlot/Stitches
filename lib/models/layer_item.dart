import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'layer.dart';

/// A sealed class representing either a bare layer or a named group of layers.
@immutable
sealed class LayerItem {
  const LayerItem();
}

/// A single layer with no group membership.
@immutable
class LayerLeaf extends LayerItem {
  final Layer layer;

  const LayerLeaf({required this.layer});

  LayerLeaf copyWith({Layer? layer}) => LayerLeaf(layer: layer ?? this.layer);
}

/// A named group containing an ordered list of layers.
@immutable
class LayerGroup extends LayerItem {
  final String id;
  final String name;

  /// Whether the group is folded in the layers panel (persisted).
  final bool collapsed;

  /// Master visibility override — when false, all layers in the group are hidden.
  final bool groupVisible;

  /// Ordered top-to-bottom within the group.
  final List<Layer> layers;

  const LayerGroup({
    required this.id,
    required this.name,
    required this.collapsed,
    required this.groupVisible,
    required this.layers,
  });

  factory LayerGroup.create({String? name}) {
    final newLayer = Layer.create(name: 'Layer 1');
    return LayerGroup(
      id: const Uuid().v4(),
      name: name ?? 'Group',
      collapsed: false,
      groupVisible: true,
      layers: [newLayer],
    );
  }

  LayerGroup copyWith({
    String? name,
    bool? collapsed,
    bool? groupVisible,
    List<Layer>? layers,
  }) {
    return LayerGroup(
      id: id,
      name: name ?? this.name,
      collapsed: collapsed ?? this.collapsed,
      groupVisible: groupVisible ?? this.groupVisible,
      layers: layers ?? this.layers,
    );
  }
}
