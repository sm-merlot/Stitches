part of 'snippet_editor_screen.dart';

// ─── Resize dialog (for editing existing snippets) ────────────────────────

class _ResizeSnippetEditorDialog extends StatefulWidget {
  final int currentWidth;
  final int currentHeight;
  const _ResizeSnippetEditorDialog({
    required this.currentWidth,
    required this.currentHeight,
  });

  @override
  State<_ResizeSnippetEditorDialog> createState() =>
      _ResizeSnippetEditorDialogState();
}

class _ResizeSnippetEditorDialogState
    extends State<_ResizeSnippetEditorDialog> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  SnippetResizeMode _mode = SnippetResizeMode.clip;
  String? _error;

  @override
  void initState() {
    super.initState();
    _wCtrl =
        TextEditingController(text: widget.currentWidth.toString());
    _hCtrl =
        TextEditingController(text: widget.currentHeight.toString());
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final w = int.tryParse(_wCtrl.text.trim());
    final h = int.tryParse(_hCtrl.text.trim());
    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(
          () => _error = 'Enter positive integers for width and height.');
      return;
    }
    Navigator.of(context).pop((w, h, _mode));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resize snippet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Current size: ${widget.currentWidth} × ${widget.currentHeight}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _wCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RadioGroup<SnippetResizeMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in SnippetResizeMode.values)
                  RadioListTile<SnippetResizeMode>(
                    dense: true,
                    title: Text(_modeLabel(mode)),
                    value: mode,
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _submit, child: const Text('Resize')),
      ],
    );
  }

  String _modeLabel(SnippetResizeMode mode) => switch (mode) {
        SnippetResizeMode.clip => 'Clip (drop stitches outside new size)',
        SnippetResizeMode.scale => 'Scale (stretch/compress stitches)',
        SnippetResizeMode.expand => 'Expand (keep stitches in place)',
      };
}

// ─── Snippet picker sheet ──────────────────────────────────────────────────

class _SnippetPickerSheet extends ConsumerWidget {
  final List<Snippet> snippets;
  final void Function(Snippet) onPick;

  const _SnippetPickerSheet({required this.snippets, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Read the parent pattern's aida color for the thumbnail backgrounds.
    // We're inside a ProviderScope override, so we need the root container
    // to access the parent pattern. Use a neutral fallback instead.
    const aidaColor = Color(0xFFFFFAF0); // linen

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text('Paste from snippet', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.75,
              ),
              itemCount: snippets.length,
              itemBuilder: (context, i) {
                final s = snippets[i];
                final hasName = s.name.isNotEmpty;
                final label = hasName ? s.name : '${s.width}×${s.height}';
                return GestureDetector(
                  onTap: () => onPick(s),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SnippetThumbnail(
                            snippet: s,
                            aidaColor: aidaColor,
                            size: double.infinity,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: hasName
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Size picker ───────────────────────────────────────────────────────────

class _SizePicker extends StatelessWidget {
  /// Index into [_presetSizes], or null if a custom size is active.
  final int? selectedPresetIndex;
  /// Label shown when a custom size is active, e.g. "24×18".
  final String customLabel;
  /// Called with a preset index, or null to request a custom size dialog.
  final ValueChanged<int?> onChanged;

  const _SizePicker({
    required this.selectedPresetIndex,
    required this.customLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // -1 is the sentinel value for "Custom" in the DropdownButton.
    const customValue = -1;
    final currentValue = selectedPresetIndex ?? customValue;

    return DropdownButton<int>(
      value: currentValue,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [
        for (var i = 0; i < _presetSizes.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(_presetSizes[i].label),
          ),
        DropdownMenuItem(
          value: customValue,
          child: Text(
            selectedPresetIndex == null ? customLabel : 'Custom…',
          ),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        onChanged(v == customValue ? null : v);
      },
    );
  }
}

// ─── Palette manager sheet ─────────────────────────────────────────────────

class _PaletteManagerSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const _PaletteManagerSheet({required this.scrollController});

  @override
  ConsumerState<_PaletteManagerSheet> createState() => _PaletteManagerSheetState();
}

class _PaletteManagerSheetState extends ConsumerState<_PaletteManagerSheet> {
  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final palettes = editorState.snippetEditorState.palettes;
    final activeIdx = editorState.snippetEditorState.activePaletteIndex;
    final sourcePalette = editorState.snippetEditorState.sourcePalette;
    final notifier = ref.read(editorProvider.notifier);

    return Column(
      children: [
        // Handle
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[400],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Palettes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        if (sourcePalette != null)
          _SourcePaletteRow(
            sourcePalette: sourcePalette,
            activePalette: activeIdx < palettes.length ? palettes[activeIdx] : null,
            onReplaceSlot: (slotIdx, thread) =>
                notifier.setSnippetPaletteThreadColor(activeIdx, slotIdx, thread),
          ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: widget.scrollController,
            itemCount: palettes.length,
            onReorderItem: (oldIndex, newIndex) =>
                notifier.reorderSnippetPaletteLocal(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final palette = palettes[index];
              return _PaletteRow(
                key: ValueKey(palette.id),
                palette: palette,
                isActive: index == activeIdx,
                canDelete: palettes.length > 1,
                onActivate: () => notifier.setSnippetActivePaletteLocal(index),
                onRename: (name) => notifier.renameSnippetPaletteLocal(palette.id, name),
                onDelete: () => notifier.deleteSnippetPaletteLocal(palette.id),
              );
            },
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add new palette…'),
          onTap: () async {
            final state = ref.read(editorProvider);
            if (state.snippetEditorState.palettes.isEmpty) return;
            final primary = state.snippetEditorState.palettes[0];
            final existingCount = state.snippetEditorState.palettes.length;
            final result = await showDialog<SnippetPalette>(
              context: context,
              builder: (dialogContext) => UncontrolledProviderScope(
                container: ProviderScope.containerOf(context),
                child: _AddPaletteDialog(
                  primaryPalette: primary,
                  existingCount: existingCount,
                ),
              ),
            );
            if (result != null) {
              notifier.addSnippetPaletteLocal(result);
            }
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Palette row ───────────────────────────────────────────────────────────

class _PaletteRow extends StatefulWidget {
  final SnippetPalette palette;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onActivate;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  const _PaletteRow({
    super.key,
    required this.palette,
    required this.isActive,
    required this.canDelete,
    required this.onActivate,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends State<_PaletteRow> {
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.palette.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        widget.isActive ? Icons.circle : Icons.circle_outlined,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: _editing
          ? TextField(
              controller: _ctrl,
              autofocus: true,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) widget.onRename(v.trim());
                setState(() => _editing = false);
              },
              onEditingComplete: () => setState(() => _editing = false),
            )
          : GestureDetector(
              onTap: widget.onActivate,
              onDoubleTap: () => setState(() => _editing = true),
              child: Text(widget.palette.name),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Colour swatches (first 5 threads)
          for (final t in widget.palette.threads.take(5))
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
              ),
            ),
          if (widget.canDelete)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: widget.onDelete,
            ),
        ],
      ),
    );
  }
}

// ─── Add palette dialog ────────────────────────────────────────────────────

class _AddPaletteDialog extends StatefulWidget {
  final SnippetPalette primaryPalette;
  final int existingCount;
  const _AddPaletteDialog({required this.primaryPalette, required this.existingCount});

  @override
  State<_AddPaletteDialog> createState() => _AddPaletteDialogState();
}

class _AddPaletteDialogState extends State<_AddPaletteDialog> {
  final _nameCtrl = TextEditingController();
  late final List<Thread?> _picked;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = 'Palette ${widget.existingCount + 1}';
    _picked = List.filled(widget.primaryPalette.threads.length, null);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _doneCount => _picked.where((t) => t != null).length;

  bool get _canAdd =>
      _nameCtrl.text.trim().isNotEmpty &&
      _doneCount == widget.primaryPalette.threads.length;

  Future<void> _pickColour(int slotIndex) async {
    final base = widget.primaryPalette.threads[slotIndex];
    final result = await showDialog<Thread>(
      context: context,
      builder: (_) => DmcPickerDialog(initialThread: base),
    );
    if (result != null) {
      setState(() => _picked[slotIndex] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.primaryPalette.threads.length;

    return AlertDialog(
      title: const Text('Add palette'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              '$_doneCount / $total done',
              style: TextStyle(
                color: _doneCount == total
                    ? Colors.green[700]
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: total,
                itemBuilder: (context, i) {
                  final base = widget.primaryPalette.threads[i];
                  final picked = _picked[i];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 16,
                      height: 16,
                      color: base.color,
                    ),
                    title: Text(
                      'DMC ${base.dmcCode} — ${base.name}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: TextButton(
                      onPressed: () => _pickColour(i),
                      child: picked != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 14, height: 14, color: picked.color),
                                const SizedBox(width: 4),
                                Text('DMC ${picked.dmcCode}', style: const TextStyle(fontSize: 12)),
                              ],
                            )
                          : const Text('Pick colour…'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canAdd
              ? () {
                  final threads = List<Thread>.generate(
                    widget.primaryPalette.threads.length,
                    (i) => _picked[i]!,
                  );
                  Navigator.of(context).pop(
                    SnippetPalette.create(
                      name: _nameCtrl.text.trim(),
                      threads: threads,
                    ),
                  );
                }
              : null,
          child: const Text('Add palette'),
        ),
      ],
    );
  }
}

// ─── Source palette row ────────────────────────────────────────────────────

/// Read-only comparison row shown at the top of the palette manager for
/// sprite-imported snippets. Displays each source colour slot alongside the
/// corresponding slot in the active DMC palette. Tapping a slot opens a
/// nearest-alternatives picker to reassign the active palette at that slot.
class _SourcePaletteRow extends StatefulWidget {
  final SnippetPalette sourcePalette;
  final SnippetPalette? activePalette;
  final void Function(int slotIdx, Thread newThread) onReplaceSlot;

  const _SourcePaletteRow({
    required this.sourcePalette,
    required this.activePalette,
    required this.onReplaceSlot,
  });

  @override
  State<_SourcePaletteRow> createState() => _SourcePaletteRowState();
}

class _SourcePaletteRowState extends State<_SourcePaletteRow> {
  bool _expanded = true;

  Future<void> _pickAlternative(int slotIdx) async {
    final sourceThread = widget.sourcePalette.threads[slotIdx];
    final activeThread = widget.activePalette != null &&
            slotIdx < widget.activePalette!.threads.length
        ? widget.activePalette!.threads[slotIdx]
        : null;

    final r = (sourceThread.color.r * 255).round();
    final g = (sourceThread.color.g * 255).round();
    final b = (sourceThread.color.b * 255).round();
    final nearest = SpriteImporter.nearestDmcColours(r, g, b, count: 12);

    if (!mounted) return;
    final picked = await showModalBottomSheet<DmcColor>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: sourceThread.color,
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Source slot ${slotIdx + 1} — pick replacement for active palette',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: nearest.length,
                itemBuilder: (_, i) {
                  final c = nearest[i];
                  final isCurrent = c.code == activeThread?.dmcCode;
                  return GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(c),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: c.color,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isCurrent
                                        ? Theme.of(ctx).colorScheme.primary
                                        : Colors.black26,
                                    width: isCurrent ? 2.5 : 1,
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                Center(
                                  child: Icon(Icons.check, size: 12,
                                      color: _contrast(c.color)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(c.code,
                            style: const TextStyle(fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search all DMC colours…'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  final thread = await showDialog<Thread>(
                    context: context,
                    builder: (_) => DmcPickerDialog(
                      initialThread: activeThread ??
                          Thread(
                            dmcCode: '',
                            color: sourceThread.color,
                            name: '',
                            symbol: '',
                          ),
                    ),
                  );
                  if (thread != null) {
                    final dmc = dmcColorByCode(thread.dmcCode);
                    if (dmc != null && mounted) {
                      widget.onReplaceSlot(
                        slotIdx,
                        Thread(
                          dmcCode: dmc.code,
                          color: dmc.color,
                          name: dmc.name,
                          symbol: activeThread?.symbol ?? '',
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (picked != null && mounted) {
      widget.onReplaceSlot(
        slotIdx,
        Thread(
          dmcCode: picked.code,
          color: picked.color,
          name: picked.name,
          symbol: activeThread?.symbol ?? '',
        ),
      );
    }
  }

  Color _contrast(Color bg) {
    final l = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;
    return l > 0.4 ? Colors.black54 : Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = widget.sourcePalette.threads;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 14,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Source (read-only reference)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tap any slot to change the active palette colour',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < slots.length; i++)
                          GestureDetector(
                            onTap: () => _pickAlternative(i),
                            child: Container(
                              width: 32,
                              margin: const EdgeInsets.only(right: 4),
                              child: Column(
                                children: [
                                  // Source colour
                                  Tooltip(
                                    message: 'Source ${i + 1}',
                                    child: Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        color: slots[i].color,
                                        border: Border.all(color: Colors.black26),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // Arrow
                                  Icon(Icons.arrow_downward,
                                      size: 10,
                                      color: theme.colorScheme.onSurfaceVariant),
                                  const SizedBox(height: 2),
                                  // Active palette colour for this slot
                                  Tooltip(
                                    message: widget.activePalette != null &&
                                            i < widget.activePalette!.threads.length
                                        ? widget.activePalette!.threads[i].dmcCode
                                        : '',
                                    child: Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        color: widget.activePalette != null &&
                                                i < widget.activePalette!.threads.length
                                            ? widget.activePalette!.threads[i].color
                                            : Colors.grey,
                                        border: Border.all(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.5),
                                          width: 1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.edit, size: 10,
                                            color: Colors.white54),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

