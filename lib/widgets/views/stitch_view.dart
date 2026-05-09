import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/editor/editor_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/stitching_timer_provider.dart';
import '../../utils/commands/shortcut_router.dart';
import '../../utils/controllers/stitch_controller.dart';
import '../canvas/aida_widget.dart';
import '../dialogs/timer_start_dialog.dart';
import '../dialogs/timer_swap_dialog.dart';
import '../editor_shared_widgets.dart';
import '../toolbar/editor_toolbar.dart';

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
      onAnyProgressAction: _onAnyProgressAction,
    );
    ShortcutRouter.instance.push(_stitchController);
  }

  Future<void> _onAnyProgressAction() async {
    final timerNotifier = ref.read(stitchingTimerProvider.notifier);
    if (!mounted) return;

    if (timerNotifier.shouldShowSwapPrompt()) {
      final timerState = ref.read(stitchingTimerProvider);
      final currentName = ref.read(editorProvider).pattern.name;
      final result = await showTimerSwapDialog(
        context,
        timerPatternName: timerState.timerPatternName,
        currentPatternName: currentName,
      );
      if (!mounted) return;
      if (result == TimerSwapResult.swap) timerNotifier.swapTimer();
      return;
    }

    if (!timerNotifier.shouldShowStartPrompt()) return;
    final result = await showTimerStartDialog(context);
    if (!mounted) return;
    switch (result) {
      case TimerStartResult.start:
        timerNotifier.start();
      case TimerStartResult.snooze:
        timerNotifier.snoozeStartPrompt();
      case TimerStartResult.mute:
        ref.read(settingsProvider.notifier).setDisableTimerStartPrompt(true);
      case null:
        break;
    }
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
