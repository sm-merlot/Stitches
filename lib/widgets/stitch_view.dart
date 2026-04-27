import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor/editor_provider.dart';
import '../utils/shortcut_router.dart';
import '../utils/stitch_controller.dart';
import 'aida_widget.dart';
import 'editor_shared_widgets.dart';
import 'editor_toolbar.dart';

/// Canvas layout for stitch mode.
///
/// Owns [StitchController], manages its lifecycle (attachCanvas / detachCanvas,
/// ShortcutRouter push / pop), and renders the canvas, progress bar, and toolbar.
///
/// Pattern mutation is structurally impossible: [StitchController] composes no
/// [DrawHandler] or [PasteHandler], and [AidaWidget] receives no [EditController].
///
/// The AppBar and sidebars are owned by the parent screen, not by this widget.
class StitchView extends ConsumerStatefulWidget {
  /// Called when Cmd/Ctrl+S is pressed in stitch mode.
  final VoidCallback? onSave;

  const StitchView({super.key, this.onSave});

  @override
  ConsumerState<StitchView> createState() => _StitchViewState();
}

class _StitchViewState extends ConsumerState<StitchView> {
  late final StitchController _stitchController;

  @override
  void initState() {
    super.initState();
    _stitchController = StitchController(
      notifier: ref.read(editorProvider.notifier),
      getState: () => ref.read(editorProvider),
      onSave: widget.onSave,
    );
    ShortcutRouter.instance.push(_stitchController);
  }

  @override
  void dispose() {
    ShortcutRouter.instance.pop(_stitchController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: AidaWidget(stitchController: _stitchController),
        ),
        const ProgressInfoBar(),
        const SafeArea(top: false, child: EditorToolbar()),
      ],
    );
  }
}
