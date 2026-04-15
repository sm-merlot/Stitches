import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../utils/snackbars.dart';

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
      message: keepOn ? 'Keep screen on: on' : 'Keep screen on: off',
      child: IconButton(
        isSelected: keepOn,
        icon: const Icon(Icons.lock_open_outlined),
        selectedIcon: const Icon(Icons.lock),
        style: keepOn
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              )
            : null,
        onPressed: () {
          final next = !keepOn;
          ref.read(settingsProvider.notifier).setKeepScreenOn(next);
          if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
            showSuccess(context,
                next ? 'Screen will stay on' : 'Screen can now sleep',
                duration: const Duration(seconds: 2));
          }
        },
      ),
    );
  }
}


// ─── Import format banner ─────────────────────────────────────────────────────

class EditorImportBanner extends StatelessWidget {
  final String filePath;

  /// Called when the user taps "Convert to .stitches". Null if a native
  /// .stitches file already exists beside this file (use [onOpenNative]).
  final VoidCallback? onConvert;

  /// Called when the user taps "Open .stitches". Non-null only when a native
  /// sibling already exists.
  final VoidCallback? onOpenNative;

  const EditorImportBanner({
    required this.filePath,
    this.onConvert,
    this.onOpenNative,
    super.key,
  }) : assert(onConvert != null || onOpenNative != null,
            'At least one of onConvert or onOpenNative must be provided');

  String get _ext {
    final dot = filePath.lastIndexOf('.');
    return dot >= 0 ? filePath.substring(dot + 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buttonLabel =
        onOpenNative != null ? 'Open .stitches' : 'Convert to .stitches';
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
                'Viewing $_ext file — read-only mode.',
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
              onPressed: onOpenNative ?? onConvert,
              child: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
