# Architecture

This document is the source of truth for how Freshly is put together. If a
change contradicts something here, update this file in the same pull request.

## Layout

```
Freshly/
├── Freshly.xcodeproj        Xcode project (app target only)
├── Freshly/                 SwiftUI app: windows, menu bar extra, settings
└── Packages/
    └── FreshlyCore/         Swift package — all logic lives here
        ├── FreshlyModels    shared data model (no dependencies)
        ├── FreshlyScanner   discovers installed apps
        ├── FreshlySources   update source engine
        ├── FreshlyEngine    orchestration: scan → check → stream statuses
        ├── FreshlyInstaller download, verify, install pipeline
        └── FreshlySecurity  code signing / notarization / Gatekeeper checks
```

The app target is deliberately thin: UI and app lifecycle only. Everything
testable lives in `FreshlyCore`, which builds and tests with plain
`swift test` — no signing, no Xcode UI, contributor-friendly.

The app is **not sandboxed** (an updater must modify other apps' bundles) but
ships with the hardened runtime enabled. It is distributed outside the Mac
App Store, signed with Developer ID and notarized.

## Data flow

```
AppScanner ──InstalledApp──▶ UpdateCoordinator ──AppUpdateStatus──▶ UI store
                                   │  ▲
                     TaskGroup     ▼  │ ReleaseInfo
                              SourceRegistry
                        (Sparkle, MAS, Homebrew, GitHub…)
```

1. `AppScanner` walks `/Applications` and `~/Applications`, reads each
   bundle's `Info.plist`, and emits `InstalledApp` values through an
   `AsyncStream`. The UI renders apps as they are found — perceived speed is
   an architectural property, not a UI trick.
2. For each discovered app, the coordinator (an actor) asks the
   `SourceRegistry` which sources apply, then queries them concurrently in a
   `TaskGroup` with a bounded width (~8–12 network tasks).
3. Results merge into an `AppUpdateStatus` per app, streamed to an
   `@Observable` store that the SwiftUI views and the menu bar badge observe.
4. Updating goes through `FreshlyInstaller`: download → verification
   (`FreshlySecurity`) → backup → replace → relaunch.

## The update source engine

Every update channel implements one protocol (`FreshlySources`):

```swift
public protocol UpdateSource: Sendable {
    var id: SourceID { get }
    func applicability(for app: InstalledApp) -> SourceApplicability
    func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo?
}
```

`applicability(for:)` is cheap and offline — it inspects what the scanner
found on disk:

| Source | Authoritative when | Candidate when |
|---|---|---|
| Sparkle | `SUFeedURL` in `Info.plist` | feed known via app definition |
| Mac App Store | `_MASReceipt` present in the bundle | — |
| Homebrew | installed via a cask (brew manifest) | a cask exists for the bundle ID |
| GitHub | — | an app definition maps bundle ID → repo |

**Conflict resolution**: the channel the app was installed through wins.
The resolver picks the first authoritative source as `best` (ties break by
registration order: Mac App Store, then Sparkle, then Homebrew); everything
else is kept as `alternatives` and shown in the UI as alternative channels.
The user can override the preferred channel per app ("Update Via" in the
row's context menu), persisted in Application Support.

**Homebrew matching is deliberately conservative** — a wrong match nags the
user about a different app's updates. App-artifact names claimed by more
than one cask are ambiguous and excluded; Apple bundle IDs (including
Safari Web Apps) never match; freshness compares the cask's marketing
version only, because the suffix after the comma in `"2.2.1,5287…"` is
brew's artifact bookkeeping, not the app's `CFBundleVersion`. Casks
installed through brew upgrade through `brew upgrade --cask` (keeping its
bookkeeping consistent); manually installed apps matched to a cask update
through Freshly's own verified pipeline using the cask's artifact URL.

**Version comparison** uses `AppVersion` (Sparkle-compatible semantics,
tolerant of `1.2.3 (4567)`, `2.1b5`, and Homebrew's `1.2.3,4567`). Every
false "update available" starts with a version comparison bug — new edge
cases belong in `AppVersionTests` first.

**Freshness** is decided by `ReleaseInfo.isNewer(than:)`: when both the
release and the installed app carry a build identifier (`sparkle:version` ↔
`CFBundleVersion`), builds decide — feeds often decorate the marketing
version (`1.39.0 (83141)`) in ways that would falsely read as newer.
Marketing versions are the fallback.

**Release notes** shown before updating come from `ReleaseNotesLoader`
(`FreshlySources`): notes embedded in the source's response when present
(appcast `<description>` HTML, GitHub's Markdown body, the App Store's
plain text), Sparkle's `releaseNotesLink` document fetched on demand
otherwise. The loader only tags content with its markup; rendering is the
app layer's job.

### Security invariants (installer)

Nothing touches the installed bundle until every applicable check passes,
in this order:

1. **EdDSA** — when the installed app pins `SUPublicEDKey` and the update
   comes from its Sparkle feed, the artifact's `sparkle:edSignature` must
   verify against it; a Sparkle release without one is a hard failure.
   This is Sparkle's trust anchor. Artifacts from other channels (Homebrew
   cask URLs, GitHub releases) legitimately carry no signature — the pin
   does not block them; they must pass Gatekeeper instead (rule 5). Some
   apps pin a key without declaring a feed (AltTab configures its feed in
   code), so this distinction matters in practice.
2. **Deep code-signature validation** of the extracted bundle (all
   architectures, nested code, strict rules) — unsigned or tampered
   bundles fail.
3. **Identity continuity** — the bundle identifier must not change, and
   when the installed app has a team identifier, the update must be signed
   by the same team.
4. **Downgrade protection** — the extracted bundle must actually be newer
   than what is installed (builds compared when available), regardless of
   what the feed claimed.
5. **Gatekeeper** (`spctl`) — required whenever the download's EdDSA
   signature could not be verified. EdDSA-verified team-matched updates
   follow Sparkle's own trust model and skip the notarization requirement.

The old bundle is moved aside, not deleted, and restored automatically if
the swap fails. Running apps are never touched without explicit consent
(quit & relaunch is a user choice). Installer packages (`.pkg`) are refused.

### Privacy invariants

- No server-side component, ever. Sources talk directly to their upstream
  (appcast URL, Apple's lookup API, `formulae.brew.sh`, GitHub API).
- Prefer bulk catalog downloads over per-app queries so no service can
  reconstruct the user's app list (the Homebrew source downloads the entire
  cask index; the definitions catalog is fetched whole).
- No telemetry and no crash reporting of any kind.

## App definitions

A Git-versioned JSON catalog (`Definitions/`, one file per bundle ID)
mapping apps to facts the scanner cannot derive on its own: a cask token
when name matching fails or is ambiguous, a GitHub repository, a Sparkle
feed the app only declares in code, or a version-key quirk. See
`docs/APP_DEFINITIONS.md` for the schema and contribution flow; definitions
are licensed CC0.

The catalog ships inside the app bundle as a resource. At scan time an
`EnrichingDiscoverer` applies definitions to each discovered app before the
sources see it (never overriding what the app itself declares), the
Homebrew source consumes cask pins, and the GitHub source only checks apps
a definition maps to a repository. `validate-definitions` (an executable in
`FreshlyCore`) enforces the schema; CI runs it on every pull request.

Definitions cannot weaken the install pipeline: whatever they point at
still passes the installer's verification gauntlet.

## Concurrency model

Swift 6 strict concurrency throughout. Model types are `Sendable` value
types; the coordinator is an actor; the UI store is `@MainActor`. The app
target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; package targets use
the Swift 6 default (nonisolated).

## Persistence

Lightweight JSON files in `~/Library/Application Support/Freshly/`: the
last-scan cache (`ScanCache` in `FreshlyEngine` — loaded at launch so the
UI opens with the previous state), the update history (`UpdateHistory`,
capped, newest first — every install attempt with its outcome), per-app
skips, per-app source overrides, and the network caches (Homebrew index,
GitHub releases).
Preferences live in `UserDefaults`; the optional GitHub token lives in
the keychain, never in preferences. There is no database.

## Background behavior

The app-layer store schedules automatic re-checks on a user-configurable
interval and re-runs the scan without clearing the list (rows update in
place; missing apps are pruned at the end). Only automatic checks post a
notification, and only for apps that newly became outdated relative to
the previous state (`AppUpdateStatus.newlyOutdated`) — skipped versions
never notify.

## Localization

English is the development language; strings use String Catalogs so
translations can be contributed without code changes. Portuguese is the
first translation.

Engine errors follow the same boundary as everything else: `FreshlyCore`
reports failures as data (`UpdateError.Reason`, an enum carrying whatever
context the message needs), and the app layer turns reasons into localized,
actionable text. Cached or recorded errors therefore re-localize when the
user's language changes, and the core stays free of presentation strings.
