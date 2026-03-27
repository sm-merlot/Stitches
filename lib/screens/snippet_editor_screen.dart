import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../data/dmc_colors.dart';
import '../models/layer.dart';
import '../models/layer_item.dart';
import '../models/pattern.dart';
import '../models/snippet.dart';
import '../models/snippet_palette.dart';
import '../models/thread.dart';
import '../providers/editor_provider.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/pattern_canvas.dart';
import '../widgets/snippet_thumbnail.dart';

/// Preset canvas sizes shown in the size picker for new snippets.
const _presetSizes = [
  (label: '8×8',   w: 8,  h: 8),
  (label: '16×16', w: 16, h: 16),
  (label: '32×32', w: 32, h: 32),
  (label: '64×64', w: 64, h: 64),
];

/// Full-screen editor for creating or editing a [Snippet].
///
/// Pass [snippet] to edit an existing one; pass null to create a new one.
/// Pass [siblingSnippets] to allow importing other snippets as paste content.
/// On save, pops with the resulting [Snippet].
class SnippetEditorScreen extends StatelessWidget {
  final Snippet? snippet;
  final List<Snippet> siblingSnippets;
  final bool initialBlockMode;

  const SnippetEditorScreen({
    super.key,
    this.snippet,
    this.siblingSnippets = const [],
    this.initialBlockMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // Override editorProvider with a fresh scope so the reused
    // PatternCanvas and EditorToolbar operate on the snippet canvas.
    return ProviderScope(
      overrides: [editorProvider.overrideWith(EditorNotifier.new)],
      child: _SnippetEditorBody(
        snippet: snippet,
        siblingSnippets: siblingSnippets,
        initialBlockMode: initialBlockMode,
      ),
    );
  }
}

class _SnippetEditorBody extends ConsumerStatefulWidget {
  final Snippet? snippet;
  final List<Snippet> siblingSnippets;
  final bool initialBlockMode;
  const _SnippetEditorBody({
    required this.snippet,
    required this.siblingSnippets,
    required this.initialBlockMode,
  });

  @override
  ConsumerState<_SnippetEditorBody> createState() => _SnippetEditorBodyState();
}

class _SnippetEditorBodyState extends ConsumerState<_SnippetEditorBody> {
  late final TextEditingController _nameController;
  // null = custom size chosen via dialog
  int? _selectedPresetIndex = 1; // default 16×16
  int _canvasW = 16;
  int _canvasH = 16;

  @override
  void initState() {
    super.initState();
    final s = widget.snippet;
    _nameController = TextEditingController(text: s?.name ?? 'New snippet');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s != null) {
        // Editing existing snippet — load its data as a pattern.
        ref.read(editorProvider.notifier).loadPattern(
          CrossStitchPattern(
            name: s.name,
            width: s.width,
            height: s.height,
            threads: s.threads,
            layerItems: [
              LayerLeaf(
                layer: Layer(
                  id: const Uuid().v4(),
                  name: 'Layer 1',
                  visible: true,
                  opacity: 1.0,
                  stitches: s.stitches,
                ),
              ),
            ],
          ),
          filePath: null,
        );
      } else {
        // New snippet — load empty pattern at selected size.
        _loadEmptyPattern();
      }
      if (widget.initialBlockMode) {
        ref.read(editorProvider.notifier).toggleBlockMode();
      }
      // Initialise local palette state for this snippet editor session.
      final editorNotifier = ref.read(editorProvider.notifier);
      if (s != null) {
        editorNotifier.state = editorNotifier.state.copyWith(
          snippetPalettes: s.palettes,
          snippetActivePaletteIndex: s.activePaletteIndex,
        );
      } else {
        editorNotifier.state = editorNotifier.state.copyWith(
          snippetPalettes: [SnippetPalette.create(name: 'Palette 1')],
          snippetActivePaletteIndex: 0,
        );
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadEmptyPattern() {
    ref.read(editorProvider.notifier).loadPattern(
      CrossStitchPattern.empty(
        name: _nameController.text,
        width: _canvasW,
        height: _canvasH,
      ),
    );
  }

  void _onPresetSelected(int? index) {
    if (index == null) {
      // Custom — show dialog
      _showCustomSizeDialog();
      return;
    }
    final preset = _presetSizes[index];
    setState(() {
      _selectedPresetIndex = index;
      _canvasW = preset.w;
      _canvasH = preset.h;
    });
    _loadEmptyPattern();
  }

  Future<void> _showCustomSizeDialog() async {
    final wCtrl = TextEditingController(text: _canvasW.toString());
    final hCtrl = TextEditingController(text: _canvasH.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom size'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: wCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Width'),
                autofocus: true,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('×'),
            ),
            Expanded(
              child: TextField(
                controller: hCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    wCtrl.dispose();
    hCtrl.dispose();

    if (confirmed != true || !mounted) return;

    final w = int.tryParse(wCtrl.text) ?? _canvasW;
    final h = int.tryParse(hCtrl.text) ?? _canvasH;
    if (w < 1 || h < 1) return;

    setState(() {
      _selectedPresetIndex = null; // custom
      _canvasW = w;
      _canvasH = h;
    });
    _loadEmptyPattern();
  }

  KeyEventResult _handleKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final notifier = ref.read(editorProvider.notifier);
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final key = event.logicalKey;

    if (meta || ctrl) {
      if (key == LogicalKeyboardKey.keyZ && !shift) {
        notifier.undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyZ && shift) {
        notifier.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        notifier.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        notifier.selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        notifier.copySelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        notifier.enterPasteMode();
        return KeyEventResult.handled;
      }
    }

    switch (key) {
      case LogicalKeyboardKey.keyD:
        notifier.setDrawingMode(DrawingMode.draw);
      case LogicalKeyboardKey.keyE:
        notifier.setDrawingMode(DrawingMode.erase);
      case LogicalKeyboardKey.keyP:
      case LogicalKeyboardKey.space:
        notifier.setDrawingMode(DrawingMode.pan);
      case LogicalKeyboardKey.keyS:
        notifier.setDrawingMode(DrawingMode.select);
      case LogicalKeyboardKey.keyC:
        notifier.setDrawingMode(DrawingMode.colorPicker);
      case LogicalKeyboardKey.digit1:
        notifier.setTool(DrawingTool.fullStitch);
      case LogicalKeyboardKey.digit2:
        notifier.setTool(DrawingTool.halfForward);
      case LogicalKeyboardKey.digit3:
        notifier.setTool(DrawingTool.halfBackward);
      case LogicalKeyboardKey.digit4:
        notifier.setTool(DrawingTool.halfCross);
      case LogicalKeyboardKey.digit5:
        notifier.setTool(DrawingTool.quarterDiag);
      case LogicalKeyboardKey.digit6:
        notifier.setTool(DrawingTool.quarterCross);
      case LogicalKeyboardKey.digit7:
        notifier.setTool(DrawingTool.backstitch);
      case LogicalKeyboardKey.digit8:
        notifier.setTool(DrawingTool.fill);
      case LogicalKeyboardKey.digit9:
        notifier.setTool(DrawingTool.fillErase);
      case LogicalKeyboardKey.escape:
        notifier.cancelSelection();
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        notifier.deleteSelection();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _loadSnippetIntoClipboard(Snippet other) {
    ref.read(editorProvider.notifier).loadSnippetToClipboard(other);
  }

  void _showSnippetPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _SnippetPickerSheet(
        snippets: widget.siblingSnippets,
        onPick: (s) {
          Navigator.of(ctx).pop();
          _loadSnippetIntoClipboard(s);
        },
      ),
    );
  }

  void _save(BuildContext context) {
    final editorState = ref.read(editorProvider);
    final pattern = editorState.pattern;
    final name = _nameController.text.trim();

    // Collect only the threads actually used by stitches in this snippet.
    final usedIds = pattern.stitches.map((s) => s.threadId).toSet();
    final usedThreads =
        pattern.threads.where((t) => usedIds.contains(t.dmcCode)).toList();

    final localPalettes = editorState.snippetPalettes;
    final activePaletteIdx = editorState.snippetActivePaletteIndex;

    // Build the final palette list: update primary palette threads with
    // currently used threads, keep additional palettes as-is.
    final savedPalettes = localPalettes.isNotEmpty
        ? [
            localPalettes[0].copyWith(threads: usedThreads),
            ...localPalettes.skip(1),
          ]
        : [SnippetPalette.create(name: 'Palette 1', threads: usedThreads)];

    final result = widget.snippet != null
        ? widget.snippet!.copyWith(
            name: name,
            width: pattern.width,
            height: pattern.height,
            palettes: savedPalettes,
            activePaletteIndex: activePaletteIdx.clamp(0, savedPalettes.length - 1),
            stitches: pattern.stitches,
          )
        : Snippet.create(
            name: name,
            width: pattern.width,
            height: pattern.height,
            threads: usedThreads,
            stitches: pattern.stitches,
          );

    Navigator.of(context).pop(result);
  }

  void _openPaletteManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, ctrl) => _PaletteManagerSheet(scrollController: ctrl),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.snippet == null;
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          width: 200,
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Snippet name',
              border: InputBorder.none,
            ),
            style: theme.textTheme.titleMedium,
          ),
        ),
        actions: [
          if (isNew) ...[
            const SizedBox(width: 8),
            _SizePicker(
              selectedPresetIndex: _selectedPresetIndex,
              customLabel: '$_canvasW×$_canvasH',
              onChanged: _onPresetSelected,
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: state.blockMode ? 'Block mode: on' : 'Block mode: off',
            isSelected: state.blockMode,
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            onPressed: () => notifier.toggleBlockMode(),
            style: state.blockMode
                ? IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  )
                : null,
          ),
          IconButton(
            tooltip: 'Manage palettes',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => _openPaletteManager(context),
          ),
          TextButton(
            onPressed: () => _save(context),
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKeys,
        child: Column(
          children: [
            Expanded(child: PatternCanvas()),
            EditorToolbar(
              showSnippetsButton: false,
              showSaveAsSnippetButton: false,
              showSpriteSheetButton: false,
              onPasteFromSnippet: widget.siblingSnippets.isNotEmpty
                  ? () => _showSnippetPicker(context)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
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
    final palettes = editorState.snippetPalettes;
    final activeIdx = editorState.snippetActivePaletteIndex;
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
        Expanded(
          child: ReorderableListView.builder(
            scrollController: widget.scrollController,
            itemCount: palettes.length,
            onReorder: (oldIndex, newIndex) =>
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
            if (state.snippetPalettes.isEmpty) return;
            final primary = state.snippetPalettes[0];
            final result = await showDialog<SnippetPalette>(
              context: context,
              builder: (dialogContext) => UncontrolledProviderScope(
                container: ProviderScope.containerOf(context),
                child: _AddPaletteDialog(primaryPalette: primary),
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
  const _AddPaletteDialog({required this.primaryPalette});

  @override
  State<_AddPaletteDialog> createState() => _AddPaletteDialogState();
}

class _AddPaletteDialogState extends State<_AddPaletteDialog> {
  final _nameCtrl = TextEditingController();
  late final List<Thread?> _picked;

  @override
  void initState() {
    super.initState();
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
      builder: (_) => _DmcPickerDialog(initialThread: base),
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

// ─── Simple DMC colour picker dialog ──────────────────────────────────────

class _DmcPickerDialog extends StatefulWidget {
  final Thread initialThread;
  const _DmcPickerDialog({required this.initialThread});

  @override
  State<_DmcPickerDialog> createState() => _DmcPickerDialogState();
}

class _DmcPickerDialogState extends State<_DmcPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DmcColor> get _filtered {
    final q = _query.toLowerCase();
    if (q.isEmpty) return dmcColors;
    return dmcColors.where((c) {
      return c.code.toLowerCase().contains(q) || c.name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return AlertDialog(
      title: const Text('Pick DMC colour'),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search by code or name…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final c = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: c.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    title: Text('DMC ${c.code}', style: const TextStyle(fontSize: 13)),
                    subtitle: Text(c.name, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.of(context).pop(
                      Thread(dmcCode: c.code, color: c.color, name: c.name),
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
      ],
    );
  }
}
