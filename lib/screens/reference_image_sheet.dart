import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor/editor_provider.dart';

class ReferenceImageSheet extends ConsumerWidget {
  const ReferenceImageSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final hasImage = state.referenceImage != null;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Reference Image',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Overlay an image on the canvas as a drawing guide. '
              'Not saved as part of the pattern artwork.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // Current image path or placeholder
            if (hasImage) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _basename(state.pattern.referenceImagePath ?? ''),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Visibility toggle
              Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Visible')),
                  Switch(
                    value: state.referenceVisible,
                    onChanged: (_) => notifier.toggleReferenceVisible(),
                  ),
                ],
              ),

              // Opacity slider
              Row(
                children: [
                  const Icon(Icons.opacity, size: 18),
                  const SizedBox(width: 8),
                  const Text('Opacity'),
                  Expanded(
                    child: Slider(
                      value: state.referenceOpacity,
                      min: 0.05,
                      max: 1.0,
                      divisions: 19,
                      label: '${(state.referenceOpacity * 100).round()}%',
                      onChanged: notifier.setReferenceOpacity,
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${(state.referenceOpacity * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'No reference image selected.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(hasImage ? 'Replace Image' : 'Choose Image'),
                    onPressed: () async {
                      await notifier.pickReferenceImage();
                    },
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: Icon(Icons.delete_outline,
                        color: theme.colorScheme.error),
                    label: Text('Remove',
                        style: TextStyle(color: theme.colorScheme.error)),
                    onPressed: () {
                      notifier.clearReferenceImage();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _basename(String path) {
    if (path.isEmpty) return '';
    return path.split(RegExp(r'[/\\]')).last;
  }
}
