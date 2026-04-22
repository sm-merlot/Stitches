import 'dart:io';

/// Resolves a file path inside the private stitches-test-fixtures repo.
///
/// Locally, clone that repo as a sibling of this repo:
///   ~/dev/Stitches/               ← this repo
///   ~/dev/stitches-test-fixtures/ ← private fixtures repo
///
/// In CI the fixtures repo is checked out at ../stitches-test-fixtures
/// relative to the workspace root, producing the same relative layout.
String testFixturePath(String name) =>
    Uri.directory(Directory.current.path)
        .resolve('../stitches-test-fixtures/$name')
        .toFilePath();
