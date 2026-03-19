import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents an open PDF file in the workspace viewer.
class OpenPdf {
  /// Local (or cached temp) file path used to render the PDF.
  final String localPath;

  /// Drive file ID — set for Drive-backed PDFs, null for local ones.
  /// Used to highlight the correct entry in the sidebar tree.
  final String? driveFileId;

  /// Human-readable display name (without extension). Falls back to the
  /// basename of [localPath] when not set explicitly.
  final String? displayName;

  const OpenPdf({required this.localPath, this.driveFileId, this.displayName});

  String get title =>
      displayName ?? localPath.split('/').last.replaceAll('.pdf', '');
}

/// The currently open PDF, or null when no PDF is being viewed.
/// Setting this to a non-null value switches the workspace to PDF view.
/// Setting it to null (or opening a pattern) returns to the editor.
final pdfViewerProvider = StateProvider<OpenPdf?>((ref) => null);
