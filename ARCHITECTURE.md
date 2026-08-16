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
        ├── FreshlyCLI       read-only `freshly check --json` entry point
        ├── FreshlyInstaller download, verify, install pipeline
        └── FreshlySecurity  code signing / notarization / Gatekeeper checks
```

The app target is intended to stay thin: UI, app lifecycle, and system-service
adapters only. Testable domain logic belongs in `FreshlyCore`, which builds
and tests with plain `swift test` — no signing, no Xcode UI,
contributor-friendly. Some scan, scheduling, notification, and install wiring
still lives in `AppListStore`; Milestone 14 tracks the remaining extraction
and an app-target test harness.

The app is **not sandboxed** (an updater must modify other apps' bundles) but
builds with the hardened runtime enabled. It is currently built from source;
the intended distribution is outside the Mac App Store, signed with Developer
ID and notarized once Milestone 6 and its certificate are available.

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
2. For each discovered app, the coordinator asks the `SourceRegistry` which
   sources apply. Checks for different apps run concurrently with a bounded
   width (10 by default); the applicable sources for one app are currently
   queried in precedence order. Milestone 15 will replace this app-level bound
   with one shared request limit and concurrent per-source queries, without
   changing deterministic conflict resolution.
3. Results merge into an `AppUpdateStatus` per app. The GUI streams them to
   an `@Observable` store; the CLI reduces the final states into a versioned
   `UpdateCheckReport`.
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
| Electron | `app-update.yml` in the bundle's resources | — |
| GitHub | — | an app definition maps bundle ID → repo |

The App Store lookup accepts both native `mac-software` records and
universal `software` records that explicitly list `MacDesktop` support.
An iPhone/iPad-only result with the same bundle ID is never treated as a
Mac update. The minimum OS field on a universal record is an iOS deployment
target, so it is not compared with the host macOS version.

**Conflict resolution**: the channel the app was installed through wins.
The resolver picks the first authoritative source as `best` (ties break by
registration order: Mac App Store, Sparkle, Homebrew, then Electron — a
brew-installed Electron app keeps updating through brew so its bookkeeping
stays honest — GitHub is candidate-only and never breaks authoritative
ties); everything
else is kept as `alternatives` and shown in the UI as alternative channels.
The user can override the preferred channel per app ("Update Via" in the
row's context menu), persisted in Application Support.

**Homebrew matching is deliberately conservative** — a wrong match nags the
user about a different app's updates. App-artifact names claimed by more
than one cask are ambiguous and excluded; Apple bundle IDs (including
Safari Web Apps) never match; freshness compares the cask's marketing
version only, because the suffix after the comma in `"2.2.1,5287…"` — and
the trailing build hash in `"3.6.2-57f0b637"` — is brew's artifact
bookkeeping, not the app's `CFBundleVersion`. Casks
installed through brew upgrade through `brew upgrade --cask` (keeping its
bookkeeping consistent); manually installed apps matched to a cask update
through Freshly's own verified pipeline using the cask's artifact URL.

**Electron (electron-updater/Squirrel.Mac)** apps declare their channel in
a bundled `Contents/Resources/app-update.yml` — the Electron ecosystem's
`SUFeedURL`. The scanner reduces every provider it understands (`generic`,
`github`, `s3`) to one manifest URL (`latest-mac.yml` or a channel
variant); the source fetches it and picks the zip for this Mac's
architecture. Auth-gated endpoints (private buckets) make the app simply
unsupported, not failed. The manifest's SHA-512 rides along and is
verified after download.

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
   does not block them; they must pass Gatekeeper instead (rule 6). Some
   apps pin a key without declaring a feed (AltTab configures its feed in
   code), so this distinction matters in practice.
2. **SHA-512** — when the release publishes a checksum (electron-updater
   manifests), the downloaded artifact must hash to it. Integrity only:
   it proves the bytes are the ones the manifest describes, not who
   published them, so it never waives Gatekeeper (rule 6).
3. **Deep code-signature validation** of the extracted bundle (all
   architectures, nested code, strict rules) — unsigned or tampered
   bundles fail.
4. **Identity continuity** — the bundle identifier must not change, and
   when the installed app has a team identifier, the update must be signed
   by the same team.
5. **Downgrade protection** — the extracted bundle must not be older than
   what is installed, regardless of what the feed claimed. This compares the
   bundle's own clean `CFBundleShortVersionString` first (marketing version),
   using the build only to break a marketing-version tie — the opposite
   priority to freshness detection, because the extracted `Info.plist` is
   not feed-decorated. Apps that ship a static `CFBundleVersion` (e.g. `0`)
   are thus not wrongly blocked when their marketing version increments.
6. **Gatekeeper** (`spctl`) — required whenever the download's EdDSA
   signature could not be verified. EdDSA-verified team-matched updates
   follow Sparkle's own trust model and skip the notarization requirement.

All applicable checks must pass and the pipeline fails closed; the
numbering reflects trust role, not strict execution order — on the
extracted bundle, identity, downgrade, and code-signature validation are
mutually independent (a bundle whose Info.plist was altered to pass the
identity or downgrade checks cannot also pass code-signature validation).

The old bundle is moved aside, not deleted, and restored automatically if
the swap fails. Running apps are never touched without explicit consent
(quit & relaunch is a user choice). Installer packages (`.pkg`) are refused.
Artifacts use `URLSession`'s native download task, which streams into a
temporary file and reports progress in transfer-sized chunks instead of
iterating individual bytes. The download is size-capped (refused past 4 GB,
both on the declared `Content-Length` and the running total) so a compromised
or broken feed cannot exhaust the disk before verification ever runs.

### Privacy invariants

- No server-side component, ever. Sources talk directly to their upstream
  (appcast URL, Apple's lookup API, `formulae.brew.sh`, GitHub API).
- Prefer bulk catalog downloads over per-app queries so no service can
  reconstruct the user's app list (the Homebrew source downloads the entire
  cask index; the definitions catalog is fetched whole).
- App-specific channels necessarily receive an app-specific request:
  publisher-owned Sparkle/Electron endpoints, Apple's lookup API, and
  definition-mapped GitHub repositories. The GUI and CLI share this behavior.
- No telemetry and no crash reporting of any kind.

`CachedFetcher` (`FreshlySources`) owns the shared conditional-GET policy
used by the Homebrew index, GitHub releases, and the remote definitions
catalog: ETag storage, 304 handling, atomic writes, and offline fallback.
Responses are decoded before replacing the last good cache, stale ETags are
removed when a successful response omits one, and the cache directory is
kept private (`0700`). Each source still maps HTTP and transport failures
into its own `UpdateError.Reason`.

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

Between app releases the catalog refreshes itself: the repository commits
a generated single-document pack (`definitions-catalog.json`, regenerated
by `validate-definitions --pack`, freshness enforced by CI), and on every
scan `RemoteDefinitionsCatalog` (`FreshlyEngine`) fetches it from the
repository's `main` branch — one bulk ETag-cached request, stored in
Application Support. Remote definitions override their bundled
counterparts per bundle ID; when the fetch fails, the last cached copy
and the bundled catalog still apply. A remote pack that fails to decode
(or declares a newer schema than the app understands) is discarded,
never cached.

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
GitHub releases, remote definitions catalog).
Preferences live in `UserDefaults`; the optional GitHub token lives in
the keychain, never in preferences. There is no database.

## Main-window navigation

The main window uses a two-column `NavigationSplitView`. Its sidebar owns
the status category selection and live counts; the detail column renders
one focused app list at a time, with Updates selected by default. Search
filters only the selected category. `AppListStore` remains the sole owner
of scan and install state — the navigation layer only projects its existing
status sections and does not duplicate or persist them.

## Background behavior

`AutomaticCheckSchedule` in `FreshlyEngine` is the pure, tested policy for
automatic checks. Given the configured interval, last completed scan,
current time, and whether the app is busy, it returns one of four decisions:
disabled, wait, check now, or retry after five minutes. `AppListStore`
executes that decision and re-arms it after every completed manual or
automatic scan. At launch it therefore waits only for the remainder of the
interval, checks immediately when overdue, and never postpones longer than
one interval when the system clock moves backwards. It also reapplies the
policy when macOS wakes, so time spent asleep cannot leave an overdue check
waiting on a stale timer. A scan that produces only network or rate-limit
failures is not recorded as a completed check. Retries start after five
minutes, back off by a factor of three, cap at six hours, and reset after a
useful scan instead of postponing recovery for the full configured interval.
While a retry is pending, restored connectivity advances it immediately;
connectivity changes never trigger extra scans otherwise. Once macOS has
reported the device offline, a due automatic check enters the same backoff
without issuing doomed requests; user-initiated checks remain available. The
pending retry date and backoff attempt are persisted in preferences, so
relaunching the app or restarting macOS resumes the same recovery plan.
Switching to manual mode clears any pending automatic recovery.

A scan updates rows in place without clearing the list and prunes missing
apps at the end. Only automatic checks post a notification, and only for
apps that newly became outdated relative to the previous state
(`AppUpdateStatus.newlyOutdated`) — skipped versions never notify. A
single-app notification carries only the local bundle path needed to
resolve the already-checked status and offers "Update Now"; a multi-app
notification offers "Update All". Both actions route through the same
`AppListStore` methods as the window and menu bar. A running app still
requires explicit quit confirmation, while bulk updates never force-quit.

## Localization

English is the development language; strings use String Catalogs so
translations can be contributed without code changes. Portuguese is the
first translation.

Engine errors follow the same boundary as everything else: `FreshlyCore`
reports failures as data (`UpdateError.Reason`, an enum carrying whatever
context the message needs), and the app layer turns reasons into localized,
actionable text. Cached or recorded errors therefore re-localize when the
user's language changes, and the core stays free of presentation strings.
