import 'package:flutter/material.dart';

enum TimerStartResult { start, snooze, mute }

/// Shows the "start a timer?" prompt after the user marks a region done.
///
/// Returns [TimerStartResult.start] / [.snooze] / [.mute], or null if the
/// user taps outside (treat as a one-time dismiss — prompt again next mark).
Future<TimerStartResult?> showTimerStartDialog(BuildContext context) {
  return showDialog<TimerStartResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Start a timer?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You just marked stitches done. Would you like to start the timer?',
          ),
          const SizedBox(height: 12),
          Text(
            'Mute will stop this prompt. Re-enable anytime in Settings → Stitching Timer.',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, TimerStartResult.mute),
          child: const Text('Mute'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, TimerStartResult.snooze),
          child: const Text('Snooze (10m)'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, TimerStartResult.start),
          child: const Text('Start timer'),
        ),
      ],
    ),
  );
}
