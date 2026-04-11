import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/page_config.dart';
import '../models/pattern.dart';
import '../models/pattern_progress.dart';
import '../models/storage_location.dart';
import '../providers/editor/editor_provider.dart';
import '../services/pattern_cache.dart';
import '../providers/file_loading_provider.dart';
import '../providers/folder_contents_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/image_viewer_provider.dart';
import '../providers/pdf_viewer_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import '../services/pattern_thumbnail.dart';
import '../services/thumbnail_cache.dart';
import '../services/format_service.dart';
import '../services/pdf_service.dart';
import '../services/png_export_service.dart';
import '../utils/editor_key_handler.dart';
import '../providers/recent_items_provider.dart';
import '../utils/snackbars.dart';
import '../widgets/editor_shared_widgets.dart';
import '../widgets/share_format_picker.dart';
import 'drive_folder_picker_dialog.dart';
import 'materials_list_screen.dart';
import '../services/grid_detector.dart';
import '../services/grid_symbol_matcher.dart';
import '../services/pdf_scanner.dart';
import 'pattern_scan_symbol_screen.dart';
import '../widgets/editor_canvas_area.dart';
import '../widgets/file_sidebar.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/pdf_page_picker.dart';
import '../widgets/image_viewer_panel.dart';
import '../widgets/pdf_viewer_panel.dart';
import 'new_pattern_dialog.dart';
import 'pattern_scan_cell_screen.dart';
import 'pattern_scan_crop_screen.dart';
import 'pattern_scan_preview.dart';
import 'pattern_scan_review_screen.dart';
import 'pattern_info_dialog.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';
import 'page_mode_dialog.dart';

part 'workspace_screen_components.dart';

// No overflow menu — all actions are direct app bar buttons.

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}


class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  Timer? _autoSaveTimer;
  final _pdfPanelKey = GlobalKey<PdfViewerPanelState>();

  // Phone-only: right sidebar starts collapsed; coordinates with folder sidebar.
  bool _rightSidebarCollapsed = true;

  bool _isPhone(BuildContext context) =>
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      MediaQuery.of(context).size.shortestSide < 600;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = ref.read(workspaceProvider).workspace;
      if (ws is LocalFolder) {
        unawaited(_refreshThumbnailsInBackground(ws.path));
      } else if (ws is DriveFolder) {
        unawaited(_refreshDriveThumbnailsInBackground(ws));
      }
    });
  }

  /// Walks [folderPath] and generates thumbnails for any `.stitches` file
  /// not already in the cache, then adds every file to recents (with its
  /// thumbnailKey) so the folder thumbnail strip is fully populated even for
  /// files never explicitly opened. Fire-and-forget.
  Future<void> _refreshThumbnailsInBackground(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return;
      final notifier = ref.read(recentItemsProvider.notifier);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.stitches')) continue;
        final path = entity.path;
        final key = localThumbnailKey(path);
        // Check if cache already has the thumbnail.
        var cached = await ThumbnailCache.load(key);
        if (cached == null) {
          try {
            final (pattern, _, _) =
                await FileService.openFileFromPath(path);
            final bytes = await generatePatternThumbnail(pattern);
            if (bytes != null) {
              await ThumbnailCache.store(key, bytes);
              cached = bytes;
            }
          } catch (_) {
            // Skip files that can't be parsed.
            continue;
          }
        }
        // Add as thumbnail-only so the folder strip shows it without
        // creating a visible standalone entry in the recents list.
        if (cached != null && mounted) {
          notifier.add(path, isFolder: false, thumbnailKey: key,
              thumbnailOnly: true, parentId: folderPath);
        }
      }
    } catch (_) {
      // Silently ignore filesystem errors.
    }
  }

  /// Recursively collects all [DrivePatternFile]s under [folder], up to
  /// [maxDepth] levels deep. Silently skips inaccessible sub-folders.
  Future<List<DrivePatternFile>> _collectDriveFiles(
      dynamic service, DriveFolder folder,
      {int maxDepth = 4}) async {
    if (maxDepth <= 0) return [];
    final contents = await service.listFolderContents(folder);
    final files = contents.files.whereType<DrivePatternFile>().toList();
    for (final sub in contents.subfolders.whereType<DriveFolder>()) {
      try {
        files.addAll(
            await _collectDriveFiles(service, sub, maxDepth: maxDepth - 1));
      } catch (_) {}
    }
    return files;
  }

  /// Lists [folder] on Drive (recursively) and generates thumbnails for
  /// .stitches files, adding each as a thumbnail-only recents entry so the
  /// folder strip shows them. Fire-and-forget.
  Future<void> _refreshDriveThumbnailsInBackground(DriveFolder folder) async {
    try {
      final service =
          await ref.read(googleDriveProvider.notifier).getService();
      if (service == null || !mounted) return;
      final allFiles = await _collectDriveFiles(service, folder);
      if (!mounted) return;
      final notifier = ref.read(recentItemsProvider.notifier);
      // Drive folder RecentItems use bare folderId as their id (not 'drive:…').
      final parentId = folder.folderId;
      for (final file in allFiles) {
        final key = driveThumbnailKey(file.fileId);
        var cached = await ThumbnailCache.load(key);
        if (cached == null) {
          try {
            final bytes = await service.downloadFile(file.fileId);
            final tempDir = await getTemporaryDirectory();
            final tempPath = '${tempDir.path}/${file.fileId}.stitches';
            await File(tempPath).writeAsBytes(bytes);
            final (pattern, _, _) =
                await FileService.openFileFromPath(tempPath);
            final thumbBytes = await generatePatternThumbnail(pattern);
            if (thumbBytes != null) {
              await ThumbnailCache.store(key, thumbBytes);
              cached = thumbBytes;
            }
          } catch (_) {
            continue;
          }
        }
        if (cached != null && mounted) {
          notifier.add(
            file.fileId,
            isFolder: false,
            thumbnailKey: key,
            thumbnailOnly: true,
            parentId: parentId,
          );
        }
      }
    } catch (_) {
      // Silently ignore Drive errors.
    }
  }

  void _openFolderSidebar() {
    ref.read(workspaceProvider.notifier).setSidebarVisible(true);
    setState(() => _rightSidebarCollapsed = true);
  }

  void _onRightSidebarCollapsedChanged(bool collapsed) {
    setState(() => _rightSidebarCollapsed = collapsed);
    if (!collapsed) {
      // Right sidebar expanding — close folder sidebar on phones.
      ref.read(workspaceProvider.notifier).setSidebarVisible(false);
    }
  }

  // PDF scan overlay — full-screen Overlay entry so AppBar is also blocked.
  final _scanStatus = ValueNotifier<String?>(null);
  final _scanSubtitle = ValueNotifier<String?>(null);
  bool _scanCancelled = false;
  OverlayEntry? _scanOverlayEntry;

  void _showScanOverlay(BuildContext context, String initialStatus) {
    _scanStatus.value = initialStatus;
    _scanOverlayEntry?.remove();
    _scanOverlayEntry = OverlayEntry(
      builder: (_) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Full-screen dim absorbs all taps (AppBar, back button, body).
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(color: const Color(0x66000000)),
              ),
            ),
            // Card is a sibling — NOT inside AbsorbPointer — so cancel works.
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<String?>(
                        valueListenable: _scanStatus,
                        builder: (context, status, child) =>
                            Text(status ?? ''),
                      ),
                      const SizedBox(height: 6),
                      ValueListenableBuilder<String?>(
                        valueListenable: _scanSubtitle,
                        builder: (context, subtitle, child) => subtitle != null
                            ? Text(
                                subtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          _scanCancelled = true;
                          _removeScanOverlay();
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_scanOverlayEntry!);
  }

  void _removeScanOverlay() {
    _scanStatus.value = null;
    _scanSubtitle.value = null;
    _scanOverlayEntry?.remove();
    _scanOverlayEntry = null;
  }

  @override
  void dispose() {
    // If a pending auto-save timer was cancelled without firing, flush it now.
    if (_autoSaveTimer != null) {
      _autoSaveTimer!.cancel();
      _autoSaveTimer = null;
      final state = ref.read(editorProvider);
      if (state.isDirty && state.filePath != null && state.isNativeFormat) {
        FileService.saveFile(state.patternForSave, state.filePath!,
            compress: state.compressOnSave);
      }
    }
    _scanOverlayEntry?.remove();
    _scanStatus.dispose();
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _save(context, quiet: true);
    });
  }

  Future<void> _save(BuildContext context, {bool quiet = false}) async {
    final state = ref.read(editorProvider);
    if (!state.isDirty) return;
    try {
      if (state.filePath != null) {
        // If the open file is in a foreign format, write back in that format.
        if (!state.isNativeFormat) {
          final format = CrossStitchFormat.forPath(state.filePath!);
          if (format != null) {
            await FormatService.exportFile(
                state.patternForSave, state.filePath!, format);
          }
        } else {
          await FileService.saveFile(
              state.patternForSave, state.filePath!,
              compress: state.compressOnSave);
        }
        ref.read(editorProvider.notifier).markSaved();
        if (!quiet && context.mounted) showSuccess(context, 'Saved');

        // Auto-upload to Drive only for native .stitches files.
        if (state.isNativeFormat) {
          final driveFileId = state.driveFileId;
          final parentFolderId = state.driveParentFolderId;
          if (driveFileId != null && parentFolderId != null) {
            final notifier = ref.read(googleDriveProvider.notifier);
            await notifier.uploadPattern(
              state.patternForSave,
              driveFileId,
              parentFolderId,
              compress: state.compressOnSave,
            );
          }
        }
      } else {
        await _saveAs(context);
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Save failed: $e');
    }
  }

  Future<void> _saveAs(BuildContext context) async {
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

  /// Share the pattern via the OS share sheet (iOS/Android/macOS only).
  Future<void> _share(BuildContext context) async {
    final state = ref.read(editorProvider);
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    final result = await showShareFormatPicker(context,
        hasProgress: state.pattern.progress.completedStitches.isNotEmpty,
        hasPageSettings: state.pattern.pageConfig.enabled);
    if (result == null || !context.mounted) return;
    try {
      var pattern = state.pattern;
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
          // Always compress for sharing (matches release-mode behaviour).
          bytes = Uint8List.fromList(gzip.encode(utf8.encode(yaml)));
          fileName = '$suggested.stitches';
          mimeType = 'application/octet-stream';
        case ShareFormat.oxs:
          bytes = Uint8List.fromList(utf8.encode(
              FormatService.encodeFile(pattern, CrossStitchFormat.oxs)));
          fileName = '$suggested.oxs';
          mimeType = 'application/xml';
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

  /// Export to a chosen format + location (local file picker or Drive folder picker).
  Future<void> _export(BuildContext context) async {
    final state = ref.read(editorProvider);
    final result = await showShareFormatPicker(context,
        title: 'Export as…',
        hasProgress: state.pattern.progress.completedStitches.isNotEmpty,
        hasPageSettings: state.pattern.pageConfig.enabled);
    if (result == null || !context.mounted) return;

    // Drive-backed file: show Drive folder picker first.
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
        await _exportToDriveFolder(context, state, result, driveResult.$1);
        return;
      }
      if (!saveLocally) return; // cancelled
      // saveLocally == true → fall through to local picker
    }

    await _exportToLocalFile(context, state, result);
  }

  /// Upload an exported file to a Drive folder.
  Future<void> _exportToDriveFolder(
      BuildContext context,
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
            name: fileName,
            bytes: bytes,
            parentFolderId: folder.folderId,
          );
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

  /// Save exported bytes via the native file picker.
  Future<void> _exportToLocalFile(
      BuildContext context, EditorState state, PatternShareResult result) async {
    final suggested = state.pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    // Default directory = folder of the currently open local file.
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
            final path = await FilePicker.saveFile(
              fileName: '$suggested.stitches',
              type: FileType.any,
              bytes: bytes,
            );
            if (path != null) {
              ref.read(editorProvider.notifier).setFilePath(path);
              ref.read(editorProvider.notifier).markSaved();
              if (context.mounted) showSuccess(context, 'Saved');
            }
          } else {
            final path = await FilePicker.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['stitches'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath =
                path.endsWith('.stitches') ? path : '$path.stitches';
            await FileService.saveFile(sharePattern, finalPath,
                compress: state.compressOnSave);
            ref.read(editorProvider.notifier).setFilePath(finalPath);
            ref.read(editorProvider.notifier).markSaved();
            if (context.mounted) {
              showSuccess(context,
                  'Saved as ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.oxs:
          final bytes = Uint8List.fromList(utf8.encode(
              FormatService.encodeFile(state.pattern, CrossStitchFormat.oxs)));
          if (isMobile) {
            await FilePicker.saveFile(
              fileName: '$suggested.oxs',
              type: FileType.any,
              bytes: bytes,
            );
            if (context.mounted) showSuccess(context, 'Exported $suggested.oxs');
          } else {
            final path = await FilePicker.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['oxs'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.oxs') ? path : '$path.oxs';
            await FormatService.exportFile(state.pattern, finalPath, CrossStitchFormat.oxs);
            if (context.mounted) {
              showSuccess(context,
                  'Exported ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.pdf:
          final bytes = await PdfService.buildPdfBytes(state.pattern,
              useDmc: ref.read(settingsProvider).useDmc);
          if (!context.mounted) return;
          if (isMobile) {
            await FilePicker.saveFile(
              fileName: '$suggested.pdf',
              type: FileType.any,
              bytes: bytes,
            );
            if (context.mounted) showSuccess(context, 'Exported $suggested.pdf');
          } else {
            final path = await FilePicker.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['pdf'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.pdf') ? path : '$path.pdf';
            await File(finalPath).writeAsBytes(bytes);
            if (context.mounted) {
              showSuccess(context,
                  'Exported ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
        case ShareFormat.png:
          final bytes = await PngExportService.export(state.pattern);
          if (!context.mounted) return;
          if (isMobile) {
            await FilePicker.saveFile(
              fileName: '$suggested.png',
              type: FileType.any,
              bytes: bytes,
            );
            if (context.mounted) showSuccess(context, 'Exported $suggested.png');
          } else {
            final path = await FilePicker.saveFile(
              fileName: suggested,
              type: FileType.custom,
              allowedExtensions: ['png'],
              initialDirectory: initialDir,
            );
            if (path == null) return;
            final finalPath = path.endsWith('.png') ? path : '$path.png';
            await File(finalPath).writeAsBytes(bytes);
            if (context.mounted) {
              showSuccess(context,
                  'Exported ${finalPath.split(Platform.pathSeparator).last}');
            }
          }
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Export failed: $e');
    }
  }

  /// Convert the open non-native file to .stitches, saved beside the original.
  Future<void> _convertToNative(BuildContext context) async {
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
        showSuccess(context,
            'Converted to ${targetPath.split(Platform.pathSeparator).last}');
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Convert failed: $e');
    }
  }

  /// Builds the canvas area, wiring up the import banner callbacks.
  Widget _buildCanvasArea(BuildContext context, EditorState editorState) {
    if (editorState.isNativeFormat) {
      return const EditorCanvasArea();
    }
    final filePath = editorState.filePath!;
    final lastDot = filePath.lastIndexOf('.');
    final withoutExt = lastDot > 0 ? filePath.substring(0, lastDot) : filePath;
    final nativePath = '$withoutExt.stitches';
    final nativeExists = File(nativePath).existsSync();
    return EditorCanvasArea(
      importFilePath: filePath,
      onConvert: nativeExists ? null : () => _convertToNative(context),
      onOpenNative: nativeExists ? () => _openNativeFile(context, nativePath) : null,
    );
  }

  /// Open the native-format version of the currently open non-native file.
  Future<void> _openNativeFile(BuildContext context, String nativePath) async {
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

  /// Flushes any pending auto-save immediately before navigating away.
  Future<bool> _onWillPop(BuildContext context) async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    final state = ref.read(editorProvider);
    if (state.isDirty && state.isFileOpen) {
      await _save(context, quiet: true);
    }
    PatternCache.clear();
    ref.read(editorProvider.notifier).closeFile();
    ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
    return true;
  }

  String _title(EditorState editorState, WorkspaceState wsState, OpenPdf? openPdf) {
    if (openPdf != null) {
      return openPdf.title;
    }
    if (editorState.filePath != null || editorState.pattern.name != 'Untitled') {
      final name = editorState.pattern.name;
      return name;
    }
    return wsState.workspace?.displayName ?? 'Workspace';
  }

  Future<void> _newFileInWorkspace(
      BuildContext context, StorageLocation? workspace) async {
    final pattern = await showDialog<CrossStitchPattern>(
      context: context,
      builder: (_) => const NewPatternDialog(),
    );
    if (pattern == null || !context.mounted) return;
    final compress = ref.read(settingsProvider).compressNewFiles;

    if (workspace is LocalFolder) {
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final filePath =
          '${workspace.path}${Platform.pathSeparator}$safeName.stitches';
      try {
        await FileService.saveFile(pattern, filePath, compress: compress);
        ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
        ref.read(editorProvider.notifier).loadPattern(pattern, filePath: filePath, compressOnSave: compress);
        refreshFolder(ref, workspace);
      } catch (e) {
        if (context.mounted) showError(context, 'Could not create file: $e');
      }
    } else if (workspace is DriveFolder) {
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final fileName = '$safeName.stitches';
      ref.read(fileLoadingProvider.notifier).set(true);
      try {
        // Write to temp and open immediately — Drive upload happens in background.
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        final tempPath = '${tempDir.path}/$fileName';
        await FileService.saveFile(pattern, tempPath, compress: compress);

        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: tempPath,
          driveParentFolderId: workspace.folderId,
          compressOnSave: compress,
          // driveFileId left null — set after background upload.
        );

        // Show the file in the sidebar tree immediately via a placeholder.
        addPendingDriveFile(
          ref,
          workspace.folderId,
          DrivePatternFile(
            fileId: tempPath, // placeholder — replaced once upload completes
            name: fileName,
            parentFolder: workspace,
            modified: DateTime.now(),
          ),
        );

        unawaited(_uploadNewFileToDrive(workspace, pattern, tempPath, compress: compress));
      } catch (e) {
        if (context.mounted) showError(context, 'Could not create file: $e');
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
    } else {
      // No workspace — fall back to standalone new pattern
      ref.read(editorProvider.notifier).newPattern(pattern);
    }
  }

  Future<void> _uploadNewFileToDrive(
      DriveFolder folder, CrossStitchPattern pattern, String tempPath, {bool compress = true }) async {
    final newFileId = await ref.read(googleDriveProvider.notifier).uploadPattern(
      pattern, null, folder.folderId, compress: compress);
    if (!mounted) return;
    // Remove the optimistic placeholder before refreshing from Drive.
    clearPendingDriveFiles(ref, folder.folderId);
    if (newFileId != null) {
      ref.read(editorProvider.notifier).setDriveFileId(newFileId);
      refreshFolder(ref, folder);
    } else {
      showError(context, 'Could not upload file to Drive.');
    }
  }

  Future<void> _showResizeDialog(
      BuildContext context, EditorState state) async {
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

  Future<void> _scanPage(
      BuildContext context,
      String pdfPath,
      List<int> legendPageNumbers,
      List<int> gridPageNumbers,
      String title) async {
    _scanCancelled = false;
    final allPageNumbers = {
      ...legendPageNumbers,
      ...gridPageNumbers,
    }.toList()..sort();
    final renderMsg = allPageNumbers.length == 1
        ? 'Rendering page…'
        : 'Rendering ${allPageNumbers.length} pages…';
    _showScanOverlay(context, renderMsg);

    try {
      // Rasterise all unique pages in one batch.
      final allPages = await PdfScanner.rasterisePages(pdfPath, allPageNumbers);
      if (_scanCancelled) return;

      // Build page-number → bytes lookup.
      final pageByNumber = <int, Uint8List>{
        for (var i = 0; i < allPageNumbers.length; i++)
          allPageNumbers[i]: allPages[i],
      };

      final legendPages =
          legendPageNumbers.map((n) => pageByNumber[n]!).toList();
      final gridPages =
          gridPageNumbers.map((n) => pageByNumber[n]!).toList();

      final totalKb = allPages.fold(0, (s, p) => s + p.length) ~/ 1024;
      debugPrint('[PdfScanner] ${allPages.length} page(s) rendered: '
          '$totalKb KB total '
          '(legend: ${legendPages.length}, grid: ${gridPages.length})');

      // Auto-detect the grid layout on each page while the overlay is showing.
      _scanStatus.value = 'Detecting grid layout…';
      _scanSubtitle.value = null;
      final detections = await GridDetector.detectPages(gridPages);
      if (_scanCancelled) return;

      for (var i = 0; i < detections.length; i++) {
        final d = detections[i];
        if (d != null) {
          debugPrint('[GridDetector] page $i: '
              'cellW=${d.cellW.toStringAsFixed(1)} '
              'cellH=${d.cellH.toStringAsFixed(1)} '
              'conf=${d.confidence.toStringAsFixed(2)}');
        } else {
          debugPrint('[GridDetector] page $i: no result');
        }
      }

      // Present the grid-crop selection UI, pre-populated from detection.
      final initialCrops = detections
          .map((d) => d == null
              ? null
              : Rect.fromLTRB(
                  d.gridLeft, d.gridTop, d.gridRight, d.gridBottom))
          .toList();

      _removeScanOverlay();
      if (!context.mounted) return;
      final crops = await PatternScanCropScreen.show(
        context,
        pages: gridPages,
        initialCrops: initialCrops,
      );
      if (crops == null || !context.mounted) return;
      debugPrint('[PdfScanner] crop(s): ${crops.map((c) => c.cropRect).join(', ')}');

      // Step 2a — Prompt for pattern dimensions (cols × rows).
      _removeScanOverlay();
      if (!context.mounted) return;
      final size = await _promptPatternSize(context);
      if (size == null || !context.mounted) return;
      final (patternW, patternH) = size;

      // Step 2c — Build GridCellResult for each page directly from pattern dims.
      final pageCount = crops.length;
      final rowsPerPage = patternH ~/ pageCount;
      final extraRows   = patternH - rowsPerPage * pageCount;

      final cellResults = <GridCellResult>[];
      for (var i = 0; i < crops.length; i++) {
        final crop     = crops[i];
        final pageRows = rowsPerPage + (i == pageCount - 1 ? extraRows : 0);
        final cellW    = crop.cropRect.width  / patternW;
        final cellH    = crop.cropRect.height / pageRows;

        // Re-express the detected grid phase relative to this crop.
        // Clamp to 0 when the offset is > half a cell to avoid losing a column/row.
        final det = i < detections.length ? detections[i] : null;
        double phaseX = 0;
        double phaseY = 0;
        if (det != null) {
          final dx = det.gridLeft - crop.cropRect.left;
          final dy = det.gridTop  - crop.cropRect.top;
          phaseX = ((det.phaseX + dx) % cellW + cellW) % cellW;
          phaseY = ((det.phaseY + dy) % cellH + cellH) % cellH;
          if (phaseX > cellW * 0.5) phaseX = 0;
          if (phaseY > cellH * 0.5) phaseY = 0;
        }

        cellResults.add(GridCellResult(
          crop: crop,
          cellW: cellW,
          cellH: cellH,
          cellOffsetX: phaseX,
          cellOffsetY: phaseY,
          columns: ((crop.cropRect.width  - phaseX) / cellW).round().clamp(1, 9999),
          rows:    ((crop.cropRect.height - phaseY) / cellH).round().clamp(1, 9999),
        ));
      }
      debugPrint(
        '[PdfScanner] cell size(s): '
        '${cellResults.map((c) => '${c.columns}×${c.rows}').join(', ')}',
      );

      // Step 3 — Symbol sampling: user taps one cell per symbol type.
      final samples = await PatternScanSymbolScreen.show(
        context,
        cellResults: cellResults,
        legendPages: legendPages,
      );
      if (samples == null || !context.mounted) return;
      debugPrint('[PdfScanner] ${samples.length} symbol type(s) sampled');

      // Step 4 — Per-cell template matching.
      final matchResults = <GridMatchResult>[];
      for (int i = 0; i < cellResults.length; i++) {
        if (_scanCancelled) return;
        if (!context.mounted) return;
        final cellResult = cellResults[i];

        _showScanOverlay(context,
            'Scanning page ${i + 1} of ${cellResults.length}…');
        _scanSubtitle.value =
            '${cellResult.columns}×${cellResult.rows} cells';

        debugPrint('[CellScanner] page $i: '
            'cols=${cellResult.columns} rows=${cellResult.rows} '
            'cellW=${cellResult.cellW.toStringAsFixed(1)} '
            'cellH=${cellResult.cellH.toStringAsFixed(1)} '
            'offsetX=${cellResult.cellOffsetX.toStringAsFixed(1)} '
            'offsetY=${cellResult.cellOffsetY.toStringAsFixed(1)} '
            'samples=${samples.length}');

        final matchResult = await GridSymbolMatcher.matchGrid(
          gridResult: cellResult,
          samples: samples,
        );
        debugPrint(
            '[CellScanner] page $i: ${matchResult.cells.where((c) => !c.isEmpty).length} occupied, '
            '${matchResult.cells.where((c) => c.isEmpty).length} empty');
        matchResults.add(matchResult);
      }
      if (_scanCancelled) return;

      // Step 5 — Review / correct low-confidence cells.
      final totalLowConf =
          matchResults.fold<int>(0, (s, r) => s + r.lowConfidenceCount);
      var reviewedResults = matchResults;
      if (totalLowConf > 0) {
        _removeScanOverlay();
        if (!context.mounted) return;
        final reviewed = await PatternScanReviewScreen.show(
          context,
          matchResults: matchResults,
          cellResults: cellResults,
        );
        if (reviewed == null || !context.mounted) return;
        reviewedResults = reviewed;
      }

      final result = GridMatchResult.combineFromSamples(reviewedResults, samples);
      _removeScanOverlay();
      if (!context.mounted) return;

      if (reviewedResults.length == 1) {
        // ── Single grid: preview then load as a new full pattern ─────────────
        final pattern = await Navigator.of(context).push<CrossStitchPattern>(
          MaterialPageRoute(
            builder: (_) => PatternScanPreviewScreen(
              result: result,
              patternName: title,
            ),
          ),
        );
        if (pattern != null && context.mounted) {
          // Auto-save the new pattern next to the source PDF.
          final savePath =
              '${File(pdfPath).parent.path}${Platform.pathSeparator}$title.stitches';
          final scanCompress = ref.read(settingsProvider).compressNewFiles;
          try {
            await FileService.saveFile(pattern, savePath, compress: scanCompress);
          } catch (_) {
            // Saving failed (e.g. read-only location) — load without a file path.
          }
          if (!context.mounted) return;
          ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: File(savePath).existsSync() ? savePath : null,
            compressOnSave: scanCompress,
          );
          ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
        }
      } else {
        // ── Multiple grids: each page becomes a Snippet ──────────────────────
        // The user arranges them on the canvas via the Snippets panel.
        final notifier = ref.read(editorProvider.notifier);
        for (var i = 0; i < reviewedResults.length; i++) {
          notifier.addSnippet(
            reviewedResults[i].toSnippet('$title — page ${i + 1}'),
          );
        }
        if (context.mounted) {
          showSuccess(
            context,
            '${reviewedResults.length} grids added as snippets — '
            'open the Snippets panel to place them on the canvas.',
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (e, st) {
      if (_scanCancelled) return;
      debugPrint('[PdfScanner] caught: $e\n$st');
      _removeScanOverlay();
      if (!context.mounted) return;
      _showScanError(context, e);
    } finally {
      _removeScanOverlay();
    }
  }

  /// Dialog shown when the AI did not detect pattern dimensions.
  /// Returns (cols, rows) or null if the user cancelled.
  Future<(int, int)?> _promptPatternSize(BuildContext context) async {
    final colsCtrl = TextEditingController();
    final rowsCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();

    final result = await showDialog<(int, int)>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter pattern size'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the pattern size in stitches. '
                'You can find this on the legend page of the PDF.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: colsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Columns',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Enter a number';
                        return null;
                      },
                      autofocus: true,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('×', style: TextStyle(fontSize: 20)),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: rowsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rows',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Enter a number';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop((
                  int.parse(colsCtrl.text),
                  int.parse(rowsCtrl.text),
                ));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return result;
  }

  void _showScanError(BuildContext context, Object e) {
    debugPrint('[PdfScanner] error: $e');
    final msg = e.toString();
    final isRateLimit = msg.contains('Quota exceeded') ||
        msg.contains('quota') ||
        msg.contains('rate') ||
        msg.contains('RESOURCE_EXHAUSTED');

    if (isRateLimit) {
      // Try to extract the retry-after seconds from the message.
      final retryMatch =
          RegExp(r'retry in ([\d.]+)s', caseSensitive: false).firstMatch(msg);
      final retryStr = retryMatch != null
          ? ' Try again in ~${retryMatch.group(1)!.split('.').first}s.'
          : '';

      showWarning(context, 'Rate limit reached.$retryStr',
          duration: const Duration(seconds: 6));
    } else if (msg.contains('API key') || msg.contains('api_key') ||
        msg.contains('API_KEY_INVALID')) {
      showError(context, 'Invalid API key. Check your Gemini key in Settings.',
          duration: const Duration(seconds: 6));
    } else {
      showError(context, 'Scan failed: $msg',
          duration: const Duration(seconds: 6));
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final wsState = ref.watch(workspaceProvider);
    final driveState = ref.watch(googleDriveProvider);
    final isFileLoading = ref.watch(fileLoadingProvider);
    final openPdf = ref.watch(pdfViewerProvider);
    final openImage = ref.watch(imageViewerProvider);

    // ── Auto-save listener ────────────────────────────────────────────────
    ref.listen<EditorState>(editorProvider, (prev, next) {
      // Cancel a pending timer whenever the active file changes — the stale
      // timer was for the previous file and must not fire against the new one.
      if (prev != null && prev.filePath != next.filePath) {
        _autoSaveTimer?.cancel();
        _autoSaveTimer = null;
      }
      if (!next.isDirty || !next.isFileOpen) return;
      _scheduleAutoSave();
    });

    // ── Phone sidebar coordination ────────────────────────────────────────
    // When a file is opened on a phone, close the folder sidebar so the canvas
    // gets the full width.
    final isPhone = _isPhone(context);
    if (isPhone) {
      ref.listen<EditorState>(editorProvider, (prev, next) {
        if (prev != null && !prev.isFileOpen && next.isFileOpen) {
          ref.read(workspaceProvider.notifier).setSidebarVisible(false);
        }
      });
    }

    // ── Keyboard handler ──────────────────────────────────────────────────
    KeyEventResult handleKeys(FocusNode node, KeyEvent event) {
      return handleEditorKeys(
        event,
        editorState,
        ref.read(editorProvider.notifier),
        // No onSave — workspace uses auto-save.
        onShowShortcuts: () => showDialog(
          context: context,
          builder: (_) => const _ShortcutsDialog(),
        ),
        onPdfZoomIn:
            openPdf != null ? () => _pdfPanelKey.currentState?.zoomIn() : null,
        onPdfZoomOut: openPdf != null
            ? () => _pdfPanelKey.currentState?.zoomOut()
            : null,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(context);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drive sync indicator — left of title, all modes ──────────
              if (editorState.driveParentFolderId != null) ...[
                Tooltip(
                  message: (driveState.isSyncing || editorState.driveFileId == null || editorState.isDirty)
                      ? 'Syncing to Google Drive…'
                      : 'Synced to Google Drive',
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: (driveState.isSyncing || editorState.driveFileId == null || editorState.isDirty)
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
              ] else if (editorState.isFileOpen && openPdf == null) ...[
                Tooltip(
                  message: editorState.isDirty ? 'Saving…' : 'Saved',
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: editorState.isDirty
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
                  _title(editorState, wsState, openPdf),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // ── Block mode toggle — in title area, consistent across modes ──
              if (editorState.isFileOpen && openPdf == null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: editorState.stitchMode
                      ? (!editorState.blockMode ? 'B&W mode: on' : 'B&W mode: off')
                      : (!editorState.blockMode ? 'Realistic mode: on' : 'Realistic mode: off'),
                  isSelected: !editorState.blockMode,
                  icon: const Icon(Icons.grid_view_outlined),
                  selectedIcon: const Icon(Icons.grid_view),
                  onPressed: () =>
                      ref.read(editorProvider.notifier).toggleBlockMode(),
                  style: !editorState.blockMode
                      ? IconButton.styleFrom(
                          backgroundColor: editorState.mode == AppMode.stitch
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.primaryContainer,
                          foregroundColor: editorState.mode == AppMode.stitch
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                        )
                      : null,
                ),
              ],
            ],
          ),
          backgroundColor: editorState.mode == AppMode.stitch
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          actions: [
            // PDF viewer actions
            if (openPdf != null) ...[
              IconButton(
                icon: const Icon(Icons.document_scanner_outlined),
                tooltip: 'Scan page as pattern (Beta)',
                onPressed: () async {
                  final picked = await PdfPagePickerDialog.show(
                    context,
                    pdfPath: openPdf.localPath,
                    initialPage: _pdfPanelKey.currentState?.currentPage ?? 1,
                  );
                  if (picked != null && context.mounted) {
                    _scanPage(
                      context,
                      openPdf.localPath,
                      picked.legendPages,
                      picked.gridPages,
                      openPdf.title,
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                tooltip: 'Zoom out',
                onPressed: () => _pdfPanelKey.currentState?.zoomOut(),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                tooltip: 'Zoom in',
                onPressed: () => _pdfPanelKey.currentState?.zoomIn(),
              ),
              const EditorScreenLockButton(),
            ],
            // ── View mode: info + materials + share + export + Edit + Stitch ──
            if (editorState.isFileOpen && editorState.mode == AppMode.view && openPdf == null) ...[
              IconButton(
                tooltip: 'Pattern Info',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showPatternInfo(context, ref, editorState),
              ),
              IconButton(
                tooltip: 'Materials list',
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => showMaterialsList(context, editorState),
              ),
              // Share: iOS, Android, macOS only
              if (!kIsWeb && !Platform.isWindows)
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _share(context),
                ),
              IconButton(
                tooltip: 'Export',
                icon: const Icon(Icons.upload_outlined),
                onPressed: () => _export(context),
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
            // ── Edit mode: ref image + resize + save + Done ──────────────────
            if (editorState.isFileOpen && editorState.mode == AppMode.edit && openPdf == null) ...[
              IconButton(
                tooltip: editorState.referenceImage != null && editorState.referenceVisible
                    ? 'Reference Image (on)'
                    : 'Reference Image',
                isSelected: editorState.referenceImage != null && editorState.referenceVisible,
                icon: const Icon(Icons.image_outlined),
                selectedIcon: const Icon(Icons.image),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ReferenceImageSheet(),
                ),
              ),
              IconButton(
                tooltip: 'Resize Aida',
                icon: const Icon(Icons.aspect_ratio),
                onPressed: () => _showResizeDialog(context, editorState),
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
            if (editorState.isFileOpen && editorState.mode == AppMode.stitch && openPdf == null) ...[
              IconButton(
                tooltip: 'Progress tracking',
                icon: const Icon(Icons.checklist),
                onPressed: () =>
                    showProgressHelpDialog(context, ref, state: editorState),
              ),
              IconButton(
                tooltip: editorState.pattern.pageConfig.enabled
                    ? 'Page mode: on'
                    : 'Page mode: off',
                isSelected: editorState.pattern.pageConfig.enabled,
                icon: const Icon(Icons.auto_stories_outlined),
                selectedIcon: const Icon(Icons.auto_stories),
                onPressed: () => showPageModeDialog(context, ref),
                style: editorState.pattern.pageConfig.enabled
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
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Editor, PDF viewer, image viewer, or empty state
                Expanded(
                  child: openPdf != null
                      ? Focus(
                          autofocus: true,
                          onKeyEvent: handleKeys,
                          child: PdfViewerPanel(key: _pdfPanelKey, path: openPdf.localPath),
                        )
                      : openImage != null
                          ? Focus(
                              autofocus: true,
                              onKeyEvent: handleKeys,
                              child: ImageViewerPanel(path: openImage.localPath),
                            )
                          : editorState.isFileOpen
                              ? Focus(
                                  autofocus: true,
                                  onKeyEvent: handleKeys,
                                  child: _buildCanvasArea(context, editorState),
                                )
                              : _EmptyState(
                                  workspace: wsState.workspace,
                                  onNewFile: () => _newFileInWorkspace(
                                      context, wsState.workspace),
                                ),
                ),
                RightSidebar(
                  sidebarContext: RightSidebarContext.mainEditor,
                  collapsedOverride: isPhone ? _rightSidebarCollapsed : null,
                  onCollapsedChanged:
                      isPhone ? _onRightSidebarCollapsedChanged : null,
                ),
              ],
            ),
            // File sidebar overlay — slides over the canvas so the canvas never moves
            if (wsState.sidebarVisible)
              Positioned(
                left: editorState.mode == AppMode.view
                    ? 0.0
                    : -(wsState.sidebarWidth + 5.0),
                top: 0,
                bottom: 0,
                width: wsState.sidebarWidth + 5,
                child: Row(
                  children: [
                    Expanded(child: const FileSidebar()),
                    _ResizeDivider(
                      onDrag: (delta) => ref
                          .read(workspaceProvider.notifier)
                          .setSidebarWidth(wsState.sidebarWidth + delta),
                    ),
                  ],
                ),
              ),
            // Blocking loading overlay (Drive download in progress)
            if (isFileLoading)
              const Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Color(0x55000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),

            // Open-sidebar tab (visible only when sidebar is hidden)
            if (!wsState.sidebarVisible)
              Positioned(
                left: 0,
                top: 12,
                child: Material(
                  elevation: 2,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: InkWell(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    onTap: () => isPhone
                        ? _openFolderSidebar()
                        : ref
                            .read(workspaceProvider.notifier)
                            .toggleSidebar(),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Tooltip(
                        message: 'Open sidebar',
                        child: Icon(Icons.chevron_right, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

