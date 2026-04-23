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

- [x] **Add tests** – as described in README (unit + integration coverage for core editor logic) (see [test-coverage pr](https://github.com/scme0/Stitches/pull/73))

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
- [x] **Windows file association** – self-registers `.stitches` → `StitchesFile` under `HKCU\Software\Classes` at launch (no admin required); file path passed via `com.scme0.stitches/file_open` MethodChannel matching macOS behaviour
- [ ] **PDF Import Improvements** – add support for PatternKeeper as a minimum. What else can we improve in this space? (see [pdf-import-research](./specs/pdf-import-research.md))
- [ ] **Remaining PatternKeeper-style features** – parking stitches, key view, rescan/adjust grid, long-press options (see [ideas-from-pattern-progress-trackers](./specs/ideas-from-pattern-progress-trackers.md) — items 1, 3, 7, 8, 10)

---

## Recently Shipped (reference)

Features landed since initial planning — no longer blockers, kept here for context:

- ✅ Three-mode architecture: View / Edit / Stitch (#36)
- ✅ File format v2 with progress tracking (#35)
- ✅ Stitch progress tracking with frogging support (#42)
- ✅ StitchOps analytics: per-pattern + workspace aggregate stats, charts, pattern filter (#64)
- ✅ StitchOps time tracking: session timer, time-per-pattern, time breakdown charts (#68)
- ✅ B&W stitch mode — unmarked stitches show B&W symbol, done cells fill with colour (#53); realistic mode removed (#54)
- ✅ Page colour filter in stitch mode — filter canvas to show only stitches matching the current page colour (#72)
- ✅ 2D floodfill + vertical column detection for fuzzy PDF page edges (#74)
- ✅ Selection drag size tooltip — shows W×H stitch count while rubber-banding a selection (#71)
- ✅ GIF export with explicit stitch list from JSON file (#67)
- ✅ Unified Share/Export with all formats (#39)
- ✅ Home screen uplift: thumbnails, unified pickers, workspace improvements (#40)
- ✅ Page mode in stitch view (#34)
- ✅ Colour list sort options: by ID, by count, completed last (#52)
- ✅ Frog terminology (#51)
- ✅ Focus-mode outline for near-grey threads (#21)
- ✅ PDF export improvements (#20)
- ✅ Materials list / skein calculator (#19)
- ✅ Open `.stitches` from Finder, Files app, and Android file managers (#33)

---

## Launch

- [ ] **Make repo public** – switch GitHub repository visibility from private to public

---

## Merge Queue

Branches that need to land before v1.0.0:

_None currently._
