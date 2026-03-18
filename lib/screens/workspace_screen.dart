import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../models/pattern.dart';
import '../providers/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import '../services/pdf_service.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/file_sidebar.dart';
import '../widgets/pattern_canvas.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  // ─── Helpers (mirrored from EditorScreen) ─────────────────────────────────

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

        // Auto-upload to Drive if this file is Drive-backed
        final driveFileId = state.driveFileId;
        final parentFolderId = state.driveParentFolderId;
        if (driveFileId != null && parentFolderId != null) {
          final notifier = ref.read(googleDriveProvider.notifier);
          final newId = await notifier.uploadPattern(
            _patternWithEditorState(state),
            state.filePath!,
            driveFileId,
            parentFolderId,
          );
          if (newId != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Synced to Google Drive')),
            );
          }
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

  String _title(EditorState editorState, WorkspaceState wsState) {
    if (editorState.filePath != null || editorState.pattern.name != 'Untitled') {
      final name = editorState.pattern.name;
      final dirty = editorState.isDirty ? ' •' : '';
      return '$name$dirty';
    }
    return wsState.workspace?.displayName ?? 'Workspace';
  }

  Future<void> _exportPdf(BuildContext context, EditorState state) async {
    try {
      await PdfService.exportPattern(state.pattern);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('PDF export failed: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _showResizeDialog(
      BuildContext context, WidgetRef ref, EditorState state) async {
    final result = await showDialog<ResizeResult>(
      context: context,
      builder: (_) => ResizeCanvasDialog(
        currentWidth: state.pattern.width,
        currentHeight: state.pattern.height,
      ),
    );
    if (result == null) return;
    ref.read(editorProvider.notifier).resizePattern(
          result.width,
          result.height,
          result.anchorX,
          result.anchorY,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorProvider);
    final wsState = ref.watch(workspaceProvider);
    final driveState = ref.watch(googleDriveProvider);

    // ── Keyboard handler (identical to EditorScreen) ─────────────────────
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

      // In stitch mode: allow save, pan/select mode toggle, and Escape.
      if (editorState.stitchMode) {
        if ((meta || ctrl) && key == LogicalKeyboardKey.keyS) {
          _save(context, ref);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyS) {
          notifier.setDrawingMode(DrawingMode.select);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyP ||
            key == LogicalKeyboardKey.space) {
          notifier.setDrawingMode(DrawingMode.pan);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          if (editorState.selectionRect != null) {
            notifier.cancelSelection();
          } else {
            notifier.toggleStitchMode();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

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
        if (key == LogicalKeyboardKey.keyA) {
          notifier.selectAll();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyC) {
          notifier.copySelection();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyX) {
          notifier.cutSelection();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyV) {
          notifier.enterPasteMode();
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
        case LogicalKeyboardKey.keyC:
          notifier.setDrawingMode(DrawingMode.colorPicker);
        case LogicalKeyboardKey.keyS:
          notifier.setDrawingMode(DrawingMode.select);
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(context, ref);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Toggle sidebar',
            onPressed: () =>
                ref.read(workspaceProvider.notifier).toggleSidebar(),
          ),
          title: Text(_title(editorState, wsState)),
          backgroundColor: editorState.stitchMode
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          actions: [
            if (!editorState.stitchMode) ...[
              // Drive sync indicator
              if (editorState.driveFileId != null)
                Tooltip(
                  message: driveState.isSyncing
                      ? 'Syncing to Google Drive…'
                      : 'Synced to Google Drive',
                  child: driveState.isSyncing
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.cloud_done_outlined),
                ),
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
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export PDF…',
                onPressed: () => _exportPdf(context, editorState),
              ),
              IconButton(
                icon: const Icon(Icons.crop_outlined),
                tooltip: 'Resize Aida',
                onPressed: () =>
                    _showResizeDialog(context, ref, editorState),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Pattern Info',
                onPressed: () => _showPatternInfo(context, editorState),
              ),
              IconButton(
                icon: Icon(
                  editorState.referenceImage != null
                      ? Icons.photo_filter
                      : Icons.photo_filter_outlined,
                  color: editorState.referenceImage != null &&
                          editorState.referenceVisible
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: 'Reference Image',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ReferenceImageSheet(),
                ),
              ),
            ],
            // Keep screen on — only shown in stitch mode
            if (editorState.stitchMode) ...[
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: ref.watch(settingsProvider).keepScreenOn,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setKeepScreenOn(v ?? false),
                  ),
                  const Text('Keep screen on',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                ],
              ),
            ],
            // Stitch mode toggle — always visible
            Tooltip(
              message: editorState.stitchMode
                  ? 'Exit Stitch Mode'
                  : 'Stitch Mode',
              child: Switch(
                value: editorState.stitchMode,
                onChanged: (_) =>
                    ref.read(editorProvider.notifier).toggleStitchMode(),
              ),
            ),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sidebar
            if (wsState.sidebarVisible) ...[
              const FileSidebar(),
              const VerticalDivider(width: 1, thickness: 1),
            ],
            // Editor
            Expanded(
              child: Focus(
                autofocus: true,
                onKeyEvent: handleKeys,
                child: const Column(
                  children: [
                    Expanded(child: PatternCanvas()),
                    EditorToolbar(),
                  ],
                ),
              ),
            ),
          ],
        ),
        endDrawer: const _StitchPalettePanel(),
        endDrawerEnableOpenDragGesture: false,
      ),
    );
  }
}

// ─── Stitch mode palette side panel ──────────────────────────────────────────
// (identical to the one in editor_screen.dart)

class _StitchPalettePanel extends ConsumerWidget {
  const _StitchPalettePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final threads = state.pattern.threads;
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Text('Threads', style: theme.textTheme.titleMedium),
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
            if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No threads yet.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: threads.length,
                  itemBuilder: (_, i) {
                    final t = threads[i];
                    final displayCode = useDmc
                        ? t.dmcCode
                        : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
                    final textColor = t.color.computeLuminance() > 0.35
                        ? Colors.black
                        : Colors.white;
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: t.color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.grey.shade400, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: t.symbol.isNotEmpty
                            ? Text(
                                t.symbol,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  height: 1.0,
                                ),
                              )
                            : null,
                      ),
                      title: Text('$displayCode – ${t.name}',
                          style: const TextStyle(fontSize: 13)),
                    );
                  },
                ),
              ),
          ],
        ),
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
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
