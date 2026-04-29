import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/snippet/snippet_palette.dart';
import '../../models/thread.dart';
import '../../providers/editor/editor_provider.dart';
import '../dialogs/confirm_dialog.dart';
import '../dialogs/dmc_picker_dialog.dart';

class PalettesPanel extends ConsumerWidget {
  const PalettesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final palettes = state.snippetPalettes;
    final activeIdx = state.snippetActivePaletteIndex;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: palettes.length + 1,
      itemBuilder: (_, i) {
        if (i == palettes.length) {
          return TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add palette…'),
            onPressed: () => _showAddPalette(context, ref, palettes),
          );
        }
        return _PaletteRow(
          key: ValueKey(palettes[i].id),
          palette: palettes[i],
          index: i,
          isActive: i == activeIdx,
          canDelete: palettes.length > 1,
          primaryPalette: palettes[0],
        );
      },
    );
  }

  Future<void> _showAddPalette(BuildContext context, WidgetRef ref,
      List<SnippetPalette> existing) async {
    if (existing.isEmpty) return;
    final result = await showDialog<SnippetPalette>(
      context: context,
      builder: (_) => _AddPaletteDialog(
        primaryPalette: existing[0],
        existingCount: existing.length,
      ),
    );
    if (result != null && context.mounted) {
      ref.read(editorProvider.notifier).addSnippetPaletteLocal(result);
    }
  }
}

class _PaletteRow extends ConsumerStatefulWidget {
  final SnippetPalette palette;
  final int index;
  final bool isActive;
  final bool canDelete;
  final SnippetPalette primaryPalette;

  const _PaletteRow({
    required super.key,
    required this.palette,
    required this.index,
    required this.isActive,
    required this.canDelete,
    required this.primaryPalette,
  });

  @override
  ConsumerState<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends ConsumerState<_PaletteRow> {
  bool _expanded = false;
  bool _renaming = false;
  late TextEditingController _renameCtrl;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.palette.name);
  }

  @override
  void didUpdateWidget(_PaletteRow old) {
    super.didUpdateWidget(old);
    if (old.palette.name != widget.palette.name && !_renaming) {
      _renameCtrl.text = widget.palette.name;
    }
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(editorProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Palette header row ─────────────────────────────────────────────
        GestureDetector(
          onTap: () => notifier.setSnippetActivePaletteLocal(widget.index),
          child: Container(
            decoration: BoxDecoration(
              color: widget.isActive
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : null,
              border: widget.isActive
                  ? Border(
                      left: BorderSide(
                          color: theme.colorScheme.primary, width: 3))
                  : const Border(
                      left: BorderSide(
                          color: Colors.transparent, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                // Expand chevron
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 4),
                // Name (double-tap to rename)
                Expanded(
                  child: _renaming
                      ? TextField(
                          controller: _renameCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitRename(notifier),
                          onEditingComplete: () => _commitRename(notifier),
                        )
                      : GestureDetector(
                          onDoubleTap: () {
                            _renameCtrl.text = widget.palette.name;
                            setState(() => _renaming = true);
                          },
                          child: Text(widget.palette.name,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                ),
                // Delete button
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 16,
                      color:
                          widget.canDelete ? theme.colorScheme.error : Colors.grey),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.canDelete
                      ? () => _confirmDelete(context, notifier)
                      : null,
                ),
              ],
            ),
          ),
        ),
        // ── Colour slots (expandable) ──────────────────────────────────────
        if (_expanded)
          ...widget.palette.threads.asMap().entries.map((entry) {
            final slotIdx = entry.key;
            final thread = entry.value;
            final isDuplicate = _isDuplicate(slotIdx, thread);
            final primary = slotIdx < widget.primaryPalette.threads.length
                ? widget.primaryPalette.threads[slotIdx]
                : thread;
            return _SlotRow(
              thread: thread,
              slotIndex: slotIdx,
              paletteIndex: widget.index,
              isDuplicate: isDuplicate,
              primaryThread: primary,
            );
          }),
      ],
    );
  }

  void _commitRename(EditorNotifier notifier) {
    final name = _renameCtrl.text.trim();
    if (name.isNotEmpty) notifier.renameSnippetPaletteByIndex(widget.index, name);
    setState(() => _renaming = false);
  }

  Future<void> _confirmDelete(
      BuildContext context, EditorNotifier notifier) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete palette?',
      message: 'Delete "${widget.palette.name}"?',
    );
    if (confirmed) {
      ref.read(editorProvider.notifier).deleteSnippetPaletteByIndex(widget.index);
    }
  }

  bool _isDuplicate(int slotIdx, Thread thread) {
    final threads = widget.palette.threads;
    for (int i = 0; i < threads.length; i++) {
      if (i != slotIdx && threads[i].dmcCode == thread.dmcCode) return true;
    }
    return false;
  }
}

class _SlotRow extends ConsumerWidget {
  final Thread thread;
  final int slotIndex;
  final int paletteIndex;
  final bool isDuplicate;
  final Thread primaryThread;

  const _SlotRow({
    required this.thread,
    required this.slotIndex,
    required this.paletteIndex,
    required this.isDuplicate,
    required this.primaryThread,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _pickColour(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 8, 4),
        child: Row(
          children: [
            // Colour swatch
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: thread.color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                paletteIndex == 0
                    ? thread.dmcCode
                    : '${primaryThread.dmcCode} → ${thread.dmcCode}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            if (isDuplicate)
              Tooltip(
                message: 'Same colour as another slot — '
                    "this slot can't be drawn on this palette until "
                    "it's given a unique colour.",
                child: Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.orange.shade700),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickColour(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Thread>(
      context: context,
      builder: (_) => DmcPickerDialog(initialThread: thread),
    );
    if (result != null) {
      final notifier = ref.read(editorProvider.notifier);
      if (paletteIndex == 0) {
        // Primary palette: remap stitches on canvas too.
        notifier.replaceThread(
            thread.dmcCode, result.dmcCode, result.color, result.name);
      }
      notifier.setSnippetPaletteThreadColor(paletteIndex, slotIndex, result);
    }
  }
}

// ─── Add palette dialog ───────────────────────────────────────────────────────

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
                    title: Text('DMC ${base.dmcCode} — ${base.name}',
                        style: const TextStyle(fontSize: 13)),
                    trailing: TextButton(
                      onPressed: () => _pickColour(i),
                      child: picked != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                    width: 14,
                                    height: 14,
                                    color: picked.color),
                                const SizedBox(width: 4),
                                Text('DMC ${picked.dmcCode}',
                                    style: const TextStyle(fontSize: 12)),
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

