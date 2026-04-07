import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:yaml/yaml.dart';
import '../models/layer.dart';
import 'pattern_cache.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_item.dart';
import '../models/page_config.dart';
import '../models/pattern.dart';
import '../models/snippet.dart';
import 'format_service.dart';

class FileService {
  static const String _ext = 'stitches';

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const List<String> _openExtensions = [_ext, 'oxs'];

  /// Pick a .stitches or .oxs file; returns (pattern, filePath, wasCompressed), or null if cancelled.
  static Future<(CrossStitchPattern, String, bool)?> openFile() async {
    final result = await FilePicker.pickFiles(
      type: _isMobile ? FileType.any : FileType.custom,
      allowedExtensions: _isMobile ? null : _openExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    return openFileFromPath(path);
  }

  /// Load a pattern directly from a known file path.
  /// Supports both .stitches (YAML) and .oxs (XML) formats.
  /// Returns (pattern, filePath, wasCompressed).
  ///
  /// Checks [PatternCache] first; if the file is unchanged since it was last
  /// cached the parse is skipped entirely.  Otherwise the decompression and
  /// YAML parsing run in a background isolate so the UI thread stays free.
  static Future<(CrossStitchPattern, String, bool)> openFileFromPath(
      String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('File not found: $path');
    if (path.toLowerCase().endsWith('.oxs')) {
      final pattern = await FormatService.importFile(path);
      return (pattern, path, false);
    }

    // Cache hit — skip disk read and parse entirely.
    final cached = await PatternCache.get(path);
    if (cached != null) {
      final (pattern, wasCompressed) = cached;
      return (pattern, path, wasCompressed);
    }

    final bytes = await file.readAsBytes();
    final (pattern, wasCompressed) =
        await Isolate.run(() => _parseBytesToPattern(bytes));

    // Populate cache; stat is cheap after readAsBytes.
    final stat = await file.stat();
    PatternCache.put(path, pattern, wasCompressed, stat.modified);

    return (pattern, path, wasCompressed);
  }

  /// Parse raw bytes (possibly gzip-compressed) into a pattern in a background
  /// isolate.  Used by Drive refresh logic to avoid a cache-miss window between
  /// the file write and the subsequent re-parse.
  static Future<(CrossStitchPattern, bool)> parseBytesToPattern(Uint8List bytes) =>
      Isolate.run(() => _parseBytesToPattern(bytes));

  /// Runs in a background isolate: decompress + decode + parse the raw bytes.
  static (CrossStitchPattern, bool) _parseBytesToPattern(Uint8List bytes) {
    final wasCompressed =
        bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    final content = _decodeBytes(_maybeDecompress(bytes));
    return (parseYamlString(content), wasCompressed);
  }

  /// Decompress gzip bytes if the gzip magic bytes (1f 8b) are present.
  static List<int> _maybeDecompress(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return gzip.decode(bytes);
    }
    return bytes;
  }

  /// Decode file bytes as UTF-8, stripping a BOM if present.
  /// Falls back to latin1 for files with non-UTF-8 byte sequences.
  static String _decodeBytes(List<int> bytes) {
    // Strip UTF-8 BOM (EF BB BF) if present.
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Open a known directory path and return all .stitches file paths within it.
  static Future<List<String>> openFolderFromPath(String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) throw Exception('Folder not found: $dir');
    final files = await directory
        .list(recursive: false)
        .where((e) => e is File && e.path.endsWith('.$_ext'))
        .map((e) => e.path)
        .toList();
    files.sort();
    return files;
  }

  /// Pick a directory and return all .stitches file paths within it, or null if cancelled.
  static Future<List<String>?> openFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return null;
    final directory = Directory(dir);
    final files = await directory
        .list(recursive: false)
        .where((e) => e is File && e.path.endsWith('.$_ext'))
        .map((e) => e.path)
        .toList();
    files.sort();
    return files;
  }

  /// Save pattern to an existing file path.
  /// Pass [compress] = true (default) for gzip compression, false for plain UTF-8 text.
  ///
  /// Updates [PatternCache] after a successful write so the next workspace
  /// file-switch is served from cache without re-reading the file.
  static Future<void> saveFile(CrossStitchPattern pattern, String path,
      {bool compress = true}) async {
    // Release builds always compress regardless of the per-file flag.
    final effectiveCompress = kDebugMode ? compress : true;
    final yaml = toYamlString(pattern);
    final bytes =
        effectiveCompress ? gzip.encode(utf8.encode(yaml)) : utf8.encode(yaml);
    await File(path).writeAsBytes(bytes, flush: true);
    final stat = await File(path).stat();
    PatternCache.put(path, pattern, effectiveCompress, stat.modified);
  }

  /// Prompt the user for a save location; returns the chosen path or null.
  /// [compress] controls whether the written file is gzip-compressed.
  static Future<String?> saveFileAs(CrossStitchPattern pattern,
      {bool compress = true}) async {
    // Release builds always compress regardless of the per-file flag.
    final effectiveCompress = kDebugMode ? compress : true;
    final suggestedName = pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    if (_isMobile) {
      // On iOS/Android the platform manages writing; bytes must be provided.
      final yaml = toYamlString(pattern);
      final bytes =
          effectiveCompress ? gzip.encode(utf8.encode(yaml)) : utf8.encode(yaml);
      final path = await FilePicker.saveFile(
        fileName: '$suggestedName.$_ext',
        type: FileType.any,
        bytes: Uint8List.fromList(bytes),
      );
      return path; // null if user cancelled; path if platform returns one
    }
    final path = await FilePicker.saveFile(
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [_ext],
    );
    if (path == null) return null;
    final finalPath = path.endsWith('.$_ext') ? path : '$path.$_ext';
    await saveFile(pattern, finalPath, compress: effectiveCompress);
    return finalPath;
  }

  // ─── Serialisation ───────────────────────────────────────────────────────

  static CrossStitchPattern parseYamlString(String yamlString) {
    final doc = loadYaml(yamlString);
    if (doc is! Map) throw const FormatException('Invalid .stitches file');
    return CrossStitchPattern.fromYaml(Map<String, dynamic>.from(doc));
  }

  static String toYamlString(CrossStitchPattern pattern) {
    final buf = StringBuffer();
    buf.writeln('version: 2');

    // ── patternInfo: section — metadata (equiv. to k8s metadata) ─────────────
    buf.writeln('patternInfo:');
    buf.writeln('  name: ${_yamlStr(pattern.name)}');
    if (pattern.designer != null) buf.writeln('  designer: ${_yamlStr(pattern.designer!)}');
    if (pattern.description != null) buf.writeln('  description: ${_yamlStr(pattern.description!)}');
    if (pattern.difficulty != null) buf.writeln('  difficulty: ${_yamlStr(pattern.difficulty!)}');
    if (pattern.estimatedHours != null) buf.writeln('  estimatedHours: ${_yamlStr(pattern.estimatedHours!)}');
    if (pattern.copyright != null) buf.writeln('  copyright: ${_yamlStr(pattern.copyright!)}');
    if (pattern.materialsSuggestions.isNotEmpty) {
      buf.writeln('  materialsSuggestions:');
      for (final s in pattern.materialsSuggestions) {
        buf.writeln('    - aidaCount: ${s.aidaCount}');
        buf.writeln('      strands: ${s.strands}');
      }
    }

    // ── pattern: section — the design spec ───────────────────────────────────
    buf.writeln('pattern:');
    buf.writeln('  width: ${pattern.width}');
    buf.writeln('  height: ${pattern.height}');
    buf.writeln('  aidaColor: ${_yamlStr(pattern.aidaColorHex)}');
    if (pattern.referenceImagePath != null) {
      buf.writeln('  overlay:');
      buf.writeln('    imagePath: ${_yamlStr(pattern.referenceImagePath!)}');
      buf.writeln('    opacity: ${pattern.referenceOpacity.toStringAsFixed(2)}');
    }

    buf.writeln('  threads:');
    for (final t in pattern.threads) {
      final m = t.toYaml();
      buf.writeln('    - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
      buf.writeln('      color: ${_yamlStr(m['color'] as String)}');
      buf.writeln('      name: ${_yamlStr(m['name'] as String)}');
      buf.writeln('      symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}');
    }

    buf.writeln('  layerItems:');
    for (final item in pattern.layerItems) {
      switch (item) {
        case LayerLeaf(:final layer):
          _writeLayer(buf, layer, listIndent: '    ', bodyIndent: '      ');
        case LayerGroup():
          _writeGroup(buf, item, listIndent: '    ', bodyIndent: '      ');
      }
    }

    if (pattern.snippets.isNotEmpty) {
      buf.writeln('  snippets:');
      for (final snippet in pattern.snippets) {
        _writeSnippet(buf, snippet, base: '    ');
      }
    }

    if (pattern.compositeSymbols.isNotEmpty) {
      buf.writeln('  compositeSymbols:');
      for (final entry in pattern.compositeSymbols.entries) {
        buf.writeln('    ${_yamlStr(entry.key)}: ${_yamlStr(entry.value)}');
      }
    }

    // ── stitching: section — act-of-stitching state ───────────────────────────
    // Page mode config — only written when ever configured (even if disabled,
    // so the user's page dimensions are preserved across saves).
    final pc = pattern.pageConfig;
    if (pc != PageConfig.disabled) {
      buf.writeln('stitching:');
      buf.writeln('  pageMode:');
      buf.writeln('    enabled: ${pc.enabled}');
      buf.writeln('    pageWidth: ${pc.pageWidth}');
      buf.writeln('    pageHeight: ${pc.pageHeight}');
      buf.writeln('    fuzzyAmount: ${pc.fuzzyAmount}');
    }

    return buf.toString();
  }

  static void _writeStitch(StringBuffer buf, s, {String indent = '  '}) {
    final m = s.toYaml();
    final type = m['type'] as String;
    final thread = _yamlStr(m['thread'] as String);
    switch (type) {
      case 'full':
        buf.writeln('$indent- {type: $type, x: ${m['x']}, y: ${m['y']}, thread: $thread}');
      case 'half':
        buf.writeln('$indent- {type: $type, x: ${m['x']}, y: ${m['y']}, dir: ${m['dir']}, thread: $thread}');
      case 'quarter':
        buf.writeln('$indent- {type: $type, x: ${m['x']}, y: ${m['y']}, quadrant: ${m['quadrant']}, thread: $thread}');
      case 'halfcross':
        buf.writeln('$indent- {type: $type, x: ${m['x']}, y: ${m['y']}, half: ${m['half']}, thread: $thread}');
      case 'quartercross':
        buf.writeln('$indent- {type: $type, x: ${m['x']}, y: ${m['y']}, quadrant: ${m['quadrant']}, thread: $thread}');
      case 'back':
        buf.writeln('$indent- {type: $type, x1: ${m['x1']}, y1: ${m['y1']}, x2: ${m['x2']}, y2: ${m['y2']}, thread: $thread}');
    }
  }

  static void _writeLayer(StringBuffer buf, Layer layer,
      {String listIndent = '  ', String bodyIndent = '    '}) {
    buf.writeln('$listIndent- type: layer');
    buf.writeln('${bodyIndent}id: ${_yamlStr(layer.id)}');
    buf.writeln('${bodyIndent}name: ${_yamlStr(layer.name)}');
    buf.writeln('${bodyIndent}visible: ${layer.visible}');
    if (layer.locked) buf.writeln('${bodyIndent}locked: true');
    buf.writeln('${bodyIndent}opacity: ${layer.opacity.toStringAsFixed(3)}');
    if (layer.blendMode != LayerBlendMode.normal) {
      buf.writeln('${bodyIndent}blendMode: ${layer.blendMode.yamlKey}');
    }
    buf.writeln('${bodyIndent}stitches:');
    for (final s in layer.stitches) {
      _writeStitch(buf, s, indent: '$bodyIndent  ');
    }
  }

  static void _writeGroup(StringBuffer buf, LayerGroup group,
      {String listIndent = '  ', String bodyIndent = '    '}) {
    buf.writeln('$listIndent- type: group');
    buf.writeln('${bodyIndent}id: ${_yamlStr(group.id)}');
    buf.writeln('${bodyIndent}name: ${_yamlStr(group.name)}');
    buf.writeln('${bodyIndent}collapsed: ${group.collapsed}');
    buf.writeln('${bodyIndent}groupVisible: ${group.groupVisible}');
    if (group.groupLocked) buf.writeln('${bodyIndent}groupLocked: true');
    if (group.layers.isEmpty) {
      buf.writeln('${bodyIndent}layers: []');
    } else {
      buf.writeln('${bodyIndent}layers:');
      final innerList = '$bodyIndent  ';
      final innerBody = '$bodyIndent    ';
      for (final layer in group.layers) {
        _writeLayer(buf, layer, listIndent: innerList, bodyIndent: innerBody);
      }
    }
  }

  static void _writeSnippet(StringBuffer buf, Snippet snippet,
      {String base = '  '}) {
    final body = '$base  ';
    buf.writeln('$base- id: ${_yamlStr(snippet.id)}');
    buf.writeln('${body}name: ${_yamlStr(snippet.name)}');
    buf.writeln('${body}width: ${snippet.width}');
    buf.writeln('${body}height: ${snippet.height}');
    buf.writeln('${body}activePalette: ${snippet.activePaletteIndex}');
    buf.writeln('${body}palettes:');
    for (final palette in snippet.palettes) {
      buf.writeln('$body  - id: ${_yamlStr(palette.id)}');
      buf.writeln('$body    name: ${_yamlStr(palette.name)}');
      buf.writeln('$body    threads:');
      for (final t in palette.threads) {
        final m = t.toYaml();
        buf.writeln('$body      - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
        buf.writeln('$body        color: ${_yamlStr(m['color'] as String)}');
        buf.writeln('$body        name: ${_yamlStr(m['name'] as String)}');
        buf.writeln('$body        symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}');
      }
    }
    buf.writeln('${body}stitches:');
    for (final s in snippet.stitches) {
      _writeStitch(buf, s, indent: '$body  ');
    }
  }

  /// Wrap a string in YAML single quotes, escaping any internal single quotes.
  static String _yamlStr(String value) {
    final escaped = value.replaceAll("'", "''");
    return "'$escaped'";
  }
}
