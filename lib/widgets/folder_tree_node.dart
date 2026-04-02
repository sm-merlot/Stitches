import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/storage_location.dart';
import '../providers/folder_contents_provider.dart';

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

class FolderTreeNode extends ConsumerStatefulWidget {
  final StorageLocation folder;
  final String? selectedFilePath;
  final String? selectedDriveFileId;
  /// Local path of the currently open PDF (for selection highlight).
  final String? selectedPdfPath;
  /// Drive file ID of the currently open PDF (for selection highlight).
  final String? selectedDrivePdfId;
  /// Local path of the currently open image (for selection highlight).
  final String? selectedImagePath;
  /// Drive file ID of the currently open image (for selection highlight).
  final String? selectedDriveImageId;
  /// Whether PDF files are shown in the tree.
  final bool showPdfs;
  /// Whether image files are shown in the tree.
  final bool showImages;
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
    required this.selectedDriveFileId,
    this.selectedPdfPath,
    this.selectedDrivePdfId,
    this.selectedImagePath,
    this.selectedDriveImageId,
    this.showPdfs = true,
    this.showImages = true,
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
    // Optimistic files added before the Drive upload completes.
    final pendingFiles = widget.folder is DriveFolder
        ? (ref.watch(pendingDriveFilesProvider)[
                (widget.folder as DriveFolder).folderId] ??
            const [])
        : const <PatternFile>[];

    final isTouch = _isTouch;
    final rowV = isTouch ? 6.0 : 2.0;
    final iconSize = isTouch ? 20.0 : 16.0;
    final textStyle = isTouch
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)
        : theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Folder row
        GestureDetector(
          onSecondaryTapDown: (details) {
            widget.onFolderContextMenu(widget.folder, details.globalPosition);
          },
          onLongPressStart: (details) {
            widget.onFolderContextMenu(widget.folder, details.globalPosition);
          },
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.only(left: indent, top: rowV, bottom: rowV, right: 4),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: iconSize,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.folder_open : Icons.folder,
                    size: iconSize,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.folder.displayName,
                      style: textStyle,
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
                        selectedDriveFileId: widget.selectedDriveFileId,
                        selectedPdfPath: widget.selectedPdfPath,
                        selectedDrivePdfId: widget.selectedDrivePdfId,
                        selectedImagePath: widget.selectedImagePath,
                        selectedDriveImageId: widget.selectedDriveImageId,
                        showPdfs: widget.showPdfs,
                        showImages: widget.showImages,
                        filter: widget.filter,
                        onFileTap: widget.onFileTap,
                        onFolderContextMenu: widget.onFolderContextMenu,
                        onFileContextMenu: widget.onFileContextMenu,
                        depth: widget.depth + 1,
                        startExpanded: false,
                      )),

                  // Files (filtered by type, text filter) + optimistic pending files
                  ...[...contents.files, ...pendingFiles]
                      .where((f) {
                        if (!widget.showPdfs && (f is LocalPdfFile || f is DrivePdfFile)) return false;
                        if (!widget.showImages && (f is LocalImageFile || f is DriveImageFile)) return false;
                        return filterLower.isEmpty ||
                            f.displayName.toLowerCase().contains(filterLower);
                      })
                      .map((file) => _FileTile(
                            file: file,
                            selectedFilePath: widget.selectedFilePath,
                            selectedDriveFileId: widget.selectedDriveFileId,
                            selectedPdfPath: widget.selectedPdfPath,
                            selectedDrivePdfId: widget.selectedDrivePdfId,
                            selectedImagePath: widget.selectedImagePath,
                            selectedDriveImageId: widget.selectedDriveImageId,
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
  final String? selectedDriveFileId;
  final String? selectedPdfPath;
  final String? selectedDrivePdfId;
  final String? selectedImagePath;
  final String? selectedDriveImageId;
  final int depth;
  final VoidCallback onTap;
  final void Function(Offset) onContextMenu;

  const _FileTile({
    required this.file,
    required this.selectedFilePath,
    required this.selectedDriveFileId,
    this.selectedPdfPath,
    this.selectedDrivePdfId,
    this.selectedImagePath,
    this.selectedDriveImageId,
    required this.depth,
    required this.onTap,
    required this.onContextMenu,
  });

  bool get _isSelected {
    if (file is LocalPatternFile) {
      return (file as LocalPatternFile).path == selectedFilePath;
    }
    if (file is DrivePatternFile) {
      final driveFile = file as DrivePatternFile;
      if (driveFile.fileId == selectedDriveFileId) return true;
      // Pending placeholder: fileId is the local temp path.
      if (selectedDriveFileId == null &&
          driveFile.fileId == selectedFilePath) { return true; }
    }
    if (file is LocalPdfFile) {
      return (file as LocalPdfFile).path == selectedPdfPath;
    }
    if (file is DrivePdfFile) {
      return (file as DrivePdfFile).fileId == selectedDrivePdfId;
    }
    if (file is LocalImportableFile) {
      return (file as LocalImportableFile).path == selectedFilePath;
    }
    if (file is DriveImportableFile) {
      // Imported Drive file: cached temp path is used as filePath.
      final f = file as DriveImportableFile;
      return selectedFilePath != null &&
          selectedFilePath!.contains(f.fileId);
    }
    if (file is LocalImageFile) {
      return (file as LocalImageFile).path == selectedImagePath;
    }
    if (file is DriveImageFile) {
      return (file as DriveImageFile).fileId == selectedDriveImageId;
    }
    return false;
  }

  bool get _isPdf => file is LocalPdfFile || file is DrivePdfFile;
  bool get _isImage => file is LocalImageFile || file is DriveImageFile;
  bool get _isImportable =>
      file is LocalImportableFile || file is DriveImportableFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = depth * 12.0;
    final selected = _isSelected;

    final isTouch = _isTouch;
    final tileV = isTouch ? 7.0 : 3.0;
    final fileIconSize = isTouch ? 18.0 : 14.0;
    final fileTextStyle = isTouch
        ? theme.textTheme.bodyMedium?.copyWith(
            color: selected ? theme.colorScheme.primary : null,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          )
        : theme.textTheme.bodySmall?.copyWith(
            color: selected ? theme.colorScheme.primary : null,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          );

    return GestureDetector(
      onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
      onLongPressStart: (details) => onContextMenu(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          padding: EdgeInsets.only(left: indent + 20, right: 4, top: tileV, bottom: tileV),
          child: Row(
            children: [
              Icon(
                _isImage
                    ? Icons.image_outlined
                    : _isPdf
                        ? Icons.picture_as_pdf_outlined
                        : _isImportable
                            ? Icons.swap_horiz
                            : Icons.grid_4x4,
                size: fileIconSize,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  file.displayName,
                  style: fileTextStyle,
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
