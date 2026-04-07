part of 'editor_toolbar.dart';

// ─── Sprite sheet ─────────────────────────────────────────────────────────────

Future<void> _openSpriteSheet(BuildContext context, WidgetRef ref) async {
  final workspace = ref.read(workspaceProvider).workspace;

  String? imagePath;
  if (workspace != null) {
    if (!context.mounted) return;
    imagePath = await showDialog<String>(
      context: context,
      builder: (ctx) => _SpriteImageSourceDialog(folder: workspace),
    );
    if (imagePath == null) return; // cancelled
  } else {
    // No open folder — go straight to the system file picker.
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    imagePath = result.files.first.path;
    if (imagePath == null) return;
  }

  if (!await File(imagePath).exists()) return;
  if (!context.mounted) return;

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

/// Dialog shown when a folder is open (local or Drive). Lets the user choose
/// between browsing the folder tree or opening from the system file picker.
class _SpriteImageSourceDialog extends ConsumerStatefulWidget {
  final StorageLocation folder;
  const _SpriteImageSourceDialog({required this.folder});

  @override
  ConsumerState<_SpriteImageSourceDialog> createState() =>
      _SpriteImageSourceDialogState();
}

class _SpriteImageSourceDialogState
    extends ConsumerState<_SpriteImageSourceDialog> {
  bool _showTree = false;
  bool _downloading = false;
  PatternFile? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_showTree ? 'Choose image' : 'Open sprite sheet'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 360,
        child: _showTree ? _buildTree() : _buildSourceChoice(),
      ),
      actions: [
        if (_showTree)
          TextButton(
            onPressed: _downloading
                ? null
                : () => setState(() {
                      _showTree = false;
                      _selected = null;
                    }),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed:
              _downloading ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        if (_showTree)
          _downloading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _selected == null ? null : _openSelected,
                  child: const Text('Open'),
                ),
      ],
    );
  }

  Widget _buildSourceChoice() {
    final isDrive = widget.folder is DriveFolder;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(isDrive
              ? Icons.cloud_outlined
              : Icons.folder_open_outlined),
          title: const Text('From folder'),
          subtitle: Text(widget.folder.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
          onTap: () => setState(() => _showTree = true),
        ),
        ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: const Text('From file system'),
          onTap: () async {
            final result = await FilePicker.pickFiles(
              type: FileType.image,
              allowMultiple: false,
            );
            if (!mounted) return;
            Navigator.of(context).pop(result?.files.firstOrNull?.path);
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTree() {
    return SizedBox(
      height: 380,
      child: SingleChildScrollView(
        child: _ImageFolderNode(
          folder: widget.folder,
          selected: _selected,
          onSelect: (file) => setState(() => _selected = file),
          startExpanded: true,
          showHeader: false,
          depth: 0,
        ),
      ),
    );
  }

  Future<void> _openSelected() async {
    final file = _selected!;
    if (file is LocalImageFile) {
      Navigator.of(context).pop(file.path);
      return;
    }
    if (file is DriveImageFile) {
      setState(() => _downloading = true);
      try {
        final service =
            await ref.read(googleDriveProvider.notifier).getService();
        if (service == null) {
          if (mounted) setState(() => _downloading = false);
          return;
        }
        final tempPath = await driveGetOrDownload(
            file.fileId, '${file.fileId}_${file.name}', service);
        if (mounted) Navigator.of(context).pop(tempPath);
      } catch (_) {
        if (mounted) setState(() => _downloading = false);
      }
    }
  }
}

/// Recursive tree node that lists subdirectories and image files for picking.
/// Uses [folderContentsProvider] so it works for both local and Drive folders.
class _ImageFolderNode extends ConsumerStatefulWidget {
  final StorageLocation folder;
  final PatternFile? selected;
  final void Function(PatternFile) onSelect;
  final int depth;
  final bool startExpanded;
  final bool showHeader;

  const _ImageFolderNode({
    required this.folder,
    required this.selected,
    required this.onSelect,
    this.depth = 0,
    this.startExpanded = false,
    this.showHeader = true,
  });

  @override
  ConsumerState<_ImageFolderNode> createState() => _ImageFolderNodeState();
}

class _ImageFolderNodeState extends ConsumerState<_ImageFolderNode> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.startExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = widget.depth * 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  EdgeInsets.only(left: indent, top: 3, bottom: 3, right: 4),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.folder_open : Icons.folder,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.folder.displayName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_expanded)
          ref.watch(folderContentsProvider(widget.folder)).when(
                loading: () => Padding(
                  padding:
                      EdgeInsets.only(left: indent + 24, top: 6, bottom: 6),
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (e, s) => Padding(
                  padding: EdgeInsets.only(
                      left: indent + (widget.showHeader ? 24 : 8),
                      top: 4,
                      bottom: 4),
                  child: Text('Could not load folder',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700)),
                ),
                data: (contents) {
                  final images = contents.files
                      .whereType<LocalImageFile>()
                      .cast<PatternFile>()
                      .followedBy(contents.files.whereType<DriveImageFile>())
                      .toList();
                  if (contents.subfolders.isEmpty && images.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.only(
                          left: indent + (widget.showHeader ? 24 : 8),
                          top: 4,
                          bottom: 4),
                      child: Text(
                        'No images',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45)),
                      ),
                    );
                  }
                  final childDepth =
                      widget.showHeader ? widget.depth + 1 : widget.depth;
                  final fileIndent = childDepth * 14.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...contents.subfolders.map((sub) => _ImageFolderNode(
                            folder: sub,
                            selected: widget.selected,
                            onSelect: widget.onSelect,
                            depth: childDepth,
                            startExpanded: false,
                            showHeader: true,
                          )),
                      ...images.map((file) {
                        final isSelected = file == widget.selected;
                        return InkWell(
                          onTap: () => widget.onSelect(file),
                          child: Container(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5)
                                : null,
                            padding: EdgeInsets.only(
                                left: fileIndent + 20,
                                right: 4,
                                top: 3,
                                bottom: 3),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 14,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    file.displayName,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : null,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
      ],
    );
  }
}
