import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pattern.dart';
import '../models/snippet.dart';
import '../providers/editor_provider.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/pattern_canvas.dart';

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
/// On save, pops with the resulting [Snippet].
class SnippetEditorScreen extends StatelessWidget {
  final Snippet? snippet;

  const SnippetEditorScreen({super.key, this.snippet});

  @override
  Widget build(BuildContext context) {
    // Override editorProvider with a fresh scope so the reused
    // PatternCanvas and EditorToolbar operate on the snippet canvas.
    return ProviderScope(
      overrides: [editorProvider.overrideWith(EditorNotifier.new)],
      child: _SnippetEditorBody(snippet: snippet),
    );
  }
}

class _SnippetEditorBody extends ConsumerStatefulWidget {
  final Snippet? snippet;
  const _SnippetEditorBody({required this.snippet});

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
            stitches: s.stitches,
          ),
          filePath: null,
        );
      } else {
        // New snippet — load empty pattern at selected size.
        _loadEmptyPattern();
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

  void _save(BuildContext context) {
    final editorState = ref.read(editorProvider);
    final pattern = editorState.pattern;
    final name = _nameController.text.trim();

    // Collect only the threads actually used by stitches in this snippet.
    final usedIds = pattern.stitches.map((s) => s.threadId).toSet();
    final usedThreads =
        pattern.threads.where((t) => usedIds.contains(t.dmcCode)).toList();

    final result = widget.snippet != null
        ? widget.snippet!.copyWith(
            name: name,
            width: pattern.width,
            height: pattern.height,
            threads: usedThreads,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.snippet == null;

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
            EditorToolbar(showSnippetsButton: false, showSaveAsSnippetButton: false),
          ],
        ),
      ),
    );
  }
}

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
