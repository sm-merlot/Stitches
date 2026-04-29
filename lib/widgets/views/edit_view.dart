import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/editor/editor_provider.dart';
import '../../utils/controllers/edit_controller.dart';
import '../../utils/commands/shortcut_router.dart';
import '../../utils/controllers/view_mode_controller.dart';
import '../canvas/aida_widget.dart';
import '../editor_shared_widgets.dart';
import '../toolbar/editor_toolbar.dart';

/// Canvas layout for edit and view modes.
///
/// Owns [EditController] and [ViewModeController], manages their lifecycle
/// (attachCanvas / detachCanvas, ShortcutRouter push / pop), and renders
/// the canvas with the toolbar below.
///
/// The AppBar and sidebars are owned by the parent screen, not by this widget.
class EditView extends ConsumerStatefulWidget {
  /// Called when Cmd/Ctrl+S is pressed. Null for screens that use auto-save.
  final VoidCallback? onSave;

  /// Called when Shift+? is pressed. Null for screens without a shortcuts dialog.
  final VoidCallback? onShowShortcuts;

  /// Called when Cmd/Ctrl+= is pressed (PDF panel zoom in).
  final VoidCallback? onPdfZoomIn;

  /// Called when Cmd/Ctrl+- is pressed (PDF panel zoom out).
  final VoidCallback? onPdfZoomOut;

  /// When non-null, shows an import-format banner for this non-native file.
  final String? importFilePath;

  /// Called when the user taps "Convert to .stitchx".
  /// Null when [onOpenNative] is provided instead.
  final VoidCallback? onConvert;

  /// Called when the user taps "Open .stitchx".
  /// Non-null only when a native sibling already exists beside [importFilePath].
  final VoidCallback? onOpenNative;

  const EditView({
    super.key,
    this.onSave,
    this.onShowShortcuts,
    this.onPdfZoomIn,
    this.onPdfZoomOut,
    this.importFilePath,
    this.onConvert,
    this.onOpenNative,
  }) : assert(
          importFilePath == null || onConvert != null || onOpenNative != null,
          'onConvert or onOpenNative is required when importFilePath is provided',
        );

  @override
  ConsumerState<EditView> createState() => _EditViewState();
}

class _EditViewState extends ConsumerState<EditView> {
  late final EditController _editController;
  late final ViewModeController _viewModeController;

  @override
  void initState() {
    super.initState();
    final n = ref.read(editorProvider.notifier);
    _editController = EditController(
      notifier: n,
      getState: () => ref.read(editorProvider),
      onSave: widget.onSave,
      onShowShortcuts: widget.onShowShortcuts,
      onPdfZoomIn: widget.onPdfZoomIn,
      onPdfZoomOut: widget.onPdfZoomOut,
    );
    _viewModeController = ViewModeController(
      getState: () => ref.read(editorProvider),
    );
    // AidaWidget calls attachCanvas when it mounts; detachCanvas when it disposes.
    ShortcutRouter.instance.push(_editController);
    ShortcutRouter.instance.push(_viewModeController);
  }

  @override
  void dispose() {
    ShortcutRouter.instance.pop(_viewModeController);
    ShortcutRouter.instance.pop(_editController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.importFilePath != null)
          EditorImportBanner(
            filePath: widget.importFilePath!,
            onConvert: widget.onConvert,
            onOpenNative: widget.onOpenNative,
          ),
        Expanded(
          child: AidaWidget(
            editController: _editController,
            viewModeController: _viewModeController,
          ),
        ),
        const SafeArea(top: false, child: EditorToolbar()),
      ],
    );
  }
}
