import 'dart:async';
import 'package:flutter/services.dart';

/// Handles .stitches files and folders opened from outside the app
/// (Finder, Files app, file managers, AirDrop, etc.) via OS file-type
/// associations.
///
/// Usage:
///   1. Call [listen] once at startup (after [WidgetsFlutterBinding.ensureInitialized]).
///   2. In HomeScreen.initState, subscribe to [fileStream] / [folderStream]
///      and call [getInitialPath].
class IncomingFileService {
  static const _channel = MethodChannel('com.scme0.stitches/file_open');
  static final _fileController = StreamController<String>.broadcast();
  static final _folderController = StreamController<String>.broadcast();

  /// Emits a file path whenever the OS opens a .stitches file into a running app.
  static Stream<String> get fileStream => _fileController.stream;

  /// Emits a folder path whenever the OS opens a folder into a running app.
  static Stream<String> get folderStream => _folderController.stream;

  /// Register the method-call handler. Must be called after
  /// [WidgetsFlutterBinding.ensureInitialized] and before [runApp].
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      final path = call.arguments as String?;
      if (path == null) return;
      switch (call.method) {
        case 'openFile':
          _fileController.add(path);
        case 'openFolder':
          _folderController.add(path);
      }
    });
  }

  /// Returns the path the app was cold-started with (file or folder), or null
  /// if the app was launched normally. Checks the type and routes accordingly;
  /// also returns the path so the caller can route it.
  static Future<String?> getInitialPath() async {
    try {
      return await _channel.invokeMethod<String>('getInitialFile');
    } catch (_) {
      return null;
    }
  }
}
