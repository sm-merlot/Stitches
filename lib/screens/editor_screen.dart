import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pattern.dart';
import '../providers/editor_provider.dart';
import '../services/file_service.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/pattern_canvas.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  /// Returns the pattern with current editor state embedded for saving.
  CrossStitchPattern _patternWithEditorState(EditorState state) {
    return state.pattern.copyWith(
      editorSelectedThreadId: state.selectedThreadId,
      editorTool: state.currentTool.name,
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    try {
      if (state.filePath != null) {
        await FileService.saveFile(
            _patternWithEditorState(state), state.filePath!);
        ref.read(editorProvider.notifier).markSaved();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved')),
          );
        }
      } else {
        await _saveAs(context, ref);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _saveAs(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    try {
      final path =
          await FileService.saveFileAs(_patternWithEditorState(state));
      if (path != null) {
        ref.read(editorProvider.notifier).setFilePath(path);
        ref.read(editorProvider.notifier).markSaved();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<bool> _onWillPop(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    if (!state.isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content:
            const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop(false);
              await _save(context, ref);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _title(EditorState state) {
    final name = state.pattern.name;
    final dirty = state.isDirty ? ' •' : '';
    return '$name$dirty';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);

    // All keyboard shortcuts handled here — single Focus, no competing nodes.
    KeyEventResult handleKeys(FocusNode node, KeyEvent event) {
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

      // Modifier shortcuts
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
        if (key == LogicalKeyboardKey.keyS) {
          _save(context, ref);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      // Single-key shortcuts
      switch (key) {
        case LogicalKeyboardKey.keyD:
          notifier.setDrawingMode(DrawingMode.draw);
        case LogicalKeyboardKey.keyE:
          notifier.setDrawingMode(DrawingMode.erase);
        case LogicalKeyboardKey.keyP:
          notifier.setDrawingMode(DrawingMode.pan);
        case LogicalKeyboardKey.space:
          notifier.setDrawingMode(DrawingMode.pan);
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
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(context, ref);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title(state)),
          actions: [
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save  (Cmd+S)',
              onPressed: () => _save(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.save_as_outlined),
              tooltip: 'Save As…',
              onPressed: () => _saveAs(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Pattern Info',
              onPressed: () => _showPatternInfo(context, state),
            ),
          ],
        ),
        body: Focus(
          autofocus: true,
          onKeyEvent: handleKeys,
          child: Column(
            children: [
              const Expanded(child: PatternCanvas()),
              const EditorToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  void _showPatternInfo(BuildContext context, EditorState state) {
    final p = state.pattern;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pattern Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('Name', p.name),
            _InfoRow('Size', '${p.width} × ${p.height} stitches'),
            _InfoRow('Threads', '${p.threads.length}'),
            _InfoRow('Stitches', '${p.stitches.length}'),
            if (state.filePath != null)
              _InfoRow('File', state.filePath!.split('/').last),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'))
        ],
      ),
    );
  }
}

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
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
              child:
                  Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

