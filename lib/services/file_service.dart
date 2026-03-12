import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:yaml/yaml.dart';
import '../models/pattern.dart';

class FileService {
  static const String _ext = 'stitchx';

  /// Pick a .stitchx file and return (pattern, filePath).
  static Future<(CrossStitchPattern, String)> openFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [_ext],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      throw Exception('No file selected');
    }
    final path = result.files.single.path!;
    return openFileFromPath(path);
  }

  /// Load a pattern directly from a known file path.
  static Future<(CrossStitchPattern, String)> openFileFromPath(
      String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('File not found: $path');
    final content = await file.readAsString();
    final pattern = parseYamlString(content);
    return (pattern, path);
  }

  /// Pick a directory and return all .stitchx file paths within it.
  static Future<List<String>> openFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) throw Exception('No folder selected');
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
  static Future<void> saveFile(CrossStitchPattern pattern, String path) async {
    final file = File(path);
    await file.writeAsString(toYamlString(pattern));
  }

  /// Prompt the user for a save location; returns the chosen path or null.
  static Future<String?> saveFileAs(CrossStitchPattern pattern) async {
    final suggestedName =
        '${pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_')}.$_ext';
    final path = await FilePicker.platform.saveFile(
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [_ext],
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
    return CrossStitchPattern.fromYaml(doc);
  }

  static String toYamlString(CrossStitchPattern pattern) {
    final buf = StringBuffer();
    buf.writeln('name: ${_yamlStr(pattern.name)}');
    buf.writeln('width: ${pattern.width}');
    buf.writeln('height: ${pattern.height}');
    buf.writeln('aidaColor: ${_yamlStr(pattern.aidaColorHex)}');

    if (pattern.editorSelectedThreadId != null || pattern.editorTool != null) {
      buf.writeln('editor:');
      if (pattern.editorSelectedThreadId != null) {
        buf.writeln(
            '  selectedThread: ${_yamlStr(pattern.editorSelectedThreadId!)}');
      }
      if (pattern.editorTool != null) {
        buf.writeln('  tool: ${pattern.editorTool!}');
      }
    }

    buf.writeln('threads:');
    for (final t in pattern.threads) {
      final m = t.toYaml();
      buf.writeln('  - dmcCode: ${_yamlStr(m['dmcCode'] as String)}');
      buf.writeln('    color: ${_yamlStr(m['color'] as String)}');
      buf.writeln('    name: ${_yamlStr(m['name'] as String)}');
    }

    buf.writeln('stitches:');
    for (final s in pattern.stitches) {
      final m = s.toYaml();
      final type = m['type'] as String;
      switch (type) {
        case 'full':
          buf.writeln(
              '  - {type: full, x: ${m['x']}, y: ${m['y']}, thread: ${_yamlStr(m['thread'] as String)}}');
        case 'half':
          buf.writeln(
              '  - {type: half, x: ${m['x']}, y: ${m['y']}, dir: ${m['dir']}, thread: ${_yamlStr(m['thread'] as String)}}');
        case 'quarter':
          buf.writeln(
              '  - {type: quarter, x: ${m['x']}, y: ${m['y']}, quadrant: ${m['quadrant']}, thread: ${_yamlStr(m['thread'] as String)}}');
        case 'halfcross':
          buf.writeln(
              '  - {type: halfcross, x: ${m['x']}, y: ${m['y']}, half: ${m['half']}, thread: ${_yamlStr(m['thread'] as String)}}');
        case 'quartercross':
          buf.writeln(
              '  - {type: quartercross, x: ${m['x']}, y: ${m['y']}, quadrant: ${m['quadrant']}, thread: ${_yamlStr(m['thread'] as String)}}');
        case 'back':
          buf.writeln(
              '  - {type: back, x1: ${m['x1']}, y1: ${m['y1']}, x2: ${m['x2']}, y2: ${m['y2']}, thread: ${_yamlStr(m['thread'] as String)}}');
      }
    }

    return buf.toString();
  }

  /// Wrap a string in YAML single quotes, escaping any internal single quotes.
  static String _yamlStr(String value) {
    final escaped = value.replaceAll("'", "''");
    return "'$escaped'";
  }
}
