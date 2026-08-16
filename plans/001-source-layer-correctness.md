# Plan 001: Source layer stops reporting wrong, unparseable, or cleartext release data

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- Packages/FreshlyCore/Sources/FreshlySources Packages/FreshlyCore/Sources/FreshlyModels/ElectronUpdaterConfig.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug / security
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

Three independent defects in the update-source layer, all small, all with a
clean test story:

1. **Phantom App Store update** — when the iTunes lookup returns no
   mac-software result matching the queried bundle ID, the code falls back
   to the *first* result and reports that unrelated app's version as this
   app's update. A wrong "update available" is the single worst failure for
   an updater — it is the exact thing the conservative Homebrew matching
   exists to prevent, undone here on the App Store path.
2. **Dropped release dates** — the Electron date parser only accepts
   fractional-second timestamps, so a manifest with a whole-second
   `releaseDate` shows no date in the notes popover; the GitHub and App
   Store parsers have the mirror-image fragility (default formatter rejects
   fractional seconds). Cosmetic, but trivially fixable and symmetric.
3. **Cleartext Electron metadata** — every other channel enforces or
   upgrades HTTPS (`SparkleSource.enforcingHTTPS`; `AppDefinition` rejects
   non-https appcasts), but the Electron config accepts `http` manifest
   URLs. It is currently backstopped only by App Transport Security, so a
   future ATS exception would silently re-enable cleartext fetching of
   update metadata (version, artifact URL, checksum).

## Current state

### 1. App Store fallback — `Packages/FreshlyCore/Sources/FreshlySources/MacAppStoreSource.swift:78-82`

```swift
let macResults = decoded.results.filter { $0.kind == "mac-software" }
guard let result = macResults.first(where: { $0.bundleId?.lowercased() == bundleID.lowercased() })
    ?? macResults.first else {
    return nil
}
```

The `?? macResults.first` is the bug: it accepts a result whose bundle ID
does not match `bundleID`.

### 2a. Electron date parser — `Packages/FreshlyCore/Sources/FreshlySources/ElectronSource.swift:124-131`

```swift
/// electron-builder writes fractional seconds (`2026-07-07T23:20:34.590Z`).
/// `ISO8601DateFormatter` is not `Sendable`, so it is built per parse —
/// one manifest per app per scan makes that free.
private static func parseDate(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: raw)
}
```

With `.withFractionalSeconds` set, `2026-07-07T23:20:34Z` (no fraction)
parses to `nil`.

### 2b. GitHub & App Store date parsing (the mirror problem)

- `GitHubSource.swift` — locate the `publishedAt:` line; it uses
  `ISO8601DateFormatter().date(from: $0)` (a **default** formatter, which
  rejects fractional seconds).
- `MacAppStoreSource.swift:94-96`:

```swift
publishedAt: result.currentVersionReleaseDate.flatMap {
    ISO8601DateFormatter().date(from: $0)
},
```

### 3. Electron scheme — `Packages/FreshlyCore/Sources/FreshlyModels/ElectronUpdaterConfig.swift:53-60`

```swift
private static func url(base: String, appending name: String) -> URL? {
    let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
    guard let url = URL(string: "\(trimmed)/\(name)"),
          let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
        return nil
    }
    return url
}
```

Compare the appcast rule at
`Packages/FreshlyCore/Sources/FreshlySources/SparkleSource.swift` →
`enforcingHTTPS`, and `AppDefinition.validationProblems()` in
`Packages/FreshlyCore/Sources/FreshlyModels/AppDefinition.swift` which
appends a problem when `appcastURL.scheme != "https"`.

### Conventions

- Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`,
  `#require`) — not XCTest. Model new cases after the existing suites in
  `Packages/FreshlyCore/Tests/FreshlyCoreTests/` (e.g.
  `MacAppStoreSourceTests.swift`, `ElectronUpdaterConfigTests.swift`).
- No file-header boilerplate in Swift files.
- Comments state *why*, not *what*.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build + test the core | `swift test --package-path Packages/FreshlyCore` | all tests pass |
| Run one suite | `swift test --package-path Packages/FreshlyCore --filter MacAppStoreSource` | that suite passes |

## Scope

**In scope** (modify only these):
- `Packages/FreshlyCore/Sources/FreshlySources/MacAppStoreSource.swift`
- `Packages/FreshlyCore/Sources/FreshlySources/ElectronSource.swift`
- `Packages/FreshlyCore/Sources/FreshlySources/GitHubSource.swift`
- `Packages/FreshlyCore/Sources/FreshlyModels/ElectronUpdaterConfig.swift`
- `Packages/FreshlyCore/Sources/FreshlySources/` — you may add **one** new
  small file for the shared date helper (e.g. `ISO8601.swift`)
- The matching test files under
  `Packages/FreshlyCore/Tests/FreshlyCoreTests/` (create/extend)

**Out of scope** (do NOT touch):
- The installer pipeline (`FreshlyInstaller/`) and security checks
  (`FreshlySecurity/`) — unrelated.
- `HomebrewSource` version stripping — a deliberate, documented tradeoff.
- Any `ReleaseInfo` field or the `UpdateSource` protocol shape.

## Git workflow

- Branch: `advisor/001-source-layer-correctness`
- Commit per fix (three logical units); imperative subject ≤72 chars, no
  trailers (matches `git log` — e.g. "Reject unrelated App Store lookup
  results").
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Reject non-matching App Store results

In `MacAppStoreSource.swift`, remove the `?? macResults.first` fallback so a
lookup that returns no bundle-ID match reports nothing:

```swift
let macResults = decoded.results.filter { $0.kind == "mac-software" }
guard let result = macResults.first(where: { $0.bundleId?.lowercased() == bundleID.lowercased() }) else {
    return nil
}
```

**Verify**: `swift build --package-path Packages/FreshlyCore` → exit 0.

### Step 2: Add a shared ISO-8601 parser that tries both option sets

Add a small helper in `FreshlySources` (new file `ISO8601.swift`) that
parses with and without fractional seconds:

```swift
import Foundation

enum ISO8601 {
    /// electron-builder and some feeds emit fractional seconds
    /// (`2026-07-07T23:20:34.590Z`); others emit whole seconds. A single
    /// `ISO8601DateFormatter` only accepts one shape, so try both.
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
```

Then route all three call sites through it:
- `ElectronSource.swift` — replace the body of `parseDate` with
  `ISO8601.date(from: raw)` (or delete `parseDate` and call `ISO8601.date`
  directly at its one use site).
- `GitHubSource.swift` — replace `ISO8601DateFormatter().date(from: $0)` in
  the `publishedAt:` initializer with `ISO8601.date(from: $0)`.
- `MacAppStoreSource.swift:94-96` — replace `ISO8601DateFormatter().date(from: $0)`
  with `ISO8601.date(from: $0)`.

**Verify**: `swift build --package-path Packages/FreshlyCore` → exit 0, and
`grep -rn "ISO8601DateFormatter()" Packages/FreshlyCore/Sources` → returns
only the two occurrences inside the new `ISO8601.swift`.

### Step 3: Require HTTPS on the Electron manifest URL

In `ElectronUpdaterConfig.swift`, change the scheme guard to accept HTTPS
only:

```swift
guard let url = URL(string: "\(trimmed)/\(name)"),
      url.scheme?.lowercased() == "https" else {
    return nil
}
```

**Verify**: `swift build --package-path Packages/FreshlyCore` → exit 0.

### Step 4: Write the tests (see Test plan), then run the full suite

**Verify**: `swift test --package-path Packages/FreshlyCore` → all pass,
including the new cases.

## Test plan

Model each after the existing suite in the same file.

- **`MacAppStoreSourceTests.swift`** — add a case: build a lookup JSON whose
  single mac-software result has a *different* `bundleId` than the queried
  one; assert `MacAppStoreSource.release(fromLookup:bundleID:runningOn:)`
  returns `nil`. (Use `Data(...utf8)` inline like the existing
  `garbageResponse` test at lines 75-83, or the fixture loader the suite
  already uses.)
- **`ElectronSourceTests.swift`** — extend the manifest-parse test: a
  manifest with `releaseDate: '2026-07-07T23:20:34Z'` (no fraction) yields a
  non-nil `releaseDate`; keep an existing fractional-second case passing.
- **New `ISO8601Tests.swift`** (or fold into an existing suite) — assert
  `ISO8601.date(from:)` parses both `"2026-07-07T23:20:34.590Z"` and
  `"2026-07-07T23:20:34Z"` to non-nil, and returns `nil` for `"not a date"`.
- **`ElectronUpdaterConfigTests.swift`** — the `unusable()` test already
  asserts an `ftp://` base returns `nil`; add an `http://` base case
  asserting `nil`, and confirm the existing `https://` cases still resolve.

Verification: `swift test --package-path Packages/FreshlyCore` → all pass,
including the ~4 new cases.

## Done criteria

ALL must hold:

- [ ] `swift test --package-path Packages/FreshlyCore` exits 0 with the new
      tests present and passing.
- [ ] `grep -n "?? macResults.first" Packages/FreshlyCore/Sources/FreshlySources/MacAppStoreSource.swift`
      returns nothing.
- [ ] `grep -rn "ISO8601DateFormatter()" Packages/FreshlyCore/Sources`
      returns only occurrences inside the new `ISO8601.swift`.
- [ ] `grep -n "https" Packages/FreshlyCore/Sources/FreshlyModels/ElectronUpdaterConfig.swift`
      shows the scheme guard no longer permits `"http"`.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row for 001 updated to DONE.

## STOP conditions

Stop and report (do not improvise) if:

- The "Current state" excerpts don't match the live code (drift).
- Removing the App Store fallback breaks an existing test that *depends* on
  the fallback behavior — that would mean the fallback was load-bearing;
  report it rather than deleting the test.
- Requiring HTTPS breaks an existing Electron test that used an `http://`
  fixture — report it; do not weaken the guard back to accept `http`.

## Maintenance notes

- If a new update source parses dates, route it through `ISO8601.date` too.
- Reviewer: confirm the App Store change returns `nil` (not a throw) on the
  no-match path, matching the "app not on the store" contract.
- Deferred: the App Store lookup still trusts the first *matching* result;
  multi-result disambiguation beyond bundle ID is out of scope here.
