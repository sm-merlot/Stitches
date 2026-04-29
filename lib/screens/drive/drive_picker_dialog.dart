import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/storage_location.dart';
import '../../providers/google_drive_provider.dart';
import '../../services/drive/google_drive_service.dart';

// ── Result type ───────────────────────────────────────────────────────────────

sealed class DrivePickerResult {}

class DrivePickerFileResult extends DrivePickerResult {
  final String fileId;
  final String fileName;
  final String parentFolderId;
  final String drivePath;

  DrivePickerFileResult({
    required this.fileId,
    required this.fileName,
    required this.parentFolderId,
    required this.drivePath,
  });
}

class DrivePickerFolderResult extends DrivePickerResult {
  final DriveFolder folder;
  final String drivePath;

  DrivePickerFolderResult({required this.folder, required this.drivePath});
}

// ── Dialog ────────────────────────────────────────────────────────────────────

/// Unified Google Drive browser: tap a .stitches file to open it, or press
/// "Open This Folder" to use the current folder as a workspace.
class DrivePickerDialog extends ConsumerStatefulWidget {
  const DrivePickerDialog({super.key});

  static Future<DrivePickerResult?> show(BuildContext context) {
    return showDialog<DrivePickerResult>(
      context: context,
      builder: (_) => const DrivePickerDialog(),
    );
  }

  @override
  ConsumerState<DrivePickerDialog> createState() => _DrivePickerDialogState();
}

class _DrivePickerDialogState extends ConsumerState<DrivePickerDialog> {
  final List<DriveFolder> _breadcrumbs = [
    const DriveFolder(folderId: 'root', name: 'My Drive'),
  ];

  GoogleDriveService? _service;
  List<DriveFolder> _subfolders = [];
  List<DrivePatternFile> _files = [];
  bool _loading = true;
  String? _error;

  DriveFolder get _current => _breadcrumbs.last;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final service = await ref.read(googleDriveProvider.notifier).getService();
    if (!mounted) return;
    if (service == null) {
      setState(() {
        _loading = false;
        _error = 'Not connected to Google Drive.';
      });
      return;
    }
    _service = service;
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
      _subfolders = [];
      _files = [];
    });
    try {
      final contents = await _service!.listFolderContents(_current);
      if (!mounted) return;
      setState(() {
        _subfolders = contents.subfolders.whereType<DriveFolder>().toList();
        _files = contents.files.whereType<DrivePatternFile>().toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  void _navigateInto(DriveFolder folder) {
    _breadcrumbs.add(folder);
    _loadCurrent();
  }

  void _navigateTo(int index) {
    if (index == _breadcrumbs.length - 1) return;
    _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
    _loadCurrent();
  }

  void _selectFile(DrivePatternFile file) {
    final path = _breadcrumbs.map((b) => b.displayName).join(' › ');
    Navigator.of(context).pop(DrivePickerFileResult(
      fileId: file.fileId,
      fileName: file.displayName,
      parentFolderId: _current.folderId,
      drivePath: path,
    ));
  }

  void _selectCurrentFolder() {
    final path = _breadcrumbs.map((b) => b.displayName).join(' › ');
    Navigator.of(context)
        .pop(DrivePickerFolderResult(folder: _current, drivePath: path));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 480,
          maxWidth: 560,
          minHeight: 400,
          maxHeight: 520,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Google Drive', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 12),

            // Breadcrumbs
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _breadcrumbs.length,
                separatorBuilder: (context, i) => const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.grey),
                itemBuilder: (context, i) {
                  final crumb = _breadcrumbs[i];
                  final isLast = i == _breadcrumbs.length - 1;
                  return InkWell(
                    onTap: isLast ? null : () => _navigateTo(i),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        crumb.displayName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isLast ? FontWeight.w600 : FontWeight.normal,
                          color: isLast
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 16),

            // Content
            Expanded(child: _buildBody(theme)),

            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: _loading ? null : _selectCurrentFolder,
                    child: Text(_current.folderId == 'root'
                        ? 'Open My Drive'
                        : 'Open This Folder'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadCurrent, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_subfolders.isEmpty && _files.isEmpty) {
      return Center(
        child: Text('No folders or .stitches files here.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        ..._subfolders.map((folder) => ListTile(
              dense: true,
              leading:
                  Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
              title: Text(folder.displayName),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _navigateInto(folder),
            )),
        if (_subfolders.isNotEmpty && _files.isNotEmpty)
          const Divider(height: 8),
        ..._files.map((file) => ListTile(
              dense: true,
              leading: Icon(Icons.grid_4x4, color: theme.colorScheme.secondary),
              title: Text(file.displayName),
              subtitle: file.modified != null
                  ? Text(
                      _formatDate(file.modified!),
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  : null,
              onTap: () => _selectFile(file),
            )),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
