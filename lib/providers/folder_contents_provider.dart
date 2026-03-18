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

Future<FolderContents> _loadLocalFolder(LocalFolder folder) async {
  final dir = Directory(folder.path);
  if (!await dir.exists()) return FolderContents.empty;

  final subfolders = <StorageLocation>[];
  final files = <PatternFile>[];

  await for (final entity in dir.list(recursive: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (name.startsWith('.')) continue;

    if (entity is Directory) {
      subfolders.add(LocalFolder(entity.path));
    } else if (entity is File && entity.path.endsWith('.stitchx')) {
      final stat = await entity.stat();
      files.add(LocalPatternFile(
        path: entity.path,
        modified: stat.modified,
      ));
    } else if (entity is File && entity.path.endsWith('.pdf')) {
      final stat = await entity.stat();
      files.add(LocalPdfFile(
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
    Ref<AsyncValue<FolderContents>> ref, DriveFolder folder) async {
  final notifier = ref.read(googleDriveProvider.notifier);
  final service = await notifier.getService();
  if (service == null) return FolderContents.empty;

  try {
    return await service.listFolderContents(folder);
  } catch (_) {
    return FolderContents.empty;
  }
}

/// Optimistic pending files, keyed by Drive folderId.
/// Files added here appear in the tree immediately before the Drive upload
/// completes. The placeholder [DrivePatternFile.fileId] is set to the local
/// temp path so the tree can highlight the file via [selectedFilePath].
final pendingDriveFilesProvider =
    StateProvider<Map<String, List<PatternFile>>>((ref) => {});

/// Adds a placeholder file for [folderId] so it shows in the tree immediately.
void addPendingDriveFile(WidgetRef ref, String folderId, PatternFile file) {
  final current = Map<String, List<PatternFile>>.from(
      ref.read(pendingDriveFilesProvider));
  current[folderId] = [...(current[folderId] ?? []), file];
  ref.read(pendingDriveFilesProvider.notifier).state = current;
}

/// Removes all pending files for [folderId] (called after Drive upload + refresh).
void clearPendingDriveFiles(WidgetRef ref, String folderId) {
  final current = Map<String, List<PatternFile>>.from(
      ref.read(pendingDriveFilesProvider));
  current.remove(folderId);
  ref.read(pendingDriveFilesProvider.notifier).state = current;
}

/// Invalidates the cached folder contents so the tree reloads.
void refreshFolder(WidgetRef ref, StorageLocation loc) {
  ref.invalidate(folderContentsProvider(loc));
}
