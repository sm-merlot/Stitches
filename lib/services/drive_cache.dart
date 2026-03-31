import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'google_drive_service.dart';

/// Downloads [fileId] from Drive to the device's temp directory as
/// `${tempDir}/${localName}` (e.g. `'${fileId}.stitches'`).
///
/// Returns the local path. Uses a cached file if one already exists.
/// Throws if the download fails.
Future<String> driveGetOrDownload(
  String fileId,
  String localName,
  GoogleDriveService service,
) async {
  final tempDir = await getTemporaryDirectory();
  final tempPath = '${tempDir.path}/$localName';
  final cached = File(tempPath);
  if (await cached.exists()) return tempPath;
  final bytes = await service.downloadFile(fileId);
  await cached.writeAsBytes(bytes);
  return tempPath;
}
