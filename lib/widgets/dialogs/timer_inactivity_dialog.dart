import 'dart:async';
import 'package:flutter/material.dart';
import 'timer_dialog_utils.dart';

enum InactivityResult { keepRunning, stopAtLastActivity, stopKeepAll }

/// Shows the "are you still stitching?" inactivity prompt.
///
/// [barrierDismissible] is false — the user must make an explicit choice.
/// Returns [InactivityResult.keepRunning] if dismissed by the system (rare).
Future<InactivityResult> showInactivityDialog(
  BuildContext context, {
  required DateTime sessionStart,
  DateTime? lastInteractionAt,
}) async {
  final result = await showDialog<InactivityResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InactivityDialog(
      sessionStart: sessionStart,
      lastInteractionAt: lastInteractionAt,
    ),
  );
  return result ?? InactivityResult.keepRunning;
}

class _InactivityDialog extends StatefulWidget {
  final DateTime sessionStart;
  final DateTime? lastInteractionAt;

  const _InactivityDialog({
    required this.sessionStart,
    this.lastInteractionAt,
  });

  @override
  State<_InactivityDialog> createState() => _InactivityDialogState();
}

class _InactivityDialogState extends State<_InactivityDialog> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = fmtLastActivity(widget.lastInteractionAt, _now);
    final session = fmtDuration(_now.difference(widget.sessionStart));

    return AlertDialog(
      title: const Text('Are you still stitching?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activity.isNotEmpty) Text(activity),
          Text('Session: $session'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, InactivityResult.stopKeepAll),
          child: const Text('No, keep all time'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, InactivityResult.stopAtLastActivity),
          child: const Text('No, stop at last activity'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, InactivityResult.keepRunning),
          child: const Text('Yes, keep running'),
        ),
      ],
    );
  }
}
