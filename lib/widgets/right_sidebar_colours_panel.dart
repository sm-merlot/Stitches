import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ColoursPanelMode { design, stitch, snippet }

/// Colours panel for the right sidebar.
/// Implemented in Task 9 — this is a stub.
class ColoursPanel extends ConsumerWidget {
  final ColoursPanelMode mode;
  const ColoursPanel({super.key, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO(Task 9): implement full panel
    return Center(
      child: Text('Colours (${mode.name})',
          style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
