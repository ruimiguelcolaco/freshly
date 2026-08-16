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

- [x] Prepare the certificate-independent release plumbing: deterministic
      archives, version/tag validation, draft release assembly, appcast
      generation, least-privilege secret declarations, and a non-publishing
      dry run
- [ ] Signed + notarized releases from CI
- [ ] Freshly updates itself via its own Sparkle appcast (Sparkle integration,
      key, and signed-appcast pipeline are ready; activation awaits the first
      signed release)
- [ ] Homebrew cask (`brew install --cask freshly`; generated and validated by
      the release pipeline, submission awaits the first signed release)
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
- [x] Seed a representative starter catalog of verified app definitions
- [x] Let users request support for an unsupported app through a
      privacy-reviewed GitHub report
- [x] Electron (electron-updater/Squirrel.Mac) as a fifth source —
      detected via the bundled `app-update.yml`, artifact checksums
      verified

## Milestone 10 — Headless checks ✅

- [x] Read-only `freshly check --json` CLI over the same scanner and sources
- [x] Versioned JSON report with updates, failures, and unsupported count

## Milestone 11 — Actionable updates ✅

- [x] "Update Now" and "Update All" actions in update notifications
- [x] One-click updates from the menu bar without opening the main window

## Milestone 12 — User-controlled bug reports

- [x] Add "Report a Problem…" to update failures and update history
- [x] Prepare a focused diagnostic report locally, with a preview of exactly
      what will be shared and automatic redaction of paths, URL parameters,
      credentials, and device or user identifiers
- [x] Open a pre-filled GitHub Issue Form for the user to review and submit;
      never submit reports automatically or require a Freshly account
- [x] Offer email as an alternative for users without a GitHub account, and
      direct security reports to the private channel documented in
      `SECURITY.md`

## Milestone 13 — Failure-safe installs

- [x] During "Update All", collect running apps into one consent prompt;
      cancelling leaves them pending, while confirming quits, updates, and
      relaunches them without recording false failures
- [x] Reserve an app's install slot synchronously before starting an
      individual update, preventing duplicate pipelines for the same bundle
- [x] Treat rollback as a first-class operation: detect a failed restore,
      preserve the backup, and surface safe recovery instructions instead of
      hiding the secondary failure
- [x] Replace per-byte artifact streaming with `URLSession`'s native download
      task, rejecting both declared and received sizes above the safety cap
- [x] Add regression tests for successful and failed rollback
- [x] Add regression tests for duplicate requests and unknown-length downloads
      that cross the cap

## Milestone 14 — Testable app orchestration

- [x] Add an app-target unit-test harness with isolated storage and narrow
      seams for installer dispatch, URL hand-off, and running-app detection
- [x] Characterize individual and bulk update routing, quit confirmation,
      duplicate requests, and App Store hand-off at the app-store boundary
- [x] Add narrow seams for scan sessions, clocks and scheduling, and
      notifications
- [x] Characterize stale-scan cancellation and automatic-versus-manual
      notifications
- [x] Finish reducing `AppListStore` to a thin UI coordinator by moving only
      the remaining testable scan, scheduling, and install policies into
      `FreshlyCore`
- [x] Refuse unsupported future update-history schemas without rewriting or
      downgrading the user's history file

## Milestone 15 — Concurrency, performance & contributor feedback

- [x] Query an app's applicable sources concurrently under one shared global
      request limit, while preserving deterministic source precedence
- [x] Classify each streamed status into its UI section in one pass before
      sorting, instead of repeatedly filtering the full collection
- [x] Provide one local verification command that mirrors every CI gate and
      keeps DerivedData outside the iCloud-backed repository
- [x] Measure cold- and warm-cache CI timings; consolidate redundant SwiftPM
      compilation only when it reduces total feedback time
- [x] Keep the localization check warning-free under current and upcoming
      Python versions
