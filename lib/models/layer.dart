import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'layer_blend_mode.dart';
import 'stitch.dart';

@immutable
class Layer {
  final String id;
  final String name;
  final bool visible;
  final double opacity;
  final LayerBlendMode blendMode;
  final List<Stitch> stitches;

  const Layer({
    required this.id,
    required this.name,
    required this.visible,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    required this.stitches,
  });

  factory Layer.create({String? name}) {
    return Layer(
      id: const Uuid().v4(),
      name: name ?? 'Layer 1',
      visible: true,
      opacity: 1.0,
      blendMode: LayerBlendMode.normal,
      stitches: const [],
    );
  }

  Layer copyWith({
    String? name,
    bool? visible,
    double? opacity,
    LayerBlendMode? blendMode,
    List<Stitch>? stitches,
  }) {
    return Layer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      stitches: stitches ?? this.stitches,
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        if (blendMode != LayerBlendMode.normal) 'blendMode': blendMode.yamlKey,
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      };

  factory Layer.fromYaml(Map<String, dynamic> yaml) {
    return Layer(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      visible: yaml['visible'] as bool? ?? true,
      opacity: (yaml['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: LayerBlendMode.fromYaml(yaml['blendMode'] as String?),
      stitches: (yaml['stitches'] as List?)
              ?.map((s) => Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [],
    );
  }
}
