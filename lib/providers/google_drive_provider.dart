import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/pattern.dart';
import '../services/file_service.dart';
import '../services/google_auth_service.dart';
import '../services/google_drive_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum DriveStatus { disconnected, connecting, connected, error }

@immutable
class DriveState {
  final DriveStatus status;
  final String? email;
  final bool isSyncing;
  final String? error;
  /// False when the app was built without --dart-define-from-file credentials.
  final bool isConfigured;

  const DriveState({
    this.status = DriveStatus.disconnected,
    this.email,
    this.isSyncing = false,
    this.error,
    this.isConfigured = false,
  });

  DriveState copyWith({
    DriveStatus? status,
    Object? email = _sentinel,
    bool? isSyncing,
    Object? error = _sentinel,
    bool? isConfigured,
  }) {
    return DriveState(
      status: status ?? this.status,
      email: email == _sentinel ? this.email : email as String?,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error == _sentinel ? this.error : error as String?,
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }

  static const _sentinel = Object();
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class DriveNotifier extends Notifier<DriveState> {
  final _auth = GoogleAuthService.instance;

  @override
  DriveState build() {
    // Schedule after build() returns so `state` is initialised before
    // checkConnection() tries to write it (isConfigured=false short-circuits
    // the await, making the first write synchronous otherwise).
    Future.microtask(checkConnection);
    return const DriveState();
  }

  /// Checks stored credentials and updates status accordingly.
  Future<void> checkConnection() async {
    final configured = _auth.isConfigured;
    try {
      final signedIn = configured && await _auth.isSignedIn();
      if (!ref.mounted) return;
      if (signedIn) {
        final email = await _auth.accountEmail();
        if (!ref.mounted) return;
        state = state.copyWith(
          status: DriveStatus.connected,
          email: email,
          error: null,
          isConfigured: true,
        );
      } else {
        state = state.copyWith(
          status: DriveStatus.disconnected,
          isConfigured: configured,
          email: null,
        );
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: DriveStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Launches the OAuth2 sign-in flow.
  Future<void> connect() async {
    state = state.copyWith(status: DriveStatus.connecting, error: null);
    try {
      await _auth.signIn();
      if (!ref.mounted) return;
      final email = await _auth.accountEmail();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: DriveStatus.connected,
        email: email,
        error: null,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: DriveStatus.error,
        error: 'Sign-in failed: $e',
      );
    }
  }

  /// Signs out and clears tokens.
  Future<void> disconnect() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Sign-out failed (e.g. network error) — clear local state regardless.
    }
    state = const DriveState();
  }

  /// Returns a [GoogleDriveService] if connected, null otherwise.
  Future<GoogleDriveService?> getService() async {
    final client = await getAuthClient();
    if (client == null) return null;
    return GoogleDriveService(client);
  }

  /// Returns an auto-refreshing HTTP client, or null if not connected.
  Future<http.Client?> getAuthClient() async {
    return await _auth.authClient();
  }

  /// Serialises and uploads a pattern to Drive.
  /// [fileId] null = create new file; non-null = update existing.
  /// Returns the Drive file ID of the uploaded file.
  Future<String?> uploadPattern(
    CrossStitchPattern pattern,
    String? driveFileId,
    String parentFolderId,
  ) async {
    state = state.copyWith(isSyncing: true);
    try {
      final service = await getService();
      if (!ref.mounted) return null;
      if (service == null) {
        state = state.copyWith(
          isSyncing: false,
          error: 'Not connected to Google Drive.',
        );
        return null;
      }

      final yamlString = FileService.toYamlString(pattern);
      final bytes = Uint8List.fromList(yamlString.codeUnits);
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final name = '$safeName.stitchx';

      final newId = await service.uploadFile(
        fileId: driveFileId,
        name: name,
        bytes: bytes,
        parentFolderId: parentFolderId,
      );

      if (!ref.mounted) return null;
      state = state.copyWith(isSyncing: false, error: null);
      return newId;
    } catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(
        isSyncing: false,
        error: 'Upload failed: $e',
      );
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final googleDriveProvider =
    NotifierProvider<DriveNotifier, DriveState>(DriveNotifier.new);
