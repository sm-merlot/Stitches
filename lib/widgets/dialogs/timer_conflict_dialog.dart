import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum ConflictTimerResult { openOther, stopDiscard, keepRunning }

/// Shows a blocking dialog when the user interacts with the timer button while
/// a timer is already running for a *different* pattern.
///
/// Options:
/// - Open the other pattern in stitch mode (preferred — time logs correctly).
/// - Stop & discard (time is not logged — can't log to a pattern not open).
/// - Keep running (dismiss, no change).
Future<ConflictTimerResult> showConflictTimerDialog(
  BuildContext context, {
  required String timerFilePath,
  required DateTime sessionStart,
  DateTime? lastInteractionAt,
}) async {
  final result = await showDialog<ConflictTimerResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConflictTimerDialog(
      timerFilePath: timerFilePath,
      sessionStart: sessionStart,
      lastInteractionAt: lastInteractionAt,
    ),
  );
  return result ?? ConflictTimerResult.keepRunning;
}

class _ConflictTimerDialog extends StatefulWidget {
  final String timerFilePath;
  final DateTime sessionStart;
  final DateTime? lastInteractionAt;

  const _ConflictTimerDialog({
    required this.timerFilePath,
    required this.sessionStart,
    this.lastInteractionAt,
  });

  @override
  State<_ConflictTimerDialog> createState() => _ConflictTimerDialogState();
}

class _ConflictTimerDialogState extends State<_ConflictTimerDialog> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker =
        Timer.periodic(const Duration(seconds: 1), (_) {
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
    final fileName = p.basename(widget.timerFilePath);
    final fileExists = File(widget.timerFilePath).existsSync();
    final elapsed = _now.difference(widget.sessionStart);
    final lastAt = widget.lastInteractionAt;
    final sinceActivity = lastAt != null ? _now.difference(lastAt) : null;

    return AlertDialog(
      title: const Text('Timer running for another pattern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fileName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Running for: ${_fmt(elapsed)}'),
          if (sinceActivity != null)
            Text('Last activity: ${_fmt(sinceActivity)} ago'),
          const SizedBox(height: 12),
          const Text(
            'Stop & discard will not log any time — open the pattern in '
            'stitch mode first to log correctly.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, ConflictTimerResult.keepRunning),
          child: const Text('Keep running'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, ConflictTimerResult.stopDiscard),
          child: const Text('Stop & discard'),
        ),
        if (fileExists)
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, ConflictTimerResult.openOther),
            child: Text('Open $fileName'),
          ),
      ],
    );
  }
}
