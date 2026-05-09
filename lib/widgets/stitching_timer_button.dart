import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/file_service.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/stitching_timer_provider.dart';
import 'dialogs/timer_conflict_dialog.dart';

/// A compact play/stop button that shows elapsed session time while running.
///
/// Lives in the stitch-mode bottom row of the right sidebar alongside
/// [MarkDoneButton] and [StitchDemoButton].
class StitchingTimerButton extends ConsumerWidget {
  const StitchingTimerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(stitchingTimerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isRunning = timer.isRunning;

    // Format elapsed HH:MM:SS (or MM:SS when < 1 hour).
    final elapsed = timer.elapsed;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    final timeLabel = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: FilledButton.icon(
        icon: Icon(
          isRunning ? Icons.stop_circle_outlined : Icons.timer_outlined,
          size: 16,
        ),
        label: Text(
          isRunning ? timeLabel : 'Timer',
          style: const TextStyle(fontSize: 13),
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: isRunning ? colorScheme.tertiaryContainer : null,
          foregroundColor: isRunning ? colorScheme.onTertiaryContainer : null,
        ),
        onPressed: () => _onPressed(context, ref, timer),
      ),
    );
  }

  Future<void> _onPressed(
      BuildContext context, WidgetRef ref, StitchingTimerState timer) async {
    final notifier = ref.read(stitchingTimerProvider.notifier);
    final currentFilePath = ref.read(editorProvider).filePath;

    // If the running timer belongs to a different pattern, intercept and show
    // the conflict dialog instead of blindly stopping.
    if (timer.isRunning &&
        timer.timerFilePath != null &&
        timer.timerFilePath != currentFilePath) {
      if (!context.mounted) return;
      final result = await showConflictTimerDialog(
        context,
        timerFilePath: timer.timerFilePath!,
        timerPatternName: timer.timerPatternName,
        sessionStart: timer.sessionStart!,
        lastInteractionAt: notifier.lastInteractionAt,
      );
      if (!context.mounted) return;
      switch (result) {
        case ConflictTimerResult.stopDiscard:
          notifier.stop(); // _logTime skips logging — paths differ
        case ConflictTimerResult.openOther:
          await _openInStitchMode(context, ref, timer.timerFilePath!);
        case ConflictTimerResult.keepRunning:
          break;
      }
      return;
    }

    notifier.toggle();
  }

  Future<void> _openInStitchMode(
      BuildContext context, WidgetRef ref, String filePath) async {
    try {
      final (pattern, path, wasCompressed) =
          await FileService.openFileFromPath(filePath);
      ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: path,
            compressOnSave: wasCompressed,
          );
      ref.read(editorProvider.notifier).setMode(AppMode.stitch);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }
}
