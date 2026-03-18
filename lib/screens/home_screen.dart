import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pattern.dart';
import '../models/storage_location.dart';
import '../providers/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/recent_items_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import 'editor_screen.dart';
import 'new_pattern_dialog.dart';
import 'settings_screen.dart';
import 'drive_folder_picker_dialog.dart';
import 'workspace_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _newPattern(BuildContext context, WidgetRef ref) async {
    final pattern = await showDialog<CrossStitchPattern>(
      context: context,
      builder: (_) => const NewPatternDialog(),
    );
    if (pattern == null || !context.mounted) return;
    ref.read(editorProvider.notifier).newPattern(pattern);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }

  Future<void> _openFile(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FileService.openFile();
      if (result == null || !context.mounted) return;
      final (pattern, path) = result;
      ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path);
      ref.read(recentItemsProvider.notifier).add(path, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Could not open file: $e');
    }
  }

  Future<void> _openFolder(BuildContext context, WidgetRef ref) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null || !context.mounted) return;
      ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(dir));
      ref.read(recentItemsProvider.notifier).add(dir, isFolder: true);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Could not open folder: $e');
    }
  }

  Future<void> _openRecentFile(
      BuildContext context, WidgetRef ref, RecentItem item) async {
    try {
      final (pattern, path) = await FileService.openFileFromPath(item.path);
      if (!context.mounted) return;
      ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path);
      ref.read(recentItemsProvider.notifier).add(path, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Could not open file: $e');
    }
  }

  Future<void> _openRecentFolder(
      BuildContext context, WidgetRef ref, RecentItem item) async {
    try {
      ref
          .read(workspaceProvider.notifier)
          .openWorkspace(LocalFolder(item.path));
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Could not open folder: $e');
    }
  }

  Future<void> _connectDrive(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(googleDriveProvider.notifier).connect();
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Could not connect to Google Drive: $e');
    }
  }

  Future<void> _browseDrive(BuildContext context, WidgetRef ref) async {
    final folder = await DriveFolderPickerDialog.show(context);
    if (folder == null || !context.mounted) return;
    ref.read(workspaceProvider.notifier).openWorkspace(folder);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentItemsProvider);
    final driveState = ref.watch(googleDriveProvider);

    return Scaffold(
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
          // ── Logo + action buttons ────────────────────────────────────────
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.grid_4x4,
                    size: 48,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'StitchX',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cross-stitch pattern editor',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => _newPattern(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New Pattern'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _openFile(context, ref),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Open File'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _openFolder(context, ref),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open Folder'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),

          // ── Google Drive ─────────────────────────────────────────────────
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'GOOGLE DRIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (driveState.status == DriveStatus.connected) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          driveState.email == 'connected'
                              ? 'Connected'
                              : driveState.email ?? 'Connected',
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _browseDrive(context, ref),
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('Browse Drive'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ] else if (driveState.status == DriveStatus.connecting) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: () => _connectDrive(context, ref),
                    icon: const Icon(Icons.add_link_outlined),
                    label: const Text('Connect Google Drive'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
            ),
          ),

          // ── Recent items ─────────────────────────────────────────────────
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
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 1.1,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Clear Recent'),
                        content:
                            const Text('Remove all items from the recent list?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      for (final item in [...recents]) {
                        ref.read(recentItemsProvider.notifier).remove(item.path);
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...recents.map((item) => _RecentItemTile(
                  item: item,
                  onTap: () => item.isFolder
                      ? _openRecentFolder(context, ref, item)
                      : _openRecentFile(context, ref, item),
                  onRemove: () =>
                      ref.read(recentItemsProvider.notifier).remove(item.path),
                )),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── Recent item tile ─────────────────────────────────────────────────────────

class _RecentItemTile extends StatelessWidget {
  final RecentItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentItemTile({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          item.isFolder
              ? Icons.folder_outlined
              : Icons.insert_drive_file_outlined,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      subtitle: Text(
        item.displayPath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.relativeTime,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

