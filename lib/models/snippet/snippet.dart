import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'snippet_palette.dart';
import '../stitch/stitch.dart';
import '../thread.dart';

@immutable
class Snippet {
  final String id;
  final String name;
  final int width;
  final int height;
  final List<Stitch> stitches;
  final List<SnippetPalette> palettes;
  final int activePaletteIndex;

  /// Original source colours from a sprite import, stored for comparison only.
  /// Never used for stitch rendering. Null for non-sprite-imported snippets.
  final SnippetPalette? sourcePalette;

  const Snippet({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.stitches,
    required this.palettes,
    this.activePaletteIndex = 0,
    this.sourcePalette,
  });

  /// Backward-compatible getter: returns the primary palette's thread list.
  List<Thread> get threads => palettes.isNotEmpty ? palettes[0].threads : const [];

  factory Snippet.create({
    required String name,
    required int width,
    required int height,
    List<Thread> threads = const [],
    List<Stitch> stitches = const [],
  }) {
    return Snippet(
      id: const Uuid().v4(),
      name: name,
      width: width,
      height: height,
      stitches: stitches,
      palettes: [
        SnippetPalette.create(name: 'Palette 1', threads: threads),
      ],
      activePaletteIndex: 0,
    );
  }

  Snippet copyWith({
    String? name,
    int? width,
    int? height,
    List<Stitch>? stitches,
    List<SnippetPalette>? palettes,
    int? activePaletteIndex,
    SnippetPalette? sourcePalette,
    bool clearSourcePalette = false,
  }) {
    return Snippet(
      id: id,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      stitches: stitches ?? this.stitches,
      palettes: palettes ?? this.palettes,
      activePaletteIndex: activePaletteIndex ?? this.activePaletteIndex,
      sourcePalette: clearSourcePalette ? null : (sourcePalette ?? this.sourcePalette),
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'activePalette': activePaletteIndex,
        'stitches': stitches.map((s) => s.toYaml()).toList(),
        'palettes': palettes.map((p) => p.toYaml()).toList(),
        if (sourcePalette != null) 'sourcePalette': sourcePalette!.toYaml(),
      };

  factory Snippet.fromYaml(Map<String, dynamic> yaml) {
    // ── Palette migration ──────────────────────────────────────────────────
    // New format: 'palettes:' key present.
    // Old format: 'threads:' key only → wrap in a single SnippetPalette.
    final palettesYaml = yaml['palettes'] as List?;
    final threadsYaml = yaml['threads'] as List?;

    final List<SnippetPalette> palettes;
    if (palettesYaml != null) {
      palettes = palettesYaml
          .map((p) =>
              SnippetPalette.fromYaml(Map<String, dynamic>.from(p as Map)))
          .toList();
    } else {
      final threads = threadsYaml
              ?.map((t) =>
                  Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          <Thread>[];
      palettes = [
        SnippetPalette(
          id: const Uuid().v4(),
          name: 'Palette 1',
          threads: threads,
        ),
      ];
    }

    // Ensure at least 1 palette
    final safePalettes =
        palettes.isNotEmpty ? palettes : [SnippetPalette.create()];

    final sourcePaletteYaml = yaml['sourcePalette'] as Map?;

    return Snippet(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      activePaletteIndex: (yaml['activePalette'] as int?) ?? 0,
      stitches: Stitch.listFromYaml(yaml['stitches'] as List? ?? const []),
      palettes: safePalettes,
      sourcePalette: sourcePaletteYaml != null
          ? SnippetPalette.fromYaml(Map<String, dynamic>.from(sourcePaletteYaml))
          : null,
    );
  }

  /// Parses a YAML list into a [List<Snippet>].
  static List<Snippet> listFromYaml(List<dynamic> yaml) =>
      yaml.map((s) => Snippet.fromYaml(Map<String, dynamic>.from(s as Map))).toList();
}
