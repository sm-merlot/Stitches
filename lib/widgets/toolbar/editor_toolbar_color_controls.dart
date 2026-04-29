part of 'editor_toolbar.dart';

// ─── Colour swatch ────────────────────────────────────────────────────────────

class _ColorSwatch extends ConsumerWidget {
  final EditorState state;

  const _ColorSwatch({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useDmc = ref.watch(settingsProvider).useDmc;
    final thread = state.selectedThread;
    final displayCode = thread == null
        ? '—'
        : useDmc
            ? thread.dmcCode
            : (dmcColorByCode(thread.dmcCode)?.anchorCode ?? thread.dmcCode);
    final tooltipLabel = thread != null
        ? 'Thread: $displayCode – ${thread.name}'
        : 'No thread selected';

    return Tooltip(
      message: tooltipLabel,
      child: InkWell(
        onTap: () => showColorPicker(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThreadSwatch(thread: thread, size: 24),
              const SizedBox(width: 5),
              Text(
                displayCode,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick swatches (last 5 used) ────────────────────────────────────────────

class _QuickSwatches extends ConsumerWidget {
  final EditorState state;

  /// If set, limits how many swatches are shown (used on phones to fit
  /// only as many as the available width allows).
  final int? maxCount;

  const _QuickSwatches({required this.state, this.maxCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Exclude the currently selected thread; most recent rightmost (left-to-right order).
    var displayIds = state.recentThreadIds
        .where((id) => id != state.selectedThreadId)
        .toList()
        .reversed
        .toList();
    if (maxCount != null && displayIds.length > maxCount!) {
      displayIds = displayIds.sublist(displayIds.length - maxCount!);
    }
    if (displayIds.isEmpty) return const SizedBox.shrink();

    final progress = state.stitchMode ? state.pattern.progress : null;
    final allStitches = state.stitchMode ? state.pattern.stitches : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...displayIds.map((id) {
          final dmc = dmcColorByCode(id);
          final thread = state.pattern.threadByCode(id) ??
              (dmc != null
                  ? Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name)
                  : null);
          if (thread == null) return const SizedBox.shrink();

          // Compute progress counts in stitch mode.
          // Use composite cache for FullStitches to avoid double-counting
          // cells shared across layers (topmost thread wins).
          int? doneCount;
          int? totalCount;
          bool isDone = false;
          if (progress != null && allStitches != null) {
            int total = 0;
            int done = 0;
            // FullStitches via composite cache (deduplicated).
            final layer = state.compositeLayer;
            if (layer != null && layer.fullStitches.isNotEmpty) {
              for (final entry in layer.fullStitches.entries) {
                if (entry.value.resolvedThread.dmcCode != id) continue;
                total++;
                final x = entry.key.x;
                final y = entry.key.y;
                if (progress.completedStitches.contains(Cell(x, y))) {
                  done++;
                }
              }
            } else {
              final seen = <Cell>{};
              for (final s in allStitches) {
                if (s is! FullStitch || s.threadId != id) continue;
                final cell = Cell(s.x, s.y);
                if (!seen.add(cell)) continue;
                total++;
                if (progress.completedStitches.contains(cell)) done++;
              }
            }
            // Non-FullStitch cross-stitch types (no dedup needed).
            for (final s in allStitches) {
              if (s is FullStitch || s is BackStitch) continue;
              if (s.threadId != id) continue;
              final coords = EditorState.cellCoords(s);
              if (coords == null) continue;
              total++;
              if (progress.completedStitches.contains(coords)) done++;
            }
            if (total > 0) {
              doneCount = done;
              totalCount = total;
              isDone = done == total;
            }
          }

          final tooltip = progress != null && totalCount != null
              ? '${thread.dmcCode} – ${thread.name}\n$doneCount / $totalCount done'
              : '${thread.dmcCode} – ${thread.name}';

          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: tooltip,
              child: GestureDetector(
                onTap: () =>
                    ref.read(editorProvider.notifier).setSelectedThread(id),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _ThreadSwatch(thread: thread, size: 24),
                    if (isDone)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.check, size: 8, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─── Thread colour swatch with symbol overlay ─────────────────────────────────

class _ThreadSwatch extends StatelessWidget {
  final Thread? thread;
  final double size;

  const _ThreadSwatch({required this.thread, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final color = t?.color ?? Colors.grey.shade300;
    final symbol = t?.symbol ?? '';
    final textColor = color.computeLuminance() > 0.35 ? Colors.black : Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.17),
        border: Border.all(color: Colors.grey.shade400, width: 1),
      ),
      alignment: Alignment.center,
      child: symbol.isNotEmpty
          ? Text(
              symbol,
              style: TextStyle(
                fontSize: size * 0.46,
                fontWeight: FontWeight.bold,
                color: textColor,
                height: 1.0,
              ),
            )
          : null,
    );
  }
}

// ─── Aida colour button ───────────────────────────────────────────────────────

class _AidaButton extends ConsumerWidget {
  const _AidaButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aidaColor = ref.watch(editorProvider).pattern.aidaColor;
    final iconColor = aidaColor.computeLuminance() > 0.4
        ? Colors.black54
        : Colors.white70;

    return Tooltip(
      message: 'Aida fabric colour',
      child: GestureDetector(
        onTap: () => _showPicker(context, ref, aidaColor),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: aidaColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
          child: Icon(Icons.grid_on, size: 17, color: iconColor),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, Color current) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aida fabric colour'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: aidaPresets.map((p) {
            final selected = p.color.toARGB32() == current.toARGB32();
            return Tooltip(
              message: p.label,
              child: GestureDetector(
                onTap: () {
                  ref.read(editorProvider.notifier).setAidaColor(p.color);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade400,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: p.color.computeLuminance() > 0.4
                              ? Colors.black54
                              : Colors.white70,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
