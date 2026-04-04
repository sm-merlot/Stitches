import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/incoming_file_service.dart';

// Flutter on Windows uses BoringSSL with bundled root certs instead of the
// Windows certificate store, causing TLS failures against Google endpoints.
// This override trusts the platform certs on Windows only.
class _WindowsHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) =>
          defaultTargetPlatform == TargetPlatform.windows;
  }
}

void main() {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    HttpOverrides.global = _WindowsHttpOverrides();
  }
  WidgetsFlutterBinding.ensureInitialized();
  IncomingFileService.listen();
  runApp(
    const ProviderScope(
      child: StitchesApp(),
    ),
  );
}
