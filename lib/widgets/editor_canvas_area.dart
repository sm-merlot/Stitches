import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'editor_shared_widgets.dart';
import 'editor_toolbar.dart';
import 'pattern_canvas.dart';

/// The core editor layout: optional import-format banner → canvas → toolbar.
///
/// Callers are responsible for only rendering this widget when a file is open.
class EditorCanvasArea extends ConsumerWidget {
  /// When non-null, shows the import-format banner for this non-native file.
  final String? importFilePath;

  /// Called when user taps "Convert to .stitches". Null when [onOpenNative]
  /// is provided instead (i.e. a .stitches sibling already exists).
  final VoidCallback? onConvert;

  /// Called when user taps "Open .stitches". Non-null only when a native
  /// sibling already exists beside [importFilePath].
  final VoidCallback? onOpenNative;

  const EditorCanvasArea({
    super.key,
    this.importFilePath,
    this.onConvert,
    this.onOpenNative,
  }) : assert(
          importFilePath == null || onConvert != null || onOpenNative != null,
          'onConvert or onOpenNative is required when importFilePath is provided',
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (importFilePath != null)
          EditorImportBanner(
            filePath: importFilePath!,
            onConvert: onConvert,
            onOpenNative: onOpenNative,
          ),
        const Expanded(child: PatternCanvas()),
        const SafeArea(top: false, child: EditorToolbar()),
      ],
    );
  }
}
