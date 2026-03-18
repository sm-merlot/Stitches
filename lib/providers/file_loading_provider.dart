import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a Drive file is being downloaded/created and cannot be
/// interrupted. Widgets that watch this provider should show a blocking
/// loading overlay.
final fileLoadingProvider = StateProvider<bool>((ref) => false);
