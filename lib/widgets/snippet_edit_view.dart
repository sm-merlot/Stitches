import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor/editor_provider.dart';
import '../utils/edit_controller.dart';
import '../utils/shortcut_router.dart';
import 'aida_widget.dart';
import 'editor_toolbar.dart';

/// Canvas layout for the snippet editor.
///
/// Owns [EditController] with snippet-specific canvas-transform callbacks,
/// manages its lifecycle, and renders the canvas with the snippet toolbar.
///
/// Always in edit mode — stitch mode is unavailable for snippets.
/// The enclosing [ProviderScope] override ensures mutations apply to the
/// snippet pattern, never the parent pattern.
class SnippetEditView extends ConsumerStatefulWidget {
  /// Called when the user taps "Paste from snippet" in the toolbar.
  /// Null when no sibling snippets are available.
  final VoidCallback? onPasteFromSnippet;

  const SnippetEditView({super.key, this.onPasteFromSnippet});

  @override
  ConsumerState<SnippetEditView> createState() => _SnippetEditViewState();
}

class _SnippetEditViewState extends ConsumerState<SnippetEditView> {
  late final EditController _editController;

  @override
  void initState() {
    super.initState();
    final n = ref.read(editorProvider.notifier);
    _editController = EditController(
      notifier: n,
      getState: () => ref.read(editorProvider),
      onFlipCanvasH: () => ref.read(editorProvider.notifier).flipCanvasH(),
      onFlipCanvasV: () => ref.read(editorProvider.notifier).flipCanvasV(),
      onRotateCanvasCW: () => ref.read(editorProvider.notifier).rotateCanvasCW(),
    );
    ShortcutRouter.instance.push(_editController);
  }

  @override
  void dispose() {
    ShortcutRouter.instance.pop(_editController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: AidaWidget(editController: _editController),
        ),
        EditorToolbar(
          showSnippetsButton: false,
          showSaveAsSnippetButton: false,
          showSpriteSheetButton: false,
          showWholeCanvasTransforms: true,
          showAidaButton: false,
          onPasteFromSnippet: widget.onPasteFromSnippet,
        ),
      ],
    );
  }
}
