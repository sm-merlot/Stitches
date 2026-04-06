import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/storage_location.dart';
import '../providers/google_drive_provider.dart';
import '../services/google_drive_service.dart';

/// A dialog that lets the user navigate their Google Drive folder hierarchy
/// and select a folder to use as the workspace root.
class DriveFolderPickerDialog extends ConsumerStatefulWidget {
  /// When non-null, shows a "Save to local storage" button that calls this.
  final VoidCallback? onSaveLocally;

  const DriveFolderPickerDialog({super.key, this.onSaveLocally});

  /// Shows the dialog and returns the selected folder + its breadcrumb path,
  /// or null if cancelled.
  static Future<(DriveFolder, String)?> show(BuildContext context) {
    return showDialog<(DriveFolder, String)>(
      context: context,
      builder: (_) => const DriveFolderPickerDialog(),
    );
  }

  @override
  ConsumerState<DriveFolderPickerDialog> createState() =>
      _DriveFolderPickerDialogState();
}

class _DriveFolderPickerDialogState
    extends ConsumerState<DriveFolderPickerDialog> {
  // Breadcrumb stack — first entry is always the root.
  final List<DriveFolder> _breadcrumbs = [
    const DriveFolder(folderId: 'root', name: 'My Drive'),
  ];

  GoogleDriveService? _service;
  List<DriveFolder>? _subfolders;
  bool _loading = true;
  String? _error;

  DriveFolder get _current => _breadcrumbs.last;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final service =
        await ref.read(googleDriveProvider.notifier).getService();
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
      _subfolders = null;
    });
    try {
      final contents = await _service!.listFolderContents(_current);
      if (!mounted) return;
      setState(() {
        _subfolders = contents.subfolders.whereType<DriveFolder>().toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load folders: $e';
      });
    }
  }

  void _navigateInto(DriveFolder folder) {
    _breadcrumbs.add(folder);
    _loadCurrent();
  }

  void _navigateTo(int breadcrumbIndex) {
    if (breadcrumbIndex == _breadcrumbs.length - 1) return;
    _breadcrumbs.removeRange(breadcrumbIndex + 1, _breadcrumbs.length);
    _loadCurrent();
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
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'Select Drive Folder',
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),

            // ── Breadcrumbs ──────────────────────────────────────────────────
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _breadcrumbs.length,
                separatorBuilder: (context, i) => const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.grey,
                ),
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

            // ── Folder list ──────────────────────────────────────────────────
            Expanded(
              child: _buildBody(theme),
            ),

            const Divider(height: 1),

            // ── Actions ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.onSaveLocally != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(null);
                        widget.onSaveLocally!();
                      },
                      icon: const Icon(Icons.folder_outlined, size: 16),
                      label: const Text('Save to local storage'),
                    )
                  else
                    Text(
                      _current.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop((
                                  _current,
                                  _breadcrumbs
                                      .map((b) => b.displayName)
                                      .join(' › '),
                                )),
                        child: Text(
                          MediaQuery.of(context).size.shortestSide < 600
                              ? 'Select'
                              : 'Select This Folder',
                        ),
                      ),
                    ],
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
    final folders = _subfolders ?? [];
    if (folders.isEmpty) {
      return Center(
        child: Text(
          'No subfolders here.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: folders.length,
      itemBuilder: (context, i) {
        final folder = folders[i];
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.folder_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(folder.displayName),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _navigateInto(folder),
        );
      },
    );
  }
}
