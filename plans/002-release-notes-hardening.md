# Plan 002: Release-notes rendering can no longer be turned into a privacy beacon

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- Freshly/ReleaseNotesPopover.swift Packages/FreshlyCore/Sources/FreshlySources/ReleaseNotesLoader.swift`
> If either file changed since this plan was written, compare the "Current
> state" excerpts against the live code; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

Freshly renders release notes from an app's appcast `<description>` HTML and
from a fetched Sparkle `releaseNotesLink` document — both **feed-controlled,
untrusted** content — through AppKit's WebKit-backed
`NSAttributedString(data:options:[.documentType:.html])` importer. The only
sanitization is a regex that strips a handful of media *tags*
(`img|picture|script|iframe|video|audio|source|object|embed`). It does **not**
strip CSS resource references — `<style>`, `<link>`, `<base>`, `@import`, or
inline `url(...)` — so a hostile feed can cause the importer to fetch a
remote resource. That fetch is a network beacon that deanonymizes the user
and defeats the project's explicit privacy invariant ("no server ever; no
service can reconstruct the user's app list", `ARCHITECTURE.md` → Privacy
invariants), plus an unbounded document is a main-thread hitch.

This plan removes the enumerated remote-reference vectors and bounds the
input size, and moves the sanitizer into the testable core. It deliberately
does **not** rip out the HTML importer (that is a larger UX decision, noted
as a follow-up) — it shrinks the attack surface with a clean, tested string
transform.

## Current state

### App-side renderer — `Freshly/ReleaseNotesPopover.swift` (the `renderHTML` function)

```swift
private static func renderHTML(_ html: String) -> AttributedString? {
    let sanitized = html.replacingOccurrences(
        of: "</?(img|picture|script|iframe|video|audio|source|object|embed)[^>]*>",
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    let styled = "<style>body { font-family: -apple-system, sans-serif; font-size: 13px; }</style>" + sanitized
    guard let data = styled.data(using: .utf8),
          let imported = try? NSAttributedString(
              data: data,
              options: [
                  .documentType: NSAttributedString.DocumentType.html,
                  .characterEncoding: String.Encoding.utf8.rawValue,
              ],
              documentAttributes: nil
          ) else {
        return nil
    }
    var rendered = AttributedString(imported)
    rendered.foregroundColor = nil
    return rendered
}
```

The `sanitized` string still contains any `<style>`, `<link>`, `<base>`,
`@import`, or `url(...)` the feed supplied.

### The source of the HTML — `Packages/FreshlyCore/Sources/FreshlySources/ReleaseNotesLoader.swift`

`load(for:)` returns `.html(...)` both for the appcast's embedded
`<description>` (`embeddedNotes`) and for the fetched `releaseNotesLink`
document (`fetchDocument`). Both are feed-controlled.

### Conventions

- Content/parsing logic belongs in `FreshlyCore`; the app target is UI only
  (`ARCHITECTURE.md` → Layout). Sanitization is content logic — put the pure
  transform in `FreshlySources` next to `ReleaseNotesLoader`, and leave only
  the `NSAttributedString` importer glue in the app.
- Tests are swift-testing (`import Testing`, `@Test`, `#expect`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Core tests | `swift test --package-path Packages/FreshlyCore` | all pass |
| App build (verifies the app-side edit compiles) | `xcodebuild build -project Freshly.xcodeproj -scheme Freshly -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | `** BUILD SUCCEEDED **` |

> The app build needs Xcode 26. If `xcodebuild` is unavailable in your
> environment, complete the core changes + tests and STOP before Step 3,
> reporting that the app-target edit needs an Xcode host.

## Scope

**In scope**:
- `Packages/FreshlyCore/Sources/FreshlySources/ReleaseNotesLoader.swift`
  (add the pure sanitizer)
- `Packages/FreshlyCore/Tests/FreshlyCoreTests/ReleaseNotesLoaderTests.swift`
  (extend)
- `Freshly/ReleaseNotesPopover.swift` (call the core sanitizer)

**Out of scope**:
- The `NSAttributedString` importer call itself — keep it; this plan does
  not replace the rendering engine.
- `ReleaseNotesLoader.load`/`fetchDocument` network logic — unchanged.
- Markdown/plain-text rendering paths — only HTML is the risk.

## Git workflow

- Branch: `advisor/002-release-notes-hardening`
- Commit the core sanitizer + tests first, then the app-side call.
- Imperative subjects ≤72 chars, no trailers.

## Steps

### Step 1: Add a pure, tested HTML sanitizer in the core

In `ReleaseNotesLoader.swift`, add a `static` function (either free in the
file or on `ReleaseNotes`) that returns display-safe HTML:

```swift
/// Strips the tags and CSS constructs that would make AppKit's HTML
/// importer fetch a remote resource — a network beacon that would defeat
/// Freshly's no-server privacy invariant — and bounds the size so a huge
/// feed document can't hitch the main thread. Not a general-purpose
/// sanitizer: it removes known resource-reference vectors, it does not
/// validate the whole document.
public static func sanitizedNotesHTML(_ html: String) -> String {
    let maxLength = 200_000 // characters; far above any real changelog
    var s = html.count > maxLength ? String(html.prefix(maxLength)) : html
    let patterns = [
        "</?(img|picture|script|iframe|video|audio|source|object|embed|style|link|base)[^>]*>",
        "<style[^>]*>[\\s\\S]*?</style>",
        "@import[^;]*;?",
        "url\\s*\\([^)]*\\)",
        "\\s(style|background|src|href|srcset)\\s*=\\s*\"[^\"]*\"",
        "\\s(style|background|src|href|srcset)\\s*=\\s*'[^']*'",
    ]
    for pattern in patterns {
        s = s.replacingOccurrences(
            of: pattern, with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    return s
}
```

(Adjust the exact regex set if a test reveals a gap; the intent is: no
surviving `<style>`, `<link>`, `<base>`, `@import`, `url(...)`, or
resource-bearing attribute.)

**Verify**: `swift build --package-path Packages/FreshlyCore` → exit 0.

### Step 2: Test the sanitizer against hostile inputs

Add cases to `ReleaseNotesLoaderTests.swift` (see Test plan). Run:

**Verify**: `swift test --package-path Packages/FreshlyCore --filter ReleaseNotes`
→ all pass.

### Step 3: Route the app renderer through the core sanitizer

In `Freshly/ReleaseNotesPopover.swift`, replace the inline
`html.replacingOccurrences(of: "</?(img|...)...")` call with
`ReleaseNotesLoader.sanitizedNotesHTML(html)` (the file already
`import FreshlySources`; if not, add it). Keep the font-`<style>` prefix and
the importer call as they are — note the prefixed `<style>` is a *local,
trusted* string, so it is fine, but confirm the sanitizer runs on the
untrusted `html` only, before the trusted prefix is prepended.

**Verify**:
`xcodebuild build -project Freshly.xcodeproj -scheme Freshly -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
→ `** BUILD SUCCEEDED **`, and
`grep -n "img|picture|script" Freshly/ReleaseNotesPopover.swift` → returns
nothing (the inline regex is gone, replaced by the core call).

## Test plan

In `ReleaseNotesLoaderTests.swift`, add a suite/cases asserting
`ReleaseNotesLoader.sanitizedNotesHTML(...)` output **does not contain**
(case-insensitive) any of: `<style`, `<link`, `<base`, `@import`, `url(`,
`src=`, `href=`, `background=`, or `<img`. Cover:
- Happy path: `"<h2>New</h2><p>Fixed a <b>crash</b></p>"` survives with its
  `<h2>/<p>/<b>` intact (assert `<b>` still present).
- `<style>body{background:url(https://evil.example/x.png)}</style>` → no
  `url(` and no `<style` remain.
- `<link rel="stylesheet" href="https://evil.example/x.css">` → no `<link`.
- `<p style="background:url('https://evil.example/beacon')">hi</p>` → no
  `url(` and no `style=` remain; `hi` survives.
- `<img src="https://evil.example/track.gif">` → no `<img`.
- A 300 KB string → output length ≤ 200 000.

Model the file's existing swift-testing structure. Verification:
`swift test --package-path Packages/FreshlyCore --filter ReleaseNotes` → all
pass including the new cases.

## Done criteria

ALL must hold:

- [ ] `swift test --package-path Packages/FreshlyCore` exits 0 with the new
      sanitizer tests present and passing.
- [ ] `ReleaseNotesLoader.sanitizedNotesHTML` exists and is `public`.
- [ ] `grep -n "img|picture|script" Freshly/ReleaseNotesPopover.swift`
      returns nothing (inline regex removed).
- [ ] `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row for 002 updated.

## STOP conditions

Stop and report if:

- The "Current state" excerpts don't match the live code (drift).
- `xcodebuild` is unavailable — finish the core sanitizer + tests, commit
  those, and report that Step 3 needs an Xcode host.
- A test reveals the sanitizer misses a vector you cannot neutralize with a
  regex adjustment within two attempts — report it; do not weaken the test.

## Maintenance notes

- **Deferred (maintainer decision)**: whether to abandon the WebKit HTML
  importer entirely in favor of an allowlist/Markdown renderer, which would
  fully eliminate the class rather than enumerate its vectors. This plan is
  the pragmatic surface reduction; the fuller change is roadmap M11.
- Reviewer: confirm the sanitizer runs on the untrusted feed HTML *before*
  the trusted font `<style>` prefix is prepended, and that Markdown/
  plain-text paths were not altered.
- If a new source ever returns `.html`, it flows through this same sanitizer
  automatically — no per-source work needed.
