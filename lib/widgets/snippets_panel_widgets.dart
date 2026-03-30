part of 'snippets_panel.dart';

class _SnippetCard extends StatelessWidget {
  final Snippet snippet;
  final Color aidaColor;
  final VoidCallback onTap;
  final VoidCallback onMenuTap;
  final ValueChanged<int> onSwitchPalette;

  const _SnippetCard({
    required this.snippet,
    required this.aidaColor,
    required this.onTap,
    required this.onMenuTap,
    required this.onSwitchPalette,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasName = snippet.name.isNotEmpty;
    final label = hasName ? snippet.name : '${snippet.width}×${snippet.height}';
    final labelStyle = hasName
        ? theme.textTheme.labelSmall
        : theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor);

    final activeIdx = snippet.palettes.isNotEmpty
        ? snippet.activePaletteIndex.clamp(0, snippet.palettes.length - 1)
        : 0;
    final activeThreads = snippet.palettes.isNotEmpty
        ? snippet.palettes[activeIdx].threads
        : <Thread>[];

    return GestureDetector(
      onTap: onTap,
      onLongPress: onMenuTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SnippetThumbnail(
                    snippet: snippet,
                    aidaColor: aidaColor,
                    size: double.infinity,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: onMenuTap,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(1),
                      child: const Icon(Icons.more_vert,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (activeThreads.isNotEmpty) ...[
            const SizedBox(height: 3),
            _SnippetPaletteDots(threads: activeThreads),
          ],
          if (snippet.palettes.length > 1) ...[
            const SizedBox(height: 4),
            _PaletteChevrons(
              snippet: snippet,
              onSwitch: onSwitchPalette,
            ),
          ],
        ],
      ),
    );
  }
}

class _SnippetResizeDialog extends StatefulWidget {
  final Snippet snippet;
  final void Function(int newW, int newH, SnippetResizeMode mode) onResize;

  const _SnippetResizeDialog({required this.snippet, required this.onResize});

  @override
  State<_SnippetResizeDialog> createState() => _SnippetResizeDialogState();
}

class _SnippetResizeDialogState extends State<_SnippetResizeDialog> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  SnippetResizeMode _mode = SnippetResizeMode.clip;
  String? _error;

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController(text: widget.snippet.width.toString());
    _hCtrl = TextEditingController(text: widget.snippet.height.toString());
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
      setState(() => _error = 'Enter positive integers for width and height.');
      return;
    }
    Navigator.of(context).pop();
    widget.onResize(w, h, _mode);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resize snippet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current size: ${widget.snippet.width} × ${widget.snippet.height}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _wCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Width', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Height', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<SnippetResizeMode>(
            segments: const [
              ButtonSegment(value: SnippetResizeMode.clip, label: Text('Clip')),
              ButtonSegment(value: SnippetResizeMode.scale, label: Text('Scale')),
              ButtonSegment(value: SnippetResizeMode.expand, label: Text('Expand')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_mode) {
              SnippetResizeMode.clip =>
                'Stitches outside the new bounds are removed.',
              SnippetResizeMode.scale =>
                'All stitch positions are scaled proportionally.',
              SnippetResizeMode.expand =>
                'Only the declared size changes; no stitches are moved.',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Resize')),
      ],
    );
  }
}

// ─── Palette dots ─────────────────────────────────────────────────────────────

class _SnippetPaletteDots extends StatelessWidget {
  final List<Thread> threads;

  const _SnippetPaletteDots({required this.threads});

  @override
  Widget build(BuildContext context) {
    const maxDots = 12;
    final shown = threads.take(maxDots).toList();
    final overflow = threads.length - shown.length;

    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        ...shown.map((t) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: t.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12, width: 0.5),
              ),
            )),
        if (overflow > 0)
          Text(
            '+$overflow',
            style: const TextStyle(fontSize: 7, color: Colors.grey),
          ),
      ],
    );
  }
}

// ─── Multi-palette chevron switcher ───────────────────────────────────────────

class _PaletteChevrons extends StatelessWidget {
  final Snippet snippet;
  final ValueChanged<int> onSwitch;
  const _PaletteChevrons({required this.snippet, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final count = snippet.palettes.length;
    final active = snippet.activePaletteIndex.clamp(0, count - 1);
    final palette = snippet.palettes[active];
    final name = palette.name.isNotEmpty ? palette.name : 'Palette ${active + 1}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSwitch((active - 1 + count) % count),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.chevron_left, size: 14),
          ),
        ),
        Flexible(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSwitch((active + 1) % count),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.chevron_right, size: 14),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.collections_bookmark_outlined,
              size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(
            'No snippets yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('Create one'),
          ),
        ],
      ),
    );
  }
}
