import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../data/symbols.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/stitch_demo_screen.dart';
import 'color_select_dialog.dart';

enum ColoursPanelMode { design, stitch, snippet }

class ColoursPanel extends ConsumerWidget {
  final ColoursPanelMode mode;
  const ColoursPanel({super.key, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (mode) {
      ColoursPanelMode.design => const _DesignColoursPanel(),
      ColoursPanelMode.stitch => const _StitchColoursPanel(),
      ColoursPanelMode.snippet => const _SnippetColoursPanel(),
    };
  }
}

// ─── Design mode ──────────────────────────────────────────────────────────────

class _DesignColoursPanel extends ConsumerWidget {
  const _DesignColoursPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final theme = Theme.of(context);

    // Thread list: composite canvas OR active layer only.
    final threads = state.showCompositeThreads
        ? _compositeThreads(state)
        : state.activeLayer.stitches
            .map((s) => s.threadId)
            .toSet()
            .map((id) => state.pattern.threads.firstWhere(
                  (t) => t.dmcCode == id,
                  orElse: () => state.pattern.threads.first,
                ))
            .toList();

    final activeLayer = state.pattern.layers.firstWhere(
        (l) => l.id == state.activeLayerId,
        orElse: () => state.pattern.layers.first);

    // Stitch counts for the current view (canvas or layer).
    final stitchCounts = state.showCompositeThreads
        ? _countStitches(state.pattern.stitches)
        : _countStitches(activeLayer.stitches);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Canvas / Layer radio buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              if (state.pattern.layers.any((l) => l.visible && l.opacity < 0.99))
                Tooltip(
                  message:
                      'Opacity active — Canvas shows resulting blended colours.',
                  child: Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.primary),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: true, label: Text('Canvas')),
                    ButtonSegment(
                      value: false,
                      label: Text(activeLayer.name,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  selected: {state.showCompositeThreads},
                  onSelectionChanged: (s) {
                    notifier.setShowCompositeThreads(s.first);
                    if (s.first) notifier.refreshCompositeCache();
                  },
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ThreadList(
            threads: threads,
            selectedThreadId: state.selectedThreadId,
            useDmc: useDmc,
            stitchCounts: stitchCounts,
            onTap: (t) => notifier.setSelectedThread(t.dmcCode),
            onLongPress: (t) => _showSymbolPicker(context, notifier, t),
          ),
        ),
      ],
    );
  }

  List<Thread> _compositeThreads(EditorState state) {
    if (state.compositeThreadCache != null &&
        state.compositeThreadCache!.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in state.compositeThreadCache!.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return state.pattern.threads;
  }
}

Map<String, int> _countStitches(List<Stitch> stitches) {
  final counts = <String, int>{};
  for (final s in stitches) {
    counts[s.threadId] = (counts[s.threadId] ?? 0) + 1;
  }
  return counts;
}

// ─── Stitch mode ──────────────────────────────────────────────────────────────

class _StitchColoursPanel extends ConsumerWidget {
  const _StitchColoursPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final theme = Theme.of(context);

    final threads = _compositeThreads(state);
    final stitchCounts = _countStitchesComposite(state);

    // Only show the stitch focus row when both types of stitch are present.
    final allStitches = state.pattern.stitches;
    final hasNonBack = allStitches.any((s) => s is! BackStitch);
    final hasBack = allStitches.any((s) => s is BackStitch);
    final showFocus = hasNonBack && hasBack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Stitch Focus header ─────────────────────────────────────────────
        if (showFocus) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Stitch Focus:',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(width: 6),
                _FocusToggle(
                  label: 'Cross',
                  icon: Icons.close,
                  active: state.stitchCrossMode,
                  onTap: () =>
                      notifier.setStitchCrossMode(!state.stitchCrossMode),
                  theme: theme,
                ),
                const SizedBox(width: 4),
                _FocusToggle(
                  label: 'Back',
                  icon: Icons.show_chart,
                  active: state.stitchBackMode,
                  onTap: () =>
                      notifier.setStitchBackMode(!state.stitchBackMode),
                  theme: theme,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        // ── Thread list with focus ────────────────────────────────────────
        Expanded(
          child: _ThreadList(
            threads: threads,
            selectedThreadId: state.stitchFocusThreadId,
            useDmc: useDmc,
            stitchCounts: stitchCounts,
            onTap: (t) => notifier.setStitchFocusThread(
                state.stitchFocusThreadId == t.dmcCode ? null : t.dmcCode),
            focusMode: true,
          ),
        ),
      ],
    );
  }

  List<Thread> _compositeThreads(EditorState state) {
    if (state.compositeThreadCache != null &&
        state.compositeThreadCache!.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in state.compositeThreadCache!.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return state.pattern.threads;
  }

  /// Counts stitches using composite cache for FullStitches (so blended cells
  /// are attributed to the composite DMC code, not the raw per-layer thread)
  /// and raw threadId for non-FullStitch types.
  Map<String, int> _countStitchesComposite(EditorState state) {
    final cache = state.compositeThreadCache;
    if (cache == null || cache.isEmpty) {
      return _countStitches(state.pattern.stitches);
    }
    final counts = <String, int>{};
    // FullStitch cells → composite result
    for (final thread in cache.values) {
      counts[thread.dmcCode] = (counts[thread.dmcCode] ?? 0) + 1;
    }
    // Non-FullStitch stitches → raw threadId
    for (final s in state.pattern.stitches) {
      if (s is FullStitch) continue;
      counts[s.threadId] = (counts[s.threadId] ?? 0) + 1;
    }
    return counts;
  }
}

class _FocusToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FocusToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:
              active ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? theme.colorScheme.onPrimaryContainer : null),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? theme.colorScheme.onPrimaryContainer : null,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Demo button — launches [StitchDemoScreen]. Used in stitch-mode AppBar.
class StitchDemoButton extends StatelessWidget {
  final EditorState state;
  const StitchDemoButton({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : state.pattern.stitches;
    final focusId = state.stitchFocusThreadId;
    final hasFullStitches = !state.stitchBackMode &&
        pool.any((s) =>
            s is FullStitch && (focusId == null || s.threadId == focusId));

    return Tooltip(
      message: 'Demonstrate stitching (beta)',
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.play_circle_outline, size: 16),
              label: const Text('Demo', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: const Size(0, 32),
              ),
              onPressed: hasFullStitches ? () => _onDemonstrate(context) : null,
            ),
            Positioned(
              top: -5,
              right: -5,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('β',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        height: 1.3)),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _onDemonstrate(BuildContext context) async {
    final pattern = state.pattern;
    final focusId = state.stitchFocusThreadId;
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : pattern.stitches;
    final fullStitches = pool.whereType<FullStitch>().toList();

    Thread? thread;
    if (focusId != null) {
      thread = pattern.threadByCode(focusId);
    } else {
      final threadIds = fullStitches.map((s) => s.threadId).toSet();
      final candidates =
          pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
      if (candidates.isEmpty) return;
      if (candidates.length == 1) {
        thread = candidates.first;
      } else {
        if (!context.mounted) return;
        thread = await showDialog<Thread>(
          context: context,
          builder: (_) => ColorSelectDialog(threads: candidates),
        );
        if (thread == null) return;
      }
    }

    if (thread == null || !context.mounted) return;

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

// ─── Snippet mode ──────────────────────────────────────────────────────────────

class _SnippetColoursPanel extends ConsumerWidget {
  const _SnippetColoursPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final useDmc = ref.watch(settingsProvider).useDmc;

    final palettes = state.snippetPalettes;
    final activeIdx = state.snippetActivePaletteIndex;
    final threads = (palettes.isNotEmpty && activeIdx < palettes.length)
        ? palettes[activeIdx].threads
        : state.pattern.threads;

    final stitchCounts = _countStitches(state.pattern.stitches);

    return _ThreadList(
      threads: threads,
      selectedThreadId: state.selectedThreadId,
      useDmc: useDmc,
      stitchCounts: stitchCounts,
      onTap: (t) => notifier.setSelectedThread(t.dmcCode),
      onLongPress: (t) => _showSymbolPicker(context, notifier, t),
    );
  }
}

// ─── Shared thread list ───────────────────────────────────────────────────────

class _ThreadList extends StatelessWidget {
  final List<Thread> threads;
  final String? selectedThreadId;
  final bool useDmc;
  final Map<String, int> stitchCounts;
  final void Function(Thread) onTap;
  final void Function(Thread)? onLongPress;
  final bool focusMode;

  const _ThreadList({
    required this.threads,
    required this.selectedThreadId,
    required this.useDmc,
    required this.stitchCounts,
    required this.onTap,
    this.onLongPress,
    this.focusMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No threads yet.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    final sorted = [...threads]..sort((a, b) {
        if (useDmc) {
          final ia = int.tryParse(a.dmcCode) ?? 999999;
          final ib = int.tryParse(b.dmcCode) ?? 999999;
          return ia != ib
              ? ia.compareTo(ib)
              : a.dmcCode.compareTo(b.dmcCode);
        } else {
          final anchorA = dmcColorByCode(a.dmcCode)?.anchorCode;
          final anchorB = dmcColorByCode(b.dmcCode)?.anchorCode;
          final ia = int.tryParse(anchorA ?? '') ?? 999999;
          final ib = int.tryParse(anchorB ?? '') ?? 999999;
          return ia != ib
              ? ia.compareTo(ib)
              : (anchorA ?? '').compareTo(anchorB ?? '');
        }
      });
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final t = sorted[i];
        final isSelected = t.dmcCode == selectedThreadId;
        final code = useDmc
            ? t.dmcCode
            : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
        final textColor = t.color.computeLuminance() > 0.35
            ? Colors.black
            : Colors.white;
        final count = stitchCounts[t.dmcCode];

        return InkWell(
          onTap: () => onTap(t),
          onLongPress: onLongPress != null ? () => onLongPress!(t) : null,
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                  )
                : const BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            color: Colors.transparent, width: 3))),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Colour swatch with symbol
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: t.color,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.grey.shade400, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: t.symbol.isNotEmpty
                      ? Text(t.symbol,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                              height: 1.0))
                      : null,
                ),
                const SizedBox(width: 8),
                // Code + name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      Text(t.name,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // Stitch count
                if (count != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close,
                        size: 10,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Symbol picker ────────────────────────────────────────────────────────────

Future<void> _showSymbolPicker(
  BuildContext context,
  EditorNotifier notifier,
  Thread thread,
) async {
  final symbol = await showDialog<String>(
    context: context,
    builder: (_) => _SymbolPickerDialog(current: thread.symbol),
  );
  if (symbol != null) {
    notifier.setThreadSymbol(thread.dmcCode, symbol);
  }
}

class _SymbolPickerDialog extends StatefulWidget {
  final String current;
  const _SymbolPickerDialog({required this.current});

  @override
  State<_SymbolPickerDialog> createState() => _SymbolPickerDialogState();
}

class _SymbolPickerDialogState extends State<_SymbolPickerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(String symbol) {
    Navigator.of(context).pop(symbol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Edit symbol'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Custom input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Custom symbol',
                      hintText: 'Type any character…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLength: 2,
                    style: const TextStyle(fontSize: 18),
                    onSubmitted: (v) {
                      if (v.isNotEmpty) _pick(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Or choose from the list:',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 6),
            // Symbol grid
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: kPatternSymbols.map((s) {
                    final isSelected = _controller.text == s;
                    return GestureDetector(
                      onTap: () => _pick(s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(s,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurface,
                            )),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final v = _controller.text;
            if (v.isNotEmpty) _pick(v);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
