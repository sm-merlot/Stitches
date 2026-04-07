# Road to v1.0.0

Tracking everything needed before the first public release.

---

## Distribution & Signing

- [ ] **Windows installer** — build + package (note: not notarised/signed; document this in README)
- [ ] **Android production signing** — keystore, signing config, release build
- [ ] **Android Play Store publication** — store listing, screenshots, content rating, release
- [ ] **iOS production signing** — provisioning profiles, certificates
- [ ] **iOS CI build** — automated build pipeline for App Store distribution
- [ ] **macOS production signing** — Developer ID certificate for distribution outside Mac App Store
- [ ] **macOS notarisation** — separate step from signing; required to pass Gatekeeper on first launch
- [ ] **App Store publication (iOS + macOS)** — store listing, screenshots, review submission

---

## Infrastructure

- [ ] **Publish Google Cloud auth project** — move OAuth client from dev/test project to production
- [ ] **Update OAuth clients** — point all platforms to the production Cloud project credentials
- [ ] **Google Drive API quota / billing** — set appropriate quotas, enable billing alerts before public traffic hits

---

## Quality & Testing

- [ ] **Add tests** — as described in README (unit + integration coverage for core editor logic)
- [ ] **Strip debug logging** — remove temporary `[DriveRefresh]` and `[Canvas]` console prints added during Drive refresh bug investigation (branch: `scme0/fix/drive-refresh-state-reset`)

---

## Legal & Store Requirements

- [ ] **Privacy policy** — required by Apple, Google Play, and most jurisdictions; must cover Google Drive OAuth scope and any data handling
- [ ] **App store assets** — screenshots, preview/demo videos, descriptions, keywords, age ratings (for each platform: iOS, macOS, Android, Windows)

---

## Documentation

- [ ] **Rewrite README** — human-written prose; replace AI-generated sections
- [ ] **Add video demos** to README
- [ ] **Document unsigned/unnotarised builds** — clearly note which platform builds are not signed/notarised (e.g. Windows installer) so users know what to expect from OS security warnings

---

## Known Issues / Feature Gaps to Resolve Pre-1.0

- [ ] **Anchor colour database** — toggle exists in Settings but always shows DMC colours (database not fully populated); either complete it, remove the toggle, or clearly mark as "coming soon" so it doesn't look like a bug
- [ ] **Phase 4 gaps** — PDF Scanner and Proton Drive are not yet started; confirm whether these are post-1.0 or blocking (see `docs/phase4.md`)
- [ ] **File association** — `.stitches` files should open the app directly from Finder / File Explorer when the app is not already running

---

## Merge Queue

Branches that need to land before v1.0.0:

- [ ] `scme0/fix/drive-refresh-state-reset` — fixes canvas position / mode / page resetting after Google Drive background refresh (pending debug log strip + PR)
