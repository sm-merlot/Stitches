import 'dart:async';
import 'package:flutter/services.dart';

/// Handles .stitches files opened from outside the app (Finder, Files app,
/// file managers, AirDrop, etc.) via the OS file-type association.
///
/// Usage:
///   1. Call [listen] once at startup (after [WidgetsFlutterBinding.ensureInitialized]).
///   2. In HomeScreen.initState, subscribe to [stream] and call [getInitialFile].
class IncomingFileService {
  static const _channel = MethodChannel('com.scme0.stitches/file_open');
  static final _controller = StreamController<String>.broadcast();

  /// Emits a file path whenever the OS opens a .stitches file into a running app.
  static Stream<String> get stream => _controller.stream;

  /// Register the method-call handler. Must be called after
  /// [WidgetsFlutterBinding.ensureInitialized] and before [runApp].
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final path = call.arguments as String?;
        if (path != null) _controller.add(path);
      }
    });
  }

  /// Returns the file path the app was cold-started with, or null if the app
  /// was launched normally. Clears the path on the native side after reading.
  static Future<String?> getInitialFile() async {
    try {
      return await _channel.invokeMethod<String>('getInitialFile');
    } catch (_) {
      return null;
    }
  }
}
