import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/settings_provider.dart';
import '../services/file_service.dart';
import '../utils/editor_key_handler.dart';
import '../utils/snackbars.dart';
import '../widgets/editor_canvas_area.dart';
import '../widgets/editor_shared_widgets.dart';
import 'export_dialog.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/right_sidebar_colours_panel.dart';
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
      return handleEditorKeys(
        event,
        state,
        ref.read(editorProvider.notifier),
        onSave: () => _save(context, ref),
      );
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
                    child: EditorMenuRow(
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
                    child: EditorMenuRow(
                        icon: Icons.aspect_ratio, label: 'Resize Aida'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.patternInfo,
                    child: EditorMenuRow(
                        icon: Icons.info_outline, label: 'Pattern Info'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _MenuAction.saveAs,
                    child: EditorMenuRow(
                        icon: Icons.save_as_outlined, label: 'Save As…'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.export,
                    child: EditorMenuRow(
                        icon: Icons.upload_outlined,
                        label: 'Export…'),
                  ),
                  if (state.isNativeFormat)
                    PopupMenuItem(
                      value: _MenuAction.toggleCompress,
                      child: EditorMenuRow(
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
            // Stitch mode actions — Materials + Demo + Screen Lock
            if (state.stitchMode) ...[
              IconButton(
                tooltip: 'Materials list',
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => showMaterialsList(context, state),
              ),
              StitchDemoButton(state: state),
              const EditorScreenLockButton(),
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
                child: EditorCanvasArea(
                  importFilePath:
                      state.isNativeFormat ? null : state.filePath,
                  onSaveAs: state.isNativeFormat
                      ? null
                      : () => _saveAs(context, ref),
                ),
              ),
              const RightSidebar(sidebarContext: RightSidebarContext.mainEditor),
            ],
          ),
        ),
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

