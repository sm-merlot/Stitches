---
"stitches": patch
---

Fix Google Sign-In on Android

- Register the correct debug keystore SHA-1 (used by Flutter builds via `~/.config/.android`) as an Android OAuth client in GCP; the previously registered SHA-1 was never used by any Flutter build
- Remove explicit `serverClientId` from `GoogleSignIn.instance.initialize()` on Android — the SDK reads it automatically from `google-services.json`
- Restore silent sign-in (`attemptLightweightAuthentication`) on app startup
