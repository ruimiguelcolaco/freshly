# Roadmap

Freshly ships in small, usable milestones. Each milestone ends in something
you can actually run. Order can shift based on community feedback — open a
discussion if you think a priority is wrong.

## Milestone 0 — Foundation ✅

- [x] Repository structure: thin app target + `FreshlyCore` package
- [x] Data model (`InstalledApp`, `ReleaseInfo`, `UpdateState`, `AppVersion`)
- [x] `UpdateSource` protocol and registry
- [x] Version comparator with test battery
- [x] Documentation set and CI

## Milestone 1 — See the problem ✅

- [x] Scanner: `/Applications` and `~/Applications`, streaming results
- [x] Signature info per app (signed / team ID)
- [x] Sparkle source: read `SUFeedURL`, fetch and parse appcasts
- [x] Main window: sidebar by update state, focused app list, installed vs.
      available, outdated highlighted
- [x] Menu bar extra with pending-updates badge
- [x] "Update" opens the download or the app itself (no in-place installs yet)

## Milestone 2 — Update for real ✅

- [x] Install pipeline: download → verify (EdDSA, codesign, team ID,
      Gatekeeper) → backup → replace → relaunch
- [x] "App Management" permission onboarding
- [x] Individual and bulk updates with progress
- [x] Skip-this-version per app; running-app handling

## Milestone 3 — Mac App Store ✅

- [x] Detect MAS installs via receipt; check versions via lookup API
- [x] Recognize Mac-compatible universal/Catalyst lookup results
- [x] Hand off to the App Store (direct installs are no longer possible
      for third parties since macOS Tahoe 26.1)

## Milestone 4 — Homebrew ✅

- [x] Version checks against the public cask index (no local brew required)
- [x] Install/upgrade via brew when present
- [x] Full conflict resolution with per-app source override

## Milestone 5 — GitHub + community definitions ✅

- [x] GitHub Releases source (ETag caching, optional token)
- [x] App definitions catalog, contributed via pull requests
- [x] Definition validation in CI

## Milestone 6 — Distribution & polish *(waiting on a Developer ID certificate)*

- [ ] Signed + notarized releases from CI
- [ ] Freshly updates itself via its own Sparkle appcast
- [ ] Homebrew cask (`brew install --cask freshly`)
- [x] Localization (Portuguese first), VoiceOver labels

## Milestone 7 — Live in the background ✅

- [x] Scheduled update checks anchored to the last completed scan
      (configurable interval, overdue-at-launch/wake, busy retry,
      backoff after total network failure, immediate retry when connectivity
      returns, offline deferral, retry persistence, tested policy)
- [x] Launch at login
- [x] Notifications when new updates appear
- [x] Last-scan cache: the window opens instantly with the previous state
- [x] Next automatic check visible in Settings and the menu bar
- [x] Settings window: check frequency, login item, notifications,
      GitHub token (stored in the keychain)

## Milestone 8 — Trust & transparency ✅

- [x] Inline release notes before updating
- [x] Local update history (what, when, from which source)
- [x] Localized, actionable engine error messages

## Milestone 9 — Coverage that grows on its own

- [x] Remote definitions catalog refresh (bulk, ETag-cached — new
      definitions reach users without an app release)
- [ ] Seed more verified app definitions (23 and growing)
- [x] Electron (electron-updater/Squirrel.Mac) as a fifth source —
      detected via the bundled `app-update.yml`, artifact checksums
      verified

## Milestone 10 — Headless checks ✅

- [x] Read-only `freshly check --json` CLI over the same scanner and sources
- [x] Versioned JSON report with updates, failures, and unsupported count

## Milestone 11 — Actionable updates ✅

- [x] "Update Now" and "Update All" actions in update notifications
- [x] One-click updates from the menu bar without opening the main window
