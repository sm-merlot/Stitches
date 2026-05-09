import 'package:flutter/material.dart';

enum TimerSwapResult { swap, keep }

/// Shows a prompt when the user stitches on a pattern that isn't the one the
/// timer is currently running for.
///
/// Returns [TimerSwapResult.swap] if the user wants to swap the timer to the
/// current pattern, [TimerSwapResult.keep] to leave it unchanged, or null if
/// dismissed (treat as keep).
///
/// Note: swapping stops the old timer without logging its time, because the
/// old pattern file is no longer open.
Future<TimerSwapResult?> showTimerSwapDialog(
  BuildContext context, {
  required String? timerPatternName,
  required String currentPatternName,
}) {
  final otherName = timerPatternName ?? 'another pattern';
  return showDialog<TimerSwapResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Swap timer?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The timer is running for "$otherName".'),
          const SizedBox(height: 8),
          Text('Swap it to "$currentPatternName"?'),
          const SizedBox(height: 12),
          Text(
            'Time recorded for "$otherName" will not be saved '
            'because it is no longer open.',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, TimerSwapResult.keep),
          child: const Text('Keep'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, TimerSwapResult.swap),
          child: const Text('Swap timer'),
        ),
      ],
    ),
  );
}
