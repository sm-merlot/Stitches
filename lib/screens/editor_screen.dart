import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/settings_provider.dart';
import '../services/file_service.dart';
import '../utils/snackbars.dart';
import 'export_dialog.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/right_sidebar_colours_panel.dart';
import '../widgets/pattern_canvas.dart';
import 'materials_list_screen.dart';
import 'pattern_info_dialog.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';


enum _MenuAction { saveAs, export, resize, patternInfo, referenceImage, toggleCompress }

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    try {
      if (state.filePath != null) {
        await FileService.saveFile(state.patternForSave, state.filePath!,
            compress: state.compressOnSave);
        ref.read(editorProvider.notifier).markSaved();
        if (context.mounted) showSuccess(context, 'Saved');

        // Auto-upload to Drive if this file is Drive-backed
        final driveFileId = state.driveFileId;
        final parentFolderId = state.driveParentFolderId;
        if (driveFileId != null && parentFolderId != null) {
          final notifier = ref.read(googleDriveProvider.notifier);
          final newId = await notifier.uploadPattern(
            state.patternForSave,
            driveFileId,
            parentFolderId,
            compress: state.compressOnSave,
          );
          if (newId != null && context.mounted) {
            showSuccess(context, 'Synced to Google Drive');
          }
        }
      } else {
        await _saveAs(context, ref);
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Save failed: $e');
    }
  }

  Future<void> _saveAs(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    try {
      final path = await FileService.saveFileAs(state.patternForSave,
          compress: state.compressOnSave);
      if (path != null) {
        ref.read(editorProvider.notifier).setFilePath(path);
        ref.read(editorProvider.notifier).markSaved();
        if (context.mounted) showSuccess(context, 'Saved');
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Save failed: $e');
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
    final driveState = ref.watch(googleDriveProvider);

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

      // In stitch mode: allow save, pan/select mode toggle, and Escape.
      if (state.stitchMode) {
        if ((meta || ctrl) && key == LogicalKeyboardKey.keyS) {
          _save(context, ref);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyS) {
          notifier.setDrawingMode(DrawingMode.select);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          // Clear selection first; if nothing to clear, exit stitch mode.
          if (state.selectionRect != null) {
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
        if (!shift && key == LogicalKeyboardKey.keyV) {
          notifier.enterPasteMode();
          return KeyEventResult.handled;
        }
        if (shift && key == LogicalKeyboardKey.keyH) {
          if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
            notifier.flipSelectionH();
          } else if (state.drawingMode == DrawingMode.paste) {
            notifier.flipClipboardH();
          }
          return KeyEventResult.handled;
        }
        if (shift && key == LogicalKeyboardKey.keyV) {
          if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
            notifier.flipSelectionV();
          } else if (state.drawingMode == DrawingMode.paste) {
            notifier.flipClipboardV();
          }
          return KeyEventResult.handled;
        }
        if (shift && key == LogicalKeyboardKey.bracketRight) {
          if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
            notifier.rotateSelectionCW();
          } else if (state.drawingMode == DrawingMode.paste) {
            notifier.rotateClipboardCW();
          }
          return KeyEventResult.handled;
        }
        if (shift && key == LogicalKeyboardKey.bracketLeft) {
          if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
            notifier.rotateSelectionCW();
            notifier.rotateSelectionCW();
            notifier.rotateSelectionCW();
          } else if (state.drawingMode == DrawingMode.paste) {
            notifier.rotateClipboardCW();
            notifier.rotateClipboardCW();
            notifier.rotateClipboardCW();
          }
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
        case LogicalKeyboardKey.digit8:
          notifier.setTool(DrawingTool.fill);
        case LogicalKeyboardKey.digit9:
          notifier.setDrawingMode(DrawingMode.erase);
          if (!state.fillEraseActive) notifier.toggleFillErase();
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
          title: Text(_title(state)),
          backgroundColor: state.stitchMode
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          actions: [
            if (!state.stitchMode) ...[
              // Drive sync indicator
              if (state.driveFileId != null)
                Tooltip(
                  message: driveState.isSyncing
                      ? 'Syncing to Google Drive…'
                      : 'Synced to Google Drive',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: driveState.isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined, size: 22),
                  ),
                ),
              IconButton(
                tooltip: state.blockMode ? 'Block mode: on' : 'Block mode: off',
                isSelected: state.blockMode,
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view),
                onPressed: () =>
                    ref.read(editorProvider.notifier).toggleBlockMode(),
                style: state.blockMode
                    ? IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Save  (Cmd+S)',
                onPressed: () => _save(context, ref),
              ),
              PopupMenuButton<_MenuAction>(
                tooltip: 'More',
                onSelected: (action) {
                  switch (action) {
                    case _MenuAction.saveAs:
                      _saveAs(context, ref);
                    case _MenuAction.export:
                      showExportDialog(context, state.pattern,
                          useDmc: ref.read(settingsProvider).useDmc,
                          notifier: ref.read(editorProvider.notifier));
                    case _MenuAction.resize:
                      _showResizeDialog(context, ref, state);
                    case _MenuAction.patternInfo:
                      showPatternInfo(context, ref, state);
                    case _MenuAction.referenceImage:
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ReferenceImageSheet(),
                      );
                    case _MenuAction.toggleCompress:
                      ref.read(editorProvider.notifier).toggleCompressOnSave();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: _MenuAction.referenceImage,
                    child: _MenuRow(
                      icon: Icons.image_outlined,
                      label: 'Reference Image',
                      trailing: state.referenceImage != null &&
                              state.referenceVisible
                          ? Icon(Icons.check,
                              size: 16,
                              color: Theme.of(ctx).colorScheme.primary)
                          : null,
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.resize,
                    child: _MenuRow(
                        icon: Icons.aspect_ratio, label: 'Resize Aida'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.patternInfo,
                    child:
                        _MenuRow(icon: Icons.info_outline, label: 'Pattern Info'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _MenuAction.saveAs,
                    child: _MenuRow(
                        icon: Icons.save_as_outlined, label: 'Save As…'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.export,
                    child: _MenuRow(
                        icon: Icons.upload_outlined,
                        label: 'Export…'),
                  ),
                  if (state.isNativeFormat)
                    PopupMenuItem(
                      value: _MenuAction.toggleCompress,
                      child: _MenuRow(
                        icon: Icons.folder_zip_outlined,
                        label: state.compressOnSave
                            ? 'File Compressed'
                            : 'File Uncompressed',
                        trailing: state.compressOnSave
                            ? Icon(Icons.check,
                                size: 16,
                                color: Theme.of(ctx).colorScheme.primary)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
            // Stitch mode actions — Block mode + Materials + Demo + Screen Lock
            if (state.stitchMode) ...[
              IconButton(
                tooltip: 'Materials list',
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => showMaterialsList(context, state),
              ),
              IconButton(
                tooltip: state.blockMode ? 'Block mode: on' : 'Block mode: off',
                isSelected: state.blockMode,
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view),
                onPressed: () =>
                    ref.read(editorProvider.notifier).toggleBlockMode(),
                style: state.blockMode
                    ? IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
              StitchDemoButton(state: state),
              _ScreenLockButton(ref: ref),
              const SizedBox(width: 4),
            ],
          ],
        ),
        body: Focus(
          autofocus: true,
          onKeyEvent: handleKeys,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    if (!state.isNativeFormat)
                      _ImportBanner(
                        filePath: state.filePath!,
                        onSaveAs: () => _saveAs(context, ref),
                      ),
                    const Expanded(child: PatternCanvas()),
                    const SafeArea(top: false, child: EditorToolbar()),
                  ],
                ),
              ),
              const RightSidebar(sidebarContext: RightSidebarContext.mainEditor),
            ],
          ),
        ),
        floatingActionButton: state.isFileOpen
            ? Padding(
                padding: EdgeInsets.only(bottom: state.stitchMode ? 16 : 58),
                child: FloatingActionButton.extended(
                  onPressed: () =>
                      ref.read(editorProvider.notifier).toggleStitchMode(),
                  icon: Icon(state.stitchMode
                      ? Icons.edit_outlined
                      : Icons.auto_stories_outlined),
                  label: Text(
                      state.stitchMode ? 'Exit Stitch Mode' : 'Stitch Mode'),
                  backgroundColor: state.stitchMode
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  foregroundColor: state.stitchMode
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : null,
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      ),
    );
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

}

// ─── Shared popup menu row ───────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const _MenuRow({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}
// ─── Screen lock toggle button ────────────────────────────────────────────────

class _ScreenLockButton extends ConsumerWidget {
  final WidgetRef ref;
  const _ScreenLockButton({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keepOn = ref.watch(settingsProvider).keepScreenOn;
    return Tooltip(
      message: keepOn ? 'Screen lock: off' : 'Screen lock: on',
      child: IconButton(
        isSelected: keepOn,
        icon: const Icon(Icons.screen_lock_portrait_outlined),
        selectedIcon: const Icon(Icons.screen_lock_portrait),
        style: keepOn
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              )
            : null,
        onPressed: () => ref
            .read(settingsProvider.notifier)
            .setKeepScreenOn(!keepOn),
      ),
    );
  }
}

// ─── Import format banner ─────────────────────────────────────────────────────

class _ImportBanner extends StatelessWidget {
  final String filePath;
  final VoidCallback onSaveAs;

  const _ImportBanner({required this.filePath, required this.onSaveAs});

  String get _ext {
    final dot = filePath.lastIndexOf('.');
    return dot >= 0 ? filePath.substring(dot + 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Imported $_ext file — snippets require .stitches format.',
                style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs.onTertiaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onSaveAs,
              child: const Text('Save As .stitches', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
