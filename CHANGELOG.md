# Changelog

All notable changes to Freshly are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- An app-target unit-test harness for install orchestration, with isolated
  storage and injected installer, URL-opening, and running-app adapters.
- Native sidebar navigation with live counts for available updates, all
  applications, up-to-date apps, skipped updates, and apps without an
  update source.
- A tested automatic-check policy covering manual mode, first launch,
  interval remainder, overdue checks, busy retries, and future clock
  corrections.
- Future update-history schemas are now left untouched instead of being
  rewritten by an older Freshly version.
- App-level scan tests now cover superseded-scan cancellation and ensure only
  automatic checks notify about newly available updates.
- A read-only `freshly check --json` command for scripts and CI, with a
  versioned report covering updates, source failures, and unsupported apps.
- Search to filter the app list.
- An "everything is fresh" summary — a checkmark and the time of the last
  check, also shown as the window subtitle — for when nothing needs updating.
- A per-row overflow menu, revealed on hover, for the row's actions.
- Download progress shown as a percentage during an install.
- One-click "Update All" and per-app "Update" actions in the menu bar;
  non-running apps begin updating without opening the main window.
- "Update Now" and "Update All" actions on new-update notifications.
- An outcome filter (all / installed / failed) in the update-history window.
- The app version and a repository link in Settings.
- App definitions for Rectangle, Stats, IINA, MonitorControl, and Ice.
- App definitions for Android Studio and the current ChatGPT bundle ID.
- Menu-bar-first behavior: the app lives in the menu bar with the pending
  update count worn as a badge, with a Settings toggle to also show the
  Dock icon.
- Electron (electron-updater) as a fifth update source: apps are detected
  via the bundled `app-update.yml`, and artifact checksums are verified
  against the manifest's published SHA-512 before install.
- Remote definitions catalog refresh: a generated, single-document pack
  (`definitions-catalog.json`) committed at the repository root and
  fetched from `main` on every scan — one bulk, ETag-cached request, so
  new definitions reach users without an app release and no service
  learns the user's app list. Remote definitions override bundled ones
  per bundle ID.
- Structured, localized engine error messages: engine errors are reported
  as data (`UpdateError.Reason`) and mapped to actionable, localized text
  in the app layer.
- Local update-history window: what updated, when, and from which
  source, with a clear-all action.
- Inline release notes shown before updating.
- Background life: scheduled update checks (hourly / every 6 hours /
  daily / manual) anchored to the last completed scan, optional launch at
  login, and a notification when an automatic check finds new updates.
  Overdue checks run at launch or wake, busy checks retry after five
  minutes, and a scan that fails entirely because of network or rate-limit
  errors retries with progressive backoff from five minutes up to six hours.
  Due automatic checks wait instead of issuing requests while macOS reports
  the device offline, and a pending retry runs immediately when connectivity
  returns. Manual refreshes never notify. Retry state survives app and system
  restarts, and the next check or retry is clearly identified in Settings
  and in the menu bar.
- Last-scan cache: the window and the menu bar badge open instantly with
  the previous state while a fresh scan runs underneath; refreshes update
  rows in place instead of clearing the list.
- Settings window: check frequency with the next automatic check shown
  inline, login item, notifications, and an optional GitHub token — stored
  in the keychain, never in preferences.
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

### Changed

- Consolidated the Homebrew, GitHub, and remote-definitions conditional-GET
  paths behind one private, ETag-aware disk cache. Malformed responses no
  longer replace the last good copy.
- Decluttered the main window: a sidebar replaces mixed collapsible sections
  with one focused status list at a time; the signature badge now flags only
  ad-hoc or unsigned apps rather than marking every notarized one; the bundle
  identifier moved to a hover tooltip; each update row shows its source and
  how recent it is; and opening the release notes is now the version
  transition itself.
- Faster scans and installs: the Homebrew cask index and the app-list sections
  are memoized, and the update artifact is memory-mapped instead of read fully
  into memory for each verification check.

### Fixed

- A failed in-place installation now verifies that the previous app was
  restored; if restoration also fails, Freshly preserves the backup and shows
  its location with manual recovery instructions.
- Repeated update requests for the same app can no longer start duplicate
  install pipelines before the first request becomes visible in the UI.
- Large update downloads no longer iterate the response byte by byte; they
  use `URLSession`'s native file-transfer path while preserving progress,
  cancellation, HTTP error handling, and the 4 GB safety cap.
- The main window now comes to the front when the app is launched or reopened
  from the menu bar.
- Ignore Homebrew's trailing build hash when comparing cask versions —
  it was read as part of the version and produced a phantom update.
- Retry disk image mounts more patiently instead of failing under load.

### Security

- Update downloads are size-capped (refused past 4 GB) so a compromised or
  broken feed cannot exhaust the disk before the verification pipeline runs.
