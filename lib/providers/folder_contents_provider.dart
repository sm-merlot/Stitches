import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/storage_location.dart';

final folderContentsProvider = FutureProvider.autoDispose
    .family<FolderContents, StorageLocation>((ref, location) async {
  return switch (location) {
    LocalFolder f => _loadLocalFolder(f),
    DriveFolder _ => Future.value(FolderContents.empty),
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
    }
  }

  subfolders.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  files.sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  return FolderContents(subfolders: subfolders, files: files);
}

/// Invalidates the cached folder contents so the tree reloads.
void refreshFolder(WidgetRef ref, StorageLocation loc) {
  ref.invalidate(folderContentsProvider(loc));
}
