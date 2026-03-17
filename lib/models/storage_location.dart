import 'dart:io';

/// Represents a folder location in either the local filesystem or Google Drive.
sealed class StorageLocation {
  const StorageLocation();

  String get displayName;

  /// Stable identifier used as a key (e.g. for SharedPreferences persistence).
  String get id;
}

class LocalFolder extends StorageLocation {
  final String path;

  const LocalFolder(this.path);

  @override
  String get displayName => path.split(Platform.pathSeparator).last;

  @override
  String get id => 'local:$path';

  @override
  bool operator ==(Object other) => other is LocalFolder && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'LocalFolder($path)';
}

class DriveFolder extends StorageLocation {
  final String folderId;
  final String? parentId;
  final String name;

  const DriveFolder({
    required this.folderId,
    required this.name,
    this.parentId,
  });

  @override
  String get displayName => name;

  @override
  String get id => 'drive:$folderId';

  @override
  bool operator ==(Object other) =>
      other is DriveFolder && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;

  @override
  String toString() => 'DriveFolder($name, $folderId)';
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

/// Represents a .stitchx file in either local storage or Google Drive.
sealed class PatternFile {
  const PatternFile();

  String get displayName;
  DateTime? get modified;

  /// The parent location of this file.
  StorageLocation get parent;
}

class LocalPatternFile extends PatternFile {
  final String path;
  @override
  final DateTime? modified;

  const LocalPatternFile({required this.path, this.modified});

  @override
  String get displayName =>
      path.split(Platform.pathSeparator).last.replaceAll('.stitchx', '');

  @override
  StorageLocation get parent =>
      LocalFolder(path.substring(0, path.lastIndexOf(Platform.pathSeparator)));

  @override
  bool operator ==(Object other) =>
      other is LocalPatternFile && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'LocalPatternFile($path)';
}

class DrivePatternFile extends PatternFile {
  final String fileId;
  final String name;
  final DriveFolder parentFolder;
  @override
  final DateTime? modified;

  const DrivePatternFile({
    required this.fileId,
    required this.name,
    required this.parentFolder,
    this.modified,
  });

  @override
  String get displayName => name.replaceAll('.stitchx', '');

  @override
  StorageLocation get parent => parentFolder;

  @override
  bool operator ==(Object other) =>
      other is DrivePatternFile && other.fileId == fileId;

  @override
  int get hashCode => fileId.hashCode;

  @override
  String toString() => 'DrivePatternFile($name, $fileId)';
}

// ---------------------------------------------------------------------------
// Folder contents
// ---------------------------------------------------------------------------

/// The contents of a folder: child folders and .stitchx files.
class FolderContents {
  final List<StorageLocation> subfolders;
  final List<PatternFile> files;

  const FolderContents({
    required this.subfolders,
    required this.files,
  });

  static const empty = FolderContents(subfolders: [], files: []);
}
