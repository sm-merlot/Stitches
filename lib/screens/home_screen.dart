import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/pattern.dart';
import '../models/storage_location.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/recent_items_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/drive_pattern_refresh.dart';
import '../services/editor_session_service.dart';
import '../services/file_service.dart';
import '../services/incoming_file_service.dart';
import '../services/pattern_thumbnail.dart';
import '../services/thumbnail_cache.dart';
import '../utils/snackbars.dart';
import '../widgets/dialogs/confirm_dialog.dart';
import 'drive_picker_dialog.dart';
import 'editor_screen.dart';
import 'new_pattern_dialog.dart';
import 'settings_screen.dart';
import 'workspace_screen.dart';

part 'home_screen_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loading = false;
  StreamSubscription<String>? _incomingFileSub;
  StreamSubscription<String>? _incomingFolderSub;
  String? _homeFolderPath;

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _incomingFileSub =
        IncomingFileService.fileStream.listen(_openFromIncomingPath);
    _incomingFolderSub =
        IncomingFileService.folderStream.listen(_openFromIncomingFolder);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Prune recents whose local files have been deleted.
      ref.read(recentItemsProvider.notifier).pruneDeletedFiles();

      // Refresh thumbnails for any Drive folder recents that lack children.
      unawaited(_refreshDriveFolderThumbnails());

      // Load home folder path on mobile.
      if (_isMobile) {
        final path = await homeFolderPath();
        if (mounted) setState(() => _homeFolderPath = path);
      }

      // Handle file opened via OS (Finder / Files app, etc.).
      final path = await IncomingFileService.getInitialPath();
      if (path == null || !mounted) return;
      if (await FileSystemEntity.isDirectory(path)) {
        await _openFromIncomingFolder(path);
      } else {
        await _openFromIncomingPath(path);
      }
    });
  }

  @override
  void dispose() {
    _incomingFileSub?.cancel();
    _incomingFolderSub?.cancel();
    super.dispose();
  }

  // ─── Thumbnail helper ──────────────────────────────────────────────────────

  /// Generates and caches a thumbnail for [pattern] under [key].
  /// No-ops if the cache already has an entry. Errors are silently swallowed.
  static Future<void> _generateAndCacheThumbnail(
      CrossStitchPattern pattern, String key) async {
    try {
      final existing = await ThumbnailCache.load(key);
      if (existing != null) return;
      final bytes = await generatePatternThumbnail(pattern);
      if (bytes != null) await ThumbnailCache.store(key, bytes);
    } catch (_) {}
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

  /// For every Drive folder in recents, ensure its .stitches files have
  /// thumbnail-only recents entries. Skips folders that already have children,
  /// so it's cheap on repeat visits.
  Future<void> _refreshDriveFolderThumbnails() async {
    try {
      final recents = ref.read(recentItemsProvider);
      final driveFolders = recents.where((r) => r.isFolder && r.isDrive);
      if (driveFolders.isEmpty) return;

      final service =
          await ref.read(googleDriveProvider.notifier).getService();
      if (service == null || !mounted) return;

      final notifier = ref.read(recentItemsProvider.notifier);

      for (final folderItem in driveFolders) {
        // Skip if we already have thumbnail children for this folder.
        final alreadyHasChildren = recents
            .any((r) => r.thumbnailOnly && r.parentId == folderItem.id);
        if (alreadyHasChildren) continue;

        final folder = DriveFolder(
            folderId: folderItem.id, name: folderItem.driveName ?? 'Drive');
        try {
          final allFiles =
              await _collectDriveFiles(service, folder);
          if (!mounted) return;

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
                parentId: folderItem.id,
              );
            }
          }
        } catch (_) {
          // Skip this folder on error — try again next launch.
          continue;
        }
      }
    } catch (_) {
      // Silently ignore — thumbnails are non-critical.
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _newPattern() async {
    final pattern = await showDialog<CrossStitchPattern>(
      context: context,
      builder: (_) => const NewPatternDialog(),
    );
    if (pattern == null || !mounted) return;

    if (_isMobile && _homeFolderPath != null) {
      // Mobile: auto-save to home folder with a unique filename.
      final base = pattern.name
          .replaceAll(RegExp(r'[^\w\s\-]'), '_')
          .trim();
      final baseName = base.isNotEmpty ? base : 'Pattern';
      var path = '$_homeFolderPath/$baseName.stitches';
      var counter = 1;
      while (File(path).existsSync()) {
        path = '$_homeFolderPath/${baseName}_$counter.stitches';
        counter++;
      }
      try {
        await FileService.saveFile(pattern, path);
      } catch (_) {
        // If save fails, open the editor unsaved — user can save manually.
      }
      if (!mounted) return;
      ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path);
      final thumbKey = localThumbnailKey(path);
      ref
          .read(recentItemsProvider.notifier)
          .add(path, isFolder: false, thumbnailKey: thumbKey);
      unawaited(_generateAndCacheThumbnail(pattern, thumbKey));
    } else {
      ref.read(editorProvider.notifier).newPattern(pattern);
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }

  Future<void> _openFile() async {
    try {
      final result = await FileService.openFile();
      if (result == null || !mounted) return;
      final (pattern, path, wasCompressed) = result;
      final session = await EditorSessionService.load('local:$path');
      if (!mounted) return;
      ref.read(editorProvider.notifier).loadPattern(pattern,
          filePath: path, compressOnSave: wasCompressed, session: session);
      // Add to recents immediately (no thumbnail yet — avoids race condition).
      final notifier = ref.read(recentItemsProvider.notifier);
      notifier.add(path, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
      // Background: write thumbnail to cache, then refresh the recents entry
      // with the key so _CachedThumbnailImage finds it on first load.
      final thumbKey = localThumbnailKey(path);
      unawaited(() async {
        await _generateAndCacheThumbnail(pattern, thumbKey);
        notifier.add(path, isFolder: false, thumbnailKey: thumbKey);
      }());
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open file: $e');
    }
  }

  /// Opens a file from a known [path] (e.g. from the unified local picker).
  Future<void> _openFilePath(String path) async {
    setState(() => _loading = true);
    try {
      final (pattern, resolvedPath, wasCompressed) =
          await FileService.openFileFromPath(path);
      if (!mounted) return;
      final session = await EditorSessionService.load('local:$resolvedPath');
      if (!mounted) return;
      ref.read(editorProvider.notifier).loadPattern(pattern,
          filePath: resolvedPath,
          compressOnSave: wasCompressed,
          session: session);
      final notifier = ref.read(recentItemsProvider.notifier);
      notifier.add(resolvedPath, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
      final thumbKey = localThumbnailKey(resolvedPath);
      unawaited(() async {
        await _generateAndCacheThumbnail(pattern, thumbKey);
        notifier.add(resolvedPath, isFolder: false, thumbnailKey: thumbKey);
      }());
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens a file or folder using a unified picker.
  /// On macOS, uses the native NSOpenPanel (file + directory in one shot).
  /// On other platforms, falls back to the file picker.
  Future<void> _smartOpenLocal() async {
    try {
      String? path;
      if (!kIsWeb && Platform.isMacOS) {
        path = await const MethodChannel('com.scme0.stitches/file_open')
            .invokeMethod<String>('pickFileOrFolder');
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['stitches'],
        );
        path = result?.files.single.path;
      }
      if (path == null || !mounted) return;
      if (await FileSystemEntity.isDirectory(path)) {
        if (!mounted) return;
        ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(path));
        ref.read(recentItemsProvider.notifier).add(path, isFolder: true);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
        );
      } else {
        await _openFilePath(path);
      }
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open: $e');
    }
  }

  /// Opens a pattern from a path delivered by the OS.
  Future<void> _openFromIncomingPath(String path) async {
    setState(() => _loading = true);
    try {
      final (pattern, resolvedPath, wasCompressed) =
          await FileService.openFileFromPath(path);
      if (!mounted) return;
      final session = await EditorSessionService.load('local:$resolvedPath');
      if (!mounted) return;
      ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: resolvedPath,
            compressOnSave: wasCompressed,
            session: session,
          );
      final notifier = ref.read(recentItemsProvider.notifier);
      notifier.add(resolvedPath, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
      final thumbKey = localThumbnailKey(resolvedPath);
      unawaited(() async {
        await _generateAndCacheThumbnail(pattern, thumbKey);
        notifier.add(resolvedPath, isFolder: false, thumbnailKey: thumbKey);
      }());
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFromIncomingFolder(String path) async {
    ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(path));
    ref.read(recentItemsProvider.notifier).add(path, isFolder: true);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
    );
  }

  Future<void> _openFolder() async {
    try {
      final dir = await FilePicker.getDirectoryPath();
      if (dir == null || !mounted) return;
      ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(dir));
      ref.read(recentItemsProvider.notifier).add(dir, isFolder: true);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open folder: $e');
    }
  }

  Future<void> _openHomeFolder() async {
    final path = _homeFolderPath;
    if (path == null) return;
    ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(path));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
    );
  }

  /// Unified Drive picker — handles both files and folders.
  Future<void> _openDrive() async {
    final result = await DrivePickerDialog.show(context);
    if (result == null || !mounted) return;

    if (result is DrivePickerFolderResult) {
      ref.read(workspaceProvider.notifier).openWorkspace(result.folder);
      final email = ref.read(googleDriveProvider).email;
      ref.read(recentItemsProvider.notifier).add(
            result.folder.folderId,
            isFolder: true,
            isDrive: true,
            driveName: result.folder.name,
            driveEmail: email,
            drivePath: result.drivePath,
          );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
      );
      return;
    }

    // File result
    final sel = result as DrivePickerFileResult;
    try {
      final tempDir = await getTemporaryDirectory();
      await Directory(tempDir.path).create(recursive: true);
      final tempPath = '${tempDir.path}/${sel.fileId}.stitches';
      final cached = File(tempPath);
      final thumbKey = driveThumbnailKey(sel.fileId);

      final email = ref.read(googleDriveProvider).email;
      final notifier = ref.read(recentItemsProvider.notifier);

      void addToRecents({String? thumbnailKey}) {
        notifier.add(
          sel.fileId,
          isFolder: false,
          isDrive: true,
          driveName: sel.fileName,
          driveEmail: email,
          drivePath: sel.drivePath,
          thumbnailKey: thumbnailKey,
        );
      }

      if (await cached.exists()) {
        if (!mounted) return;
        final (pattern, path, wasCompressed) =
            await FileService.openFileFromPath(tempPath);
        if (!mounted) return;
        final session = await EditorSessionService.load('drive:${sel.fileId}');
        if (!mounted) return;
        ref.read(editorProvider.notifier).loadPattern(
              pattern,
              filePath: path,
              driveFileId: sel.fileId,
              driveParentFolderId: sel.parentFolderId,
              compressOnSave: wasCompressed,
              session: session,
            );
        addToRecents();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
        unawaited(() async {
          await _generateAndCacheThumbnail(pattern, thumbKey);
          addToRecents(thumbnailKey: thumbKey);
        }());
        unawaited(refreshDrivePatternInBackground(ref,
            fileId: sel.fileId,
            parentFolderId: sel.parentFolderId,
            tempPath: tempPath));
      } else {
        setState(() => _loading = true);
        try {
          final service =
              await ref.read(googleDriveProvider.notifier).getService();
          if (!mounted) return;
          if (service == null) {
            showError(context, 'Not connected to Google Drive.');
            return;
          }
          final bytes = await service.downloadFile(sel.fileId);
          if (!mounted) return;
          await cached.writeAsBytes(bytes);
          if (!mounted) return;
          final (pattern, path, wasCompressed) =
              await FileService.openFileFromPath(tempPath);
          if (!mounted) return;
          final session =
              await EditorSessionService.load('drive:${sel.fileId}');
          if (!mounted) return;
          ref.read(editorProvider.notifier).loadPattern(
                pattern,
                filePath: path,
                driveFileId: sel.fileId,
                driveParentFolderId: sel.parentFolderId,
                compressOnSave: wasCompressed,
                session: session,
              );
          addToRecents();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EditorScreen()),
          );
          unawaited(() async {
            await _generateAndCacheThumbnail(pattern, thumbKey);
            addToRecents(thumbnailKey: thumbKey);
          }());
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open Drive file: $e');
    }
  }


  Future<void> _openRecentFile(RecentItem item) async {
    try {
      if (item.isDrive) {
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        final tempPath = '${tempDir.path}/${item.id}.stitches';
        final cached = File(tempPath);

        final driveThumbKey =
            item.thumbnailKey ?? driveThumbnailKey(item.id);
        final driveNotifier = ref.read(recentItemsProvider.notifier);

        if (await cached.exists()) {
          if (!mounted) return;
          final (pattern, path, wasCompressed) =
              await FileService.openFileFromPath(tempPath);
          if (!mounted) return;
          final session =
              await EditorSessionService.load('drive:${item.id}');
          if (!mounted) return;
          ref.read(editorProvider.notifier).loadPattern(
                pattern,
                filePath: path,
                driveFileId: item.id,
                driveParentFolderId: null,
                compressOnSave: wasCompressed,
                session: session,
              );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EditorScreen()),
          );
          unawaited(() async {
            await _generateAndCacheThumbnail(pattern, driveThumbKey);
            if (item.thumbnailKey == null) {
              driveNotifier.add(item.id,
                  isFolder: false,
                  isDrive: true,
                  driveName: item.driveName,
                  driveEmail: item.driveEmail,
                  drivePath: item.drivePath,
                  thumbnailKey: driveThumbKey);
            }
          }());
          unawaited(refreshDrivePatternInBackground(ref,
              fileId: item.id,
              parentFolderId: '',
              tempPath: tempPath));
        } else {
          setState(() => _loading = true);
          try {
            final service =
                await ref.read(googleDriveProvider.notifier).getService();
            if (!mounted) return;
            if (service == null) {
              showError(context, 'Not connected to Google Drive.');
              return;
            }
            final bytes = await service.downloadFile(item.id);
            if (!mounted) return;
            await cached.writeAsBytes(bytes);
            if (!mounted) return;
            final (pattern, path, wasCompressed) =
                await FileService.openFileFromPath(tempPath);
            if (!mounted) return;
            final session =
                await EditorSessionService.load('drive:${item.id}');
            if (!mounted) return;
            ref.read(editorProvider.notifier).loadPattern(
                  pattern,
                  filePath: path,
                  driveFileId: item.id,
                  compressOnSave: wasCompressed,
                  session: session,
                );
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EditorScreen()),
            );
            unawaited(() async {
              await _generateAndCacheThumbnail(pattern, driveThumbKey);
              if (item.thumbnailKey == null) {
                driveNotifier.add(item.id,
                    isFolder: false,
                    isDrive: true,
                    driveName: item.driveName,
                    driveEmail: item.driveEmail,
                    drivePath: item.drivePath,
                    thumbnailKey: driveThumbKey);
              }
            }());
          } finally {
            if (mounted) setState(() => _loading = false);
          }
        }
      } else {
        final (pattern, path, wasCompressed) =
            await FileService.openFileFromPath(item.id);
        if (!mounted) return;
        final session =
            await EditorSessionService.load('local:${item.id}');
        if (!mounted) return;
        ref.read(editorProvider.notifier).loadPattern(pattern,
            filePath: path,
            compressOnSave: wasCompressed,
            session: session);
        final thumbKey = item.thumbnailKey ?? localThumbnailKey(path);
        final notifier = ref.read(recentItemsProvider.notifier);
        // Keep existing thumbnailKey if we already have one (avoids flicker).
        notifier.add(path, isFolder: false, thumbnailKey: item.thumbnailKey);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
        unawaited(() async {
          await _generateAndCacheThumbnail(pattern, thumbKey);
          // If we didn't have a key yet, refresh the entry now that it's cached.
          if (item.thumbnailKey == null) {
            notifier.add(path, isFolder: false, thumbnailKey: thumbKey);
          }
        }());
      }
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open file: $e');
    }
  }

  Future<void> _openRecentFolder(RecentItem item) async {
    try {
      final location = item.isDrive
          ? DriveFolder(folderId: item.id, name: item.driveName ?? 'Drive')
          : LocalFolder(item.id);
      ref.read(workspaceProvider.notifier).openWorkspace(location);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open folder: $e');
    }
  }

  Future<void> _connectDrive() async {
    try {
      await ref.read(googleDriveProvider.notifier).connect();
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not connect to Google Drive: $e');
    }
  }

  void _showOpenModal() {
    final driveState = ref.read(googleDriveProvider);
    final content = _OpenModal(
      driveConnected: driveState.status == DriveStatus.connected,
      driveConfigured: driveState.isConfigured,
      driveEmail: driveState.email,
      onOpenLocal: _smartOpenLocal,
      onOpenLocalFile: _openFile,
      onOpenLocalFolder: _openFolder,
      onOpenDrive: _openDrive,
      onConnectDrive: _connectDrive,
    );

    if (_isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => content,
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: SizedBox(width: 400, child: content),
        ),
      );
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentItemsProvider);
    final theme = Theme.of(context);

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            children: [
              const SizedBox(height: 48),

              // ── Centered header ────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.grid_4x4,
                          size: 48,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Stitches',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cross-stitch pattern editor',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // ── Action buttons ─────────────────────────────────────────────
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _newPattern,
                          icon: const Icon(Icons.add),
                          label: const Text('New Pattern'),
                          style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _showOpenModal,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Open\u2026'),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── HOME item (mobile only) ────────────────────────────────────
              if (_isMobile && _homeFolderPath != null)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _HomeItem(
                      homePath: _homeFolderPath!,
                      onTap: _loading ? () {} : _openHomeFolder,
                    ),
                  ),
                ),

              // ── Recent items ───────────────────────────────────────────────
              if (recents.isNotEmpty)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const _SectionLabel(label: 'RECENT'),
                            TextButton(
                              onPressed: () async {
                                final confirmed = await confirmDestructive(
                                  context,
                                  title: 'Clear Recent',
                                  message:
                                      'Remove all items from the recent list?',
                                  confirmLabel: 'Clear',
                                );
                                if (confirmed) {
                                  for (final item in [...recents]) {
                                    ref
                                        .read(recentItemsProvider.notifier)
                                        .remove(item.id);
                                  }
                                }
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              child: Text('Clear',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...recents
                            .where((item) => !item.thumbnailOnly)
                            .map((item) => _RecentItemTile(
                                  item: item,
                                  onTap: _loading
                                      ? null
                                      : () => item.isFolder
                                          ? _openRecentFolder(item)
                                          : _openRecentFile(item),
                                  onRemove: () => ref
                                      .read(recentItemsProvider.notifier)
                                      .remove(item.id),
                                )),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),

        // Blocking overlay while a Drive file is downloading.
        if (_loading)
          const Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
      ],
    );
  }
}
