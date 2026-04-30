import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/aida_presets.dart';
import '../providers/editor/editor_provider.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────

void showPatternInfo(BuildContext context, WidgetRef ref, EditorState state) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 480,
          child: _PatternInfoDialog(initialState: state),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          body: _PatternInfoDialog(initialState: state),
        ),
      ),
    );
  }
}

// ─── Dialog widget ───────────────────────────────────────────────────────────

class _PatternInfoDialog extends ConsumerStatefulWidget {
  final EditorState initialState;
  const _PatternInfoDialog({required this.initialState});

  @override
  ConsumerState<_PatternInfoDialog> createState() => _PatternInfoDialogState();
}

class _PatternInfoDialogState extends ConsumerState<_PatternInfoDialog> {
  bool _editing = false;

  // Form controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _designerCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _difficultyCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _copyrightCtrl;
  late List<({int aidaCount, int strands})> _suggestions;

  static const _aidaCounts = [11, 14, 16, 18, 28, 32];
  static const _strandOptions = [1, 2, 3, 4, 5, 6];

  @override
  void initState() {
    super.initState();
    final p = widget.initialState.pattern;
    _nameCtrl = TextEditingController(text: p.name);
    _designerCtrl = TextEditingController(text: p.designer ?? '');
    _descriptionCtrl = TextEditingController(text: p.description ?? '');
    _difficultyCtrl = TextEditingController(text: p.difficulty ?? '');
    _hoursCtrl = TextEditingController(text: p.estimatedHours ?? '');
    _copyrightCtrl = TextEditingController(text: p.copyright ?? '');
    _suggestions = List.of(p.materialsSuggestions);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _designerCtrl.dispose();
    _descriptionCtrl.dispose();
    _difficultyCtrl.dispose();
    _hoursCtrl.dispose();
    _copyrightCtrl.dispose();
    super.dispose();
  }

  void _enterEdit() => setState(() => _editing = true);

  void _cancelEdit() {
    final p = ref.read(editorProvider).pattern;
    setState(() {
      _editing = false;
      _nameCtrl.text = p.name;
      _designerCtrl.text = p.designer ?? '';
      _descriptionCtrl.text = p.description ?? '';
      _difficultyCtrl.text = p.difficulty ?? '';
      _hoursCtrl.text = p.estimatedHours ?? '';
      _copyrightCtrl.text = p.copyright ?? '';
      _suggestions = List.of(p.materialsSuggestions);
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    ref.read(editorProvider.notifier).updatePatternMetadata(
          name: name,
          designer: _designerCtrl.text.trim().isEmpty
              ? null
              : _designerCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          difficulty: _difficultyCtrl.text.trim().isEmpty
              ? null
              : _difficultyCtrl.text.trim(),
          estimatedHours:
              _hoursCtrl.text.trim().isEmpty ? null : _hoursCtrl.text.trim(),
          copyright: _copyrightCtrl.text.trim().isEmpty
              ? null
              : _copyrightCtrl.text.trim(),
          materialsSuggestions: _suggestions,
        );
    setState(() => _editing = false);
  }

  // ─── View mode ──────────────────────────────────────────────────────────

  Widget _viewContent() {
    final state = ref.watch(editorProvider);
    final p = state.pattern;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow('Name', p.name),
        _InfoRow('Size', '${p.width} × ${p.height} stitches'),
        _InfoRow('Threads', '${p.threads.length}'),
        _AidaColorRow(color: p.aidaColor, onTap: null),
        _InfoRow('Stitches (canvas)', '${p.canvasCellCount}'),
        _InfoRow(
          'Stitches (all layers)',
          '${p.layers.fold(0, (sum, l) => sum + l.stitches.length)}',
        ),
        if (state.filePath != null)
          _InfoRow(
            'File',
            state.driveParentFolderId != null
                ? '${p.name}.stitches  (Google Drive)'
                : state.filePath!.split('/').last,
          ),
        if (p.designer?.isNotEmpty == true) _InfoRow('Designer', p.designer!),
        if (p.difficulty?.isNotEmpty == true)
          _InfoRow('Difficulty', p.difficulty!),
        if (p.estimatedHours?.isNotEmpty == true)
          _InfoRow('Est. time', p.estimatedHours!),
        if (p.description?.isNotEmpty == true)
          _InfoRow('Description', p.description!),
        if (p.copyright?.isNotEmpty == true)
          _InfoRow('Copyright', p.copyright!),
        if (p.materialsSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Materials suggestions:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          for (final s in p.materialsSuggestions)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('${s.aidaCount}-count · ${s.strands} strand${s.strands == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ],
    );
  }

  // ─── Edit mode ──────────────────────────────────────────────────────────

  Widget _editContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('Name', _nameCtrl),
        _field('Designer', _designerCtrl),
        _field('Description', _descriptionCtrl, minLines: 2),
        const SizedBox(height: 4),
        Text('Difficulty',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: _difficultyCtrl,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: ['Beginner', 'Intermediate', 'Advanced'].map((d) {
            return ActionChip(
              label: Text(d, style: const TextStyle(fontSize: 12)),
              onPressed: () => setState(() => _difficultyCtrl.text = d),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        _field('Est. time', _hoursCtrl, hint: 'e.g. 8 or 6–8'),
        _field('Copyright', _copyrightCtrl, hint: 'e.g. Jane Smith'),
        const SizedBox(height: 8),
        _AidaColorRow(
          color: ref.watch(editorProvider).pattern.aidaColor,
          onTap: () => _showAidaPicker(context),
        ),
        const SizedBox(height: 8),
        Text('Materials suggestions',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ..._suggestions.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: s.aidaCount,
                  isDense: true,
                  items: _aidaCounts
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text('$v-count')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _suggestions[i] =
                          (aidaCount: v, strands: s.strands));
                    }
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: s.strands,
                  isDense: true,
                  items: _strandOptions
                      .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('$v strand${v == 1 ? '' : 's'}')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _suggestions[i] =
                          (aidaCount: s.aidaCount, strands: v));
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () =>
                      setState(() => _suggestions.removeAt(i)),
                ),
              ],
            ),
          );
        }),
        if (_suggestions.length < 3)
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add suggestion'),
            onPressed: () =>
                setState(() => _suggestions.add((aidaCount: 14, strands: 2))),
          ),
      ],
    );
  }

  void _showAidaPicker(BuildContext context) {
    final current = ref.read(editorProvider).pattern.aidaColor;
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

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    int minLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 13),
            minLines: minLines,
            maxLines: minLines > 1 ? null : 1,
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.shortestSide >= 600;
    final content = _editing ? _editContent() : _viewContent();

    final titleRow = Row(
      children: [
        Expanded(
          child: Text(
            _editing ? 'Edit Pattern' : 'Pattern Info',
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (_editing) ...[
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _cancelEdit,
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: _enterEdit,
          ),
          if (isWide)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ],
    );

    final compressToggle = _compressToggle();

    if (isWide) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: titleRow,
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
          if (compressToggle != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: compressToggle,
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Pattern' : 'Pattern Info'),
        actions: [
          if (_editing) ...[
            IconButton(
                icon: const Icon(Icons.check),
                tooltip: 'Save',
                onPressed: _save),
            IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: _cancelEdit),
          ] else
            IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: _enterEdit),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
          if (compressToggle != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: compressToggle,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _compressToggle() {
    if (!kDebugMode) return null;
    final state = ref.watch(editorProvider);
    if (!state.isNativeFormat) return null;
    return Row(
      children: [
        const Expanded(
          child: Text('Compress file',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Switch(
          value: state.compressOnSave,
          onChanged: (_) =>
              ref.read(editorProvider.notifier).toggleCompressOnSave(),
        ),
      ],
    );
  }
}

// ─── Aida colour row ──────────────────────────────────────────────────────────

class _AidaColorRow extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;
  const _AidaColorRow({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = aidaColorLabel(color);
    final row = Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        if (onTap != null) ...[
          const SizedBox(width: 6),
          Icon(Icons.edit_outlined, size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text('Aida colour',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          if (onTap != null)
            GestureDetector(onTap: onTap, child: row)
          else
            row,
        ],
      ),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
