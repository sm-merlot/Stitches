import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/pattern.dart';
import '../providers/editor/editor_provider.dart';
import '../services/format_service.dart';
import '../utils/snackbars.dart';

/// Export the pattern as OXS (Open Cross Stitch / WinStitch compatible).
/// Returns true if the export succeeded.
/// [notifier] and [useDmc] are retained for API compatibility but not used by
/// OXS export (OXS always embeds DMC codes).
Future<bool> showExportDialog(
    BuildContext context, CrossStitchPattern pattern,
    {bool useDmc = true, EditorNotifier? notifier}) async {
  try {
    const format = CrossStitchFormat.oxs;
    final suggested = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (isMobile) {
      final bytes =
          Uint8List.fromList(utf8.encode(FormatService.encodeFile(pattern, format)));
      await FilePicker.saveFile(
        fileName: '$suggested.${format.extension}',
        type: FileType.any,
        bytes: bytes,
      );
      if (context.mounted) {
        showSuccess(context, 'Exported as $suggested.${format.extension}');
      }
    } else {
      final bytes =
          Uint8List.fromList(utf8.encode(FormatService.encodeFile(pattern, format)));
      final path = await FilePicker.saveFile(
        fileName: '$suggested.${format.extension}',
        type: FileType.custom,
        allowedExtensions: [format.extension],
        bytes: bytes,
      );
      if (path == null) return false;

      if (context.mounted) {
        showSuccess(
            context, 'Exported as ${path.split(Platform.pathSeparator).last}');
      }
    }
    return true;
  } catch (e) {
    if (context.mounted) showError(context, 'Export failed: $e');
    return false;
  }
}

