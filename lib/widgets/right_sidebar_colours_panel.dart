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
import 'editor_shared_widgets.dart';

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
        ? _countStitchesComposite(state)
        : _countStitches(activeLayer.stitches);

    // Symbol issue count (no symbol, duplicate, or similar) across displayed threads.
    // Uses `threads` (canvas composites or layer threads) so the banner matches
    // what _ThreadList actually shows.
    final allSymbolCounts = <String, int>{};
    for (final t in threads) {
      if (symbolIsVisible(t.symbol) && !symbolIsPdfUnsupported(t.symbol)) {
        allSymbolCounts[t.symbol] = (allSymbolCounts[t.symbol] ?? 0) + 1;
      }
    }
    final allGroupSymbols = <int, Set<String>>{};
    for (final t in threads) {
      if (symbolIsVisible(t.symbol) && !symbolIsPdfUnsupported(t.symbol)) {
        final g = symbolSimilarityGroup(t.symbol);
        if (g >= 0) (allGroupSymbols[g] ??= {}).add(t.symbol);
      }
    }
    final allConflictingGroups = allGroupSymbols.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();
    final issueCount = threads
        .where((t) {
          if (!symbolIsVisible(t.symbol)) return true;
          if (symbolIsPdfUnsupported(t.symbol)) return true;
          if ((allSymbolCounts[t.symbol] ?? 0) > 1) return true;
          final g = symbolSimilarityGroup(t.symbol);
          return g >= 0 && allConflictingGroups.contains(g);
        })
        .length;

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
        if (issueCount > 0) ...[
          Container(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
            padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 13, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$issueCount symbol ${issueCount == 1 ? 'issue' : 'issues'}',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _autoFixSymbols(notifier, state.pattern.threads);
                    // Rebuild composite cache so blended-thread symbols are
                    // also reassigned using the fixed pattern-thread symbols.
                    if (state.showCompositeThreads) {
                      notifier.refreshCompositeCache();
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 0),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Auto-fix'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: _ThreadList(
            threads: threads,
            selectedThreadId: state.selectedThreadId,
            useDmc: useDmc,
            stitchCounts: stitchCounts,
            onTap: (t) => notifier.setSelectedThread(t.dmcCode),
            onSwatchTap: (t) {
              final isLayerThread = state.pattern.threads
                  .any((pt) => pt.dmcCode == t.dmcCode);
              if (isLayerThread) {
                _showSymbolPicker(
                  context, notifier, t,
                  state.pattern.threads
                      .where((pt) => pt.dmcCode != t.dmcCode)
                      .map((pt) => pt.symbol)
                      .where(symbolIsVisible)
                      .toSet(),
                );
              } else {
                // Composite thread — use changeCompositeSymbol so the
                // compositeSymbols registry (and PDF) is updated correctly.
                final usedSymbols = <String>{
                  ...state.pattern.threads
                      .map((pt) => pt.symbol)
                      .where(symbolIsVisible),
                  ...state.pattern.compositeSymbols.entries
                      .where((e) => e.key != t.dmcCode)
                      .map((e) => e.value)
                      .where(symbolIsVisible),
                };
                _showCompositeSymbolPicker(
                    context, notifier, t, usedSymbols);
              }
            },
          ),
        ),
      ],
    );
  }

  List<Thread> _compositeThreads(EditorState state) {
    final cache = state.compositeResult?.compositeThreads;
    if (cache != null && cache.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in cache.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return state.pattern.threads;
  }
}

/// Assigns new symbols to every thread that:
/// - has no visible symbol,
/// - shares its exact symbol with another thread (duplicate), or
/// - uses a symbol from the same visual-similarity group as another thread.
/// Lowest DMC number keeps its symbol when resolving conflicts.
void _autoFixSymbols(EditorNotifier notifier, List<Thread> allThreads) {
  final sorted = [...allThreads]..sort((a, b) {
      final ia = int.tryParse(a.dmcCode) ?? 999999;
      final ib = int.tryParse(b.dmcCode) ?? 999999;
      return ia != ib ? ia.compareTo(ib) : a.dmcCode.compareTo(b.dmcCode);
    });

  // Phase 1: collect kept symbols, flagging no-symbol, PDF-incompatible, and exact duplicates.
  final kept = <String>{};
  final toFix = <String>{};  // dmcCodes that need a new symbol
  for (final t in sorted) {
    if (!symbolIsVisible(t.symbol) || symbolIsPdfUnsupported(t.symbol) ||
        kept.contains(t.symbol)) {
      toFix.add(t.dmcCode);
    } else {
      kept.add(t.symbol);
    }
  }

  // Phase 2: flag similar-symbol conflicts. Lowest DMC keeps its symbol;
  // higher-DMC threads whose symbol shares a group get reassigned.
  final usedGroups = <int, String>{};  // groupIndex → symbol that claimed it
  for (final t in sorted) {
    if (toFix.contains(t.dmcCode)) continue;
    final g = symbolSimilarityGroup(t.symbol);
    if (g < 0) continue;
    if (usedGroups.containsKey(g)) {
      toFix.add(t.dmcCode);
      kept.remove(t.symbol);
    } else {
      usedGroups[g] = t.symbol;
    }
  }

  // Assign new symbols — pick candidates not in kept and not in a conflicting group.
  for (final t in sorted) {
    if (!toFix.contains(t.dmcCode)) continue;
    for (final s in kPatternSymbols) {
      if (kept.contains(s)) continue;
      final g = symbolSimilarityGroup(s);
      if (g >= 0 && usedGroups.containsKey(g)) continue;
      kept.add(s);
      if (g >= 0) usedGroups[g] = s;
      notifier.setThreadSymbol(t.dmcCode, s);
      break;
    }
  }
}

/// Counts how many completed-progress stitches (cross + back) belong to each thread.
Map<String, int> _countDoneStitches(EditorState state) {
  final progress = state.pattern.progress;
  final counts = <String, int>{};
  for (final layer in state.pattern.layers) {
    for (final stitch in layer.stitches) {
      final bool isDone;
      if (stitch is BackStitch) {
        isDone = progress.isBackstitchDone(
            stitch.x1, stitch.y1, stitch.x2, stitch.y2);
      } else {
        final c = EditorState.cellCoords(stitch);
        isDone = c != null && progress.completedStitches.contains(c);
      }
      if (isDone) {
        counts[stitch.threadId] = (counts[stitch.threadId] ?? 0) + 1;
      }
    }
  }
  return counts;
}

Map<String, int> _countStitches(List<Stitch> stitches) {
  final counts = <String, int>{};
  for (final s in stitches) {
    counts[s.threadId] = (counts[s.threadId] ?? 0) + 1;
  }
  return counts;
}

/// Counts stitches using the composite cache for FullStitches (deduplicates
/// cells shared across layers) and raw threadId for non-FullStitch types.
Map<String, int> _countStitchesComposite(EditorState state) {
  final cache = state.compositeResult?.compositeThreads;
  if (cache == null || cache.isEmpty) {
    return _countStitches(state.pattern.stitches);
  }
  final counts = <String, int>{};
  for (final thread in cache.values) {
    counts[thread.dmcCode] = (counts[thread.dmcCode] ?? 0) + 1;
  }
  for (final s in state.pattern.stitches) {
    if (s is FullStitch) continue;
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
    final progress = state.pattern.progress;
    final doneCounts = !progress.isEmpty
        ? _countDoneStitches(state)
        : null;

    // Only show the stitch focus row when both types of stitch are present.
    final allStitches = state.pattern.stitches;
    final hasNonBack = allStitches.any((s) => s is! BackStitch);
    final hasBack = allStitches.any((s) => s is BackStitch);
    final showFocus = hasNonBack && hasBack;

    final totalCross = stitchCounts.values
        .fold<int>(0, (sum, c) => sum + c) -
        allStitches.whereType<BackStitch>().length;
    final totalBack = allStitches.whereType<BackStitch>().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Total stitch count summary ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: [
              Icon(Icons.grid_4x4, size: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                '$totalCross stitches${totalBack > 0 ? '  •  $totalBack backstitches' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
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
            doneCounts: doneCounts,
            onTap: (t) => notifier.setStitchFocusThread(
                state.stitchFocusThreadId == t.dmcCode ? null : t.dmcCode),
            focusMode: true,
          ),
        ),
      ],
    );
  }

  List<Thread> _compositeThreads(EditorState state) {
    final cache = state.compositeResult?.compositeThreads;
    if (cache != null && cache.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in cache.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return state.pattern.threads;
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

/// Demo button — launches [StitchDemoScreen]. Shown at the bottom of the
/// stitch-mode sidebar. Enabled only when stitches are rubber-band selected
/// on the canvas. If focus mode is active (one colour highlighted) that colour
/// is used directly; otherwise a picker is shown for multi-colour selections.
class StitchDemoButton extends StatelessWidget {
  final EditorState state;
  const StitchDemoButton({super.key, required this.state});

  /// Returns the pool of stitches for the Demo button.
  /// In stitch mode: stitches within progressRegion (page-filtered if needed).
  /// In edit mode: selectedStitches from selectionRect.
  /// Fallback: all pattern stitches.
  List<Stitch> _stitchPool() {
    final region = state.stitchMode ? state.progressRegion : state.selectionRect;
    if (region != null) {
      final layout = state.pageLayout;
      final (pageCol, pageRow) = layout != null
          ? layout.pageCoords(state.currentPage)
          : (0, 0);
      final stitches = <Stitch>[];
      for (final layer in state.pattern.layers) {
        if (!layer.visible) continue;
        for (final stitch in layer.stitches) {
          if (stitch is BackStitch) continue;
          final coords = EditorState.cellCoords(stitch);
          if (coords == null) continue;
          final (sx, sy) = coords;
          if (sx >= region.left && sx < region.right &&
              sy >= region.top && sy < region.bottom) {
            if (layout != null && !layout.cellOnPage(sx, sy, pageCol, pageRow)) continue;
            stitches.add(stitch);
          }
        }
      }
      return stitches;
    }
    if (state.selectionRect != null) return state.selectedStitches;
    return state.pattern.stitches;
  }

  @override
  Widget build(BuildContext context) {
    // Enabled only when the user has a selection or progress region with stitches,
    // and at least one is a FullStitch matching the focused thread (if any).
    final focusId = state.stitchFocusThreadId;
    final hasRegion = state.stitchMode
        ? state.progressRegion != null
        : state.selectionRect != null;
    final pool = _stitchPool();
    final enabled = hasRegion &&
        pool.any((s) => s is FullStitch && (focusId == null || s.threadId == focusId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: enabled
                ? null
                : () {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                        content:
                            Text('Select some stitches on the canvas first'),
                        duration: Duration(seconds: 2),
                      ));
                  },
            child: FilledButton.icon(
              icon: const Icon(Icons.play_circle_outline, size: 16),
              label: const Text('Demo', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: enabled ? () => _onDemonstrate(context) : null,
            ),
          ),
          Positioned(
            top: -5,
            right: -5,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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
    );
  }

  Future<void> _onDemonstrate(BuildContext context) async {
    final pattern = state.pattern;
    final focusId = state.stitchFocusThreadId;
    final fullStitches = _stitchPool().whereType<FullStitch>().toList();

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

    // Stitches always reference primary-palette DMC codes. For a secondary
    // palette we remap counts slot-by-slot: secondary[i] inherits the count
    // from primary[i], so the list shows identical numbers regardless of
    // which palette is active.
    final rawCounts = _countStitches(state.pattern.stitches);
    final Map<String, int> stitchCounts;
    if (activeIdx == 0 || palettes.isEmpty) {
      stitchCounts = rawCounts;
    } else {
      final primary = palettes[0].threads;
      stitchCounts = {
        for (var i = 0; i < threads.length && i < primary.length; i++)
          threads[i].dmcCode: rawCounts[primary[i].dmcCode] ?? 0,
      };
    }

    return _ThreadList(
      threads: threads,
      selectedThreadId: state.selectedThreadId,
      useDmc: useDmc,
      stitchCounts: stitchCounts,
      onTap: (t) => notifier.setSelectedThread(t.dmcCode),
      onSwatchTap: (t) => _showSymbolPicker(
        context, notifier, t,
        state.pattern.threads
            .where((pt) => pt.dmcCode != t.dmcCode)
            .map((pt) => pt.symbol)
            .where(symbolIsVisible)
            .toSet(),
      ),
    );
  }
}

// ─── Shared thread list ───────────────────────────────────────────────────────

class _ThreadList extends ConsumerWidget {
  final List<Thread> threads;
  final String? selectedThreadId;
  final bool useDmc;
  final Map<String, int> stitchCounts;
  /// Per-thread done counts — when non-null, shows `done/total` instead of `total`.
  final Map<String, int>? doneCounts;
  final void Function(Thread) onTap;
  final void Function(Thread)? onSwatchTap;
  final bool focusMode;

  const _ThreadList({
    required this.threads,
    required this.selectedThreadId,
    required this.useDmc,
    required this.stitchCounts,
    this.doneCounts,
    required this.onTap,
    this.onSwatchTap,
    this.focusMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (threads.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No threads yet.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sortMode = settings.colourSortMode;
    final completedLast = settings.completedColoursLast;

    // Pre-compute duplicate symbols across the displayed list.
    final symbolCounts = <String, int>{};
    for (final t in threads) {
      if (symbolIsVisible(t.symbol) && !symbolIsPdfUnsupported(t.symbol)) {
        symbolCounts[t.symbol] = (symbolCounts[t.symbol] ?? 0) + 1;
      }
    }
    // Pre-compute similar-symbol conflicts (different symbols from same group).
    final groupSymbols = <int, Set<String>>{};
    for (final t in threads) {
      if (symbolIsVisible(t.symbol) && !symbolIsPdfUnsupported(t.symbol)) {
        final g = symbolSimilarityGroup(t.symbol);
        if (g >= 0) (groupSymbols[g] ??= {}).add(t.symbol);
      }
    }
    final conflictingGroups = groupSymbols.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();

    bool isSimilarOnly(Thread t) {
      if (!symbolIsVisible(t.symbol) || symbolIsPdfUnsupported(t.symbol)) return false;
      if ((symbolCounts[t.symbol] ?? 0) > 1) return false; // already a dup
      final g = symbolSimilarityGroup(t.symbol);
      return g >= 0 && conflictingGroups.contains(g);
    }

    bool isThreadComplete(Thread t) {
      if (doneCounts == null) return false;
      final total = stitchCounts[t.dmcCode] ?? 0;
      final done = doneCounts![t.dmcCode] ?? 0;
      return total > 0 && done >= total;
    }

    final sorted = [...threads]..sort((a, b) {
        // Completed colours last (only when doneCounts available and toggle on).
        if (completedLast && doneCounts != null) {
          final aDone = isThreadComplete(a);
          final bDone = isThreadComplete(b);
          if (aDone != bDone) return aDone ? 1 : -1;
        }
        // No-symbol (incl. PDF-incompatible) first, then duplicates, then similar, then normal.
        final aNoSym = !symbolIsVisible(a.symbol) || symbolIsPdfUnsupported(a.symbol);
        final bNoSym = !symbolIsVisible(b.symbol) || symbolIsPdfUnsupported(b.symbol);
        if (aNoSym != bNoSym) return aNoSym ? -1 : 1;
        final aDup = !aNoSym && (symbolCounts[a.symbol] ?? 0) > 1;
        final bDup = !bNoSym && (symbolCounts[b.symbol] ?? 0) > 1;
        if (aDup != bDup) return aDup ? -1 : 1;
        final aSim = !aDup && isSimilarOnly(a);
        final bSim = !bDup && isSimilarOnly(b);
        if (aSim != bSim) return aSim ? -1 : 1;
        // Secondary: sort by chosen mode.
        if (sortMode == ColourSortMode.byStitchCount) {
          final ca = stitchCounts[a.dmcCode] ?? 0;
          final cb = stitchCounts[b.dmcCode] ?? 0;
          if (ca != cb) return cb.compareTo(ca); // descending
        }
        // Fallback / byId: numeric code sort.
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

    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Sort controls ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
          child: Row(
            children: [
              Text('Sort:',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6))),
              const SizedBox(width: 4),
              Expanded(
                child: SegmentedButton<ColourSortMode>(
                  segments: [
                    ButtonSegment(
                      value: ColourSortMode.byId,
                      label: Text(useDmc ? 'DMC' : 'Anchor'),
                    ),
                    const ButtonSegment(
                      value: ColourSortMode.byStitchCount,
                      label: Text('Count'),
                    ),
                  ],
                  selected: {sortMode},
                  onSelectionChanged: (s) =>
                      settingsNotifier.setColourSortMode(s.first),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              if (doneCounts != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Completed colours last',
                  child: IconButton(
                    icon: Icon(
                      completedLast
                          ? Icons.vertical_align_bottom
                          : Icons.vertical_align_bottom_outlined,
                      size: 18,
                      color: completedLast
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.4),
                    ),
                    onPressed: () => settingsNotifier
                        .setCompletedColoursLast(!completedLast),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Thread list ────────────────────────────────────────────────
        Expanded(child: ListView.builder(
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

        final hasSymbol = symbolIsVisible(t.symbol);
        final isPdfBad = hasSymbol && symbolIsPdfUnsupported(t.symbol);
        final isDuplicate = hasSymbol && !isPdfBad && (symbolCounts[t.symbol] ?? 0) > 1;
        final isSimilar = !isPdfBad && isSimilarOnly(t);
        // PDF-incompatible symbols are treated as "no symbol" for display.
        final effectivelyNoSymbol = !hasSymbol || isPdfBad;

        final swatchBorderColor = effectivelyNoSymbol
            ? Colors.orange.shade600
            : isDuplicate
                ? Colors.red.shade500
                : isSimilar
                    ? Colors.amber.shade600
                    : Colors.grey.shade400;

        Widget swatch = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: t.color,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: swatchBorderColor,
              width: (effectivelyNoSymbol || isDuplicate || isSimilar) ? 1.5 : 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: effectivelyNoSymbol
              ? Text('?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textColor.withValues(alpha: 0.4),
                      height: 1.0))
              : Text(t.symbol,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.0)),
        );
        if (isDuplicate || isSimilar) {
          swatch = Stack(
            clipBehavior: Clip.none,
            children: [
              swatch,
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: isDuplicate
                        ? Colors.red.shade500
                        : Colors.amber.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(isDuplicate ? '!' : '~',
                      style: const TextStyle(
                          fontSize: 7,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          height: 1.0)),
                ),
              ),
            ],
          );
        }
        if (onSwatchTap != null) {
          swatch = Tooltip(
            message: isPdfBad
                ? "Symbol '${t.symbol}' won't render in PDF — tap to assign a compatible one"
                : !hasSymbol
                    ? 'No symbol — tap to assign'
                    : isDuplicate
                        ? 'Duplicate symbol — tap to fix'
                        : isSimilar
                            ? 'Similar to another symbol — may be hard to distinguish'
                            : 'Tap to edit symbol',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSwatchTap!(t),
                child: swatch,
              ),
            ),
          );
        }

        return InkWell(
          onTap: () => onTap(t),
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
                swatch,
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
                        doneCounts != null
                            ? '${doneCounts![t.dmcCode] ?? 0}/$count'
                            : '$count',
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
    )),
      ],
    );
  }
}

// ─── Symbol picker ────────────────────────────────────────────────────────────

Future<void> _showSymbolPicker(
  BuildContext context,
  EditorNotifier notifier,
  Thread thread,
  Set<String> usedSymbols,
) async {
  final symbol = await showDialog<String>(
    context: context,
    builder: (_) => _SymbolPickerDialog(
      current: symbolIsVisible(thread.symbol) ? thread.symbol : '',
      usedSymbols: usedSymbols,
    ),
  );
  if (symbol != null) {
    notifier.setThreadSymbol(thread.dmcCode, symbol);
  }
}

/// Symbol picker for composite (blended-layer) threads.
/// Uses [changeCompositeSymbol] so the compositeSymbols registry is updated
/// rather than the layer-thread list.
Future<void> _showCompositeSymbolPicker(
  BuildContext context,
  EditorNotifier notifier,
  Thread thread,
  Set<String> usedSymbols,
) async {
  final symbol = await showDialog<String>(
    context: context,
    builder: (_) => _SymbolPickerDialog(
      current: symbolIsVisible(thread.symbol) ? thread.symbol : '',
      usedSymbols: usedSymbols,
    ),
  );
  if (symbol != null) {
    notifier.changeCompositeSymbol(thread.dmcCode, symbol);
  }
}

class _SymbolPickerDialog extends StatefulWidget {
  final String current;
  final Set<String> usedSymbols;
  const _SymbolPickerDialog({
    required this.current,
    this.usedSymbols = const {},
  });

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

  Widget _symbolTile(String s, ThemeData theme, {bool disabled = false}) {
    final isSelected = !disabled && _controller.text == s;
    return GestureDetector(
      onTap: disabled ? null : () => _pick(s),
      child: Opacity(
        opacity: disabled ? 0.3 : 1.0,
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
      ),
    );
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
            // Symbol grid — available symbols first, in-use greyed out below
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: kPatternSymbols
                          .where((s) => !widget.usedSymbols.contains(s))
                          .map((s) => _symbolTile(s, theme))
                          .toList(),
                    ),
                    if (widget.usedSymbols
                        .any((s) => kPatternSymbols.contains(s))) ...[
                      const SizedBox(height: 10),
                      Text('Already in use:',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45))),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: kPatternSymbols
                            .where((s) => widget.usedSymbols.contains(s))
                            .map((s) => _symbolTile(s, theme, disabled: true))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 4),
                  ],
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

// ─── MarkDoneButton ──────────────────────────────────────────────────────────

/// "Mark done" / "Mark not done" button shown in the stitch-mode sidebar.
///
/// • No selection → visible but disabled; tapping opens the progress info dialog.
/// • Selection with stitches on the current page:
///   - All done → shows "Unmark" (orange)
///   - Otherwise → shows "Mark"
/// Pressing the button does NOT deselect the region so the user can act again.
class MarkDoneButton extends ConsumerWidget {
  final EditorState state;
  const MarkDoneButton({super.key, required this.state});

  /// Whether the region contains any visible stitches (cross or back) on the
  /// current page that match the focus thread (if one is active).
  static bool _regionHasPageStitches(EditorState s) {
    final region = s.progressRegion;
    if (region == null) return false;
    final layout = s.pageLayout;
    final focusId = s.stitchFocusThreadId;
    final (pageCol, pageRow) = layout != null ? layout.pageCoords(s.currentPage) : (0, 0);
    for (final layer in s.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (focusId != null && stitch.threadId != focusId) continue;
        if (stitch is BackStitch) {
          // Cross-stitch focus mode: backstitches don't count.
          if (s.stitchCrossMode) continue;
          final midX = (stitch.x1 + stitch.x2) / 2;
          final midY = (stitch.y1 + stitch.y2) / 2;
          if (midX >= region.left && midX < region.right &&
              midY >= region.top && midY < region.bottom) {
            if (layout != null &&
                !layout.cellOnPage(midX.floor(), midY.floor(), pageCol, pageRow)) { continue; }
            return true;
          }
        } else {
          // Backstitch focus mode: cross-stitches don't count.
          if (s.stitchBackMode) continue;
          final coords = EditorState.cellCoords(stitch);
          if (coords == null) continue;
          final (sx, sy) = coords;
          if (sx >= region.left && sx < region.right &&
              sy >= region.top && sy < region.bottom) {
            if (layout != null && !layout.cellOnPage(sx, sy, pageCol, pageRow)) continue;
            return true;
          }
        }
      }
    }
    return false;
  }

  static bool _isRegionAllDone(EditorState s) {
    final region = s.progressRegion;
    if (region == null) return false;
    final progress = s.pattern.progress;
    final layout = s.pageLayout;
    final focusId = s.stitchFocusThreadId;
    final (pageCol, pageRow) = layout != null ? layout.pageCoords(s.currentPage) : (0, 0);
    bool hasAny = false;
    for (final layer in s.pattern.layers) {
      if (!layer.visible) continue;
      for (final stitch in layer.stitches) {
        if (focusId != null && stitch.threadId != focusId) continue;
        if (stitch is BackStitch) {
          if (s.stitchCrossMode) continue;
          final midX = (stitch.x1 + stitch.x2) / 2;
          final midY = (stitch.y1 + stitch.y2) / 2;
          if (midX >= region.left && midX < region.right &&
              midY >= region.top && midY < region.bottom) {
            if (layout != null &&
                !layout.cellOnPage(midX.floor(), midY.floor(), pageCol, pageRow)) { continue; }
            hasAny = true;
            if (!progress.isBackstitchDone(stitch.x1, stitch.y1, stitch.x2, stitch.y2)) return false;
          }
        } else {
          if (s.stitchBackMode) continue;
          final coords = EditorState.cellCoords(stitch);
          if (coords == null) continue;
          final (sx, sy) = coords;
          if (sx >= region.left && sx < region.right &&
              sy >= region.top && sy < region.bottom) {
            if (layout != null && !layout.cellOnPage(sx, sy, pageCol, pageRow)) continue;
            hasAny = true;
            if (!progress.completedStitches.contains((sx, sy))) return false;
          }
        }
      }
    }
    return hasAny;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = _regionHasPageStitches(state);
    final allDone = enabled && _isRegionAllDone(state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: GestureDetector(
        onTap: enabled
            ? null
            : () => showProgressHelpDialog(context, ref, state: state),
        child: FilledButton.icon(
          icon: Icon(allDone ? Icons.remove_done : Icons.done_all, size: 16),
          label: Text(
            allDone ? 'Unmark' : 'Mark',
            style: const TextStyle(fontSize: 13),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: allDone ? Colors.orange.shade700 : null,
          ),
          onPressed: enabled
              ? () {
                  final notifier = ref.read(editorProvider.notifier);
                  final region = state.progressRegion!;
                  if (allDone) {
                    notifier.markRegionNotDone(region);
                  } else {
                    notifier.markRegionDone(region);
                  }
                  // Keep the region selected so the user can act again
                }
              : null,
        ),
      ),
    );
  }
}
