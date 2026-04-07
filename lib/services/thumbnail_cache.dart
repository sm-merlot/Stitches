import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Stable thumbnail key for a local file path.
/// URL-safe base64 of the UTF-8 path bytes — filename-safe, reversible.
String localThumbnailKey(String path) => base64Url.encode(utf8.encode(path));

/// Stable thumbnail key for a Google Drive file.
/// The fileId is already alphanumeric, no encoding needed.
String driveThumbnailKey(String fileId) => fileId;

class ThumbnailCache {
  static Directory? _dir;

  static Future<Directory> _thumbnailDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    _dir = Directory('${support.path}/thumbnails');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  // Encode key → safe filename (replace chars that are invalid in filenames).
  static String _filename(String key) =>
      key.replaceAll('/', '-').replaceAll('+', '_').replaceAll('=', '');

  /// Write [pngBytes] to cache under [key].
  static Future<void> store(String key, Uint8List pngBytes) async {
    final dir = await _thumbnailDir();
    await File('${dir.path}/${_filename(key)}.png').writeAsBytes(pngBytes);
  }

  /// Return cached bytes for [key], or null if not present.
  static Future<Uint8List?> load(String key) async {
    final dir = await _thumbnailDir();
    final file = File('${dir.path}/${_filename(key)}.png');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Delete the cached entry for [key] (no-op if absent).
  static Future<void> remove(String key) async {
    final dir = await _thumbnailDir();
    final file = File('${dir.path}/${_filename(key)}.png');
    if (await file.exists()) await file.delete();
  }

  /// Delete thumbnail entries for local paths that no longer exist on disk.
  static Future<void> pruneLocal(Iterable<String> localPaths) async {
    for (final path in localPaths) {
      if (!File(path).existsSync()) {
        await remove(localThumbnailKey(path));
      }
    }
  }
}
