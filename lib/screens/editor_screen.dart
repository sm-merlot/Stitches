import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/files/folder_contents_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stitching_timer_provider.dart';
import '../widgets/dialogs/timer_inactivity_dialog.dart';
import '../models/page/page_config.dart';
import '../models/progress/pattern_progress.dart';
import '../models/storage_location.dart';
import '../services/file_service.dart';
import '../services/format_service.dart';
import '../services/pdf_service.dart';
import '../services/png_export_service.dart';
import '../utils/snackbars.dart';
import '../widgets/views/edit_view.dart';
import '../widgets/editor_shared_widgets.dart';
import '../widgets/views/stitch_view.dart';
import '../widgets/share_format_picker.dart';
import 'drive/drive_folder_picker_dialog.dart';
import '../widgets/sidebar/right_sidebar.dart';
import 'materials_list_screen.dart';
import 'page_mode_dialog.dart';
import 'pattern_info_dialog.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';
import 'settings_screen.dart';
import 'stitch_ops_screen.dart';


// No overflow menu — all actions are direct app bar buttons.

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      ref.read(stitchingTimerProvider.notifier).checkInactivityNow();
    }
  }

  bool _inactivityDialogShowing = false;

  Future<void> _handleInactivityPrompt() async {
    final timerNotifier = ref.read(stitchingTimerProvider.notifier);

    final editorState = ref.read(editorProvider);
    if (!editorState.stitchMode) {
      timerNotifier.acknowledgeInactivityPrompt();
      return;
    }

    if (_inactivityDialogShowing) return;
    _inactivityDialogShowing = true;
    timerNotifier.acknowledgeInactivityPrompt();

    if (!mounted) {
      _inactivityDialogShowing = false;
      return;
    }

    // editor_screen is phone-only — no workspace, so workspaceId is always null.
    final session = ref.read(stitchingTimerProvider).sessionFor(null);
    final lastInteraction = timerNotifier.lastInteractionForWorkspace(null);
    final result = await showInactivityDialog(
      context,
      sessionStart: session!.sessionStart!,
      lastInteractionAt: lastInteraction,
    );
    _inactivityDialogShowing = false;
    if (!mounted) return;

    switch (result) {
      case InactivityResult.keepRunning:
        timerNotifier.recordInteraction();
      case InactivityResult.stopAtLastActivity:
        timerNotifier.stop(stopAt: lastInteraction);
      case InactivityResult.stopKeepAll:
        timerNotifier.stop();
    }
  }

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
          if (result.stripProgress) sharePattern = sharePattern.copyWith(progress: PatternProgress.empty, progressLog: const []);
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
              useDmc: ref.read(settingsProvider).useDmc,
              realistic: result.realisticStitches);
          fileName = '$suggested.pdf';
        case ShareFormat.png:
          bytes = await PngExportService.export(state.pattern,
              realistic: result.realisticStitches);
          fileName = '$suggested.png';
      }
      if (!context.mounted) return;
      final id = await ref.read(googleDriveProvider.notifier).uploadRawFile(
            name: fileName, bytes: bytes, parentFolderId: folder.folderId);
      if (!context.mounted) return;
      if (id != null) {
        showSuccess(context, 'Exported to Drive as $fileName');
        refreshFolder(ref, folder);
        if (result.format == ShareFormat.pdf && result.patternKeeperPdf && context.mounted) {
          final pkBytes = await PdfService.buildPdfBytes(state.pattern,
              useDmc: ref.read(settingsProvider).useDmc,
              patternKeeperMode: true);
          final pkFileName = '${suggested}_PatternKeeper.pdf';
          final pkId = await ref.read(googleDriveProvider.notifier)
              .uploadRawFile(name: pkFileName, bytes: pkBytes, parentFolderId: folder.folderId);
          if (context.mounted && pkId != null) {
            showSuccess(context, 'Also exported PatternKeeper PDF');
            refreshFolder(ref, folder);
          }
        }
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
          if (result.stripProgress) sharePattern = sharePattern.copyWith(progress: PatternProgress.empty, progressLog: const []);
          if (result.stripPageSettings) sharePattern = sharePattern.copyWith(pageConfig: PageConfig.disabled);
          if (isMobile) {
            final yaml = FileService.toYamlString(sharePattern);
            final bytes = Uint8List.fromList(gzip.encode(utf8.encode(yaml)));
            final path = await FilePicker.saveFile(
              fileName: '$suggested.stitches', type: FileType.any, bytes: bytes);
            if (path != null) {
              ref.read(editorProvider.notifier).setFilePath(path);
              ref.read(editorProvider.notifier).markSaved();
              if (context.mounted) showSuccess(context, 'Saved');
            }
          } else {
            final yaml = FileService.toYamlString(sharePattern);
            final effectiveCompress = kDebugMode ? state.compressOnSave : true;
            final bytes = Uint8List.fromList(effectiveCompress
                ? gzip.encode(utf8.encode(yaml))
                : utf8.encode(yaml));
            final path = await FilePicker.saveFile(
              fileName: '$suggested.stitches',
              type: FileType.custom,
              allowedExtensions: ['stitches'],
              initialDirectory: initialDir,
              bytes: bytes,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.stitches') ? path : '$path.stitches';
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
            await FilePicker.saveFile(
              fileName: '$suggested.oxs', type: FileType.any, bytes: bytes);
            if (context.mounted) showSuccess(context, 'Exported $suggested.oxs');
          } else {
            final path = await FilePicker.saveFile(
              fileName: '$suggested.oxs',
              type: FileType.custom,
              allowedExtensions: ['oxs'],
              initialDirectory: initialDir,
              bytes: bytes,
            );
            if (path == null) return;
            if (context.mounted) {
              showSuccess(context, 'Exported ${path.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.pdf:
          final bytes = await PdfService.buildPdfBytes(state.pattern,
              useDmc: ref.read(settingsProvider).useDmc,
              realistic: result.realisticStitches);
          if (!context.mounted) return;
          if (isMobile) {
            await FilePicker.saveFile(
              fileName: '$suggested.pdf', type: FileType.any, bytes: bytes);
            if (context.mounted) showSuccess(context, 'Exported $suggested.pdf');
            if (result.patternKeeperPdf && context.mounted) {
              final pkBytes = await PdfService.buildPdfBytes(state.pattern,
                  useDmc: ref.read(settingsProvider).useDmc,
                  patternKeeperMode: true);
              if (context.mounted) {
                await FilePicker.saveFile(
                  fileName: '${suggested}_PatternKeeper.pdf', type: FileType.any, bytes: pkBytes);
                if (context.mounted) showSuccess(context, 'Exported PatternKeeper PDF');
              }
            }
          } else {
            final path = await FilePicker.saveFile(
              fileName: '$suggested.pdf',
              type: FileType.custom,
              allowedExtensions: ['pdf'],
              initialDirectory: initialDir,
              bytes: bytes,
            );
            if (path == null) return;
            if (context.mounted) {
              showSuccess(context, 'Exported ${path.split(Platform.pathSeparator).last}');
            }
            if (result.patternKeeperPdf && context.mounted) {
              final pkBytes = await PdfService.buildPdfBytes(state.pattern,
                  useDmc: ref.read(settingsProvider).useDmc,
                  patternKeeperMode: true);
              if (context.mounted) {
                await FilePicker.saveFile(
                  fileName: '${suggested}_PatternKeeper.pdf',
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                  bytes: pkBytes,
                );
                if (context.mounted) showSuccess(context, 'Exported PatternKeeper PDF');
              }
            }
          }
        case ShareFormat.png:
          final bytes = await PngExportService.export(state.pattern,
              realistic: result.realisticStitches);
          if (!context.mounted) return;
          if (isMobile) {
            await FilePicker.saveFile(
              fileName: '$suggested.png', type: FileType.any, bytes: bytes);
            if (context.mounted) showSuccess(context, 'Exported $suggested.png');
          } else {
            final path = await FilePicker.saveFile(
              fileName: '$suggested.png',
              type: FileType.custom,
              allowedExtensions: ['png'],
              initialDirectory: initialDir,
              bytes: bytes,
            );
            if (path == null) return;
            if (context.mounted) {
              showSuccess(context, 'Exported ${path.split(Platform.pathSeparator).last}');
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
    if (state.stitchMode) {
      return Listener(
        onPointerDown: (_) =>
            ref.read(stitchingTimerProvider.notifier).recordInteraction(),
        child: StitchView(onSave: () => _save(context, ref)),
      );
    }
    if (state.isNativeFormat) {
      return EditView(onSave: () => _save(context, ref));
    }
    final filePath = state.filePath!;
    final lastDot = filePath.lastIndexOf('.');
    final withoutExt = lastDot > 0 ? filePath.substring(0, lastDot) : filePath;
    final nativePath = '$withoutExt.stitches';
    final nativeExists = File(nativePath).existsSync();
    return EditView(
      onSave: () => _save(context, ref),
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
          if (result.stripProgress) sharePattern = sharePattern.copyWith(progress: PatternProgress.empty, progressLog: const []);
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
              useDmc: ref.read(settingsProvider).useDmc,
              realistic: result.realisticStitches);
          fileName = '$suggested.pdf';
          mimeType = 'application/pdf';
        case ShareFormat.png:
          bytes = await PngExportService.export(pattern,
              realistic: result.realisticStitches);
          fileName = '$suggested.png';
          mimeType = 'image/png';
      }

      final tmpFile = File('${tmpDir.path}/$fileName');
      await tmpFile.writeAsBytes(bytes, flush: true);

      final shareFiles = <XFile>[XFile(tmpFile.path, mimeType: mimeType, name: fileName)];
      if (result.format == ShareFormat.pdf && result.patternKeeperPdf) {
        final pkBytes = await PdfService.buildPdfBytes(pattern,
            useDmc: ref.read(settingsProvider).useDmc,
            patternKeeperMode: true);
        final pkName = '${suggested}_PatternKeeper.pdf';
        final pkFile = File('${tmpDir.path}/$pkName');
        await pkFile.writeAsBytes(pkBytes, flush: true);
        shareFiles.add(XFile(pkFile.path, mimeType: 'application/pdf', name: pkName));
      }

      await SharePlus.instance.share(ShareParams(
        files: shareFiles,
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (context.mounted) showError(context, 'Share failed: $e');
    }
  }

  Future<bool> _onWillPop(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);

    // In edit or stitch mode, back exits to view mode instead of leaving.
    if (state.editMode || state.stitchMode) {
      ref.read(editorProvider.notifier).setMode(AppMode.view);
      return false;
    }

    // Always confirm before closing — even when clean — to prevent
    // accidental navigation away from the editor.
    final isUnsavedNew = state.filePath == null && state.driveParentFolderId == null;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(state.isDirty ? 'Unsaved Changes' : 'Close Pattern'),
        content: Text(
          state.isDirty
              ? (isUnsavedNew
                  ? 'This pattern hasn\'t been saved. Leave now and your work will be lost.'
                  : 'You have unsaved changes. Leave without saving?')
              : 'Close this pattern and return home?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(state.isDirty ? 'Leave' : 'Close',
                style: state.isDirty ? const TextStyle(color: Colors.red) : null),
          ),
          if (state.isDirty)
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop(false);
                await _save(context, ref);
              },
              child: Text(isUnsavedNew ? 'Save As…' : 'Save'),
            ),
        ],
      ),
    );
    return result ?? false;
  }

  String _title(EditorState state) => state.pattern.name;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final driveState = ref.watch(googleDriveProvider);

    ref.listen<StitchingTimerState>(stitchingTimerProvider, (prev, next) {
      // editor_screen is phone-only — no workspace, workspaceId is always null.
      if (next.sessionFor(null)?.showInactivityPrompt == true &&
          prev?.sessionFor(null)?.showInactivityPrompt != true) {
        _handleInactivityPrompt();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(context, ref);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: state.mode == AppMode.view
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close pattern',
                  onPressed: () async {
                    final shouldPop = await _onWillPop(context, ref);
                    if (shouldPop && context.mounted) Navigator.of(context).pop();
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to view',
                  onPressed: () =>
                      ref.read(editorProvider.notifier).setMode(AppMode.view),
                ),
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
                // New unsaved file (no path yet) — can't auto-save; show
                // a static "needs saving" badge. Saved/saving: spinner → tick.
                if (state.filePath == null)
                  Tooltip(
                    message: 'Not saved — use Save As to save this pattern',
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Icon(
                          Icons.save_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  )
                else
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  _title(state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
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
              IconButton(
                tooltip: 'StitchOps — progress stats',
                icon: const Icon(Icons.bar_chart_outlined),
                onPressed: () => showStitchOps(context, state.pattern,
                    onClearProgress: () =>
                        ref.read(editorProvider.notifier).clearProgress(),
                    onAdjustTime: (date, mins) =>
                        ref.read(editorProvider.notifier).setTimeForDate(date, mins)),
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
                isSelected: state.editSession.referenceImage != null && state.editSession.referenceVisible,
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
              const SizedBox(width: 8),
            ],
            // ── Stitch mode: page nav + demo + screen lock + Done ────────────
            if (state.mode == AppMode.stitch) ...[
              IconButton(
                tooltip: 'StitchOps — progress stats',
                icon: const Icon(Icons.bar_chart_outlined),
                onPressed: () => showStitchOps(context, state.pattern,
                    onClearProgress: () =>
                        ref.read(editorProvider.notifier).clearProgress(),
                    onAdjustTime: (date, mins) =>
                        ref.read(editorProvider.notifier).setTimeForDate(date, mins)),
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
              const SizedBox(width: 8),
            ],
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildCanvasArea(context, ref, state),
            ),
            const RightSidebar(sidebarContext: RightSidebarContext.mainEditor),
          ],
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


