import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/settings_provider.dart';
import '../models/page_config.dart';
import '../models/pattern_progress.dart';
import '../models/storage_location.dart';
import '../services/file_service.dart';
import '../services/format_service.dart';
import '../services/pdf_service.dart';
import '../services/png_export_service.dart';
import '../utils/editor_key_handler.dart';
import '../utils/snackbars.dart';
import '../widgets/editor_canvas_area.dart';
import '../widgets/editor_shared_widgets.dart';
import '../widgets/share_format_picker.dart';
import 'drive_folder_picker_dialog.dart';
import '../widgets/right_sidebar.dart';
import 'materials_list_screen.dart';
import 'page_mode_dialog.dart';
import 'pattern_info_dialog.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';


// No overflow menu — all actions are direct app bar buttons.

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

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    final result = await showShareFormatPicker(context,
        title: 'Export as…',
        hasProgress: state.pattern.progress.completedStitches.isNotEmpty,
        hasPageSettings: state.pattern.pageConfig.enabled);
    if (result == null || !context.mounted) return;

    if (state.driveParentFolderId != null) {
      bool saveLocally = false;
      final driveResult = await showDialog<(DriveFolder, String)?>(
        context: context,
        builder: (_) => DriveFolderPickerDialog(
          onSaveLocally: () => saveLocally = true,
        ),
      );
      if (!context.mounted) return;
      if (driveResult != null) {
        await _exportToDriveFolder(context, ref, state, result, driveResult.$1);
        return;
      }
      if (!saveLocally) return;
    }

    await _exportToLocalFile(context, ref, state, result);
  }

  Future<void> _exportToDriveFolder(
      BuildContext context,
      WidgetRef ref,
      EditorState state,
      PatternShareResult result,
      DriveFolder folder) async {
    final suggested = state.pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    try {
      late final Uint8List bytes;
      late final String fileName;
      switch (result.format) {
        case ShareFormat.stitchesFile:
          var sharePattern = state.patternForSave;
          if (result.stripProgress) sharePattern = sharePattern.copyWith(progress: PatternProgress.empty);
          if (result.stripPageSettings) sharePattern = sharePattern.copyWith(pageConfig: PageConfig.disabled);
          final yaml = FileService.toYamlString(sharePattern);
          bytes = Uint8List.fromList(gzip.encode(utf8.encode(yaml)));
          fileName = '$suggested.stitches';
        case ShareFormat.oxs:
          bytes = Uint8List.fromList(utf8.encode(
              FormatService.encodeFile(state.pattern, CrossStitchFormat.oxs)));
          fileName = '$suggested.oxs';
        case ShareFormat.pdf:
          bytes = await PdfService.buildPdfBytes(state.pattern,
              useDmc: ref.read(settingsProvider).useDmc);
          fileName = '$suggested.pdf';
        case ShareFormat.png:
          bytes = await PngExportService.export(state.pattern);
          fileName = '$suggested.png';
      }
      if (!context.mounted) return;
      final id = await ref.read(googleDriveProvider.notifier).uploadRawFile(
            name: fileName, bytes: bytes, parentFolderId: folder.folderId);
      if (!context.mounted) return;
      if (id != null) {
        showSuccess(context, 'Exported to Drive as $fileName');
      } else {
        showError(context, 'Drive export failed');
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Export failed: $e');
    }
  }

  Future<void> _exportToLocalFile(
      BuildContext context, WidgetRef ref, EditorState state, PatternShareResult result) async {
    final suggested = state.pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final initialDir = (state.filePath != null && state.driveParentFolderId == null)
        ? File(state.filePath!).parent.path
        : null;
    try {
      switch (result.format) {
        case ShareFormat.stitchesFile:
          var sharePattern = state.patternForSave;
          if (result.stripProgress) sharePattern = sharePattern.copyWith(progress: PatternProgress.empty);
          if (result.stripPageSettings) sharePattern = sharePattern.copyWith(pageConfig: PageConfig.disabled);
          if (isMobile) {
            final yaml = FileService.toYamlString(sharePattern);
            final bytes = Uint8List.fromList(gzip.encode(utf8.encode(yaml)));
            final path = await FilePicker.platform.saveFile(
              fileName: '$suggested.stitches', type: FileType.any, bytes: bytes);
            if (path != null) {
              ref.read(editorProvider.notifier).setFilePath(path);
              ref.read(editorProvider.notifier).markSaved();
              if (context.mounted) showSuccess(context, 'Saved');
            }
          } else {
            final path = await FilePicker.platform.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['stitches'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.stitches') ? path : '$path.stitches';
            await FileService.saveFile(sharePattern, finalPath,
                compress: state.compressOnSave);
            ref.read(editorProvider.notifier).setFilePath(finalPath);
            ref.read(editorProvider.notifier).markSaved();
            if (context.mounted) {
              showSuccess(context, 'Saved as ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.oxs:
          final bytes = Uint8List.fromList(utf8.encode(
              FormatService.encodeFile(state.pattern, CrossStitchFormat.oxs)));
          if (isMobile) {
            await FilePicker.platform.saveFile(
              fileName: '$suggested.oxs', type: FileType.any, bytes: bytes);
            if (context.mounted) showSuccess(context, 'Exported $suggested.oxs');
          } else {
            final path = await FilePicker.platform.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['oxs'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.oxs') ? path : '$path.oxs';
            await FormatService.exportFile(state.pattern, finalPath, CrossStitchFormat.oxs);
            if (context.mounted) {
              showSuccess(context, 'Exported ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.pdf:
          final bytes = await PdfService.buildPdfBytes(state.pattern,
              useDmc: ref.read(settingsProvider).useDmc);
          if (!context.mounted) return;
          if (isMobile) {
            await FilePicker.platform.saveFile(
              fileName: '$suggested.pdf', type: FileType.any, bytes: bytes);
            if (context.mounted) showSuccess(context, 'Exported $suggested.pdf');
          } else {
            final path = await FilePicker.platform.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['pdf'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.pdf') ? path : '$path.pdf';
            await File(finalPath).writeAsBytes(bytes);
            if (context.mounted) {
              showSuccess(context, 'Exported ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.png:
          final bytes = await PngExportService.export(state.pattern);
          if (!context.mounted) return;
          if (isMobile) {
            await FilePicker.platform.saveFile(
              fileName: '$suggested.png', type: FileType.any, bytes: bytes);
            if (context.mounted) showSuccess(context, 'Exported $suggested.png');
          } else {
            final path = await FilePicker.platform.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['png'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.png') ? path : '$path.png';
            await File(finalPath).writeAsBytes(bytes);
            if (context.mounted) {
              showSuccess(context, 'Exported ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Export failed: $e');
    }
  }

  Future<void> _convertToNative(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    final filePath = state.filePath;
    if (filePath == null) return;
    final lastDot = filePath.lastIndexOf('.');
    final withoutExt = lastDot > 0 ? filePath.substring(0, lastDot) : filePath;
    final targetPath = '$withoutExt.stitches';
    try {
      await FileService.saveFile(state.patternForSave, targetPath,
          compress: state.compressOnSave);
      ref.read(editorProvider.notifier).setFilePath(targetPath);
      ref.read(editorProvider.notifier).markSaved();
      if (context.mounted) {
        showSuccess(
            context, 'Converted to ${targetPath.split(Platform.pathSeparator).last}');
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Convert failed: $e');
    }
  }

  /// Builds the canvas area, wiring up the import banner callbacks.
  Widget _buildCanvasArea(BuildContext context, WidgetRef ref, EditorState state) {
    if (state.isNativeFormat) {
      return const EditorCanvasArea();
    }
    final filePath = state.filePath!;
    final lastDot = filePath.lastIndexOf('.');
    final withoutExt = lastDot > 0 ? filePath.substring(0, lastDot) : filePath;
    final nativePath = '$withoutExt.stitches';
    final nativeExists = File(nativePath).existsSync();
    return EditorCanvasArea(
      importFilePath: filePath,
      onConvert: nativeExists ? null : () => _convertToNative(context, ref),
      onOpenNative: nativeExists ? () => _openNativeFile(context, ref, nativePath) : null,
    );
  }

  Future<void> _openNativeFile(
      BuildContext context, WidgetRef ref, String nativePath) async {
    try {
      final (pattern, path, wasCompressed) =
          await FileService.openFileFromPath(nativePath);
      ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: path,
            compressOnSave: wasCompressed,
          );
    } catch (e) {
      if (context.mounted) showError(context, 'Open failed: $e');
    }
  }


  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    final result = await showShareFormatPicker(context,
        hasProgress: state.pattern.progress.completedStitches.isNotEmpty,
        hasPageSettings: state.pattern.pageConfig.enabled);
    if (result == null || !context.mounted) return;
    try {
      final pattern = state.pattern;
      final suggested =
          pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final tmpDir = await getTemporaryDirectory();

      late final Uint8List bytes;
      late final String fileName;
      late final String mimeType;

      switch (result.format) {
        case ShareFormat.stitchesFile:
          var sharePattern = pattern;
          if (result.stripProgress) sharePattern = sharePattern.copyWith(progress: PatternProgress.empty);
          if (result.stripPageSettings) sharePattern = sharePattern.copyWith(pageConfig: PageConfig.disabled);
          final yaml = FileService.toYamlString(sharePattern);
          bytes = Uint8List.fromList(gzip.encode(utf8.encode(yaml)));
          fileName = '$suggested.stitches';
          mimeType = 'application/octet-stream';
        case ShareFormat.oxs:
          bytes = Uint8List.fromList(utf8.encode(
              FormatService.encodeFile(pattern, CrossStitchFormat.oxs)));
          fileName = '$suggested.oxs';
          mimeType = 'application/octet-stream';
        case ShareFormat.pdf:
          bytes = await PdfService.buildPdfBytes(pattern,
              useDmc: ref.read(settingsProvider).useDmc);
          fileName = '$suggested.pdf';
          mimeType = 'application/pdf';
        case ShareFormat.png:
          bytes = await PngExportService.export(pattern);
          fileName = '$suggested.png';
          mimeType = 'image/png';
      }

      final tmpFile = File('${tmpDir.path}/$fileName');
      await tmpFile.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(tmpFile.path, mimeType: mimeType, name: fileName)],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (context.mounted) showError(context, 'Share failed: $e');
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
            // ── View mode: pattern info + share + overflow + Edit + Stitch ──
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
              // Share button: iOS, Android, macOS only
              if (!kIsWeb && !Platform.isWindows)
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _share(context, ref),
                ),
              IconButton(
                tooltip: 'Export',
                icon: const Icon(Icons.upload_outlined),
                onPressed: () => _export(context, ref),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: () =>
                    ref.read(editorProvider.notifier).setMode(AppMode.edit),
                child: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final pruned = ref
                      .read(editorProvider.notifier)
                      .setMode(AppMode.stitch);
                  if (pruned > 0 && context.mounted) {
                    showWarning(context,
                        '$pruned completed ${pruned == 1 ? 'stitch' : 'stitches'} removed — no longer in the pattern');
                  }
                },
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
              IconButton(
                tooltip: 'Reference Image',
                isSelected: state.referenceImage != null && state.referenceVisible,
                icon: const Icon(Icons.image_outlined),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ReferenceImageSheet(),
                ),
              ),
              IconButton(
                tooltip: 'Resize Aida',
                icon: const Icon(Icons.aspect_ratio),
                onPressed: () => _showResizeDialog(context, ref, state),
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
                tooltip: 'Progress tracking',
                icon: const Icon(Icons.checklist),
                onPressed: () =>
                    showProgressHelpDialog(context, ref, state: state),
              ),
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
                child: _buildCanvasArea(context, ref, state),
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


