import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

// ─── Shared popup menu row ────────────────────────────────────────────────────

class EditorMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const EditorMenuRow(
      {required this.icon, required this.label, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

// ─── Screen lock toggle button ────────────────────────────────────────────────

class EditorScreenLockButton extends ConsumerWidget {
  const EditorScreenLockButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keepOn = ref.watch(settingsProvider).keepScreenOn;
    return Tooltip(
      message: keepOn ? 'Screen lock: off' : 'Screen lock: on',
      child: IconButton(
        isSelected: keepOn,
        icon: const Icon(Icons.screen_lock_portrait_outlined),
        selectedIcon: const Icon(Icons.screen_lock_portrait),
        style: keepOn
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              )
            : null,
        onPressed: () =>
            ref.read(settingsProvider.notifier).setKeepScreenOn(!keepOn),
      ),
    );
  }
}

// ─── Import format banner ─────────────────────────────────────────────────────

class EditorImportBanner extends StatelessWidget {
  final String filePath;
  final VoidCallback onSaveAs;

  /// When true, the banner also mentions Drive sync (workspace context).
  final bool showDriveNote;

  const EditorImportBanner({
    required this.filePath,
    required this.onSaveAs,
    this.showDriveNote = false,
    super.key,
  });

  String get _ext {
    final dot = filePath.lastIndexOf('.');
    return dot >= 0 ? filePath.substring(dot + 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final features = showDriveNote ? 'snippets and Drive sync' : 'snippets';
    return Material(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Imported $_ext file — $features require .stitches format.',
                style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs.onTertiaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onSaveAs,
              child: const Text('Save As .stitches',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
