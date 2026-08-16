# Plan 008: Performance — memoization, mapped hashing, native downloads

> Expanded from the roadmap entry (PERF-01/02/03/04). Four independent,
> high-confidence wins, each with a clean before/after. Verify with
> `swift test --package-path Packages/FreshlyCore` (Homebrew + installer
> suites) and the app build.

## Status

- **Priority**: P2
- **Effort**: M (done)
- **Risk**: LOW–MED (PERF-02 had to keep `@Observable` invalidation correct)
- **Depends on**: none
- **Category**: performance / dx

## What was done

**PERF-01 — Homebrew index re-parse memo** (`FreshlySources/HomebrewCatalog.swift`).
`loadEntries()` re-parsed the multi-MB cask index (`JSONSerialization` over
~7700 casks) on every scan, even on an ETag `304`. Added a process-wide
`actor Memo` keyed on the ETag: a `304` (or an offline fallback) whose ETag
matches the memo returns the already-reduced `[CaskEntry]` with no re-parse.
Never memoizes under a nil ETag (no proof of freshness). The on-disk cache +
etag files are unchanged, so a cold launch still works from disk.

**PERF-02 — section memoization** (`Freshly/AppListStore.swift`).
The five sections (`outdated`/`checking`/`upToDate`/`skipped`/`notCheckable`)
were computed properties, each calling the O(n) `displayStatuses` projection;
`ContentView` reads them many times per body eval and a streaming scan
evaluates the body often. Converted them to stored `private(set)` properties
rebuilt in one pass by `rebuildSections()`, called only when an input changes
(`statuses`, overrides, skips). Reads are now free; `@Observable` notifies on
the stored-property writes, which happen off the view-body path (async scan
task and user actions), so there's no "mutation during view update". Bonus:
override/skip changes now refresh the list deterministically instead of
relying on incidental observation of the sub-stores.

**PERF-03 — map the artifact once** (`FreshlyInstaller/UpdateInstaller.swift`).
The 100–300 MB update artifact was read into RAM in full via
`Data(contentsOf:)` — twice when both an EdDSA signature and a SHA-512 apply.
Now read once with `.mappedIfSafe` (lazy page faults, out of the resident
set) via a local `artifactBytes()`, reused by both digests.

**PERF-04 — native artifact downloads**
(`FreshlyInstaller/ArtifactDownloader.swift`). The installer consumed
`URLSession.AsyncBytes` one `UInt8` at a time, making a 317 MB Claude update
pathologically slow despite batching disk writes. It now uses
`URLSession.download(for:delegate:)`, which streams to a temporary file in
native transfer chunks. The delegate preserves determinate progress and
cancels promptly for non-success HTTP responses or when the declared or
running size exceeds the 4 GB cap. Response filenames, task cancellation,
and structured errors retain their previous behavior (commit `8d77769`).

## Verification

- The downloader suite covers content, response filenames, determinate
  progress, cancellation, HTTP errors, and the artifact-size cap.
- Full `swift test` → 193 tests / 37 suites pass.
- App build → `** BUILD SUCCEEDED **`.
- The 317 MB Claude update completed successfully in a real-app retest after
  PERF-04.

## Notes

Not micro-benchmarked with Instruments; the wins are structural (fewer
re-parses, fewer projections, no full-RAM reads, and no per-byte async
iteration). PERF-04 also has a successful real-world regression check.
