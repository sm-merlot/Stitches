// Google OAuth2 credentials are injected at build/run time via --dart-define-from-file.
// Never hardcode secrets here. See secrets.json.example for setup instructions.

// Desktop app OAuth client (macOS/Windows) — has client secret.
const String kGoogleDesktopClientId =
    String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID', defaultValue: '');
const String kGoogleDesktopClientSecret =
    String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET', defaultValue: '');

// iOS OAuth client (bundle ID verified by Google).
const String kGoogleIosClientId =
    String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

// Web OAuth client — used as serverClientId for google_sign_in on iOS.
const String kGoogleWebClientId =
    String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');
