# Plan 007: A renamed enum case can no longer wipe the user's update history

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report. Commit your work in
> the worktree following the plan's git workflow section. SKIP updating
> `plans/README.md` — your reviewer maintains the index. Before reporting,
> audit every claim against an actual tool result. Reply with the report
> format at the end.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- Packages/FreshlyCore/Sources/FreshlyEngine/UpdateHistory.swift Packages/FreshlyCore/Sources/FreshlyModels/UpdateRecord.swift`
> If either changed since this plan was written, compare against "Current
> state"; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt / bug
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

`UpdateHistory` is user-owned data that cannot be regenerated (unlike the
scan cache, which a rescan rebuilds). Its `load()` does an all-or-nothing
`try? JSONDecoder().decode([UpdateRecord].self)` and returns `[]` on any
failure. `UpdateRecord` embeds `SourceID` and `UpdateError.Reason` — enums
persisted directly. Renaming or removing any case of either (the
`UpdateError.Reason` enum grows with the install pipeline) makes the
**entire** history array fail to decode, and `load()` silently returns `[]`:
the user's whole update history is erased with no error surfaced. This plan
makes persistence resilient — a versioned envelope plus per-record lenient
decoding, so one unreadable record costs one record, never the whole file —
and migrates existing bare-array files transparently.

## Current state

### `Packages/FreshlyCore/Sources/FreshlyEngine/UpdateHistory.swift` (whole file)

```swift
import Foundation
import FreshlyModels

public struct UpdateHistory: Sendable {
    private let fileURL: URL
    private let limit: Int

    public init(directory: URL, limit: Int = 500) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "update-history.json")
        self.limit = limit
    }

    public func load() -> [UpdateRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([UpdateRecord].self, from: data) else {
            return []
        }
        return records
    }

    @discardableResult
    public func append(_ record: UpdateRecord) -> [UpdateRecord] {
        var records = load()
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
        save(records)
        return records
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save(_ records: [UpdateRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

The file today is a bare JSON array `[ {record}, {record}, … ]`.

### `UpdateRecord` — `Packages/FreshlyCore/Sources/FreshlyModels/UpdateRecord.swift`

A `Codable` struct with `id, date, bundleID, appName, fromVersion,
toVersion, source: SourceID, outcome: Outcome` where
`Outcome = .installed | .failed(UpdateError)`. No schema version anywhere.

### Conventions

- Tests are swift-testing (`import Testing`, `@Test`, `#expect`, `#require`).
  See `Packages/FreshlyCore/Tests/FreshlyCoreTests/UpdateHistoryTests.swift`
  for the existing suite (temp-directory pattern, `makeDirectory()` helper,
  `record(...)` factory) — extend it.
- Persisted-model changes belong in `FreshlyModels`/`FreshlyEngine` (core).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build + test | `swift test --package-path Packages/FreshlyCore` | all pass |
| Run the suite | `swift test --package-path Packages/FreshlyCore --filter UpdateHistory` | passes |

## Scope

**In scope**:
- `Packages/FreshlyCore/Sources/FreshlyEngine/UpdateHistory.swift`
- `Packages/FreshlyCore/Tests/FreshlyCoreTests/UpdateHistoryTests.swift`
- You may add ONE small helper file in `FreshlyEngine` or `FreshlyModels`
  for the lenient-decode wrapper if you prefer not to nest it.

**Out of scope**:
- `ScanCache.swift` — it has the same all-or-nothing decode but self-heals
  on the next scan, so it is not part of this plan (noted as a follow-up).
  Do NOT change it.
- `UpdateRecord`'s stored properties or `SourceID`/`UpdateError` — do not
  add a version field to the *record*; the version lives on the file
  envelope.
- The `AppListStore` call sites — `UpdateHistory`'s public API
  (`load`/`append`/`clear`) must not change shape.

## Git workflow

- Commit on the worktree's existing branch. Imperative subject ≤72, no
  trailers, e.g. "Make update history resilient to unreadable records".

## Steps

### Step 1: Add a lenient per-element decode wrapper

Add a small generic that decodes one element and never throws (this is the
idiom that makes array decoding skip a bad element instead of failing the
whole array — a throwing `decode` inside an unkeyed container does not
reliably advance, so the wrapper must swallow the error itself):

```swift
/// Decodes `T` if possible, otherwise `nil` — without throwing, so an
/// array of these skips unreadable elements instead of failing wholesale.
private struct Resilient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
```

### Step 2: Add a versioned envelope and rewrite load/save

Introduce the envelope and make `load()` resilient with migration:

```swift
private struct Envelope: Codable {
    var schemaVersion: Int
    var records: [UpdateRecord]
}

private static let currentSchemaVersion = 1
```

- `save(_:)`: encode `Envelope(schemaVersion: Self.currentSchemaVersion, records: records)`.
- `load()`:
  1. Read the data; on failure return `[]`.
  2. Try to decode a resilient envelope — decode a struct whose `records`
     is `[Resilient<UpdateRecord>]`, then `compactMap(\.value)`. This
     handles the current/new format and drops only unreadable records.
  3. If that fails (no `schemaVersion` key — an old bare-array file), fall
     back to decoding `[Resilient<UpdateRecord>].self` directly and
     `compactMap(\.value)` (the migration path; the next `append` rewrites
     it as an envelope via `save`).
  4. If both fail, return `[]`.

Keep `append`/`clear` unchanged in behavior (append still loads, inserts at
0, caps at `limit`, saves; clear still removes the file).

**Verify**: `swift build --package-path Packages/FreshlyCore` → exit 0.

### Step 3: Write the tests (see Test plan), run the suite

**Verify**: `swift test --package-path Packages/FreshlyCore --filter UpdateHistory`
→ all pass, then the full `swift test --package-path Packages/FreshlyCore`
→ all pass.

## Test plan

Extend `UpdateHistoryTests.swift` (reuse its `makeDirectory()`/`record(...)`
helpers). Add:

- **Envelope roundtrip**: append two records, `load()` returns them
  newest-first (the existing `roundtrip` test should still pass unchanged —
  confirm it does).
- **One unreadable record is skipped, the rest survive**: write a file whose
  JSON is an envelope (`{"schemaVersion":1,"records":[…]}`) containing two
  valid records and one object with a bogus `source` value (e.g.
  `"source":"nonexistent-source"`); assert `load()` returns exactly the two
  valid records (not `[]`). This is the core regression — it must fail
  against the old all-or-nothing code.
- **Old bare-array file migrates**: write a file that is a bare
  `[UpdateRecord]` JSON array (encode `[record]` directly with
  `JSONEncoder`), assert `load()` reads it; then `append` another and assert
  the file is now an envelope (decode it and check `schemaVersion == 1`).
- **Corrupt/empty file** still loads as `[]` (the existing `corruptFile`
  test should still pass).

Verification: `swift test --package-path Packages/FreshlyCore` → all pass,
including the new cases.

## Done criteria

ALL must hold:

- [ ] `swift test --package-path Packages/FreshlyCore` exits 0 with the new
      resilience tests present and passing.
- [ ] The "one unreadable record is skipped" test exists and asserts a
      non-empty, partial result (proves the wipe is fixed).
- [ ] `UpdateHistory`'s public API (`load`/`append`/`clear` signatures) is
      unchanged — `grep -n "public func" Packages/FreshlyCore/Sources/FreshlyEngine/UpdateHistory.swift`
      shows the same three.
- [ ] `ScanCache.swift` is not modified (`git status`).
- [ ] No files outside the in-scope list modified.
- [ ] `plans/README.md` — leave to reviewer.

## STOP conditions

Stop and report if:

- The "Current state" excerpts don't match the live code (drift).
- Making `load()` resilient forces a change to `UpdateRecord` or the
  `AppListStore` call sites — it should not; report if it seems to.
- The migration path can't distinguish an old bare-array file from a new
  envelope after two attempts — report the ambiguity.

## Maintenance notes

- Follow-up (deferred): apply the same `Resilient` per-element decode to
  `ScanCache.load()` for consistency — lower priority because the scan cache
  self-heals on the next scan.
- Document the enum-evolution rule in `ARCHITECTURE.md` (Persistence
  section) in a later docs pass: adding enum cases is safe; renaming/
  removing a persisted case now costs only the affected records, not the
  file.
- Reviewer: confirm the "one bad record" test would have returned `[]`
  under the old code (i.e. it genuinely guards the fix).
- When a truly breaking format change is needed, bump `currentSchemaVersion`
  and branch the read strategy on it.

## Report format

```
STATUS: COMPLETE | STOPPED
STEPS: per step — done/skipped + verification command result
STOPPED BECAUSE: (only if STOPPED) which STOP condition, what was observed
FILES CHANGED: list
NOTES: anything the reviewer should know
```
