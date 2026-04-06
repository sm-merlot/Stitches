import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart';
import 'editor_shared_widgets.dart';
import 'editor_toolbar.dart';
import 'pattern_canvas.dart';

/// The core editor layout: optional import-format banner → canvas → toolbar.
///
/// Callers are responsible for only rendering this widget when a file is open.
class EditorCanvasArea extends ConsumerWidget {
  /// When non-null, shows the import-format banner for this non-native file.
  final String? importFilePath;

  /// Called when user taps "Convert to .stitches". Null when [onOpenNative]
  /// is provided instead (i.e. a .stitches sibling already exists).
  final VoidCallback? onConvert;

  /// Called when user taps "Open .stitches". Non-null only when a native
  /// sibling already exists beside [importFilePath].
  final VoidCallback? onOpenNative;

  const EditorCanvasArea({
    super.key,
    this.importFilePath,
    this.onConvert,
    this.onOpenNative,
  }) : assert(
          importFilePath == null || onConvert != null || onOpenNative != null,
          'onConvert or onOpenNative is required when importFilePath is provided',
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (importFilePath != null)
          EditorImportBanner(
            filePath: importFilePath!,
            onConvert: onConvert,
            onOpenNative: onOpenNative,
          ),
        const Expanded(child: PatternCanvas()),
        const ProgressInfoBar(),
        const SafeArea(top: false, child: EditorToolbar()),
      ],
    );
  }
}

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
    if (progress.completedStitches.isEmpty && !state.canUndoProgress) {
      return const SizedBox.shrink();
    }

    // Count unique cells with non-backstitch stitches as the total.
    final totalCells = <(int, int)>{};
    for (final layer in state.pattern.layers) {
      for (final stitch in layer.stitches) {
        if (stitch is BackStitch) continue;
        final c = EditorState.cellCoords(stitch);
        if (c != null) totalCells.add(c);
      }
    }
    final total = totalCells.length;
    final done = progress.completedStitches.length;
    final pct = total > 0 ? (done * 100 / total).round() : 0;
    final fraction = total > 0 ? done / total : 0.0;

    // Colours done.
    final allStitches = state.pattern.stitches;
    final threads = state.pattern.threads;
    final doneColours = threads
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
                    Text('$done/$total stitches', style: style),
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
