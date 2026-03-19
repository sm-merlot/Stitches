import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';

class ReferenceImageService {
  /// Pick an image file and decode it. Returns (path, image) or null if cancelled.
  static Future<(String, ui.Image)?> pickAndDecode() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    final image = await decodeFromPath(path);
    if (image == null) return null;
    return (path, image);
  }

  /// Decode an image from a file path. Returns null if the file is missing or unreadable.
  static Future<ui.Image?> decodeFromPath(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      // File missing, unreadable, or unsupported format — overlay won't load.
      return null;
    }
  }
}
