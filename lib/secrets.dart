// Google OAuth2 credentials are injected at build/run time via --dart-define-from-file.
// Never hardcode secrets here. See secrets.json.example for setup instructions.
const String kGoogleClientId =
    String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: '');
const String kGoogleClientSecret =
    String.fromEnvironment('GOOGLE_CLIENT_SECRET', defaultValue: '');
