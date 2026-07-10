# Freshly

**Keep every app on your Mac fresh — from one place, for free.**

Freshly is a native, open-source macOS app that finds the applications
installed on your Mac, checks whether newer versions exist across multiple
update channels, and lets you update them from a single window.

> **Status: early development.** All four update sources work: Sparkle
> (verified in-place), the Mac App Store (handoff), Homebrew casks (via
> brew, or directly), and GitHub Releases via community
> [app definitions](docs/APP_DEFINITIONS.md). Next up: signed releases and
> distribution — see the [roadmap](ROADMAP.md).

## Why

MacUpdater, the reference tool of this category, was discontinued in January
2026 and its database dies at the end of the year. The remaining options are
paid, subscription-based, or cover only a fraction of update channels.
Freshly aims to be the tool the Mac community keeps for itself: fast, free,
private, and open.

## Principles

- **Fast** — scanning is concurrent and results stream into the UI as they
  arrive; you never wait for a full scan to finish before seeing something.
- **Private** — everything runs locally. Your list of installed apps never
  leaves your Mac. No accounts, no telemetry, no crash reporting. None.
- **Secure** — nothing is ever installed without passing code-signature,
  notarization, and Gatekeeper verification, and without the download's
  team identifier matching the installed app's.
- **Native** — Swift and SwiftUI, menu-bar first, at home on macOS.
- **Open** — MIT-licensed, built in the open, designed so the community can
  add update sources and app definitions.

## Update sources

| Source | Detect | Update | Status |
|---|---|---|---|
| Sparkle appcasts | ✓ shipped | ✓ shipped (verified, in place) | done |
| Mac App Store | ✓ shipped | redirect to App Store¹ | done |
| Homebrew casks | ✓ shipped | ✓ shipped (brew or direct) | done |
| GitHub Releases | ✓ shipped² | ✓ shipped | done |

¹ Since macOS Tahoe 26.1, third-party tools can no longer install Mac App
Store updates directly; Freshly hands you off to the App Store's Updates page.

² For apps mapped to a repository by a community
[app definition](docs/APP_DEFINITIONS.md) — guessing repos from bundles
would produce false matches.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Installing

Freshly is distributed outside the Mac App Store because an updater needs to
run un-sandboxed to modify other applications.

For now, build from source (below). Signed and notarized releases, plus a
Homebrew cask, will follow once the project reaches its first usable
milestone.

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

Contributions are welcome — from code to app definitions. Start with
[CONTRIBUTING.md](CONTRIBUTING.md) and the
[architecture overview](ARCHITECTURE.md). To teach Freshly about a new update
channel, see [docs/ADDING_A_SOURCE.md](docs/ADDING_A_SOURCE.md).

## License

[MIT](LICENSE)
