import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'editor_shared_widgets.dart';
import 'editor_toolbar.dart';
import 'pattern_canvas.dart';

/// The core editor layout: optional import-format banner → canvas → toolbar.
///
/// Callers are responsible for only rendering this widget when a file is open.
class EditorCanvasArea extends ConsumerWidget {
  /// When non-null, shows the import-format banner with a Save As button.
  final String? importFilePath;
  final VoidCallback? onSaveAs;

  /// Pass true in the Workspace context to mention Drive in the banner text.
  final bool showDriveNoteInBanner;

  const EditorCanvasArea({
    super.key,
    this.importFilePath,
    this.onSaveAs,
    this.showDriveNoteInBanner = false,
  }) : assert(
          importFilePath == null || onSaveAs != null,
          'onSaveAs is required when importFilePath is provided',
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (importFilePath != null)
          EditorImportBanner(
            filePath: importFilePath!,
            onSaveAs: onSaveAs!,
            showDriveNote: showDriveNoteInBanner,
          ),
        const Expanded(child: PatternCanvas()),
        const SafeArea(top: false, child: EditorToolbar()),
      ],
    );
  }
}
