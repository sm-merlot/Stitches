import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../secrets.dart';

/// Singleton service for Google OAuth2 authentication via loopback redirect.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const _keyRefreshToken = 'google_refresh_token';
  static const _keyEmail = 'google_email';

  static const _driveScope = 'https://www.googleapis.com/auth/drive';

  ClientId get _clientId => ClientId(kGoogleClientId, kGoogleClientSecret);

  /// True when credentials were injected via --dart-define-from-file.
  bool get isConfigured =>
      kGoogleClientId.isNotEmpty && kGoogleClientSecret.isNotEmpty;

  /// Returns true if a refresh token is stored (i.e. the user is signed in).
  Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyRefreshToken);
    return token != null && token.isNotEmpty;
  }

  /// Returns the stored account identifier, or null if not signed in.
  Future<String?> accountEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  /// Runs the OAuth2 loopback flow to sign in.
  Future<void> signIn() async {
    if (!isConfigured) {
      throw Exception(
        'Google Drive credentials are not configured.\n'
        'Copy secrets.json.example → secrets.json, add your credentials, '
        'then run:\n  flutter run --dart-define-from-file=secrets.json',
      );
    }
    final client = http.Client();
    try {
      final credentials = await obtainAccessCredentialsViaUserConsent(
        _clientId,
        [_driveScope],
        client,
        (url) => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
      );

      final refreshToken = credentials.refreshToken;
      if (refreshToken == null) {
        throw Exception('No refresh token received from Google OAuth2 flow.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRefreshToken, refreshToken);

      // Try to extract email from idToken, fall back to 'connected'
      String email = 'connected';
      try {
        final idToken = credentials.idToken;
        if (idToken != null) {
          final parts = idToken.split('.');
          if (parts.length == 3) {
            // Decode the payload (base64url)
            String payload = parts[1];
            // Convert base64url to standard base64
            payload = payload.replaceAll('-', '+').replaceAll('_', '/');
            // Pad to multiple of 4
            while (payload.length % 4 != 0) {
              payload += '=';
            }
            final decoded = utf8.decode(base64Decode(payload));
            final emailMatch =
                RegExp(r'"email"\s*:\s*"([^"]+)"').firstMatch(decoded);
            if (emailMatch != null) {
              email = emailMatch.group(1)!;
            }
          }
        }
      } catch (_) {
        // Silently ignore email extraction errors
      }

      await prefs.setString(_keyEmail, email);
    } finally {
      client.close();
    }
  }

  /// Clears stored tokens.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyEmail);
  }

  /// Returns an auto-refreshing HTTP client, or null if not signed in.
  Future<http.Client?> authClient() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_keyRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) return null;

    // Use an expired access token — autoRefreshingClient will refresh on first use
    final expiredToken = AccessToken(
      'Bearer',
      'expired',
      DateTime.now().toUtc(),
    );
    final credentials = AccessCredentials(
      expiredToken,
      refreshToken,
      [_driveScope],
    );

    return autoRefreshingClient(_clientId, credentials, http.Client());
  }
}
