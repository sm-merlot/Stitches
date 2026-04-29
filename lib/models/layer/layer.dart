import 'package:uuid/uuid.dart';
import '../cell.dart';
import 'layer_blend_mode.dart';
import '../stitch/stitch.dart';
import '../stitch/stitch_geometry.dart';

class Layer {
  final String id;
  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final LayerBlendMode blendMode;
  final List<Stitch> stitches;

  // Lazily-built index for O(1) per-cell lookup.
  // Safe as a mutable field on an otherwise-immutable value object because:
  // - [stitches] is final; the index is always consistent with it.
  // - [copyWith] creates a fresh [Layer], so the new instance starts with
  //   [_cellIndex] == null and rebuilds on first access.
  Map<Cell, List<Stitch>>? _cellIndex;

  Layer({
    required this.id,
    required this.name,
    required this.visible,
    this.locked = false,
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
    bool? locked,
    double? opacity,
    LayerBlendMode? blendMode,
    List<Stitch>? stitches,
  }) {
    return Layer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      stitches: stitches ?? this.stitches,
    );
  }

  /// Returns all stitches at cell ([x],[y]).
  ///
  /// Uses a lazily-built per-instance index so repeated lookups on the same
  /// [Layer] are O(1) after the first call. BackStitch is excluded from the
  /// index (it has no single cell coordinate) and is never returned here.
  List<Stitch> stitchesAt(int x, int y) {
    _cellIndex ??= _buildCellIndex();
    return _cellIndex![Cell(x, y)] ?? const [];
  }

  Map<Cell, List<Stitch>> _buildCellIndex() {
    final index = <Cell, List<Stitch>>{};
    for (final s in stitches) {
      final coords = s.cellCoords;
      if (coords == null) continue; // BackStitch — skip
      final key = coords;
      (index[key] ??= []).add(s);
    }
    return index;
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'visible': visible,
        if (locked) 'locked': true,
        'opacity': opacity,
        if (blendMode != LayerBlendMode.normal) 'blendMode': blendMode.yamlKey,
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      };

  factory Layer.fromYaml(Map<String, dynamic> yaml) {
    return Layer(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      visible: yaml['visible'] as bool? ?? true,
      locked: yaml['locked'] as bool? ?? false,
      opacity: (yaml['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: LayerBlendMode.fromYaml(yaml['blendMode'] as String?),
      stitches: Stitch.listFromYaml(yaml['stitches'] as List? ?? const []),
    );
  }
}
