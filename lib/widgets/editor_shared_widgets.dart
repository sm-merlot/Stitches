import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart';
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

// ─── Progress help dialog ─────────────────────────────────────────────────────

void showProgressHelpDialog(BuildContext context, WidgetRef ref,
    {EditorState? state}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => _ProgressHelpDialog(ref: ref, state: state),
  );
}

class _ProgressHelpDialog extends StatelessWidget {
  final WidgetRef ref;
  final EditorState? state;
  const _ProgressHelpDialog({required this.ref, this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    Widget? statsSection;
    if (s != null) {
      final progress = s.pattern.progress;
      final allStitches = s.pattern.stitches;
      final threads = s.pattern.threads;
      final layout = s.pageLayout;

      final totalCells = <(int, int)>{};
      var totalBack = 0;
      for (final layer in s.pattern.layers) {
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) {
            totalBack++;
          } else {
            final c = EditorState.cellCoords(stitch);
            if (c != null) totalCells.add(c);
          }
        }
      }
      final total = totalCells.length;
      final done = progress.completedStitches.length;
      final doneBack = progress.completedBackstitches.length;
      final totalAll = total + totalBack;
      final doneAll = done + doneBack;
      final pct = totalAll > 0 ? (doneAll * 100 / totalAll).round() : 0;
      final doneColours =
          threads.where((t) => progress.isColourDone(t.dmcCode, allStitches)).length;
      final donePages = progress.completedPages.length;
      final totalPages = layout?.totalPages ?? 0;
      final fraction = totalAll > 0 ? doneAll / totalAll : 0.0;
      final barColor = Color.lerp(
          Colors.orange.shade700, Colors.green.shade600, fraction)!;

      statsSection = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: fraction,
            color: barColor,
            backgroundColor: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.25),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          _StatsRow(label: 'Stitches', value: '$done / $total  ($pct%)'),
          if (totalBack > 0)
            _StatsRow(label: 'Backstitches', value: '$doneBack / $totalBack'),
          _StatsRow(label: 'Colours', value: '$doneColours / ${threads.length}'),
          if (layout != null)
            _StatsRow(label: 'Pages', value: '$donePages / $totalPages'),
          const Divider(height: 24),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Progress tracking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?statsSection,
          const _ProgressHelpRow(
              icon: Icons.touch_app_outlined,
              label: 'Tap',
              detail: 'Mark / unmark one stitch'),
          const SizedBox(height: 12),
          const _ProgressHelpRow(
              icon: Icons.mouse_outlined,
              label: 'Double-tap',
              detail:
                  'Flood fill — marks all connected stitches of the same colour (or unmarks if already done)'),
          const SizedBox(height: 12),
          const _ProgressHelpRow(
              icon: Icons.crop_outlined,
              label: 'Drag to select',
              detail:
                  'Draw a region, then tap Mark in the sidebar to mark all stitches inside it'),
        ],
      ),
      actions: [
        if ((s?.pattern.progress ?? ref.read(editorProvider).pattern.progress)
            .completedStitches.isNotEmpty)
          _ClearProgressButton(ref: ref),
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: style?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

class _ClearProgressButton extends StatelessWidget {
  final WidgetRef ref;
  const _ClearProgressButton({required this.ref});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Clear all progress?'),
            content: const Text(
                'This will remove all stitches marked as done. This can be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          ref.read(editorProvider.notifier).clearProgress();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: const Text('Clear progress'),
    );
  }
}

class _ProgressHelpRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  const _ProgressHelpRow({required this.icon, required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail, style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
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
