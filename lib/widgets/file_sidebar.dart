import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pattern.dart';
import '../models/storage_location.dart';
import '../providers/editor_provider.dart';
import '../providers/file_loading_provider.dart';
import '../providers/folder_contents_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/pdf_viewer_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import '../services/format_service.dart';
import '../providers/image_viewer_provider.dart';
import '../screens/new_pattern_dialog.dart';
import '../screens/sprite_sheet_screen.dart';
import 'snippets_panel.dart';
import 'folder_tree_node.dart';

class FileSidebar extends ConsumerStatefulWidget {
  const FileSidebar({super.key});

  @override
  ConsumerState<FileSidebar> createState() => _FileSidebarState();
}

class _FileSidebarState extends ConsumerState<FileSidebar> {
  String _filter = '';
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  // ─── New file ─────────────────────────────────────────────────────────────

  Future<void> _createNewFile(BuildContext context, StorageLocation folder) async {
    final pattern = await showDialog<CrossStitchPattern>(
      context: context,
      builder: (_) => const NewPatternDialog(),
    );
    if (pattern == null || !context.mounted) return;

    if (folder is LocalFolder) {
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final filePath = '${folder.path}${Platform.pathSeparator}$safeName.stitchx';
      try {
        await FileService.saveFile(pattern, filePath);
        ref.read(editorProvider.notifier).loadPattern(pattern, filePath: filePath);
        refreshFolder(ref, folder);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not create file: $e');
      }
    } else if (folder is DriveFolder) {
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final fileName = '$safeName.stitchx';
      ref.read(fileLoadingProvider.notifier).set(true);
      try {
        // Write to temp dir and open immediately — no waiting for Drive.
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        final tempPath = '${tempDir.path}/$fileName';
        await FileService.saveFile(pattern, tempPath);

        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: tempPath,
          driveParentFolderId: folder.folderId,
          // driveFileId left null — set after background upload completes.
        );

        // Show the file in the tree immediately using a placeholder whose
        // fileId equals the local temp path (for selection matching).
        addPendingDriveFile(
          ref,
          folder.folderId,
          DrivePatternFile(
            fileId: tempPath, // placeholder — replaced once upload completes
            name: fileName,
            parentFolder: folder,
            modified: DateTime.now(),
          ),
        );

        // Upload to Drive in the background.
        unawaited(_uploadNewFileToDrive(folder, pattern, tempPath));
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not create file: $e');
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
    }
  }

  // ─── File context menu ────────────────────────────────────────────────────

  Future<void> _showFileContextMenu(
      BuildContext context, PatternFile file, Offset position) async {
    final workspaceState = ref.read(workspaceProvider);
    final workspace = workspaceState.workspace;

    final isPdf = file is LocalPdfFile || file is DrivePdfFile;
    final isImage = file is LocalImageFile || file is DriveImageFile;
    final isImportable =
        file is LocalImportableFile || file is DriveImportableFile;
    final isFileOpen = ref.read(editorProvider).filePath != null;

    if (isImage) {
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
            position.dx, position.dy, position.dx + 1, position.dy + 1),
        items: [
          const PopupMenuItem(value: 'view', child: Text('View')),
          if (isFileOpen)
            const PopupMenuItem(
              value: 'sprite_sheet',
              child: Text('Import as Sprite Sheet'),
            ),
        ],
      );

      if (!context.mounted) return;

      switch (selected) {
        case 'view':
          await _openFile(context, file);
        case 'sprite_sheet':
          await _openAsSpriteSheet(context, file);
      }
      return;
    }

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        if (!isPdf && !isImportable) ...[
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'copy', child: Text('Copy')),
          const PopupMenuItem(value: 'cut', child: Text('Cut')),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (!context.mounted) return;

    switch (selected) {
      case 'open':
        await _openFile(context, file);
      case 'rename':
        await _renameFile(context, file, workspace);
      case 'copy':
        ref.read(workspaceProvider.notifier).copyFile(file);
      case 'cut':
        ref.read(workspaceProvider.notifier).cutFile(file);
      case 'delete':
        await _deleteFile(context, file, workspace);
    }
  }

  /// Prepares for showing a read-only viewer (PDF or image).
  /// Closes the pattern editor and clears both viewer providers so only the
  /// newly opened file is active.
  void _switchToViewer() {
    ref.read(editorProvider.notifier).closeFile();
    ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
  }

  /// Prepares for opening a pattern file.
  /// Clears both viewer providers without touching the editor state.
  void _switchToEditor() {
    ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
  }

  Future<void> _openDriveImage(
      BuildContext context, DriveImageFile file) async {
    final localPath = await _downloadDriveImage(context, file);
    if (localPath == null || !context.mounted) return;
    _switchToViewer();
    ref.read(imageViewerProvider.notifier).set(OpenImage(
      localPath: localPath,
      driveFileId: file.fileId,
      displayName: file.displayName,
    ));
  }

  Future<String?> _downloadDriveImage(
      BuildContext context, DriveImageFile file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${file.fileId}_${file.name}';
      final cached = File(tempPath);
      if (await cached.exists()) return tempPath;

      ref.read(fileLoadingProvider.notifier).set(true);
      try {
        final service =
            await ref.read(googleDriveProvider.notifier).getService();
        if (!context.mounted) return null;
        if (service == null) {
          _showError(context, 'Not connected to Google Drive.');
          return null;
        }
        final bytes = await service.downloadFile(file.fileId);
        await cached.writeAsBytes(bytes);
        return tempPath;
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not open image: $e');
      return null;
    }
  }

  Future<void> _openAsSpriteSheet(
      BuildContext context, PatternFile file) async {
    String? imagePath;
    if (file is LocalImageFile) {
      imagePath = file.path;
    } else if (file is DriveImageFile) {
      imagePath = await _downloadDriveImage(context, file);
      if (imagePath == null || !context.mounted) return;
    } else {
      return;
    }

    final addedAny = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SpriteSheetScreen(imagePath: imagePath),
        fullscreenDialog: true,
      ),
    );
    if ((addedAny ?? false) && context.mounted) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const SnippetsPanel(),
      );
    }
  }

  Future<void> _openFile(BuildContext context, PatternFile file) async {
    if (file is LocalImageFile) {
      _switchToViewer();
      ref.read(imageViewerProvider.notifier).set(OpenImage(localPath: file.path));
      return;
    }

    if (file is DriveImageFile) {
      await _openDriveImage(context, file);
      return;
    }

    if (file is LocalPdfFile) {
      _switchToViewer();
      ref.read(pdfViewerProvider.notifier).set(OpenPdf(localPath: file.path));
      return;
    }

    if (file is DrivePdfFile) {
      try {
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        final tempPath = '${tempDir.path}/${file.fileId}.pdf';
        final cached = File(tempPath);

        _switchToViewer();

        if (await cached.exists()) {
          ref.read(pdfViewerProvider.notifier).set(
              OpenPdf(localPath: tempPath, driveFileId: file.fileId, displayName: file.displayName));
        } else {
          ref.read(fileLoadingProvider.notifier).set(true);
          try {
            final service = await ref.read(googleDriveProvider.notifier).getService();
            if (!context.mounted) return;
            if (service == null) {
              _showError(context, 'Not connected to Google Drive.');
              return;
            }
            final bytes = await service.downloadFile(file.fileId);
            if (!context.mounted) return;
            await cached.writeAsBytes(bytes);
            if (!context.mounted) return;
            ref.read(pdfViewerProvider.notifier).set(
                OpenPdf(localPath: tempPath, driveFileId: file.fileId, displayName: file.displayName));
          } finally {
            if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
          }
        }
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not open PDF: $e');
      }
      return;
    }

    if (file is LocalImportableFile) {
      try {
        ref.read(fileLoadingProvider.notifier).set(true);
        final pattern = await FormatService.importFile(file.path);
        if (!context.mounted) return;
        _switchToEditor();
        ref.read(editorProvider.notifier).loadPattern(pattern,
            filePath: file.path);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not import file: $e');
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
      return;
    }

    if (file is DriveImportableFile) {
      try {
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        final tempPath = '${tempDir.path}/${file.fileId}${file.extension}';
        final cached = File(tempPath);

        ref.read(fileLoadingProvider.notifier).set(true);
        try {
          if (!await cached.exists()) {
            final service =
                await ref.read(googleDriveProvider.notifier).getService();
            if (!context.mounted) return;
            if (service == null) {
              _showError(context, 'Not connected to Google Drive.');
              return;
            }
            final bytes = await service.downloadFile(file.fileId);
            await cached.writeAsBytes(bytes);
          }
          if (!context.mounted) return;
          final pattern = await FormatService.importFile(tempPath);
          if (!context.mounted) return;
          _switchToEditor();
          ref.read(editorProvider.notifier).loadPattern(pattern,
              filePath: tempPath);
        } finally {
          if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
        }
      } catch (e) {
        if (context.mounted) {
          _showError(context, 'Could not import Drive file: $e');
        }
      }
      return;
    }

    if (file is LocalPatternFile) {
      try {
        final (pattern, path) = await FileService.openFileFromPath(file.path);
        if (!context.mounted) return;
        _switchToEditor();
        ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not open file: $e');
      }
    } else if (file is DrivePatternFile) {
      try {
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        // Use fileId as cache key so the same Drive file always maps to the
        // same local path regardless of renames.
        final tempPath = '${tempDir.path}/${file.fileId}.stitchx';
        final cached = File(tempPath);

        if (await cached.exists()) {
          // Load from cache immediately, then refresh from Drive in background.
          final (pattern, path) = await FileService.openFileFromPath(tempPath);
          if (!context.mounted) return;
          _switchToEditor();
          ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: path,
            driveFileId: file.fileId,
            driveParentFolderId: file.parentFolder.folderId,
          );
          unawaited(_refreshFromDrive(file, tempPath));
        } else {
          // No cache — download first, showing a blocking overlay.
          ref.read(fileLoadingProvider.notifier).set(true);
          try {
            final driveNotifier = ref.read(googleDriveProvider.notifier);
            final service = await driveNotifier.getService();
            if (!context.mounted) return;
            if (service == null) {
              _showError(context, 'Not connected to Google Drive.');
              return;
            }
            final bytes = await service.downloadFile(file.fileId);
            if (!context.mounted) return;
            await cached.writeAsBytes(bytes);
            if (!context.mounted) return;
            final (pattern, path) = await FileService.openFileFromPath(tempPath);
            if (!context.mounted) return;
            _switchToEditor();
            ref.read(editorProvider.notifier).loadPattern(
              pattern,
              filePath: path,
              driveFileId: file.fileId,
              driveParentFolderId: file.parentFolder.folderId,
            );
          } finally {
            if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
          }
        }
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not open Drive file: $e');
      }
    }
  }

  /// Uploads a newly created pattern to Drive and stores the resulting file ID.
  Future<void> _uploadNewFileToDrive(
      DriveFolder folder, CrossStitchPattern pattern, String tempPath) async {
    final newFileId = await ref.read(googleDriveProvider.notifier).uploadPattern(
      pattern, null, folder.folderId);
    if (!mounted) return;
    // Remove the optimistic placeholder before refreshing from Drive.
    clearPendingDriveFiles(ref, folder.folderId);
    if (newFileId != null) {
      // setDriveFileId marks dirty → auto-save will upload any edits made
      // during the background upload.
      ref.read(editorProvider.notifier).setDriveFileId(newFileId);
      refreshFolder(ref, folder);
    } else {
      _showError(context, 'Could not upload file to Drive.');
    }
  }

  /// Downloads the Drive version and silently refreshes the cached file,
  /// but only if the user has not edited the pattern since it was opened.
  Future<void> _refreshFromDrive(DrivePatternFile file, String tempPath) async {
    try {
      final service = await ref.read(googleDriveProvider.notifier).getService();
      if (!mounted || service == null) return;
      final bytes = await service.downloadFile(file.fileId);
      if (!mounted) return;
      // Don't clobber any edits the user has made since opening.
      final state = ref.read(editorProvider);
      if (state.driveFileId != file.fileId || state.isDirty) return;
      await File(tempPath).writeAsBytes(bytes);
      if (!mounted) return;
      final (pattern, path) = await FileService.openFileFromPath(tempPath);
      if (!mounted) return;
      // Re-check: still the same file and still unedited?
      final current = ref.read(editorProvider);
      if (current.driveFileId == file.fileId && !current.isDirty) {
        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: path,
          driveFileId: file.fileId,
          driveParentFolderId: file.parentFolder.folderId,
        );
      }
    } catch (_) {
      // Silently ignore — user already has a usable cached version.
    }
  }

  Future<void> _renameFile(
      BuildContext context, PatternFile file, StorageLocation? workspace) async {
    final controller = TextEditingController(text: file.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (newName == null || newName.isEmpty || !context.mounted) return;

    if (file is LocalPatternFile) {
      try {
        final dir = file.path.substring(0, file.path.lastIndexOf(Platform.pathSeparator));
        final newPath = '$dir${Platform.pathSeparator}$newName.stitchx';
        await File(file.path).rename(newPath);

        // If this file is currently open, update the editor file path
        final editorState = ref.read(editorProvider);
        if (editorState.filePath == file.path) {
          ref.read(editorProvider.notifier).setFilePath(newPath);
        }

        if (workspace != null) refreshFolder(ref, workspace);
        refreshFolder(ref, file.parent);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not rename: $e');
      }
    } else if (file is DrivePatternFile) {
      try {
        final driveNotifier = ref.read(googleDriveProvider.notifier);
        final service = await driveNotifier.getService();
        if (!context.mounted) return;
        if (service == null) {
          _showError(context, 'Not connected to Google Drive.');
          return;
        }
        await service.renameItem(file.fileId, '$newName.stitchx');
        refreshFolder(ref, file.parent);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not rename Drive file: $e');
      }
    }
  }

  Future<void> _deleteFile(
      BuildContext context, PatternFile file, StorageLocation? workspace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete "${file.displayName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    if (file is LocalPdfFile) {
      try {
        await File(file.path).delete();
        if (ref.read(pdfViewerProvider)?.localPath == file.path) {
          ref.read(pdfViewerProvider.notifier).set(null);
        }
        if (workspace != null) refreshFolder(ref, workspace);
        refreshFolder(ref, file.parent);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not delete: $e');
      }
      return;
    }

    if (file is DrivePdfFile) {
      ref.read(fileLoadingProvider.notifier).set(true);
      try {
        final service = await ref.read(googleDriveProvider.notifier).getService();
        if (!context.mounted) return;
        if (service == null) {
          _showError(context, 'Not connected to Google Drive.');
          return;
        }
        await service.deleteFile(file.fileId);
        if (ref.read(pdfViewerProvider)?.driveFileId == file.fileId) {
          ref.read(pdfViewerProvider.notifier).set(null);
        }
        if (workspace != null) refreshFolder(ref, workspace);
        refreshFolder(ref, file.parent);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not delete PDF: $e');
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
      return;
    }

    if (file is LocalPatternFile) {
      try {
        await File(file.path).delete();
        // If this was the open file, close it
        if (ref.read(editorProvider).filePath == file.path) {
          ref.read(editorProvider.notifier).closeFile();
        }
        if (workspace != null) refreshFolder(ref, workspace);
        refreshFolder(ref, file.parent);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not delete: $e');
      }
    } else if (file is DrivePatternFile) {
      ref.read(fileLoadingProvider.notifier).set(true);
      try {
        final driveNotifier = ref.read(googleDriveProvider.notifier);
        final service = await driveNotifier.getService();
        if (!context.mounted) return;
        if (service == null) {
          _showError(context, 'Not connected to Google Drive.');
          return;
        }
        await service.deleteFile(file.fileId);
        // If this was the open Drive file, close it
        if (ref.read(editorProvider).driveFileId == file.fileId) {
          ref.read(editorProvider.notifier).closeFile();
        }
        if (workspace != null) refreshFolder(ref, workspace);
        refreshFolder(ref, file.parent);
      } catch (e) {
        if (context.mounted) _showError(context, 'Could not delete Drive file: $e');
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
    }
  }

  // ─── Folder context menu ──────────────────────────────────────────────────

  Future<void> _showFolderContextMenu(
      BuildContext context, StorageLocation folder, Offset position) async {
    final workspaceState = ref.read(workspaceProvider);
    final clipboard = workspaceState.clipboard;

    final canPaste =
        clipboard != null && clipboard.file is LocalPatternFile;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'new_here', child: Text('New File Here')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (canPaste)
          const PopupMenuItem(value: 'paste', child: Text('Paste')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (!context.mounted) return;

    switch (selected) {
      case 'new_here':
        await _createNewFile(context, folder);
      case 'rename':
        await _renameFolder(context, folder);
      case 'paste':
        await _pasteToFolder(context, folder);
      case 'delete':
        await _deleteFolder(context, folder);
    }
  }

  Future<void> _renameFolder(BuildContext context, StorageLocation folder) async {
    if (folder is! LocalFolder) return;

    final controller = TextEditingController(text: folder.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (newName == null || newName.isEmpty || !context.mounted) return;

    try {
      final parent = folder.path.substring(
          0, folder.path.lastIndexOf(Platform.pathSeparator));
      final newPath = '$parent${Platform.pathSeparator}$newName';
      await Directory(folder.path).rename(newPath);

      // If this folder is the workspace, update it
      final wsState = ref.read(workspaceProvider);
      if (wsState.workspace == folder) {
        ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(newPath));
      }

      final parentLoc = LocalFolder(parent);
      refreshFolder(ref, parentLoc);
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not rename: $e');
    }
  }

  Future<void> _pasteToFolder(
      BuildContext context, StorageLocation folder) async {
    if (folder is! LocalFolder) return;

    final workspaceState = ref.read(workspaceProvider);
    final clipboard = workspaceState.clipboard;
    if (clipboard == null || clipboard.file is! LocalPatternFile) return;

    final sourceFile = clipboard.file as LocalPatternFile;
    final destPath =
        '${folder.path}${Platform.pathSeparator}${sourceFile.path.split(Platform.pathSeparator).last}';

    try {
      if (clipboard.op == ClipboardOp.cut) {
        await File(sourceFile.path).rename(destPath);
        ref.read(workspaceProvider.notifier).clearClipboard();
        refreshFolder(ref, sourceFile.parent);
      } else {
        await File(sourceFile.path).copy(destPath);
      }
      refreshFolder(ref, folder);
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not paste: $e');
    }
  }

  Future<void> _deleteFolder(
      BuildContext context, StorageLocation folder) async {
    if (folder is! LocalFolder) return;

    final dir = Directory(folder.path);
    bool isEmpty = true;
    await for (final _ in dir.list()) {
      isEmpty = false;
      break;
    }

    if (!isEmpty) {
      if (context.mounted) {
        _showError(context, 'Cannot delete a non-empty folder.');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Delete "${folder.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await dir.delete();
      final parent = folder.path.substring(
          0, folder.path.lastIndexOf(Platform.pathSeparator));
      refreshFolder(ref, LocalFolder(parent));
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not delete folder: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(workspaceProvider);
    final editorState = ref.watch(editorProvider);
    final openImage = ref.watch(imageViewerProvider);
    final workspace = workspaceState.workspace;
    final theme = Theme.of(context);

    if (workspace == null) {
      return const SizedBox.expand();
    }

    final clipboard = workspaceState.clipboard;

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    workspace.displayName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 14,
                    color: workspaceState.showPdfs
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: workspaceState.showPdfs ? 'Hide PDFs' : 'Show PDFs',
                  onPressed: () {
                    if (workspaceState.showPdfs) _switchToViewer();
                    ref.read(workspaceProvider.notifier).setShowPdfs(!workspaceState.showPdfs);
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.image_outlined,
                    size: 14,
                    color: workspaceState.showImages
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: workspaceState.showImages ? 'Hide images' : 'Show images',
                  onPressed: () {
                    if (workspaceState.showImages) _switchToViewer();
                    ref.read(workspaceProvider.notifier).setShowImages(!workspaceState.showImages);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'New file',
                  onPressed: () => _createNewFile(context, workspace),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close sidebar',
                  onPressed: () =>
                      ref.read(workspaceProvider.notifier).toggleSidebar(),
                ),
              ],
            ),
          ),

          // ── Filter field ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: 'Filter...',
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _filterController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
              ),
              style: theme.textTheme.bodySmall,
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),

          const Divider(height: 1),

          // ── Clipboard banner ─────────────────────────────────────────────
          if (clipboard != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: theme.colorScheme.secondaryContainer,
              child: Row(
                children: [
                  Icon(
                    clipboard.op == ClipboardOp.cut
                        ? Icons.content_cut
                        : Icons.content_copy,
                    size: 12,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${clipboard.op == ClipboardOp.cut ? 'Cut' : 'Copied'}: ${clipboard.file.displayName}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        ref.read(workspaceProvider.notifier).clearClipboard(),
                    child: const Icon(Icons.close, size: 12),
                  ),
                ],
              ),
            ),

          // ── Tree ─────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FolderTreeNode(
                  folder: workspace,
                  selectedFilePath: editorState.filePath,
                  selectedDriveFileId: editorState.driveFileId,
                  selectedPdfPath: ref.watch(pdfViewerProvider)?.localPath,
                  selectedDrivePdfId: ref.watch(pdfViewerProvider)?.driveFileId,
                  selectedImagePath: openImage?.localPath,
                  selectedDriveImageId: openImage?.driveFileId,
                  showPdfs: workspaceState.showPdfs,
                  showImages: workspaceState.showImages,
                  filter: _filter,
                  onFileTap: (file) => _openFile(context, file),
                  onFolderContextMenu: (folder, pos) =>
                      _showFolderContextMenu(context, folder, pos),
                  onFileContextMenu: (file, pos) =>
                      _showFileContextMenu(context, file, pos),
                  depth: 0,
                  startExpanded: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
