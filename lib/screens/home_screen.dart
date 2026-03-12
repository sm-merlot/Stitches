import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pattern.dart';
import '../providers/editor_provider.dart';
import '../providers/recent_items_provider.dart';
import '../services/file_service.dart';
import 'editor_screen.dart';
import 'new_pattern_dialog.dart';
import 'settings_screen.dart';

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
      final files = await FileService.openFolder();
      if (files == null || !context.mounted) return;
      if (files.isEmpty) {
        _showError(context, 'No .stitchx files found in that folder.');
        return;
      }
      // Record the folder path (parent of first file)
      final folderPath = files.first
          .split('/')
          .sublist(0, files.first.split('/').length - 1)
          .join('/');
      ref
          .read(recentItemsProvider.notifier)
          .add(folderPath, isFolder: true);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FolderBrowserScreen(filePaths: files),
        ),
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
      final files = await FileService.openFolderFromPath(item.path);
      if (!context.mounted) return;
      if (files.isEmpty) {
        _showError(context, 'No .stitchx files found in that folder.');
        return;
      }
      ref
          .read(recentItemsProvider.notifier)
          .add(item.path, isFolder: true);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FolderBrowserScreen(filePaths: files),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Could not open folder: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentItemsProvider);

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

// ─── Folder Browser ───────────────────────────────────────────────────────────

class FolderBrowserScreen extends ConsumerWidget {
  final List<String> filePaths;
  const FolderBrowserScreen({super.key, required this.filePaths});

  String _fileName(String path) {
    return path.split('/').last.split('\\').last;
  }

  Future<void> _openEntry(
      BuildContext context, WidgetRef ref, String path) async {
    try {
      final (pattern, filePath) = await FileService.openFileFromPath(path);
      if (!context.mounted) return;
      ref.read(editorProvider.notifier).loadPattern(pattern, filePath: filePath);
      ref.read(recentItemsProvider.notifier).add(filePath, isFolder: false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditorScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not open: $e'),
            backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Folder (${filePaths.length} patterns)'),
      ),
      body: ListView.separated(
        itemCount: filePaths.length,
        separatorBuilder: (context, idx) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final path = filePaths[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.grid_4x4,
                size: 22,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            title: Text(_fileName(path)),
            subtitle: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openEntry(context, ref, path),
          );
        },
      ),
    );
  }
}
