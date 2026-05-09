import 'dart:async';
import 'package:flutter/material.dart';

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

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _now.difference(widget.sessionStart);
    final lastAt = widget.lastInteractionAt;
    final sinceActivity = lastAt != null ? _now.difference(lastAt) : null;

    return AlertDialog(
      title: const Text('Are you still stitching?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timer running for: ${_fmt(elapsed)}'),
          if (sinceActivity != null)
            Text('Last activity: ${_fmt(sinceActivity)} ago'),
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
