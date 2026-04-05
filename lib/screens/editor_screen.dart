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
import 'materials_list_screen.dart';
import 'page_mode_dialog.dart';
import 'pattern_info_dialog.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';


enum _MenuAction { saveAs, export, resize, referenceImage }

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

  String _title(EditorState state) => state.pattern.name;

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
          titleSpacing: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drive sync indicator — left of title, all modes ──────────
              if (state.driveParentFolderId != null) ...[
                Tooltip(
                  message: (driveState.isSyncing || state.driveFileId == null || state.isDirty)
                      ? 'Syncing to Google Drive…'
                      : 'Synced to Google Drive',
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: (driveState.isSyncing || state.driveFileId == null || state.isDirty)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_done_outlined, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ] else if (state.isFileOpen) ...[
                Tooltip(
                  message: state.isDirty ? 'Saving…' : 'Saved',
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: state.isDirty
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.task_alt, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Text(_title(state)),
              const SizedBox(width: 4),
              // ── Block mode toggle — in title area, consistent across modes ──
              IconButton(
                tooltip: state.blockMode ? 'Block mode: on' : 'Block mode: off',
                isSelected: state.blockMode,
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view),
                onPressed: () =>
                    ref.read(editorProvider.notifier).toggleBlockMode(),
                style: state.blockMode
                    ? IconButton.styleFrom(
                        backgroundColor: state.mode == AppMode.stitch
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: state.mode == AppMode.stitch
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
            ],
          ),
          backgroundColor: state.mode == AppMode.stitch
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          actions: [
            // ── View mode: pattern info/export menu + Edit + Stitch ──────────
            if (state.mode == AppMode.view) ...[
              IconButton(
                tooltip: 'Pattern Info',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showPatternInfo(context, ref, state),
              ),
              IconButton(
                tooltip: 'Materials list',
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => showMaterialsList(context, state),
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
                    default:
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: _MenuAction.saveAs,
                    child: EditorMenuRow(icon: Icons.save_as_outlined, label: 'Save As…'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.export,
                    child: EditorMenuRow(icon: Icons.upload_outlined, label: 'Export…'),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: () =>
                    ref.read(editorProvider.notifier).setMode(AppMode.edit),
                child: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    ref.read(editorProvider.notifier).setMode(AppMode.stitch),
                child: const Text('Stitch'),
              ),
              const SizedBox(width: 8),
            ],
            // ── Edit mode: save + overflow + Done ────────────────────────────
            if (state.mode == AppMode.edit) ...[
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Save  (Cmd+S)',
                onPressed: () => _save(context, ref),
              ),
              PopupMenuButton<_MenuAction>(
                tooltip: 'More',
                onSelected: (action) {
                  switch (action) {
                    case _MenuAction.resize:
                      _showResizeDialog(context, ref, state);
                    case _MenuAction.referenceImage:
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ReferenceImageSheet(),
                      );
                    default:
                      break;
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
                ],
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () =>
                    ref.read(editorProvider.notifier).setMode(AppMode.view),
                child: const Text('Done'),
              ),
              const SizedBox(width: 8),
            ],
            // ── Stitch mode: page nav + demo + screen lock + Done ────────────
            if (state.mode == AppMode.stitch) ...[
              IconButton(
                tooltip: state.pattern.pageConfig.enabled
                    ? 'Page mode: on'
                    : 'Page mode: off',
                isSelected: state.pattern.pageConfig.enabled,
                icon: const Icon(Icons.auto_stories_outlined),
                selectedIcon: const Icon(Icons.auto_stories),
                onPressed: () => showPageModeDialog(context, ref),
                style: state.pattern.pageConfig.enabled
                    ? IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
              const EditorScreenLockButton(),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () =>
                    ref.read(editorProvider.notifier).setMode(AppMode.view),
                child: const Text('Done'),
              ),
              const SizedBox(width: 8),
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

