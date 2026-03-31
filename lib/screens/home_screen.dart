import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pattern.dart';
import '../models/storage_location.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/recent_items_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import '../utils/snackbars.dart';
import 'drive_file_picker_dialog.dart';
import 'drive_folder_picker_dialog.dart';
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

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _newPattern() async {
    final pattern = await showDialog<CrossStitchPattern>(
      context: context,
      builder: (_) => const NewPatternDialog(),
    );
    if (pattern == null || !mounted) return;
    ref.read(editorProvider.notifier).newPattern(pattern);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }

  Future<void> _openFile() async {
    try {
      final result = await FileService.openFile();
      if (result == null || !mounted) return;
      final (pattern, path, wasCompressed) = result;
      ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path, compressOnSave: wasCompressed);
      ref.read(recentItemsProvider.notifier).add(path, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open file: $e');
    }
  }

  Future<void> _openFolder() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
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

  Future<void> _openDriveFile() async {
    final selection = await DriveFilePickerDialog.show(context);
    if (selection == null || !mounted) return;
    try {
      final tempDir = await getTemporaryDirectory();
      await Directory(tempDir.path).create(recursive: true);
      final tempPath = '${tempDir.path}/${selection.fileId}.stitchx';
      final cached = File(tempPath);

      Future<void> addToRecents() {
        final email = ref.read(googleDriveProvider).email;
        return ref.read(recentItemsProvider.notifier).add(
              selection.fileId,
              isFolder: false,
              isDrive: true,
              driveName: selection.fileName,
              driveEmail: email,
              drivePath: selection.drivePath,
            );
      }

      if (await cached.exists()) {
        // Load from cache immediately, navigate, then refresh in background.
        final (pattern, path, wasCompressed) = await FileService.openFileFromPath(tempPath);
        if (!mounted) return;
        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: path,
          driveFileId: selection.fileId,
          driveParentFolderId: selection.parentFolderId,
          compressOnSave: wasCompressed,
        );
        unawaited(addToRecents());
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
        unawaited(_refreshDriveFileInBackground(
            ref, selection.fileId, selection.parentFolderId, tempPath));
      } else {
        // No cache — must download first; show blocking overlay.
        setState(() => _loading = true);
        try {
          final service =
              await ref.read(googleDriveProvider.notifier).getService();
          if (!mounted) return;
          if (service == null) {
            showError(context, 'Not connected to Google Drive.');
            return;
          }
          final bytes = await service.downloadFile(selection.fileId);
          if (!mounted) return;
          await cached.writeAsBytes(bytes);
          if (!mounted) return;
          final (pattern, path, wasCompressed) =
              await FileService.openFileFromPath(tempPath);
          if (!mounted) return;
          ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: path,
            driveFileId: selection.fileId,
            driveParentFolderId: selection.parentFolderId,
            compressOnSave: wasCompressed,
          );
          unawaited(addToRecents());
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EditorScreen()),
          );
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not open Drive file: $e');
    }
  }

  /// Silently downloads the Drive version and reloads the editor if the user
  /// hasn't made any edits since the file was opened.
  static Future<void> _refreshDriveFileInBackground(
    WidgetRef ref,
    String fileId,
    String parentFolderId,
    String tempPath,
  ) async {
    try {
      final service =
          await ref.read(googleDriveProvider.notifier).getService();
      if (service == null) return;
      final bytes = await service.downloadFile(fileId);
      final state = ref.read(editorProvider);
      if (state.driveFileId != fileId || state.isDirty) return;
      await File(tempPath).writeAsBytes(bytes);
      final (pattern, path, wasCompressed) = await FileService.openFileFromPath(tempPath);
      final current = ref.read(editorProvider);
      if (current.driveFileId == fileId && !current.isDirty) {
        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: path,
          driveFileId: fileId,
          driveParentFolderId: parentFolderId,
          compressOnSave: wasCompressed,
        );
      }
    } catch (_) {
      // Silently ignore — user has the cached version.
    }
  }

  Future<void> _openDriveFolder() async {
    final result = await DriveFolderPickerDialog.show(context);
    if (result == null || !mounted) return;
    final (folder, drivePath) = result;
    ref.read(workspaceProvider.notifier).openWorkspace(folder);
    final email = ref.read(googleDriveProvider).email;
    ref.read(recentItemsProvider.notifier).add(
          folder.folderId,
          isFolder: true,
          isDrive: true,
          driveName: folder.name,
          driveEmail: email,
          drivePath: drivePath,
        );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
    );
  }

  Future<void> _openRecentFile(RecentItem item) async {
    try {
      if (item.isDrive) {
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        // Use fileId as cache key for stable lookups.
        final tempPath = '${tempDir.path}/${item.id}.stitchx';
        final cached = File(tempPath);

        if (await cached.exists()) {
          if (!mounted) return;
          final (pattern, path, wasCompressed) =
              await FileService.openFileFromPath(tempPath);
          if (!mounted) return;
          ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: path,
            driveFileId: item.id,
            driveParentFolderId: null,
            compressOnSave: wasCompressed,
          );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EditorScreen()),
          );
          unawaited(_refreshDriveFileInBackground(
              ref, item.id, '', tempPath));
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
            ref.read(editorProvider.notifier).loadPattern(
              pattern,
              filePath: path,
              driveFileId: item.id,
              compressOnSave: wasCompressed,
            );
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EditorScreen()),
            );
          } finally {
            if (mounted) setState(() => _loading = false);
          }
        }
      } else {
        final (pattern, path, wasCompressed) = await FileService.openFileFromPath(item.id);
        if (!mounted) return;
        ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path, compressOnSave: wasCompressed);
        ref.read(recentItemsProvider.notifier).add(path, isFolder: false);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
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


  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentItemsProvider);
    final driveState = ref.watch(googleDriveProvider);
    final driveConnected = driveState.status == DriveStatus.connected;
    final driveConfigured = driveState.isConfigured;
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
              // ── Logo ──────────────────────────────────────────────────────
              const SizedBox(height: 48),
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

              // ── Action buttons ────────────────────────────────────────────
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _newPattern,
                      icon: const Icon(Icons.add),
                      label: const Text('New Pattern'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _SectionLabel(label: 'LOCAL'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _OpenButton(
                            icon: Icons.insert_drive_file_outlined,
                            label: 'Open File',
                            onTap: _loading ? null : _openFile,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OpenButton(
                            icon: Icons.folder_open_outlined,
                            label: 'Open Folder',
                            onTap: _loading ? null : _openFolder,
                          ),
                        ),
                      ],
                    ),

                    if (driveConfigured) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _SectionLabel(
                            label: 'GOOGLE DRIVE',
                            trailing: driveConnected
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 12,
                                          color: theme.colorScheme.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        driveState.email ?? 'Connected',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.primary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (driveState.status == DriveStatus.connecting)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (driveConnected)
                        Row(
                          children: [
                            Expanded(
                              child: _OpenButton(
                                icon: Icons.insert_drive_file_outlined,
                                label: 'Drive File',
                                cloudBadge: true,
                                onTap: _loading ? null : _openDriveFile,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _OpenButton(
                                icon: Icons.folder_open_outlined,
                                label: 'Drive Folder',
                                cloudBadge: true,
                                onTap: _loading ? null : _openDriveFolder,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _connectDrive,
                          icon: const Icon(Icons.add_link_outlined),
                          label: const Text('Connect Google Drive'),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        if (driveState.error != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            driveState.error!,
                            style: TextStyle(
                                fontSize: 12, color: Colors.red.shade600),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),

              // ── Recent items ──────────────────────────────────────────────
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                        letterSpacing: 1.1,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Clear Recent'),
                            content: const Text(
                                'Remove all items from the recent list?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Clear')),
                            ],
                          ),
                        );
                        if (confirmed == true) {
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
                              fontSize: 12, color: Colors.grey.shade500)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _RecentSection(
                  label: 'Folders',
                  icon: Icons.folder_outlined,
                  items: recents.where((r) => r.isFolder).toList(),
                  onTap: _loading ? null : (item) => _openRecentFolder(item),
                  onRemove: (item) =>
                      ref.read(recentItemsProvider.notifier).remove(item.id),
                ),
                _RecentSection(
                  label: 'Files',
                  icon: Icons.insert_drive_file_outlined,
                  items: recents.where((r) => !r.isFolder).toList(),
                  onTap: _loading ? null : (item) => _openRecentFile(item),
                  onRemove: (item) =>
                      ref.read(recentItemsProvider.notifier).remove(item.id),
                ),
              ],

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
