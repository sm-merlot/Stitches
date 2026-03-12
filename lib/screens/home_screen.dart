import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pattern.dart';
import '../providers/editor_provider.dart';
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
      final (pattern, path) = await FileService.openFile();
      if (!context.mounted) return;
      ref.read(editorProvider.notifier).loadPattern(pattern, filePath: path);
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
      if (!context.mounted) return;
      if (files.isEmpty) {
        _showError(context, 'No .stitchx files found in that folder.');
        return;
      }
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo / title area
                Column(
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
                const SizedBox(height: 48),
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
        ),
      ),
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
