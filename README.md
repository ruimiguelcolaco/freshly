<div align="center">

# Freshly

**Keep every app on your Mac fresh — from one place, for free.**

[![CI](https://github.com/ruimiguelcolaco/freshly/actions/workflows/ci.yml/badge.svg)](https://github.com/ruimiguelcolaco/freshly/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)

Freshly finds the apps installed on your Mac, checks five update channels
for newer versions, and installs updates after verifying every byte —
from a single window, or straight from your menu bar.

<!-- screenshot slot: uncomment once docs/assets/screenshot.png lands
<img src="docs/assets/screenshot.png" alt="Freshly's main window showing available updates" width="720">
-->

</div>

> **Status: early development.** All five update sources work: Sparkle
> (verified in-place), the Mac App Store (handoff), Homebrew casks (via
> brew, or directly), Electron apps through their own update manifests,
> and GitHub Releases via community
> [app definitions](docs/APP_DEFINITIONS.md) — plus inline release notes,
> a local update history, and a definitions catalog that refreshes itself
> between app releases. Next up: signed releases and distribution — see
> the [roadmap](ROADMAP.md).

## Why

MacUpdater, the reference tool of this category, was discontinued in
January 2026 and its database dies at the end of the year. The remaining
options are paid, subscription-based, or cover only a fraction of update
channels. Freshly aims to be the tool the Mac community keeps for itself:
fast, free, private, and open.

## What makes it different

**Fast.** Scanning is concurrent and results stream into the UI as they
are found — the first apps appear in milliseconds, and a full scan with
live version checks across ~70 apps finishes in about a second.

**Private.** Everything runs locally. Your list of installed apps never
leaves your Mac: sources that support it are checked through bulk catalog
downloads (the whole Homebrew cask index, the whole definitions catalog),
so no service can reconstruct what you have installed. No accounts, no
telemetry, no crash reporting. None.

**Secure.** Nothing is installed until it passes a verification gauntlet:
EdDSA signature against the app's own pinned Sparkle key, the checksum
its publisher declared (Electron update manifests), deep
code-signature validation, bundle-identity and developer-team continuity,
downgrade protection, and Gatekeeper assessment. The old version is kept
as a backup and restored automatically if anything fails.

**Native.** Swift 6 and SwiftUI, menu-bar first with a pending-updates
badge, dark mode, at home on macOS — not another 400 MB wrapper around a
web page.

**Open.** MIT-licensed, built in the open. The community extends what
Freshly knows through [app definitions](docs/APP_DEFINITIONS.md) — plain
JSON files reviewed in public, validated in CI, and licensed CC0 so any
other tool can reuse them.

## Update sources

| Source | Detect | Update |
|---|---|---|
| Sparkle appcasts | ✓ | ✓ verified, in place |
| Mac App Store | ✓ | redirect to App Store¹ |
| Homebrew casks | ✓ | ✓ via brew, or directly |
| Electron (electron-updater) | ✓ | ✓ verified, in place |
| GitHub Releases | ✓² | ✓ verified, in place |

¹ Since macOS Tahoe 26.1, third-party tools can no longer install Mac App
Store updates directly; Freshly hands you off to the App Store.

² For apps mapped to a repository by a community
[app definition](docs/APP_DEFINITIONS.md) — guessing repos from bundles
would produce false matches.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Installing

Freshly is distributed outside the Mac App Store because an updater needs
to run un-sandboxed to modify other applications.

For now, build from source (below). Signed and notarized releases, plus a
Homebrew cask, will follow once the project reaches its first tagged
release.

## Building from source

```sh
git clone https://github.com/ruimiguelcolaco/freshly.git
cd freshly
open Freshly.xcodeproj   # requires Xcode 26 or later
```

Run the core library tests without Xcode:

```sh
swift test --package-path Packages/FreshlyCore
```

## Contributing

The easiest way to help — no Swift required — is teaching Freshly about
apps it cannot match on its own: a small JSON
[app definition](docs/APP_DEFINITIONS.md) reviewed like any pull request.

For code contributions, start with [CONTRIBUTING.md](CONTRIBUTING.md) and
the [architecture overview](ARCHITECTURE.md). To add a whole new update
channel, see [docs/ADDING_A_SOURCE.md](docs/ADDING_A_SOURCE.md).

Security issues: please report privately — see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) — app definitions are
[CC0](https://creativecommons.org/publicdomain/zero/1.0/).
