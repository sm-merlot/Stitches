import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/storage_location.dart';

/// Wrapper around the Google Drive API v3.
class GoogleDriveService {
  final drive.DriveApi _api;

  GoogleDriveService(http.Client client) : _api = drive.DriveApi(client);

  /// Lists the contents of a Drive folder.
  /// Use [DriveFolder] with folderId = 'root' for My Drive root.
  Future<FolderContents> listFolderContents(DriveFolder parent) async {
    final folderId = parent.folderId;
    final result = await _api.files.list(
      q: "'$folderId' in parents and trashed = false",
      $fields: 'files(id,name,mimeType,modifiedTime)',
      spaces: 'drive',
    );

    final subfolders = <StorageLocation>[];
    final files = <PatternFile>[];

    for (final file in result.files ?? []) {
      final id = file.id;
      final name = file.name;
      if (id == null || name == null) continue;

      if (file.mimeType == 'application/vnd.google-apps.folder') {
        subfolders.add(DriveFolder(
          folderId: id,
          name: name,
          parentId: parent.folderId,
        ));
      } else if (name.endsWith('.stitchx')) {
        files.add(DrivePatternFile(
          fileId: id,
          name: name,
          parentFolder: parent,
          modified: file.modifiedTime,
        ));
      }
    }

    subfolders.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    files.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    return FolderContents(subfolders: subfolders, files: files);
  }

  /// Downloads a file's bytes by file ID.
  Future<Uint8List> downloadFile(String fileId) async {
    final response = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    final media = response as drive.Media;
    final chunks = await media.stream.toList();
    final bytes = chunks.expand((chunk) => chunk).toList();
    return Uint8List.fromList(bytes);
  }

  /// Uploads (create or update) a .stitchx file.
  /// Returns the Drive file ID.
  Future<String> uploadFile({
    String? fileId,
    required String name,
    required Uint8List bytes,
    required String parentFolderId,
  }) async {
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/octet-stream',
    );

    if (fileId == null) {
      // Create new file
      final fileMetadata = drive.File()
        ..name = name
        ..parents = [parentFolderId];
      final result = await _api.files.create(
        fileMetadata,
        uploadMedia: media,
      );
      return result.id!;
    } else {
      // Update existing file (do not change parents)
      final fileMetadata = drive.File()..name = name;
      final result = await _api.files.update(
        fileMetadata,
        fileId,
        uploadMedia: media,
      );
      return result.id ?? fileId;
    }
  }

  /// Renames a file or folder.
  Future<void> renameItem(String fileId, String newName) async {
    final fileMetadata = drive.File()..name = newName;
    await _api.files.update(fileMetadata, fileId);
  }

  /// Moves a file to the trash.
  Future<void> deleteFile(String fileId) async {
    final fileMetadata = drive.File()..trashed = true;
    await _api.files.update(fileMetadata, fileId);
  }

  /// Creates a folder and returns it as a [DriveFolder].
  Future<DriveFolder> createFolder(
      String name, String parentFolderId) async {
    final fileMetadata = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentFolderId];
    final result = await _api.files.create(fileMetadata);
    return DriveFolder(
      folderId: result.id!,
      name: name,
      parentId: parentFolderId,
    );
  }
}
