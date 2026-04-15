import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/dmc_colors.dart';
import 'layer.dart';
import 'layer_item.dart';
import 'page_config.dart';
import 'pattern_progress.dart';
import 'progress_log.dart';
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

  /// Last-saved editor state — whether block mode was active.
  final bool editorBlockMode;

  /// Last-saved canvas view position. Zero values mean "use default".
  final double editorViewPanX;
  final double editorViewPanY;
  final double editorViewScale;

  /// Path to a reference image overlay (persisted with the file).
  final String? referenceImagePath;

  /// Opacity of the reference image overlay (0.0–1.0).
  final double referenceOpacity;

  /// Saved snippets belonging to this pattern.
  final List<Snippet> snippets;

  /// Stable symbol assignments for composite (blended) thread colours.
  /// Maps dmcCode → symbol. Persisted so symbols survive save/reload.
  final Map<String, String> compositeSymbols;

  /// Optional metadata fields.
  final String? designer;
  final String? description;
  final String? difficulty;
  final String? estimatedHours;
  final String? copyright;

  /// Materials suggestions: list of {aidaCount, strands} records.
  final List<({int aidaCount, int strands})> materialsSuggestions;

  /// Page mode configuration — how the pattern is split into pages.
  final PageConfig pageConfig;

  /// Progress tracking — which stitches and pages the user has physically done.
  final PatternProgress progress;

  /// StitchOps daily progress log.  Each entry is a date → high-watermark
  /// cumulative count.  Stored at the pattern level (not inside progress) so
  /// it is NOT affected by undo/redo operations.
  final List<ProgressLogEntry> progressLog;

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
    this.editorBlockMode = true,
    this.editorViewPanX = 0,
    this.editorViewPanY = 0,
    this.editorViewScale = 0,
    this.referenceImagePath,
    this.referenceOpacity = 0.5,
    this.snippets = const [],
    this.compositeSymbols = const {},
    this.designer,
    this.description,
    this.difficulty,
    this.estimatedHours,
    this.copyright,
    this.materialsSuggestions = const [],
    this.pageConfig = PageConfig.disabled,
    this.progress = PatternProgress.empty,
    this.progressLog = const [],
  });

  /// Flattened list of all layers, applying group visibility overrides.
  /// - groupVisible = true → each layer keeps its own visible flag
  /// - groupVisible = false → each layer is forced to visible: false
  /// All rendering consumers use this getter; no rendering code needs updating.
  List<Layer> get layers => layerItems.expand((item) => switch (item) {
        LayerLeaf(:final layer) => [layer],
        LayerGroup(:final groupVisible, :final groupLocked, :final layers) => () {
            var ls = groupVisible
                ? layers
                : layers.map((l) => l.copyWith(visible: false)).toList();
            if (groupLocked) ls = ls.map((l) => l.copyWith(locked: true)).toList();
            return ls;
          }(),
      }).toList();

  /// Apply [fn] to every Layer in [layerItems], preserving group structure.
  CrossStitchPattern mapLayers(Layer Function(Layer) fn) => copyWith(
        layerItems: layerItems.map((item) => switch (item) {
              LayerLeaf(:final layer) => LayerLeaf(layer: fn(layer)),
              LayerGroup(:final layers, :final id, :final name,
                      :final collapsed, :final groupVisible, :final groupLocked) =>
                LayerGroup(
                  id: id,
                  name: name,
                  collapsed: collapsed,
                  groupVisible: groupVisible,
                  groupLocked: groupLocked,
                  layers: layers.map(fn).toList(),
                ),
            }).toList(),
      );

  /// Flat union of all stitches across all layers.
  List<Stitch> get stitches => layers.expand((l) => l.stitches).toList();

  /// Number of unique grid cells covered by cross-stitches (deduplicates cells
  /// that appear on multiple layers; excludes back stitches).
  int get canvasCellCount {
    final cells = <(int, int)>{};
    for (final s in stitches) {
      if (s is BackStitch) { continue; }
      if (s is FullStitch) { cells.add((s.x, s.y)); }
      else if (s is HalfStitch) { cells.add((s.x, s.y)); }
      else if (s is QuarterStitch) { cells.add((s.x, s.y)); }
      else if (s is HalfCrossStitch) { cells.add((s.x, s.y)); }
      else if (s is QuarterCrossStitch) { cells.add((s.x, s.y)); }
    }
    return cells.length;
  }

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
      editorBlockMode: true,
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
    bool? editorBlockMode,
    double? editorViewPanX,
    double? editorViewPanY,
    double? editorViewScale,
    Object? referenceImagePath = _sentinel,
    double? referenceOpacity,
    List<Snippet>? snippets,
    Object? compositeSymbols = _sentinel,
    Object? designer = _sentinel,
    Object? description = _sentinel,
    Object? difficulty = _sentinel,
    Object? estimatedHours = _sentinel,
    Object? copyright = _sentinel,
    List<({int aidaCount, int strands})>? materialsSuggestions,
    PageConfig? pageConfig,
    PatternProgress? progress,
    List<ProgressLogEntry>? progressLog,
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
      editorBlockMode: editorBlockMode ?? this.editorBlockMode,
      editorViewPanX: editorViewPanX ?? this.editorViewPanX,
      editorViewPanY: editorViewPanY ?? this.editorViewPanY,
      editorViewScale: editorViewScale ?? this.editorViewScale,
      referenceImagePath: referenceImagePath == _sentinel
          ? this.referenceImagePath
          : referenceImagePath as String?,
      referenceOpacity: referenceOpacity ?? this.referenceOpacity,
      snippets: snippets ?? this.snippets,
      compositeSymbols: compositeSymbols == _sentinel
          ? this.compositeSymbols
          : compositeSymbols as Map<String, String>,
      designer: designer == _sentinel ? this.designer : designer as String?,
      description: description == _sentinel ? this.description : description as String?,
      difficulty: difficulty == _sentinel ? this.difficulty : difficulty as String?,
      estimatedHours: estimatedHours == _sentinel ? this.estimatedHours : estimatedHours as String?,
      copyright: copyright == _sentinel ? this.copyright : copyright as String?,
      materialsSuggestions: materialsSuggestions ?? this.materialsSuggestions,
      pageConfig: pageConfig ?? this.pageConfig,
      progress: progress ?? this.progress,
      progressLog: progressLog ?? this.progressLog,
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
    final version = yaml['version'] as int?;
    if (version == 2) {
      final patternInfoMap = yaml['patternInfo'] != null
          ? Map<String, dynamic>.from(yaml['patternInfo'] as Map)
          : <String, dynamic>{};
      final patternMap =
          Map<String, dynamic>.from(yaml['pattern'] as Map? ?? {});
      final stitchingMap = yaml['stitching'] != null
          ? Map<String, dynamic>.from(yaml['stitching'] as Map)
          : <String, dynamic>{};
      // Flatten v2 nested structure into the same shape _fromFlat expects.
      final flat = <String, dynamic>{
        ...patternInfoMap,
        ...patternMap,
        'pageMode': stitchingMap['pageMode'],
        'progress': stitchingMap['progress'],
        'progressLog': stitchingMap['progressLog'],
      };
      return _migrateDiscontinuedThreads(_fromFlat(flat));
    }
    return _migrateDiscontinuedThreads(_fromFlat(yaml));
  }

  static CrossStitchPattern _fromFlat(Map<String, dynamic> yaml) {
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
            groupLocked: m['groupLocked'] as bool? ?? false,
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

    final parsed = CrossStitchPattern(
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      aidaColor: aidaHex != null ? _parseHex(aidaHex) : Colors.white,
      editorSelectedThreadId: editor?['selectedThread'] as String?,
      editorTool: editor?['tool'] as String?,
      editorStitchMode: editor?['stitchMode'] as bool? ?? false,
      editorActiveLayerId: editor?['activeLayer'] as String?,
      editorBlockMode: editor?['blockMode'] as bool? ?? true,
      editorViewPanX: (editor?['panX'] as num?)?.toDouble() ?? 0,
      editorViewPanY: (editor?['panY'] as num?)?.toDouble() ?? 0,
      editorViewScale: (editor?['scale'] as num?)?.toDouble() ?? 0,
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
      designer: yaml['designer'] as String?,
      description: yaml['description'] as String?,
      difficulty: yaml['difficulty'] as String?,
      estimatedHours: yaml['estimatedHours'] as String?,
      copyright: yaml['copyright'] as String?,
      materialsSuggestions: (yaml['materialsSuggestions'] as List? ?? [])
          .map((e) => (aidaCount: e['aidaCount'] as int, strands: e['strands'] as int))
          .toList(),
      pageConfig: yaml['pageMode'] != null
          ? PageConfig.fromYaml(yaml['pageMode'] as Map)
          : PageConfig.disabled,
      progress: yaml['progress'] != null
          ? PatternProgress.fromYaml(yaml['progress'] as Map)
          : PatternProgress.empty,
      progressLog: (yaml['progressLog'] as List?)
              ?.map((e) =>
                  ProgressLogEntry.fromYaml(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
    return parsed;
  }

  /// Remaps any discontinued DMC thread codes in [p] to their replacements.
  ///
  /// Applied automatically on [fromYaml] so that patterns created with old
  /// thread codes are transparently upgraded on load without touching the file.
  ///
  /// - Thread objects are updated to the replacement code/color/name; the
  ///   user's symbol assignment is preserved.
  /// - If the replacement already exists in the palette the discontinued entry
  ///   is dropped and its stitches are remapped to the existing replacement.
  /// - All stitches across layers, snippets, and palette threads are updated.
  static CrossStitchPattern _migrateDiscontinuedThreads(CrossStitchPattern p) {
    // Build remap table for discontinued codes anywhere in this pattern:
    // top-level threads, snippet palette threads, and raw stitch references.
    final remaps = <String, String>{};
    void checkCode(String code) {
      final newCode = dmcReplacements[code];
      // Skip empty-string placeholders (replacement TBD — don't auto-migrate yet).
      if (newCode != null && newCode.isNotEmpty) remaps[code] = newCode;
    }
    for (final t in p.threads) { checkCode(t.dmcCode); }
    for (final snippet in p.snippets) {
      for (final pal in snippet.palettes) {
        for (final t in pal.threads) { checkCode(t.dmcCode); }
      }
      for (final s in snippet.stitches) { checkCode(s.threadId); }
    }
    for (final s in p.stitches) { checkCode(s.threadId); }
    if (remaps.isEmpty) return p;

    List<Stitch> remapStitches(List<Stitch> stitches) => stitches
        .map((s) {
          final newId = remaps[s.threadId];
          return newId != null ? s.withThreadId(newId) : s;
        })
        .toList();

    // Remap pattern-level threads; deduplicate if replacement already present.
    final existingCodes = p.threads.map((t) => t.dmcCode).toSet();
    final newThreads = <Thread>[];
    for (final t in p.threads) {
      final newCode = remaps[t.dmcCode];
      if (newCode == null) {
        newThreads.add(t);
      } else if (existingCodes.contains(newCode)) {
        // Replacement already in palette — drop discontinued entry; stitches
        // will be remapped to the existing replacement thread below.
      } else {
        final dmcColor = dmcColorByCode(newCode);
        newThreads.add(Thread(
          dmcCode: newCode,
          color: dmcColor?.color ?? t.color,
          name: dmcColor?.name ?? t.name,
          symbol: t.symbol, // preserve user-assigned symbol
        ));
      }
    }

    // Remap stitches in all layers.
    final withRemappedLayers = p.mapLayers(
      (layer) => layer.copyWith(stitches: remapStitches(layer.stitches)),
    );

    // Remap snippet palette threads and stitches.
    final newSnippets = p.snippets.map((snippet) {
      return snippet.copyWith(
        stitches: remapStitches(snippet.stitches),
        palettes: snippet.palettes.map((pal) {
          final palCodes = pal.threads.map((t) => t.dmcCode).toSet();
          final updatedThreads = pal.threads
              .where((t) {
                final newCode = remaps[t.dmcCode];
                // Drop discontinued thread only when its replacement is already present.
                return newCode == null || !palCodes.contains(newCode);
              })
              .map((t) {
                final newCode = remaps[t.dmcCode];
                if (newCode == null) return t;
                final dmcColor = dmcColorByCode(newCode);
                return t.copyWith(
                  dmcCode: newCode,
                  color: dmcColor?.color,
                  name: dmcColor?.name,
                );
              })
              .toList();
          return pal.copyWith(threads: updatedThreads);
        }).toList(),
      );
    }).toList();

    // Remap selected-thread editor state.
    final selId = p.editorSelectedThreadId;
    final newSelId = selId != null ? (remaps[selId] ?? selId) : null;

    return withRemappedLayers.copyWith(
      threads: newThreads,
      snippets: newSnippets,
      editorSelectedThreadId: newSelId,
    );
  }
}
