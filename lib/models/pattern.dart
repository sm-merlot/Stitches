import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'layer.dart';
import 'layer_item.dart';
import 'snippet.dart';
import 'stitch.dart';
import 'thread.dart';

class CrossStitchPattern {
  final String name;
  final int width;
  final int height;
  final List<Thread> threads;
  final List<LayerItem> layerItems;
  final Color aidaColor;

  /// Last-saved editor state — which thread was active.
  final String? editorSelectedThreadId;

  /// Last-saved editor state — which tool was active (DrawingTool.name).
  final String? editorTool;

  /// Last-saved editor state — whether stitch mode was active.
  final bool editorStitchMode;

  /// Last-saved editor state — which layer was active.
  final String? editorActiveLayerId;

  /// Path to a reference image overlay (persisted with the file).
  final String? referenceImagePath;

  /// Opacity of the reference image overlay (0.0–1.0).
  final double referenceOpacity;

  /// Saved snippets belonging to this pattern.
  final List<Snippet> snippets;

  /// Stable symbol assignments for composite (blended) thread colours.
  /// Maps dmcCode → symbol. Persisted so symbols survive save/reload.
  final Map<String, String> compositeSymbols;

  const CrossStitchPattern({
    required this.name,
    required this.width,
    required this.height,
    required this.threads,
    required this.layerItems,
    this.aidaColor = Colors.white,
    this.editorSelectedThreadId,
    this.editorTool,
    this.editorStitchMode = false,
    this.editorActiveLayerId,
    this.referenceImagePath,
    this.referenceOpacity = 0.5,
    this.snippets = const [],
    this.compositeSymbols = const {},
  });

  /// Flattened list of all layers, applying group visibility overrides.
  /// - groupVisible = true → each layer keeps its own visible flag
  /// - groupVisible = false → each layer is forced to visible: false
  /// All rendering consumers use this getter; no rendering code needs updating.
  List<Layer> get layers => layerItems.expand((item) => switch (item) {
        LayerLeaf(:final layer) => [layer],
        LayerGroup(:final groupVisible, :final layers) => groupVisible
            ? layers
            : layers.map((l) => l.copyWith(visible: false)).toList(),
      }).toList();

  /// Apply [fn] to every Layer in [layerItems], preserving group structure.
  CrossStitchPattern mapLayers(Layer Function(Layer) fn) => copyWith(
        layerItems: layerItems.map((item) => switch (item) {
              LayerLeaf(:final layer) => LayerLeaf(layer: fn(layer)),
              LayerGroup(:final layers, :final id, :final name,
                      :final collapsed, :final groupVisible) =>
                LayerGroup(
                  id: id,
                  name: name,
                  collapsed: collapsed,
                  groupVisible: groupVisible,
                  layers: layers.map(fn).toList(),
                ),
            }).toList(),
      );

  /// Flat union of all stitches across all layers.
  List<Stitch> get stitches => layers.expand((l) => l.stitches).toList();

  factory CrossStitchPattern.empty({
    String name = 'New Pattern',
    int width = 30,
    int height = 30,
  }) {
    final defaultLayer = Layer.create(name: 'Layer 1');
    return CrossStitchPattern(
      name: name,
      width: width,
      height: height,
      threads: const [
        Thread(dmcCode: '310', color: Color(0xFF000000), name: 'Black'),
      ],
      layerItems: [LayerLeaf(layer: defaultLayer)],
      editorSelectedThreadId: '310',
      editorActiveLayerId: defaultLayer.id,
    );
  }

  CrossStitchPattern copyWith({
    String? name,
    int? width,
    int? height,
    List<Thread>? threads,
    List<LayerItem>? layerItems,
    Color? aidaColor,
    Object? editorSelectedThreadId = _sentinel,
    Object? editorTool = _sentinel,
    bool? editorStitchMode,
    Object? editorActiveLayerId = _sentinel,
    Object? referenceImagePath = _sentinel,
    double? referenceOpacity,
    List<Snippet>? snippets,
    Object? compositeSymbols = _sentinel,
  }) {
    return CrossStitchPattern(
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      threads: threads ?? this.threads,
      layerItems: layerItems ?? this.layerItems,
      aidaColor: aidaColor ?? this.aidaColor,
      editorSelectedThreadId: editorSelectedThreadId == _sentinel
          ? this.editorSelectedThreadId
          : editorSelectedThreadId as String?,
      editorTool: editorTool == _sentinel
          ? this.editorTool
          : editorTool as String?,
      editorStitchMode: editorStitchMode ?? this.editorStitchMode,
      editorActiveLayerId: editorActiveLayerId == _sentinel
          ? this.editorActiveLayerId
          : editorActiveLayerId as String?,
      referenceImagePath: referenceImagePath == _sentinel
          ? this.referenceImagePath
          : referenceImagePath as String?,
      referenceOpacity: referenceOpacity ?? this.referenceOpacity,
      snippets: snippets ?? this.snippets,
      compositeSymbols: compositeSymbols == _sentinel
          ? this.compositeSymbols
          : compositeSymbols as Map<String, String>,
    );
  }

  static const _sentinel = Object();

  Thread? threadByCode(String dmcCode) {
    return threads.where((t) => t.dmcCode == dmcCode).firstOrNull;
  }

  /// Hex string representation of [aidaColor], e.g. `'#FFFFFF'`.
  String get aidaColorHex {
    final argb = aidaColor.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color _parseHex(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    return Color(int.parse('FF$h', radix: 16));
  }

  factory CrossStitchPattern.fromYaml(Map<String, dynamic> yaml) {
    final editor = yaml['editor'] as Map?;
    final aidaHex = yaml['aidaColor'] as String?;

    // ── LayerItem migration (3-way) ───────────────────────────────────────────
    // 1. New format: 'layerItems:' key → parse directly.
    // 2. Legacy v2:  'layers:' key → wrap each Layer in a LayerLeaf.
    // 3. Legacy v1:  'stitches:' key only → single Layer wrapped in LayerLeaf.
    final layerItemsYaml = yaml['layerItems'] as List?;
    final layersYaml = yaml['layers'] as List?;
    final stitchesYaml = yaml['stitches'] as List?;

    final List<LayerItem> layerItems;
    if (layerItemsYaml != null) {
      layerItems = layerItemsYaml.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        if (m['type'] == 'group') {
          final innerLayers = (m['layers'] as List?)
                  ?.map((l) =>
                      Layer.fromYaml(Map<String, dynamic>.from(l as Map)))
                  .toList() ??
              [];
          return LayerGroup(
            id: m['id'] as String,
            name: m['name'] as String,
            collapsed: m['collapsed'] as bool? ?? false,
            groupVisible: m['groupVisible'] as bool? ?? true,
            layers: innerLayers,
          );
        } else {
          return LayerLeaf(layer: Layer.fromYaml(m));
        }
      }).toList();
    } else if (layersYaml != null) {
      // Migration from v2 layers: key
      layerItems = layersYaml
          .map((l) => LayerLeaf(
              layer:
                  Layer.fromYaml(Map<String, dynamic>.from(l as Map))))
          .toList();
    } else {
      // Migration from v1 flat stitches
      final stitches = stitchesYaml
              ?.map((s) =>
                  Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [];
      layerItems = [
        LayerLeaf(
          layer: Layer(
            id: const Uuid().v4(),
            name: 'Layer 1',
            visible: true,
            opacity: 1.0,
            stitches: stitches,
          ),
        ),
      ];
    }

    return CrossStitchPattern(
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      aidaColor: aidaHex != null ? _parseHex(aidaHex) : Colors.white,
      editorSelectedThreadId: editor?['selectedThread'] as String?,
      editorTool: editor?['tool'] as String?,
      editorStitchMode: editor?['stitchMode'] as bool? ?? false,
      editorActiveLayerId: editor?['activeLayer'] as String?,
      referenceImagePath: yaml['overlay']?['imagePath'] as String?,
      referenceOpacity:
          (yaml['overlay']?['opacity'] as num?)?.toDouble() ?? 0.5,
      threads: (yaml['threads'] as List?)
              ?.map((t) =>
                  Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
      layerItems: layerItems,
      snippets: (yaml['snippets'] as List?)
              ?.map((s) =>
                  Snippet.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [],
      compositeSymbols: () {
        final raw = yaml['compositeSymbols'];
        if (raw == null) return const <String, String>{};
        return Map<String, String>.from(raw as Map);
      }(),
    );
  }
}
