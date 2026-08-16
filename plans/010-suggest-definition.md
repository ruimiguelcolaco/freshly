# Plan 010: A `suggest-definition` helper drafts catalog entries from an installed app

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report. Commit your work in
> the worktree following the git workflow section. SKIP updating
> `plans/README.md` — your reviewer maintains the index. Before reporting,
> audit every claim against an actual tool result. Reply with the report
> format at the end.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- Packages/FreshlyCore/Package.swift Packages/FreshlyCore/Sources/FreshlySources/HomebrewCatalog.swift`
> If either changed since this plan was written, compare against "Current
> state"; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction / dx
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

The community definitions catalog (`Definitions/`) has only **4 entries**,
and the project's whole "open successor to MacUpdater's database" thesis
lives on breadth. Today a contributor hand-authors JSON after a manual
`plutil` dance (`docs/APP_DEFINITIONS.md`). Every building block for a helper
already exists: `AppScanner.inspect` reads a bundle's identity/feed/receipt/
Electron manifest, `HomebrewCatalog` loads the cask index, and
`AppDefinition.validationProblems()` validates a draft. A
`suggest-definition /Applications/Foo.app` that inspects the app, proposes a
cask token, and emits a ready-to-finish JSON stub turns a multi-step chore
into one command — widening the contribution funnel the catalog depends on.
Read-only, additive, no certificate dependency, no impact on the install
pipeline.

## Current state

### `Packages/FreshlyCore/Package.swift` (the executable + target pattern to mirror)

```swift
products: [
    .library(name: "FreshlyCore", targets: [ … ]),
    .executable(name: "validate-definitions", targets: ["FreshlyDefinitionsValidator"]),
],
targets: [
    .target(name: "FreshlyModels"),
    .executableTarget(name: "FreshlyDefinitionsValidator", dependencies: ["FreshlyModels"]),
    .target(name: "FreshlySecurity", dependencies: ["FreshlyModels"]),
    .target(name: "FreshlyScanner", dependencies: ["FreshlyModels", "FreshlySecurity"]),
    .target(name: "FreshlySources", dependencies: ["FreshlyModels"]),
    …
    .testTarget(name: "FreshlyCoreTests", dependencies: [ …all… ], resources: [.copy("Fixtures")]),
]
```

### Available API (all public — verified)

- `AppScanner.inspect(appAt url: URL) -> InstalledApp?` (in `FreshlyScanner`).
- `InstalledApp` exposes `bundleID`, `name`, `installChannels: Set<SourceID>`,
  `sparkleFeedURL: URL?`, `electronManifestURL: URL?`.
- `HomebrewCatalog().loadEntries() async throws -> [CaskEntry]` (in
  `FreshlySources`); `CaskEntry` has public `token: String` and
  `appNames: [String]` (each like `"Firefox.app"`).
- `AppDefinition(bundleID:name:homebrewCask:githubRepo:appcastURL:quirks:)`
  and `func validationProblems() -> [String]` (in `FreshlyModels`).
- `SourceID` cases: `.sparkle, .macAppStore, .homebrew, .github, .electron`.

### Conventions

- The executable pattern is `FreshlyDefinitionsValidator/main.swift` — a
  ~40-line top-level `main.swift`, args via `CommandLine.arguments`, errors
  to `FileHandle.standardError`, exit codes via `exit(_:)`.
- Tests are swift-testing. Pure logic that needs testing goes in a library
  target (here `FreshlySources`), not the executable, so the test target can
  import it.
- No file-header boilerplate.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build everything | `swift build --package-path Packages/FreshlyCore` | exit 0 |
| Tests | `swift test --package-path Packages/FreshlyCore` | all pass |
| Smoke: no args | `swift run --package-path Packages/FreshlyCore suggest-definition` | prints usage, non-zero exit |
| Smoke: real app | `swift run --package-path Packages/FreshlyCore suggest-definition /System/Applications/Calculator.app` | prints a result to stderr, exit 0 |

## Scope

**In scope**:
- `Packages/FreshlyCore/Package.swift` (add the product + executable target)
- `Packages/FreshlyCore/Sources/FreshlySources/HomebrewCatalog.swift` (add
  the pure cask-matching helper) — or a new small file in `FreshlySources`
- `Packages/FreshlyCore/Sources/SuggestDefinition/main.swift` (new
  executable target directory)
- `Packages/FreshlyCore/Tests/FreshlyCoreTests/` (new test file for the
  matching helper)

**Out of scope**:
- The install pipeline, the app target, existing sources' behavior.
- Network-dependent tests — the cask helper must be a **pure function over
  a passed-in `[CaskEntry]`**, tested with fabricated entries (no live
  `loadEntries()` in tests).
- Writing files to `Definitions/` — the tool prints to stdout; the human
  redirects. Do not have the tool create catalog files itself.

## Git workflow

- Commit on the worktree's existing branch: first the helper + tests, then
  the executable + Package.swift. Imperative subjects ≤72, no trailers.

## Steps

### Step 1: Add a pure cask-matching helper in FreshlySources

Add a public static function (on `HomebrewCatalog` or a free function in the
module) that returns the distinct cask tokens whose artifact app name
matches a given app file name, case-insensitively:

```swift
/// Distinct cask tokens whose `.app` artifact matches `appFileName`
/// (e.g. "Firefox.app"), case-insensitive. Zero = no cask; one =
/// a confident suggestion; more than one = ambiguous (the caller should
/// surface all and let the human choose).
public static func caskTokens(matchingAppNamed appFileName: String, in entries: [CaskEntry]) -> [String] {
    let needle = appFileName.lowercased()
    var tokens: [String] = []
    for entry in entries where entry.appNames.contains(where: { $0.lowercased() == needle }) {
        if !tokens.contains(entry.token) { tokens.append(entry.token) }
    }
    return tokens
}
```

**Verify**: `swift build --package-path Packages/FreshlyCore` → exit 0.

### Step 2: Test the matching helper (pure, no network)

Add a test file using fabricated `CaskEntry` values (construct via the
public `CaskEntry(token:version:appNames:homepage:downloadURL:)` init).
Cover: no match → `[]`; one match → `["token"]`; two casks claiming the same
app name → both tokens (ambiguous); case-insensitivity (`"firefox.app"`
matches an entry with `"Firefox.app"`).

**Verify**: `swift test --package-path Packages/FreshlyCore --filter Cask`
→ the new cases pass (adjust the filter to your suite name).

### Step 3: Add the executable target

Add to `Package.swift`:
- a product: `.executable(name: "suggest-definition", targets: ["SuggestDefinition"])`
- a target: `.executableTarget(name: "SuggestDefinition", dependencies: ["FreshlyModels", "FreshlyScanner", "FreshlySources"])`

Create `Packages/FreshlyCore/Sources/SuggestDefinition/main.swift`. Behavior:

1. Read the app path from `CommandLine.arguments`. If missing, print usage
   (`usage: suggest-definition <path-to-.app>`) to stderr and `exit(2)`.
2. `AppScanner.inspect(appAt: URL(fileURLWithPath: path))`. If `nil`, print
   "not a readable app bundle: <path>" to stderr, `exit(1)`.
3. If the app already has a source signal — `installChannels` contains
   `.sparkle`, `.macAppStore`, or `.electron` (equivalently:
   `sparkleFeedURL != nil`, a receipt, or `electronManifestURL != nil`) —
   print to stderr: "<name> already updates via <signal>; no definition
   needed." and `exit(0)` (emit no JSON).
4. Otherwise, best-effort load the cask index
   (`try? await HomebrewCatalog().loadEntries() ?? []`) and compute
   `HomebrewCatalog.caskTokens(matchingAppNamed: app.path.lastPathComponent, in: entries)`.
   - Exactly one → include `homebrewCask` in the draft.
   - Zero or many → omit `homebrewCask`; if many, print the ambiguous
     candidates to stderr for the human.
5. Build an `AppDefinition(bundleID: app.bundleID, name: app.name,
   homebrewCask: <the one token or nil>)`, encode it to pretty JSON
   (sorted keys, matching the `Definitions/*.json` style — 4-space indent is
   fine), and print the JSON to **stdout**.
6. Print guidance to **stderr**: which fields still need a human
   (`githubRepo` as `owner/repo`, `appcastURL` as an https feed) and the
   output of `AppDefinition(...).validationProblems()` (e.g. it will report
   "must provide at least one of homebrewCask, githubRepo, appcastURL" when
   no cask was found — that is the signal the human must add a channel).
   Suggest: `suggest-definition /Applications/Foo.app > Definitions/<bundleID>.json`.

Keep it a top-level `main.swift` like `FreshlyDefinitionsValidator/main.swift`
(use a top-level `await` — SPM executables support concurrency; if the
top-level-await form fights the toolchain, wrap in a `@main struct` with
`static func main() async`).

**Verify**:
- `swift build --package-path Packages/FreshlyCore` → exit 0.
- `swift run --package-path Packages/FreshlyCore suggest-definition` → prints
  usage, non-zero exit.
- `swift run --package-path Packages/FreshlyCore suggest-definition /System/Applications/Calculator.app`
  → exits 0 and prints a message (Calculator is Apple software with a
  receipt/no third-party channel; the exact message depends on its signals —
  confirm it does not crash and the JSON, if any, is valid).

### Step 4: Full suite

**Verify**: `swift test --package-path Packages/FreshlyCore` → all pass
(the existing suite plus the new matching tests). Confirm CI's
`validate-definitions` executable still builds (it shares the package):
`swift build --package-path Packages/FreshlyCore` already covers this.

## Test plan

- New test file (e.g. `SuggestDefinitionTests.swift` or fold into a Homebrew
  suite): the four `caskTokens(matchingAppNamed:in:)` cases from Step 2,
  using fabricated `CaskEntry` values — pure, no network, deterministic.
- The executable's `main` I/O is not unit-tested (matches the untested
  `validate-definitions` main); its logic core (the matcher) is.

Verification: `swift test --package-path Packages/FreshlyCore` → all pass.

## Done criteria

ALL must hold:

- [ ] `swift build --package-path Packages/FreshlyCore` exits 0 (all targets,
      including the new executable and the existing `validate-definitions`).
- [ ] `swift test --package-path Packages/FreshlyCore` exits 0 with the new
      matcher tests present and passing.
- [ ] `swift run --package-path Packages/FreshlyCore suggest-definition`
      (no args) prints usage and exits non-zero.
- [ ] `HomebrewCatalog.caskTokens(matchingAppNamed:in:)` (or the chosen
      name) is `public` and pure (takes `[CaskEntry]`, no I/O).
- [ ] The tool prints JSON to stdout and guidance to stderr; it does not
      write into `Definitions/`.
- [ ] No files outside the in-scope list modified.

## STOP conditions

Stop and report if:

- The "Current state" `Package.swift` excerpt doesn't match the live file
  (drift) — especially if the target list has changed.
- Adding the executable target breaks the existing `validate-definitions`
  build or the package's `swift test` — report the error.
- Top-level `await` in the executable won't compile after two attempts and
  the `@main struct` form also fails — report the toolchain behavior.

## Maintenance notes

- Follow-up (deferred, note in the plan index): a `--scan` mode that walks
  `/Applications` + `~/Applications` and drafts stubs for every app with no
  source signal (the set `AppListStore.notCheckable` already computes in the
  app) — a natural extension once the single-app path is proven.
- The tool intentionally cannot fill `githubRepo`/`appcastURL` — those need
  human verification (which repo actually publishes the app's releases). The
  guidance must say so, so contributors don't ship half-draft definitions.
- Reviewer: confirm the cask matcher mirrors the app's real matching
  intent (exact app-file-name match, ambiguity surfaced not guessed) and
  that the tool never writes catalog files itself.
- Document the tool in `docs/APP_DEFINITIONS.md` in a later docs pass.

## Report format

```
STATUS: COMPLETE | STOPPED
STEPS: per step — done/skipped + verification command result
STOPPED BECAUSE: (only if STOPPED) which STOP condition, what was observed
FILES CHANGED: list
NOTES: anything the reviewer should know
```
