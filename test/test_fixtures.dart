import 'dart:io';

/// Resolves a file path inside the private stitches-test-fixtures repo.
///
/// Locally, clone that repo as a sibling of this repo:
///   ~/dev/Stitches/               ← this repo
///   ~/dev/stitches-test-fixtures/ ← private fixtures repo
///
/// In CI the fixtures repo is checked out at test-fixtures/ inside the
/// workspace (actions/checkout forbids paths outside the workspace root).
/// The helper checks both locations so local and CI work without changes.
String testFixturePath(String name) {
  // CI path: <workspace>/test-fixtures/<name>
  final ciPath = Uri.directory(Directory.current.path)
      .resolve('test-fixtures/$name')
      .toFilePath();
  if (File(ciPath).existsSync() || Directory(ciPath).existsSync()) {
    return ciPath;
  }
  // Local path: sibling repo at ../stitches-test-fixtures/<name>
  return Uri.directory(Directory.current.path)
      .resolve('../stitches-test-fixtures/$name')
      .toFilePath();
}
