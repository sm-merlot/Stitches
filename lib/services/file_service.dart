import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:yaml/yaml.dart';
import '../models/layer.dart';
import '../models/layer_item.dart';
import '../models/pattern.dart';
import '../models/snippet.dart';
import 'format_service.dart';

class FileService {
  static const String _ext = 'stitchx';

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const List<String> _openExtensions = [_ext, 'oxs'];

  /// Pick a .stitchx or .oxs file; returns (pattern, filePath), or null if cancelled.
  static Future<(CrossStitchPattern, String)?> openFile() async {
    final result = await FilePicker.platform.pickFiles(
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
  /// Supports both .stitchx (YAML) and .oxs (XML) formats.
  static Future<(CrossStitchPattern, String)> openFileFromPath(
      String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('File not found: $path');
    if (path.toLowerCase().endsWith('.oxs')) {
      final pattern = await FormatService.importFile(path);
      return (pattern, path);
    }
    final bytes = await file.readAsBytes();
    final content = _decodeBytes(_maybeDecompress(bytes));
    final pattern = parseYamlString(content);
    return (pattern, path);
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

  /// Open a known directory path and return all .stitchx file paths within it.
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

  /// Pick a directory and return all .stitchx file paths within it, or null if cancelled.
  static Future<List<String>?> openFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
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

  /// Save pattern to an existing file path (gzip-compressed).
  static Future<void> saveFile(CrossStitchPattern pattern, String path) async {
    final yaml = toYamlString(pattern);
    final bytes = gzip.encode(utf8.encode(yaml));
    await File(path).writeAsBytes(bytes, flush: true);
  }

  /// Prompt the user for a save location; returns the chosen path or null.
  static Future<String?> saveFileAs(CrossStitchPattern pattern) async {
    final suggestedName = pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final path = await FilePicker.platform.saveFile(
      fileName: _isMobile ? '$suggestedName.$_ext' : suggestedName,
      type: _isMobile ? FileType.any : FileType.custom,
      allowedExtensions: _isMobile ? null : [_ext],
    );
    if (path == null) return null;
    final finalPath = path.endsWith('.$_ext') ? path : '$path.$_ext';
    await saveFile(pattern, finalPath);
    return finalPath;
  }

  // ─── Serialisation ───────────────────────────────────────────────────────

  static CrossStitchPattern parseYamlString(String yamlString) {
    final doc = loadYaml(yamlString);
    if (doc is! Map) throw const FormatException('Invalid .stitchx file');
    return CrossStitchPattern.fromYaml(Map<String, dynamic>.from(doc));
  }

  static String toYamlString(CrossStitchPattern pattern) {
    final buf = StringBuffer();
    buf.writeln('name: ${_yamlStr(pattern.name)}');
    buf.writeln('width: ${pattern.width}');
    buf.writeln('height: ${pattern.height}');
    buf.writeln('aidaColor: ${_yamlStr(pattern.aidaColorHex)}');

    if (pattern.editorSelectedThreadId != null ||
        pattern.editorTool != null ||
        pattern.editorStitchMode ||
        pattern.editorActiveLayerId != null ||
        pattern.editorBlockMode) {
      buf.writeln('editor:');
      if (pattern.editorSelectedThreadId != null) {
        buf.writeln(
            '  selectedThread: ${_yamlStr(pattern.editorSelectedThreadId!)}');
      }
      if (pattern.editorTool != null) {
        buf.writeln('  tool: ${pattern.editorTool!}');
      }
      if (pattern.editorStitchMode) {
        buf.writeln('  stitchMode: true');
      }
      if (pattern.editorActiveLayerId != null) {
        buf.writeln('  activeLayer: ${_yamlStr(pattern.editorActiveLayerId!)}');
      }
      if (pattern.editorBlockMode) {
        buf.writeln('  blockMode: true');
      }
    }

    if (pattern.referenceImagePath != null) {
      buf.writeln('overlay:');
      buf.writeln('  imagePath: ${_yamlStr(pattern.referenceImagePath!)}');
      buf.writeln('  opacity: ${pattern.referenceOpacity.toStringAsFixed(2)}');
    }

    buf.writeln('threads:');
    for (final t in pattern.threads) {
      final m = t.toYaml();
      buf.writeln('  - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
      buf.writeln('    color: ${_yamlStr(m['color'] as String)}');
      buf.writeln('    name: ${_yamlStr(m['name'] as String)}');
      buf.writeln('    symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}');
    }

    buf.writeln('layerItems:');
    for (final item in pattern.layerItems) {
      switch (item) {
        case LayerLeaf(:final layer):
          _writeLayer(buf, layer);
        case LayerGroup():
          _writeGroup(buf, item);
      }
    }

    if (pattern.snippets.isNotEmpty) {
      buf.writeln('snippets:');
      for (final snippet in pattern.snippets) {
        _writeSnippet(buf, snippet);
      }
    }

    if (pattern.compositeSymbols.isNotEmpty) {
      buf.writeln('compositeSymbols:');
      for (final entry in pattern.compositeSymbols.entries) {
        buf.writeln('  ${_yamlStr(entry.key)}: ${_yamlStr(entry.value)}');
      }
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
    buf.writeln('${bodyIndent}stitches:');
    for (final s in layer.stitches) {
      _writeStitch(buf, s, indent: '$bodyIndent  ');
    }
  }

  static void _writeGroup(StringBuffer buf, LayerGroup group) {
    buf.writeln('  - type: group');
    buf.writeln('    id: ${_yamlStr(group.id)}');
    buf.writeln('    name: ${_yamlStr(group.name)}');
    buf.writeln('    collapsed: ${group.collapsed}');
    buf.writeln('    groupVisible: ${group.groupVisible}');
    if (group.layers.isEmpty) {
      buf.writeln('    layers: []');
    } else {
      buf.writeln('    layers:');
      for (final layer in group.layers) {
        _writeLayer(buf, layer, listIndent: '      ', bodyIndent: '        ');
      }
    }
  }

  static void _writeSnippet(StringBuffer buf, Snippet snippet) {
    buf.writeln('  - id: ${_yamlStr(snippet.id)}');
    buf.writeln('    name: ${_yamlStr(snippet.name)}');
    buf.writeln('    width: ${snippet.width}');
    buf.writeln('    height: ${snippet.height}');
    buf.writeln('    activePalette: ${snippet.activePaletteIndex}');
    buf.writeln('    palettes:');
    for (final palette in snippet.palettes) {
      buf.writeln('      - id: ${_yamlStr(palette.id)}');
      buf.writeln('        name: ${_yamlStr(palette.name)}');
      buf.writeln('        threads:');
      for (final t in palette.threads) {
        final m = t.toYaml();
        buf.writeln("          - dmcCode: ${_yamlStr(m['dmcCode'] as String)}");
        buf.writeln("            color: ${_yamlStr(m['color'] as String)}");
        buf.writeln("            name: ${_yamlStr(m['name'] as String)}");
        buf.writeln("            symbol: ${_yamlStr((m['symbol'] as String?) ?? '')}");
      }
    }
    buf.writeln('    stitches:');
    for (final s in snippet.stitches) {
      _writeStitch(buf, s, indent: '      ');
    }
  }

  /// Wrap a string in YAML single quotes, escaping any internal single quotes.
  static String _yamlStr(String value) {
    final escaped = value.replaceAll("'", "''");
    return "'$escaped'";
  }
}
