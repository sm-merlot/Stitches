import 'package:flutter/material.dart';

enum InactivityResult { keepRunning, stopAtLastActivity, stopKeepAll }

/// Shows the "are you still stitching?" inactivity prompt.
///
/// [barrierDismissible] is false — the user must make an explicit choice.
/// Returns [InactivityResult.keepRunning] if dismissed by the system (rare).
Future<InactivityResult> showInactivityDialog(BuildContext context) async {
  final result = await showDialog<InactivityResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you still stitching?'),
      content: const Text('The timer is running!'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, InactivityResult.stopKeepAll),
          child: const Text('No, keep all time'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, InactivityResult.stopAtLastActivity),
          child: const Text('No, stop at last activity'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, InactivityResult.keepRunning),
          child: const Text('Yes, keep running'),
        ),
      ],
    ),
  );
  return result ?? InactivityResult.keepRunning;
}
