# Plan 013: Declutter the main window and sharpen the UI

> **Executor / next session**: This is a UI/UX plan from a design audit of
> the running app (2026-07-16). Each finding names the file:line, the
> problem, and a concrete suggestion. Start with the P1 batch (1–3) — they
> transform the view's density with little code. Verify by building and
> running the app and eyeballing the result; there are no unit tests for
> pure layout. Update the status row in `plans/README.md` when done.
>
> **Drift check (run first)**:
> `git diff --stat 9a8023b..HEAD -- Freshly/AppRowView.swift Freshly/ContentView.swift Freshly/MenuBarView.swift`

## Status

- **Status**: DONE — findings 1–9 shipped; finding 10 was covered by the
  follow-up row redesign in plan 014
- **Priority**: P1 (P1 items), P2/P3 for the rest
- **Effort**: M overall; items 1–2 are S, 3 is M
- **Risk**: LOW (presentation only; no engine/installer changes)
- **Depends on**: none
- **Category**: direction / dx (UI polish)
- **Planned at**: commit `9a8023b`, 2026-07-16

## Why this matters

The app is clean and native, but the main window is dominated by
low-actionability content — ~37 up-to-date apps, a green trust seal on every
row, and a bundle ID under every name — which dilutes the one thing that
matters: what has an update. The highest-impact fixes are cheap. Grounded in
a real machine showing 1 update + 37 up-to-date apps.

## Current state

Main window: `Freshly/ContentView.swift` (a `List` of `Section`s: Updates
Available / Checking / Up to Date / Skipped / No Update Source, `.inset`
style). Each row: `Freshly/AppRowView.swift` — 32px app icon, bold name + a
signature seal, bundle ID (caption/secondary), and trailing content (version
or version-transition, a release-notes `doc.text` button, an Update button,
or an up-to-date `checkmark.circle`). Context menu holds Skip / Update Via /
Reveal / Download-in-browser. Menu bar: `Freshly/MenuBarView.swift`.

## Findings (prioritized)

### P1 — biggest impact

**1. The trust seal is on every app — invert it.**
`AppRowView.swift:124-148` (`signatureBadge`) shows a green
`checkmark.seal.fill` for every signed/notarized app. When nearly all apps
are notarized it's noise, and it competes with the trailing up-to-date
`checkmark.circle` (two green marks per row). Show a badge **only** when
trust is *not* clean — `.adHocSigned` (orange `seal`) and `.unsigned` (red
`xmark.seal`); render nothing for `.notarized`/`.signed`. Keep the signing
identity available on hover of the app name (or a detail). This declutters
the whole list and makes the rare unsigned app stand out.

**2. Bundle IDs dominate the secondary line — repurpose it.**
`AppRowView.swift:28-30` shows `status.app.bundleID` under every name.
It's developer metadata most users don't parse. Suggested: for outdated
rows, show the update **source** there instead (`best.source.displayName`,
e.g. "via Homebrew") and/or a relative date from `best.publishedAt`; for
up-to-date rows, drop it or show it only on hover. Keep the bundle ID
reachable (hover/`help`, or a detail popover) for definitions contributors.

**3. The "Up to Date (37)" section buries the updates.**
`ContentView.swift:23-27`. Up-to-date apps are least actionable but consume
~95% of the window. Options in order of effort: (a) wrap that section in a
`DisclosureGroup` collapsed by default; (b) add a segmented filter at the top
(All · Updates · Ignored · No source) that scopes the list; (c) at minimum,
visually recede up-to-date rows (smaller/dimmer). (a) or (b) is the biggest
hierarchy win.

### P2 — noticeable polish

**4. Download progress lacks transferred and total size.** *(Partially fixed.)*
The row now shows the already-available percentage alongside its progress
bar. A downloaded/total MB readout would still need byte counts plumbed from
`ArtifactDownloader` through `InstallPhase`; consider it only if percentage
plus the existing multi-phase labels still proves insufficient in use.

**5. Row actions are right-click-only — low discoverability.**
`AppRowView.swift:158-197` (`contextMenuItems`). Skip / Update Via / Reveal /
Download are hidden in the context menu. Add a hover-revealed overflow
(`•••`, `Menu` with `ellipsis.circle`) button per row, or at least surface
"Skip This Version" on outdated rows.

**6. The release-notes affordance is easy to miss.**
`AppRowView.swift:94-96` — a small secondary `doc.text` icon squeezed between
the version and the Update button. Make the version-transition text itself
tappable to open the notes, or use a clearer "What's new" affordance.

**7. Menu-bar items aren't actionable.**
`MenuBarView.swift` — each outdated item only opens the window. Add an inline
"Update" for non-running apps (the reusable action is
`AppListStore.requestUpdate(for:)`). (This is also direction finding
DIRECTION-03; if plan for that lands, dedupe.)

### P3 — scale & detail

**8. No search.** Add `.searchable` on the list — helps find a specific app
and scales past ~40 apps.
**9. "Update All" appears/disappears** (`ContentView.swift:49-56`), shifting
the toolbar layout. Show it always (disabled at 0) or as an icon.
**10. Row balance** — a wide empty gap between name and version on up-to-date
rows vs. a crowded trailing edge on outdated rows; tightening or reusing the
gap (finding 2) helps.

## What is already good (do not "fix")

Accessibility labels on icon-only buttons and the version transition; update
state is not color-only (the "→" text carries it); empty/scanning states via
`ContentUnavailableView`; the strawberry menu-bar badge; the release-notes
popover carrying the Update action.

## Scope

**In scope**: `Freshly/AppRowView.swift`, `Freshly/ContentView.swift`,
`Freshly/MenuBarView.swift`, and `Freshly/Localizable.xcstrings` (any new
user-facing string MUST be added there — the CI localization guard
`scripts/check_localization.py` fails otherwise; add the pt-PT translation).

**Out of scope**: the engine/installer/models (`Packages/FreshlyCore`) — this
is presentation only. Do not change scan/install behavior.

## Verification

- `xcodebuild build -project Freshly.xcodeproj -scheme Freshly -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- `python3 scripts/check_localization.py` → OK (if any `String(localized:)`
  was added).
- Run the app and eyeball: updates dominate; no green seal on notarized apps;
  the list reads calmer. (Note: the app lives in the menu bar — quit stray
  instances via each menu-bar icon's "Quit Freshly".)

## Recommended first batch

Do **1, 2, 3 together** — inverting the seal, repurposing the bundle-ID line,
and receding/collapsing the up-to-date section are mutually reinforcing and
land the biggest declutter for the least code. Consider a mock-up of the
redesigned row + list before implementing.

## Report format

```
STATUS: COMPLETE | STOPPED
FINDINGS DONE: which of 1–10
FILES CHANGED: list
NOTES: screenshots / before-after impressions, anything deferred
```
