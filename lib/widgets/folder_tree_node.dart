import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/storage_location.dart';
import '../providers/folder_contents_provider.dart';

class FolderTreeNode extends ConsumerStatefulWidget {
  final StorageLocation folder;
  final String? selectedFilePath;
  final String filter;
  final void Function(PatternFile) onFileTap;
  final void Function(StorageLocation, Offset) onFolderContextMenu;
  final void Function(PatternFile, Offset) onFileContextMenu;
  final int depth;
  final bool startExpanded;

  const FolderTreeNode({
    super.key,
    required this.folder,
    required this.selectedFilePath,
    required this.filter,
    required this.onFileTap,
    required this.onFolderContextMenu,
    required this.onFileContextMenu,
    this.depth = 0,
    this.startExpanded = false,
  });

  @override
  ConsumerState<FolderTreeNode> createState() => _FolderTreeNodeState();
}

class _FolderTreeNodeState extends ConsumerState<FolderTreeNode> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.startExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = widget.depth * 12.0;
    final contentsAsync = ref.watch(folderContentsProvider(widget.folder));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Folder row
        GestureDetector(
          onSecondaryTapDown: (details) {
            widget.onFolderContextMenu(widget.folder, details.globalPosition);
          },
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.only(left: indent, top: 2, bottom: 2, right: 4),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Expanded contents
        if (_expanded)
          contentsAsync.when(
            loading: () => Padding(
              padding: EdgeInsets.only(left: indent + 24, top: 4, bottom: 4),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (err, _) => Padding(
              padding: EdgeInsets.only(left: indent + 24, top: 4, bottom: 4),
              child: Text(
                'Error: $err',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ),
            data: (contents) {
              final filterLower = widget.filter.toLowerCase();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Subfolders
                  ...contents.subfolders.map((subfolder) => FolderTreeNode(
                        folder: subfolder,
                        selectedFilePath: widget.selectedFilePath,
                        filter: widget.filter,
                        onFileTap: widget.onFileTap,
                        onFolderContextMenu: widget.onFolderContextMenu,
                        onFileContextMenu: widget.onFileContextMenu,
                        depth: widget.depth + 1,
                        startExpanded: false,
                      )),

                  // Files (filtered)
                  ...contents.files
                      .where((f) => filterLower.isEmpty ||
                          f.displayName.toLowerCase().contains(filterLower))
                      .map((file) => _FileTile(
                            file: file,
                            selectedFilePath: widget.selectedFilePath,
                            depth: widget.depth + 1,
                            onTap: () => widget.onFileTap(file),
                            onContextMenu: (pos) =>
                                widget.onFileContextMenu(file, pos),
                          )),
                ],
              );
            },
          ),
      ],
    );
  }
}

// ─── File tile ────────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final PatternFile file;
  final String? selectedFilePath;
  final int depth;
  final VoidCallback onTap;
  final void Function(Offset) onContextMenu;

  const _FileTile({
    required this.file,
    required this.selectedFilePath,
    required this.depth,
    required this.onTap,
    required this.onContextMenu,
  });

  bool get _isSelected {
    if (file is LocalPatternFile) {
      return (file as LocalPatternFile).path == selectedFilePath;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = depth * 12.0;
    final selected = _isSelected;

    return GestureDetector(
      onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        onLongPress: () {
          // Long-press for mobile context menu — we need a position estimate
          // (use the widget's center as best we can without pointer details)
        },
        child: Container(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          padding: EdgeInsets.only(left: indent + 20, right: 4, top: 3, bottom: 3),
          child: Row(
            children: [
              Icon(
                Icons.grid_4x4,
                size: 14,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  file.displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected ? theme.colorScheme.primary : null,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
