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
- [x] Main window: app list, installed vs. available, outdated highlighted
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

## Milestone 6 — Distribution & polish

- [ ] Signed + notarized releases from CI
- [ ] Freshly updates itself via its own Sparkle appcast
- [ ] Homebrew cask (`brew install --cask freshly`)
- [x] Localization (Portuguese first), VoiceOver labels
