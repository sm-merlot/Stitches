import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cell.dart';
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


// ─── Progress info bar ────────────────────────────────────────────────────────

/// Thin stats bar shown below the canvas in stitch mode when at least one
/// stitch has been marked done. Shows: stitches done/total, % done,
/// pages done (page mode only), and colours done.
class ProgressInfoBar extends ConsumerWidget {
  const ProgressInfoBar({super.key});

  static Color _barColor(int pct) =>
      Color.lerp(Colors.orange.shade700, Colors.green.shade600, pct / 100.0)!;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    if (!state.stitchMode) return const SizedBox.shrink();

    final progress = state.pattern.progress;
    // Keep the bar visible when there's undoable progress, even if cleared.
    if (progress.isEmpty && !state.canUndoProgress) {
      return const SizedBox.shrink();
    }

    // Count unique cells (cross-stitches) and individual backstitches.
    final totalCells = <Cell>{};
    var totalBack = 0;
    for (final layer in state.pattern.layers) {
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
    final fraction = totalAll > 0 ? doneAll / totalAll : 0.0;

    // Colours done.
    final allStitches = state.pattern.stitches;
    final threads = state.pattern.threads;
    final doneColours = threads.values
        .where((t) => progress.isColourDone(t.dmcCode, allStitches))
        .length;

    // Pages done (page mode only).
    final layout = state.pageLayout;
    final pageMode = layout != null;
    final donePages = progress.completedPages.length;
    final totalPages = layout?.totalPages ?? 0;

    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final barColor = _barColor(pct);
    const sep = SizedBox(width: 4);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Coloured progress bar — fills left-to-right, colour shifts orange→green.
        LinearProgressIndicator(
          value: fraction,
          color: barColor,
          backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
          minHeight: 3,
        ),
        Container(
          padding: const EdgeInsets.only(left: 12, right: 4, top: 1, bottom: 1),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          child: Row(
            children: [
              // Stats — centred in the available space
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$pct%', style: style?.copyWith(
                      color: barColor,
                      fontWeight: FontWeight.w600,
                    )),
                    sep,
                    Text('·', style: style?.copyWith(color: theme.colorScheme.outlineVariant)),
                    sep,
                    Text('$done/$total stitches${totalBack > 0 ? '  ·  $doneBack/$totalBack backstitches' : ''}', style: style),
                    if (pageMode) ...[
                      sep,
                      Text('·', style: style?.copyWith(color: theme.colorScheme.outlineVariant)),
                      sep,
                      Text('$donePages/$totalPages pages', style: style),
                    ],
                    sep,
                    Text('·', style: style?.copyWith(color: theme.colorScheme.outlineVariant)),
                    sep,
                    Text('$doneColours/${threads.length} colours', style: style),
                  ],
                ),
              ),
              // Undo / redo for progress operations
              IconButton(
                icon: const Icon(Icons.undo),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: 'Undo progress',
                onPressed: state.canUndoProgress
                    ? () => ref.read(editorProvider.notifier).undoProgress()
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: 'Redo progress',
                onPressed: state.canRedoProgress
                    ? () => ref.read(editorProvider.notifier).redoProgress()
                    : null,
              ),
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
