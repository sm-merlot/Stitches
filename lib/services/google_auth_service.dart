import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../secrets.dart';

/// Singleton service for Google OAuth2 authentication.
///
/// Desktop (macOS/Windows/Linux): loopback redirect via googleapis_auth.
/// Mobile (Android/iOS): custom-scheme redirect via flutter_web_auth_2.
///
/// The custom-scheme redirect URI `stitchx://oauth2redirect` must be added
/// to the authorized redirect URIs in your Google Cloud Console OAuth client.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const _keyRefreshToken = 'google_refresh_token';
  static const _keyEmail = 'google_email';

  static const _driveScope = 'https://www.googleapis.com/auth/drive';

  // Used for the mobile OAuth redirect — must be registered in Google Cloud Console.
  static const _mobileRedirectScheme = 'stitchx';
  static const _mobileRedirectUri = '$_mobileRedirectScheme://oauth2redirect';

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

  /// Runs the OAuth2 sign-in flow appropriate for the current platform.
  Future<void> signIn() async {
    if (!isConfigured) {
      throw Exception(
        'Google Drive credentials are not configured.\n'
        'Copy secrets.json.example → secrets.json, add your credentials, '
        'then run:\n  flutter run --dart-define-from-file=secrets.json',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await _signInMobile();
    } else {
      await _signInDesktop();
    }
  }

  /// Desktop: loopback redirect — googleapis_auth opens a localhost server.
  Future<void> _signInDesktop() async {
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
      await _saveCredentials(
        refreshToken: credentials.refreshToken,
        idToken: credentials.idToken,
      );
    } finally {
      client.close();
    }
  }

  /// Mobile: custom-scheme redirect via Chrome Custom Tabs / ASWebAuthenticationSession.
  Future<void> _signInMobile() async {
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/auth', {
      'client_id': kGoogleClientId,
      'redirect_uri': _mobileRedirectUri,
      'response_type': 'code',
      'scope': _driveScope,
      'access_type': 'offline',
      'prompt': 'consent',
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _mobileRedirectScheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) {
      throw Exception('No auth code received from Google.');
    }

    // Exchange authorization code for tokens.
    final tokenResponse = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': kGoogleClientId,
        'client_secret': kGoogleClientSecret,
        'code': code,
        'redirect_uri': _mobileRedirectUri,
        'grant_type': 'authorization_code',
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception(
        'Token exchange failed (${tokenResponse.statusCode}): ${tokenResponse.body}',
      );
    }

    final json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    await _saveCredentials(
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
    );
  }

  Future<void> _saveCredentials({
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
      String payload = parts[1]
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Decode(payload));
      return RegExp(r'"email"\s*:\s*"([^"]+)"').firstMatch(decoded)?.group(1);
    } catch (_) {
      return null;
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
