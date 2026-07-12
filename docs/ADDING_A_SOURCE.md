# Adding an Update Source

An *update source* teaches Freshly about one channel where newer app versions
are published — Sparkle appcasts, the Mac App Store, Homebrew casks,
electron-updater manifests, GitHub Releases, and whatever you add next.
This guide walks through contributing one.

## The contract

A source is a type in the `FreshlySources` target conforming to:

```swift
public protocol UpdateSource: Sendable {
    var id: SourceID { get }
    func applicability(for app: InstalledApp) -> SourceApplicability
    func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo?
}
```

The two methods have very different budgets:

- **`applicability(for:)` is cheap and offline.** It runs for every installed
  app on every scan. Decide from what the scanner already put in
  `InstalledApp` (plist values, install channels, paths) whether your source
  applies, and how strongly:
  - `.authoritative` — this is the channel the app is installed or updated
    through (e.g. a Mac App Store receipt, a declared Sparkle feed).
  - `.candidate` — you can report a version, but you are not the app's home
    channel (e.g. a cask exists for a manually installed app).
  - `.notApplicable` — this app is not yours; return this generously.
- **`latestRelease(for:)` may hit the network.** It runs concurrently with
  other checks, so it must be well-behaved (see rules below).

## Steps

1. **Add a case to `SourceID`** in
   `Packages/FreshlyCore/Sources/FreshlyModels/SourceID.swift`.
2. **Create your source** in
   `Packages/FreshlyCore/Sources/FreshlySources/<Name>Source.swift`.
3. **Register it** where the app assembles its `SourceRegistry`.
4. **Test it.** Network responses are fixtures (sample appcast XML, API JSON)
   checked into `Tests/FreshlyCoreTests/Fixtures/`; parsing and applicability
   logic must be covered without touching the network.
5. **Document it.** Add a row to the sources table in `README.md` and a
   paragraph to `ARCHITECTURE.md` describing when your source is
   authoritative vs. candidate.

## Rules for network behavior

These are invariants, not suggestions — see `ARCHITECTURE.md`:

- **Privacy.** Never send the user's app list anywhere. Prefer downloading a
  bulk index (like the Homebrew cask catalog) over per-app queries when the
  upstream service would otherwise learn which apps the user has. Per-app
  queries to the service that already distributes the app (its own appcast
  URL) are fine.
- **Cache.** Use conditional requests (`ETag` / `If-Modified-Since`) where
  the upstream supports them, and respect rate limits — assume the
  unauthenticated worst case.
- **Trust nothing.** Whatever your source reports is a *claim*. The install
  pipeline independently verifies signatures, team identifiers, and
  Gatekeeper assessment before anything is installed. Your source must still
  use HTTPS URLs exclusively and validate the payloads it parses.
- **Versions are `AppVersion`.** Never compare version strings yourself; if
  you meet a format `AppVersion` mishandles, add a failing test to
  `AppVersionTests` and fix the comparator.

## When a definition is enough

If the channel already has a source and you just need to map one app to it —
"this bundle ID lives in that GitHub repo" — you don't need code at all.
Contribute an app definition instead: see
[APP_DEFINITIONS.md](APP_DEFINITIONS.md).
