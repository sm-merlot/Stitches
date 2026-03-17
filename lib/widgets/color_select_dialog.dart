import 'package:flutter/material.dart';

import '../models/thread.dart';

/// Shown when multiple thread colours are present and the user needs to pick
/// one to demonstrate. Returns the chosen [Thread] when dismissed via a tap,
/// or null if the dialog is cancelled.
class ColorSelectDialog extends StatelessWidget {
  final List<Thread> threads;

  const ColorSelectDialog({super.key, required this.threads});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      clipBehavior: Clip.hardEdge,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 80),
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose a colour to demonstrate',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: threads.length,
                itemBuilder: (_, i) {
                  final t = threads[i];
                  final textColor = t.color.computeLuminance() > 0.35
                      ? Colors.black
                      : Colors.white;
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: t.color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      alignment: Alignment.center,
                      child: t.symbol.isNotEmpty
                          ? Text(
                              t.symbol,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                height: 1.0,
                              ),
                            )
                          : null,
                    ),
                    title: Text('${t.dmcCode} – ${t.name}'),
                    onTap: () => Navigator.of(context).pop(t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
