import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/storage_location.dart';
import 'google_drive_provider.dart';

final folderContentsProvider = FutureProvider.autoDispose
    .family<FolderContents, StorageLocation>((ref, location) async {
  return switch (location) {
    LocalFolder f => _loadLocalFolder(f),
    DriveFolder f => _loadDriveFolder(ref, f),
  };
});

bool _isHidden(String name) => name.startsWith('.');
bool _isPatternFile(String path) => path.endsWith('.stitchx');
bool _isPdfFile(String path) => path.endsWith('.pdf');

const _kImageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'};
bool _isImageFile(String path) {
  final lower = path.toLowerCase();
  return _kImageExtensions.any((ext) => lower.endsWith(ext));
}

/// Third-party cross-stitch formats that can be imported.
const _kImportableExtensions = {'.oxs'};
bool _isImportableFile(String path) {
  final lower = path.toLowerCase();
  return _kImportableExtensions.any((ext) => lower.endsWith(ext));
}

Future<FolderContents> _loadLocalFolder(LocalFolder folder) async {
  final dir = Directory(folder.path);
  if (!await dir.exists()) return FolderContents.empty;

  final subfolders = <StorageLocation>[];
  final files = <PatternFile>[];

  await for (final entity in dir.list(recursive: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (_isHidden(name)) continue;

    if (entity is Directory) {
      subfolders.add(LocalFolder(entity.path));
    } else if (entity is File && _isPatternFile(entity.path)) {
      final stat = await entity.stat();
      files.add(LocalPatternFile(
        path: entity.path,
        modified: stat.modified,
      ));
    } else if (entity is File && _isPdfFile(entity.path)) {
      final stat = await entity.stat();
      files.add(LocalPdfFile(
        path: entity.path,
        modified: stat.modified,
      ));
    } else if (entity is File && _isImportableFile(entity.path)) {
      final stat = await entity.stat();
      files.add(LocalImportableFile(
        path: entity.path,
        modified: stat.modified,
      ));
    } else if (entity is File && _isImageFile(entity.path)) {
      final stat = await entity.stat();
      files.add(LocalImageFile(
        path: entity.path,
        modified: stat.modified,
      ));
    }
  }

  subfolders.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  files.sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  return FolderContents(subfolders: subfolders, files: files);
}

Future<FolderContents> _loadDriveFolder(
    Ref ref, DriveFolder folder) async {
  final notifier = ref.read(googleDriveProvider.notifier);
  final service = await notifier.getService();
  if (service == null) return FolderContents.empty;

  try {
    return await service.listFolderContents(folder);
  } catch (_) {
    // Network/auth failure — return empty so the tree degrades gracefully.
    return FolderContents.empty;
  }
}

/// Optimistic pending files, keyed by Drive folderId.
/// Files added here appear in the tree immediately before the Drive upload
/// completes. The placeholder [DrivePatternFile.fileId] is set to the local
/// temp path so the tree can highlight the file via [selectedFilePath].
class PendingDriveFilesNotifier
    extends Notifier<Map<String, List<PatternFile>>> {
  @override
  Map<String, List<PatternFile>> build() => {};
  void set(Map<String, List<PatternFile>> value) => state = value;
}

final pendingDriveFilesProvider =
    NotifierProvider<PendingDriveFilesNotifier, Map<String, List<PatternFile>>>(
        PendingDriveFilesNotifier.new);

/// Adds a placeholder file for [folderId] so it shows in the tree immediately.
void addPendingDriveFile(WidgetRef ref, String folderId, PatternFile file) {
  final current = Map<String, List<PatternFile>>.from(
      ref.read(pendingDriveFilesProvider));
  current[folderId] = [...(current[folderId] ?? []), file];
  ref.read(pendingDriveFilesProvider.notifier).set(current);
}

/// Removes all pending files for [folderId] (called after Drive upload + refresh).
void clearPendingDriveFiles(WidgetRef ref, String folderId) {
  final current = Map<String, List<PatternFile>>.from(
      ref.read(pendingDriveFilesProvider));
  current.remove(folderId);
  ref.read(pendingDriveFilesProvider.notifier).set(current);
}

/// Invalidates the cached folder contents so the tree reloads.
void refreshFolder(WidgetRef ref, StorageLocation loc) {
  ref.invalidate(folderContentsProvider(loc));
}
