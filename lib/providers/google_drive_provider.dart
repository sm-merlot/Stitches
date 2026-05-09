import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/pattern.dart';
import '../services/file_service.dart';
import '../services/drive/google_auth_service.dart';
import '../services/drive/google_drive_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum DriveStatus { disconnected, connecting, connected, error }

// ---------------------------------------------------------------------------
// Auth-revocation intercepting HTTP client
// ---------------------------------------------------------------------------

/// Wraps an auth HTTP client and fires [onRevoked] if any request returns a
/// 401 or throws an auth-related exception (e.g. expired refresh token).
/// All requests are still passed through / rethrown so callers handle them
/// normally.
class _RevokeDetectingClient extends http.BaseClient {
  final http.Client _inner;
  final void Function() _onRevoked;

  _RevokeDetectingClient(this._inner, this._onRevoked);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      if (response.statusCode == 401) _onRevoked();
      return response;
    } catch (e) {
      if (_isAuthException(e)) _onRevoked();
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  static bool _isAuthException(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('invalid_grant') ||
        s.contains('token has been expired') ||
        s.contains('token has been revoked') ||
        s.contains('invalidcredentials') ||
        s.contains('authexception');
  }
}

@immutable
class DriveState {
  final DriveStatus status;
  final String? email;
  final bool isSyncing;
  final String? error;
  /// False when the app was built without --dart-define-from-file credentials.
  final bool isConfigured;
  /// True for one frame after auth is revoked mid-session (token expired /
  /// access revoked). Consumers should show a dialog then call
  /// [DriveNotifier.clearRevokedFlag].
  final bool wasRevoked;

  const DriveState({
    this.status = DriveStatus.disconnected,
    this.email,
    this.isSyncing = false,
    this.error,
    this.isConfigured = false,
    this.wasRevoked = false,
  });

  DriveState copyWith({
    DriveStatus? status,
    Object? email = _sentinel,
    bool? isSyncing,
    Object? error = _sentinel,
    bool? isConfigured,
    bool? wasRevoked,
  }) {
    return DriveState(
      status: status ?? this.status,
      email: email == _sentinel ? this.email : email as String?,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error == _sentinel ? this.error : error as String?,
      isConfigured: isConfigured ?? this.isConfigured,
      wasRevoked: wasRevoked ?? this.wasRevoked,
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
    // Set isConfigured immediately (sync check) so the Drive section in the
    // Open modal appears on first open even before checkConnection completes.
    Future.microtask(checkConnection);
    return DriveState(isConfigured: _auth.isConfigured);
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
        isConfigured: configured,
      );
    }
  }

  /// Launches the OAuth2 sign-in flow.
  Future<void> connect() async {
    state = state.copyWith(status: DriveStatus.connecting, error: null);
    try {
      await _auth.signIn();
      if (!ref.mounted) return;
      if (state.status != DriveStatus.connecting) return; // cancelled
      // Re-check connection so all state (email, status, isConfigured) is
      // refreshed from the auth service after a successful sign-in.
      await checkConnection();
    } catch (e) {
      if (!ref.mounted) return;
      if (state.status != DriveStatus.connecting) return; // cancelled
      state = state.copyWith(
        status: DriveStatus.error,
        error: 'Sign-in failed: $e',
      );
    }
  }

  /// Cancels an in-progress sign-in, resetting state to disconnected.
  /// The underlying OAuth future is orphaned but guarded — it will no-op
  /// if it eventually completes.
  void cancelConnect() {
    if (state.status == DriveStatus.connecting) {
      state = state.copyWith(status: DriveStatus.disconnected, error: null);
    }
  }

  /// Signs out and clears tokens.
  Future<void> disconnect() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Sign-out failed (e.g. network error) — clear local state regardless.
    }
    // Preserve isConfigured so the sign-in button remains visible.
    state = DriveState(isConfigured: _auth.isConfigured);
  }

  /// Called when a Drive request detects an auth failure mid-session
  /// (e.g. refresh token revoked). Signs out locally and sets [wasRevoked]
  /// so the UI can show a dialog. No-op if already disconnected.
  void _handleRevoked() {
    if (state.status != DriveStatus.connected) return;
    _auth.signOut().ignore();
    state = DriveState(
      isConfigured: _auth.isConfigured,
      wasRevoked: true,
    );
  }

  /// Clears the [wasRevoked] flag after the UI has shown its dialog.
  void clearRevokedFlag() {
    state = state.copyWith(wasRevoked: false);
  }

  /// Returns a [GoogleDriveService] if connected, null otherwise.
  Future<GoogleDriveService?> getService() async {
    final client = await getAuthClient();
    if (client == null) return null;
    return GoogleDriveService(client);
  }

  /// Returns an auto-refreshing HTTP client wrapped with revocation detection,
  /// or null if not connected.
  Future<http.Client?> getAuthClient() async {
    final inner = await _auth.authClient();
    if (inner == null) return null;
    return _RevokeDetectingClient(inner, _handleRevoked);
  }

  /// Serialises and uploads a pattern to Drive.
  /// [fileId] null = create new file; non-null = update existing.
  /// Pass [compress] = true (default) for gzip compression, false for plain UTF-8 text.
  /// Returns the Drive file ID of the uploaded file.
  Future<String?> uploadPattern(
    CrossStitchPattern pattern,
    String? driveFileId,
    String parentFolderId,
      {bool compress = true}
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
      final bytes =
      Uint8List.fromList(compress ? gzip.encode(utf8.encode(yamlString)) : utf8.encode(yamlString));
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final name = '$safeName.stitches';

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

  /// Upload arbitrary bytes to Drive as a new file (always creates).
  /// Returns the new Drive file ID, or null on failure.
  Future<String?> uploadRawFile({
    required String name,
    required Uint8List bytes,
    required String parentFolderId,
  }) async {
    state = state.copyWith(isSyncing: true);
    try {
      final service = await getService();
      if (!ref.mounted) return null;
      if (service == null) {
        state = state.copyWith(isSyncing: false, error: 'Not connected to Google Drive.');
        return null;
      }
      final id = await service.uploadFile(
        fileId: null,
        name: name,
        bytes: bytes,
        parentFolderId: parentFolderId,
      );
      if (!ref.mounted) return null;
      state = state.copyWith(isSyncing: false, error: null);
      return id;
    } catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(isSyncing: false, error: 'Upload failed: $e');
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final googleDriveProvider =
    NotifierProvider<DriveNotifier, DriveState>(DriveNotifier.new);
