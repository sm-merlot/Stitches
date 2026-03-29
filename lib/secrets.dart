// Google OAuth2 credentials are injected at build/run time via --dart-define-from-file.
// Never hardcode secrets here. See secrets.json.example for setup instructions.

// Desktop app OAuth client (macOS/Windows) — has client secret.
const String kGoogleClientId =
    String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: '');
const String kGoogleClientSecret =
    String.fromEnvironment('GOOGLE_CLIENT_SECRET', defaultValue: '');

// iOS OAuth client (bundle ID verified by Google).
const String kGoogleIosClientId =
    String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

// Android OAuth client (SHA-1 + package name verified by Google).
// Used for PKCE browser flow — no client secret required.
const String kGoogleAndroidClientId =
    String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID', defaultValue: '');

// Web OAuth client — used as serverClientId for google_sign_in on iOS.
const String kGoogleWebClientId =
    String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');
