import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/stitching_timer_provider.dart';

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
          backgroundColor: isRunning
              ? colorScheme.tertiaryContainer
              : null,
          foregroundColor: isRunning
              ? colorScheme.onTertiaryContainer
              : null,
        ),
        onPressed: () =>
            ref.read(stitchingTimerProvider.notifier).toggle(),
      ),
    );
  }
}

