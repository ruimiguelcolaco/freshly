# Changelog

All notable changes to Freshly are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Portuguese (pt-PT) localization via a String Catalog — the first
  translation; contributions for other languages only need to edit
  `Freshly/Localizable.xcstrings`.
- VoiceOver support: accessibility labels for the signature badges, update
  states, version transitions, and the menu bar extra; decorative app
  icons are hidden from the accessibility tree.
- Community app definitions: a Git-versioned catalog (`Definitions/`, one
  JSON file per bundle ID) that maps apps to update channels the scanner
  cannot derive on its own — a Sparkle feed declared only in code, a cask
  token for ambiguous app names, a GitHub repository. Shipped inside the
  app bundle, applied at scan time, validated in CI by
  `validate-definitions`, and licensed CC0.
- GitHub Releases source for apps mapped to a repository by a definition:
  latest-release checks with ETag caching (304s do not count against the
  rate limit), an optional token, and Mac-aware release-asset selection.
  Releases without a usable archive asset link to the release page instead.
- Homebrew source: apps are matched against the public cask index —
  downloaded in bulk and ETag-cached, so the Homebrew project never learns
  which apps are installed, and no local brew is needed to check versions.
  Casks installed through brew upgrade via `brew upgrade --cask`; manually
  installed apps matched to a cask update through Freshly's verified
  pipeline using the cask's artifact URL. Matching is conservative:
  ambiguous app names and Apple bundles are excluded, and freshness uses
  the cask's marketing version only.
- Per-app update-channel override ("Update Via" in the row's context
  menu) for apps claimed by several sources, persisted across scans.
- Mac App Store source: apps installed from the store (detected by their
  receipt) are checked against Apple's lookup API on the user's storefront.
  Store updates cannot be installed by third-party apps since macOS Tahoe
  26.1, so Freshly hands off to the app's App Store page ("Update All"
  opens the store's Updates page once). Store versions requiring a newer
  macOS than the running one are not reported.
- Deterministic source precedence: when an app is claimed by several
  authoritative sources, registration order decides — an app with both a
  store receipt and a Sparkle feed updates through the App Store.
- In-place update pipeline: download with progress → EdDSA verification
  against the app's pinned Sparkle key → extraction (zip, disk images,
  tarballs) → deep code-signature validation, identity and team
  continuity, downgrade protection, and Gatekeeper policy → backup →
  swap → optional relaunch. The old bundle is restored automatically when
  anything fails.
- Individual and bulk ("Update All") updates with live per-phase progress
  in the app list.
- Skip-this-version per app, persisted in Application Support.
- Running-app handling: updating a running app asks for consent, quits it,
  and relaunches it after the update.
- App Management permission onboarding: a clear alert with a direct link
  to System Settings when macOS blocks the first install.
- Application scanner: walks `/Applications` and `~/Applications`
  (one nesting level deep), reads bundle identity, versions, Sparkle feed,
  and Mac App Store receipts, and streams results as they are found.
- Code-signature reading for every scanned app (signing status, team ID,
  identity), shown in the UI as a per-app trust badge.
- Sparkle update source: fetches and parses appcasts (default channel,
  minimum-OS filtering, https enforcement) and reports the newest release.
- Update engine: concurrent per-app checks with bounded parallelism,
  streaming per-app statuses to the UI; freshness decided by build
  identifiers when available, marketing versions otherwise.
- Main window: live-updating app list grouped by state, with version
  transitions, release notes and download actions, and Finder integration.
- Menu bar extra with a pending-updates count and quick actions.
- Project foundation: thin app target plus the `FreshlyCore` Swift package
  (`FreshlyModels`, `FreshlyScanner`, `FreshlySources`, `FreshlyEngine`,
  `FreshlyInstaller`, `FreshlySecurity`).
- Core data model: `InstalledApp`, `ReleaseInfo`, `UpdateState`,
  `AppUpdateStatus`, `SignatureInfo`.
- `AppVersion` comparator with Sparkle-compatible semantics and a test
  battery covering real-world version string formats.
- `UpdateSource` protocol and `SourceRegistry` — the extension point for
  update channels.
- Continuous integration: package tests and app build on every push and
  pull request.
