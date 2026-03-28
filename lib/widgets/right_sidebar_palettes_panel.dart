import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Palettes panel for the snippet editor's right sidebar.
/// Implemented in Task 10 — this is a stub.
class PalettesPanel extends ConsumerWidget {
  const PalettesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO(Task 10): implement full panel
    return Center(
      child: Text('Palettes',
          style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
