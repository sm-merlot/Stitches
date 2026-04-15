# Road to v1.0.0

Tracking everything needed before the first public release.

---

## Distribution & Signing

- [ ] **Windows installer** – build + package (note: not notarised/signed; document this in README)
- [ ] **Android production signing** – keystore, signing config, release build
- [ ] **Android Play Store publication** – store listing, screenshots, content rating, release
- [ ] **iOS production signing** – provisioning profiles, certificates
- [ ] **iOS CI build** – automated build pipeline for App Store distribution
- [ ] **macOS production signing** – Developer ID certificate for distribution outside Mac App Store
- [ ] **macOS notarisation** – separate step from signing; required to pass Gatekeeper on first launch
- [ ] **App Store publication (iOS + macOS)** – store listing, screenshots, review submission

---

## Infrastructure

- [ ] **Publish Google Cloud auth project** – move OAuth client from dev/test project to production
- [ ] **Update OAuth clients** – point all platforms to the production Cloud project credentials
- [ ] **Google Drive API quota / billing** – attach a billing account to the Cloud project (card on file, no expected charges) and set a budget alert (e.g. $1/month) in Billing → Budgets & alerts

---

## Quality & Testing

- [ ] **Add tests** – as described in README (unit + integration coverage for core editor logic) (see [test-coverage](./specs/test-coverage.md))

---

## Legal & Store Requirements

- [ ] **Privacy policy** – required by Apple, Google Play, and most jurisdictions; must cover Google Drive OAuth scope and any data handling
- [ ] **App store assets** – screenshots, preview/demo videos, descriptions, keywords, age ratings (for each platform: iOS, macOS, Android, Windows)

---

## Donations

- [ ] **Tip jar (iOS + macOS + Android)** – consumable IAPs via `in_app_purchase` package (e.g. 3 tiers: $0.99 / $2.99 / $4.99); define products in App Store Connect and Play Console
- [ ] **Donations link (Windows)** – direct link to GitHub Sponsors (no store restrictions on Windows)
- [ ] **Set up GitHub Sponsors** – bank/payout details + tax info in GitHub Settings → Billing → GitHub Sponsors; set up tiers
- [ ] **Add GitHub Sponsors link to README** – visible on the GitHub repo page

---

## Documentation

- [ ] **Rewrite README** – human-written prose; replace AI-generated sections (see PR: https://github.com/scme0/Stitches/pull/28)
- [ ] **Add video demos** to README
- [ ] **Document unsigned/unnotarised builds** – clearly note which platform builds are not signed/notarised (e.g. Windows installer) so users know what to expect from OS security warnings

---

## Known Issues / Feature Gaps to Resolve Pre-1.0

- [ ] **Anchor colour database** – toggle exists in Settings but always shows DMC colours (database not fully populated); either complete it, remove the toggle, or clearly mark as "coming soon" so it doesn't look like a bug
- [ ] **Windows file association** – register `.stitches` extension in the Windows installer (macOS, iOS, and Android already done)
- [ ] **PDF Import Improvements** – add support for PatternKeeper as a minimum. What else can we improve in this space? (see [pdf-import-research](./specs/pdf-import-research.md))
- [ ] **Add more PatternKeeper-style features** – progress stats (item 9) delivered via StitchOps; remaining items: B&W stitch mode, parking stitches, visual home screen, colour-sort options, session timer (see [ideas-from-pattern-progress-trackers](./specs/ideas-from-pattern-progress-trackers.md))

---

## Launch

- [ ] **Make repo public** – switch GitHub repository visibility from private to public

---

## Merge Queue

Branches that need to land before v1.0.0:

- `claude/add-stitch-stats-fgQj3` — StitchOps (progress analytics): per-pattern stats, workspace aggregate view with charts, pattern filter, Drive caching
