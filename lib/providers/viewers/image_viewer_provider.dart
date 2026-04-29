import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents an open image file in the workspace viewer.
class OpenImage {
  final String localPath;
  final String? driveFileId;
  final String? displayName;

  const OpenImage({required this.localPath, this.driveFileId, this.displayName});

  String get title =>
      displayName ?? localPath.split('/').last;
}

class ImageViewerNotifier extends Notifier<OpenImage?> {
  @override
  OpenImage? build() => null;
  void set(OpenImage? value) => state = value;
}

final imageViewerProvider =
    NotifierProvider<ImageViewerNotifier, OpenImage?>(ImageViewerNotifier.new);
