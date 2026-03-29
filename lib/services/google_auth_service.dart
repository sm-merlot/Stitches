import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../secrets.dart';

/// Singleton service for Google OAuth2 authentication.
///
/// macOS/Windows: loopback redirect via googleapis_auth (Desktop OAuth client).
/// iOS/Android:   google_sign_in v6 — traditional GoogleSignInClient, no Credential Manager.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const _keyRefreshToken = 'google_refresh_token';
  static const _keyEmail = 'google_email';
  static const _driveScope = 'https://www.googleapis.com/auth/drive';

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // ---------------------------------------------------------------------------
  // Mobile — google_sign_in v6
  // ---------------------------------------------------------------------------

  GoogleSignIn? _googleSignIn;

  GoogleSignIn get _signIn {
    _googleSignIn ??= GoogleSignIn(
      scopes: [_driveScope],
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? kGoogleIosClientId
          : null,
      // Android: web client ID required so play-services-auth can issue tokens
      // without google-services.json. Not needed on iOS (clientId covers it).
      serverClientId: defaultTargetPlatform == TargetPlatform.android
          ? kGoogleWebClientId
          : null,
    );
    return _googleSignIn!;
  }

  // ---------------------------------------------------------------------------
  // Desktop — googleapis_auth
  // ---------------------------------------------------------------------------

  ClientId get _desktopClientId =>
      ClientId(kGoogleClientId, kGoogleClientSecret);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  bool get isConfigured {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return kGoogleIosClientId.isNotEmpty;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return true; // Android verified via package name + SHA-1 at Cloud Console
    }
    return kGoogleClientId.isNotEmpty && kGoogleClientSecret.isNotEmpty;
  }

  Future<bool> isSignedIn() async {
    if (_isMobile) return _signIn.isSignedIn();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyRefreshToken);
    return token != null && token.isNotEmpty;
  }

  Future<String?> accountEmail() async {
    if (_isMobile) {
      final account =
          _signIn.currentUser ?? await _signIn.signInSilently();
      return account?.email;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  Future<void> signIn() async {
    if (!isConfigured) {
      throw Exception(
        'Google Drive credentials are not configured.\n'
        'Copy secrets.json.example → secrets.json, add your credentials, '
        'then run:\n  flutter run --dart-define-from-file=secrets.json',
      );
    }
    if (_isMobile) {
      final account = await _signIn.signIn();
      if (account == null) throw Exception('Sign-in cancelled.');
    } else {
      await _signInDesktop();
    }
  }

  Future<void> signOut() async {
    if (_isMobile) {
      await _signIn.signOut();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyRefreshToken);
      await prefs.remove(_keyEmail);
    }
  }

  Future<http.Client?> authClient() async {
    if (_isMobile) {
      final account =
          _signIn.currentUser ?? await _signIn.signInSilently();
      if (account == null) return null;
      return _GoogleSignInV6Client(account);
    }
    return _desktopAuthClient();
  }

  // ---------------------------------------------------------------------------
  // Desktop
  // ---------------------------------------------------------------------------

  Future<void> _signInDesktop() async {
    final client = http.Client();
    try {
      final credentials = await obtainAccessCredentialsViaUserConsent(
        _desktopClientId,
        [_driveScope],
        client,
        (url) => launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication),
      );
      await _saveDesktopCredentials(
        refreshToken: credentials.refreshToken,
        idToken: credentials.idToken,
      );
    } finally {
      client.close();
    }
  }

  Future<http.Client?> _desktopAuthClient() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_keyRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final expiredToken =
        AccessToken('Bearer', 'expired', DateTime.now().toUtc());
    final credentials =
        AccessCredentials(expiredToken, refreshToken, [_driveScope]);
    return autoRefreshingClient(_desktopClientId, credentials, http.Client());
  }

  Future<void> _saveDesktopCredentials({
    required String? refreshToken,
    required String? idToken,
  }) async {
    if (refreshToken == null) {
      throw Exception(
        'No refresh token received. Try revoking app access at '
        'myaccount.google.com/permissions and signing in again.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRefreshToken, refreshToken);
    await prefs.setString(_keyEmail, _extractEmail(idToken) ?? 'connected');
  }

  String? _extractEmail(String? idToken) {
    if (idToken == null) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length != 3) return null;
      String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Decode(payload));
      return RegExp(r'"email"\s*:\s*"([^"]+)"').firstMatch(decoded)?.group(1);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// HTTP client for mobile — delegates to google_sign_in v6 authHeaders
// ---------------------------------------------------------------------------

class _GoogleSignInV6Client extends http.BaseClient {
  final GoogleSignInAccount _account;
  final http.Client _inner = http.Client();

  _GoogleSignInV6Client(this._account);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _account.authHeaders;
    request.headers.addAll(headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
