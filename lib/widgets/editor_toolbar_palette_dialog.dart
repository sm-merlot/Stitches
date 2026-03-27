part of 'editor_toolbar.dart';

// ─── Palette button ───────────────────────────────────────────────────────────

class _PaletteButton extends StatelessWidget {
  const _PaletteButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Thread palette',
      child: IconButton(
        icon: const Icon(Icons.palette_outlined, size: 20),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => UncontrolledProviderScope(
            container: ProviderScope.containerOf(context),
            child: const _PaletteDialog(),
          ),
        ),
      ),
    );
  }
}

// ─── Palette dialog ───────────────────────────────────────────────────────────

class _PaletteDialog extends ConsumerWidget {
  const _PaletteDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final displayThreads = state.showCompositeThreads
        ? (() {
            final cache = state.compositeThreadCache;
            if (cache == null) return state.pattern.threads;
            final seen = <String>{};
            final result = <Thread>[];
            for (final t in cache.values) {
              if (seen.add(t.dmcCode)) result.add(t);
            }
            return result;
          })()
        : state.pattern.threads;
    final threads = displayThreads;
    final theme = Theme.of(context);
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    // Stitch counts per thread and overall total.
    final stitchCounts = <String, int>{};
    for (final s in state.pattern.stitches) {
      stitchCounts[s.threadId] = (stitchCounts[s.threadId] ?? 0) + 1;
    }
    final totalStitches = state.pattern.stitches.length;

    String fmtCount(int n) =>
        n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

    return Dialog(
      clipBehavior: Clip.hardEdge,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Threads in Pattern', style: theme.textTheme.titleMedium),
                      if (threads.isNotEmpty)
                        Text(
                          '${threads.length} colour${threads.length == 1 ? '' : 's'} · ${fmtCount(totalStitches)} stitches',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Thread list
            if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No threads yet.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: threads.length,
                  itemExtent: 60,
                  itemBuilder: (_, i) {
                    final t = threads[i];
                    final displayCode = useDmc
                        ? t.dmcCode
                        : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
                    final isSelected = state.selectedThreadId == t.dmcCode;
                    final count = stitchCounts[t.dmcCode] ?? 0;
                    return ListTile(
                      dense: true,
                      leading: GestureDetector(
                        onTap: () => state.showCompositeThreads
                            ? _showCompositeSymbolPicker(context, ref, t)
                            : _showSymbolPicker(context, ref, t),
                        child: _ThreadSwatch(thread: t, size: 24),
                      ),
                      title: Text('$displayCode – ${t.name}'),
                      subtitle: Text(
                        count == 0 ? 'unused' : '${fmtCount(count)} stitches',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: count == 0
                              ? theme.colorScheme.error.withValues(alpha: 0.7)
                              : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      onLongPress: isDesktop
                          ? null
                          : () => _showReplaceDialog(context, t),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(Icons.check,
                                size: 16, color: theme.colorScheme.primary),
                          if (isDesktop)
                            Tooltip(
                              message: 'Replace colour',
                              child: InkWell(
                                onTap: () => _showReplaceDialog(context, t),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.swap_horiz,
                                    size: 16,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Change symbol',
                            child: GestureDetector(
                              onTap: () => state.showCompositeThreads
                                  ? _showCompositeSymbolPicker(context, ref, t)
                                  : _showSymbolPicker(context, ref, t),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: t.color,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  t.symbol.isNotEmpty ? t.symbol : '?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: t.color.computeLuminance() > 0.35
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      selected: isSelected,
                      onTap: () {
                        ref
                            .read(editorProvider.notifier)
                            .setSelectedThread(t.dmcCode);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSymbolPicker(BuildContext context, WidgetRef ref, Thread t) {
    showDialog<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _SymbolPickerDialog(
          thread: t,
          onSelect: (s) {
            final state = ref.read(editorProvider);
            final takenByOther = state.pattern.threads
                    .any((other) => other.dmcCode != t.dmcCode && other.symbol == s) ||
                state.pattern.compositeSymbols.entries.any((e) => e.value == s);
            if (takenByOther) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("'$s' is already used by another thread")),
              );
              return;
            }
            ref.read(editorProvider.notifier).changeThreadSymbol(t.dmcCode, s);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _showCompositeSymbolPicker(BuildContext context, WidgetRef ref, Thread t) {
    showDialog<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _SymbolPickerDialog(
          thread: t,
          onSelect: (s) {
            final applied =
                ref.read(editorProvider.notifier).changeCompositeSymbol(t.dmcCode, s);
            Navigator.of(context).pop();
            if (!applied) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("'$s' is already used by another thread")),
              );
            }
          },
        ),
      ),
    );
  }

  void _showReplaceDialog(BuildContext context, Thread t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: AlertDialog(
          title: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: t.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${t.dmcCode} – ${t.name}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
              'Replace all stitches using this colour with a different DMC colour.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                showColorPicker(context, replacingThreadId: t.dmcCode);
              },
              child: const Text('Replace colour…'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Symbol picker dialog ─────────────────────────────────────────────────────

class _SymbolPickerDialog extends StatefulWidget {
  final Thread thread;
  final ValueChanged<String> onSelect;
  const _SymbolPickerDialog({required this.thread, required this.onSelect});

  @override
  State<_SymbolPickerDialog> createState() => _SymbolPickerDialogState();
}

class _SymbolPickerDialogState extends State<_SymbolPickerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Pre-fill if the current symbol is a custom (non-preset) one
    final current = widget.thread.symbol;
    _controller = TextEditingController(
      text: kPatternSymbols.contains(current) ? '' : current,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final t = widget.thread;
    final textColor =
        t.color.computeLuminance() > 0.35 ? Colors.black : Colors.white;
    final customText = _controller.text.trim();

    return AlertDialog(
      title: Text('${t.dmcCode} – ${t.name}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preset symbols grid ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kPatternSymbols.map((s) {
                    final isSelected =
                        s == t.symbol && customText.isEmpty;
                    return GestureDetector(
                      onTap: () => widget.onSelect(s),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: t.color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected ? primary : Colors.grey.shade300,
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // ── Custom symbol entry ──────────────────────────────────────────
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: 'Custom symbol',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) widget.onSelect(v.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Live preview in thread colour
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: customText.isNotEmpty ? t.color : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: customText.isNotEmpty
                          ? primary
                          : Colors.grey.shade300,
                      width: customText.isNotEmpty ? 2.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    customText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              customText.isNotEmpty ? () => widget.onSelect(customText) : null,
          child: const Text('Use custom'),
        ),
      ],
    );
  }
}
