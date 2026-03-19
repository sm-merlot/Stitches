import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a Drive file is being downloaded/created and cannot be
/// interrupted. Widgets that watch this provider should show a blocking
/// loading overlay.
class FileLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final fileLoadingProvider =
    NotifierProvider<FileLoadingNotifier, bool>(FileLoadingNotifier.new);
