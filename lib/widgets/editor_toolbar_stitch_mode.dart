part of 'editor_toolbar.dart';

// ─── Stitch mode toolbar ──────────────────────────────────────────────────────

class _StitchModeToolbar extends ConsumerWidget {
  const _StitchModeToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;

    final vDivider = Container(width: 1, height: 32, color: theme.dividerColor);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
        // Tinted border top to indicate mode
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      height: 56,
      child: Row(
        children: [
          // ── LEFT: View mode toggles + focus thread list ───────────────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Interaction mode: Pan / Select
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolbarButton(
                          tooltip: 'Pan  [P]',
                          selected: state.drawingMode == DrawingMode.pan,
                          onTap: () => notifier.setDrawingMode(DrawingMode.pan),
                          builder: (c) => Icon(Icons.pan_tool_outlined, size: 16, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Select  [S]',
                          selected: state.drawingMode == DrawingMode.select,
                          onTap: state.stitchViewMode != StitchViewMode.greyed
                              ? () => notifier.setDrawingMode(DrawingMode.select)
                              : null,
                          builder: (c) => Icon(Icons.select_all_outlined, size: 16, color: c),
                        ),
                      ],
                    ),
                  ),
                  vDivider,

                  // View mode: Normal / Hidden / Greyed
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolbarButton(
                          tooltip: 'Show all',
                          selected: state.stitchViewMode == StitchViewMode.normal,
                          onTap: () => notifier.setStitchViewMode(StitchViewMode.normal),
                          builder: (c) => Icon(Icons.visibility_outlined, size: 16, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Hide backstitches',
                          selected: state.stitchViewMode == StitchViewMode.hidden,
                          onTap: () => notifier.setStitchViewMode(StitchViewMode.hidden),
                          builder: (c) =>
                              Icon(Icons.visibility_off_outlined, size: 16, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Grey stitches',
                          selected: state.stitchViewMode == StitchViewMode.greyed,
                          onTap: () {
                            notifier.setStitchViewMode(StitchViewMode.greyed);
                            if (state.drawingMode == DrawingMode.select) {
                              notifier.setDrawingMode(DrawingMode.pan);
                            }
                          },
                          builder: (c) =>
                              Icon(Icons.invert_colors_outlined, size: 16, color: c),
                        ),
                      ],
                    ),
                  ),
                  vDivider,

                  // Focus thread selector: tap a thread to highlight only it
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Focus:',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Per-thread swatches
                        ...state.pattern.threads.map((t) {
                          final isFocused = state.stitchFocusThreadId == t.dmcCode;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: '${t.dmcCode} – ${t.name}',
                              child: GestureDetector(
                                onTap: () => notifier.setStitchFocusThread(
                                    isFocused ? null : t.dmcCode),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: t.color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isFocused
                                          ? primary
                                          : Colors.grey.shade400,
                                      width: isFocused ? 2.5 : 1,
                                    ),
                                    boxShadow: isFocused
                                        ? [
                                            BoxShadow(
                                              color: primary.withValues(alpha: 0.4),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: t.symbol.isNotEmpty
                                        ? Text(
                                            t.symbol,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: t.color.computeLuminance() > 0.35
                                                  ? Colors.black
                                                  : Colors.white,
                                              height: 1.0,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── RIGHT: Demonstrate + Palette ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                vDivider,
                const SizedBox(width: 4),
                _DemonstrateButton(state: state),
                const SizedBox(width: 4),
                vDivider,
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Thread palette',
                  child: IconButton(
                    icon: const Icon(Icons.palette_outlined, size: 20),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Save as snippet ──────────────────────────────────────────────────────────

void _saveAsSnippet(BuildContext context, WidgetRef ref) {
  ref.read(editorProvider.notifier).saveSelectionAsSnippet('');
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Saved as snippet'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SnippetsPanel(),
        ),
      ),
    ),
  );
  Future.delayed(const Duration(seconds: 3), messenger.hideCurrentSnackBar);
}

// ─── Demonstrate button ───────────────────────────────────────────────────────

class _DemonstrateButton extends StatelessWidget {
  final EditorState state;

  const _DemonstrateButton({required this.state});

  @override
  Widget build(BuildContext context) {
    // When a selection is active, only consider stitches within it.
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : state.pattern.stitches;
    final focusId = state.stitchFocusThreadId;
    final greyed = state.stitchViewMode == StitchViewMode.greyed;
    final hasFullStitches = !greyed &&
        pool.any((s) =>
            s is FullStitch && (focusId == null || s.threadId == focusId));
    final hasSelection = state.selectionRect != null;

    return Tooltip(
      message: hasSelection
          ? 'Demonstrate selected stitches (beta)'
          : 'Demonstrate stitching (beta)',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FilledButton.tonalIcon(
            icon: Icon(
              hasSelection ? Icons.play_circle_filled : Icons.play_circle_outline,
              size: 18,
            ),
            label: const Text(
              'Demo',
              style: TextStyle(fontSize: 12),
            ),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
            onPressed: hasFullStitches ? () => _onDemonstrate(context) : null,
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'β',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDemonstrate(BuildContext context) async {
    final pattern = state.pattern;
    final focusId = state.stitchFocusThreadId;

    // Use selected region when a selection is active, otherwise all stitches.
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : pattern.stitches;
    final fullStitches = pool.whereType<FullStitch>().toList();

    // Determine the thread to demonstrate.
    Thread? thread;
    if (focusId != null) {
      // Focus thread is active — use it directly.
      thread = pattern.threadByCode(focusId);
    } else {
      // Collect threads that have at least one FullStitch in the pool.
      final threadIds = fullStitches.map((s) => s.threadId).toSet();
      final candidates =
          pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();

      if (candidates.isEmpty) return;

      if (candidates.length == 1) {
        thread = candidates.first;
      } else {
        // Multiple threads — ask the user to pick one.
        if (!context.mounted) return;
        thread = await showDialog<Thread>(
          context: context,
          builder: (_) => ColorSelectDialog(threads: candidates),
        );
        if (thread == null) return; // cancelled
      }
    }

    if (thread == null || !context.mounted) return;

    // Collect cells for the chosen thread from the pool.
    final cells = fullStitches
        .where((s) => s.threadId == thread!.dmcCode)
        .map<(int, int)>((s) => (s.x, s.y))
        .toList();

    if (cells.isEmpty) return;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => StitchDemoScreen(
        title: pattern.name,
        cols: pattern.width,
        rows: pattern.height,
        cells: cells,
        threadColor: thread!.color,
        threadName: '${thread.dmcCode} – ${thread.name}',
        aidaColor: pattern.aidaColor,
      ),
    );
  }
}
