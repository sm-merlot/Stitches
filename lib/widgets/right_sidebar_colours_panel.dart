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
        ? _countStitchesComposite(state)
        : _countStitches(activeLayer.stitches);

    // Symbol issue count (no symbol, duplicate, or similar) across all pattern threads.
    final allSymbolCounts = <String, int>{};
    for (final t in state.pattern.threads) {
      if (symbolIsVisible(t.symbol)) {
        allSymbolCounts[t.symbol] = (allSymbolCounts[t.symbol] ?? 0) + 1;
      }
    }
    final allGroupSymbols = <int, Set<String>>{};
    for (final t in state.pattern.threads) {
      if (symbolIsVisible(t.symbol)) {
        final g = symbolSimilarityGroup(t.symbol);
        if (g >= 0) (allGroupSymbols[g] ??= {}).add(t.symbol);
      }
    }
    final allConflictingGroups = allGroupSymbols.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();
    final issueCount = state.pattern.threads
        .where((t) {
          if (!symbolIsVisible(t.symbol)) return true;
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
                  onPressed: () =>
                      _autoFixSymbols(notifier, state.pattern.threads),
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
            onSwatchTap: (t) => _showSymbolPicker(
              context, notifier, t,
              state.pattern.threads
                  .where((pt) => pt.dmcCode != t.dmcCode)
                  .map((pt) => pt.symbol)
                  .where(symbolIsVisible)
                  .toSet(),
            ),
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

  // Phase 1: collect kept symbols, flagging no-symbol and exact duplicates.
  final kept = <String>{};
  final toFix = <String>{};  // dmcCodes that need a new symbol
  for (final t in sorted) {
    if (!symbolIsVisible(t.symbol) || kept.contains(t.symbol)) {
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
  final cache = state.compositeThreadCache;
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

class _ThreadList extends StatelessWidget {
  final List<Thread> threads;
  final String? selectedThreadId;
  final bool useDmc;
  final Map<String, int> stitchCounts;
  final void Function(Thread) onTap;
  final void Function(Thread)? onSwatchTap;
  final bool focusMode;

  const _ThreadList({
    required this.threads,
    required this.selectedThreadId,
    required this.useDmc,
    required this.stitchCounts,
    required this.onTap,
    this.onSwatchTap,
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
    // Pre-compute duplicate symbols across the displayed list.
    final symbolCounts = <String, int>{};
    for (final t in threads) {
      if (symbolIsVisible(t.symbol)) {
        symbolCounts[t.symbol] = (symbolCounts[t.symbol] ?? 0) + 1;
      }
    }
    // Pre-compute similar-symbol conflicts (different symbols from same group).
    final groupSymbols = <int, Set<String>>{};
    for (final t in threads) {
      if (symbolIsVisible(t.symbol)) {
        final g = symbolSimilarityGroup(t.symbol);
        if (g >= 0) (groupSymbols[g] ??= {}).add(t.symbol);
      }
    }
    final conflictingGroups = groupSymbols.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();

    bool isSimilarOnly(Thread t) {
      if (!symbolIsVisible(t.symbol)) return false;
      if ((symbolCounts[t.symbol] ?? 0) > 1) return false; // already a dup
      final g = symbolSimilarityGroup(t.symbol);
      return g >= 0 && conflictingGroups.contains(g);
    }

    final sorted = [...threads]..sort((a, b) {
        // No-symbol threads first, then duplicates, then similar, then normal.
        final aNoSym = !symbolIsVisible(a.symbol);
        final bNoSym = !symbolIsVisible(b.symbol);
        if (aNoSym != bNoSym) return aNoSym ? -1 : 1;
        final aDup = !aNoSym && (symbolCounts[a.symbol] ?? 0) > 1;
        final bDup = !bNoSym && (symbolCounts[b.symbol] ?? 0) > 1;
        if (aDup != bDup) return aDup ? -1 : 1;
        final aSim = !aDup && isSimilarOnly(a);
        final bSim = !bDup && isSimilarOnly(b);
        if (aSim != bSim) return aSim ? -1 : 1;
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

        final hasSymbol = symbolIsVisible(t.symbol);
        final isDuplicate = hasSymbol && (symbolCounts[t.symbol] ?? 0) > 1;
        final isSimilar = isSimilarOnly(t);

        final swatchBorderColor = !hasSymbol
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
              width: (!hasSymbol || isDuplicate || isSimilar) ? 1.5 : 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: hasSymbol
              ? Text(t.symbol,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.0))
              : Text('?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textColor.withValues(alpha: 0.4),
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
            message: !hasSymbol
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
