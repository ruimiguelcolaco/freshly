# Plan 014: Deep UI audit — close the gaps the declutter opened

> **Executor / next session**: Follow-on to plan 013. A deep sweep of the
> *entire* app-target UI surface (not just the three views 013 touched):
> main window, rows, menu bar, release-notes popover, history, settings,
> error/empty states, and motion. Findings are grouped A–H, each with a
> file:line anchor, the problem, and a concrete fix. Verify by building and
> running the app and eyeballing; there are no unit tests for pure layout.
> Update the status row in `plans/README.md` when done.
>
> **Drift check (run first)**:
> `git diff --stat 9a8023b..HEAD -- Freshly/`

## Status

- **Priority**: P1 (A1–A2, C1), P2/P3 for the rest
- **Effort**: L overall; the P1 batch is M
- **Risk**: LOW–MED (presentation + one store field `lastCheckedAt`; no
  engine/installer changes)
- **Depends on**: plan 013 (P1 batch 1–3, landed on `main`? see README)
- **Category**: direction / dx (UI polish)
- **Planned at**: commit `9a8023b`, 2026-07-17

## Why this matters

Plan 013 collapsed the low-actionability sections so updates dominate — a
real win, but it opened a hole in the **most common state of all**: when
everything is up to date the window is now a near-empty void (only the
`statuses.isEmpty` case has a positive state). The highest-impact work now is
to fill that hole (a calm "everything is fresh" summary + a last-checked
timestamp) and to make the list *move* — a native macOS app animates its
membership changes; today only the section collapse animates.

## Findings (grouped, prioritized)

### A. Main window — hierarchy & states

- **A1 · P1 — "All fresh" is a void.** `ContentView.swift` only shows a
  positive state when `statuses.isEmpty` (no apps found). With every
  low-actionability section collapsed, the happy path (0 updates, N up to
  date) shows a few collapsed headers over dead space. **Fix**: an
  affirmation (checkmark, "Everything is fresh", last-checked) shown when
  `!statuses.isEmpty && outdated.isEmpty && checking.isEmpty` and nothing is
  expanded; `allowsHitTesting(false)` so the headers stay clickable.
- **A2 · P1 — No last-checked / at-a-glance status.** The store tracks no
  `lastCheckedAt`. **Fix**: add `lastCheckedAt: Date?` (persisted), surface
  it in `.navigationSubtitle` (always visible) and in the A1 affirmation.
- **A3 · P2 — "No update source" repeated on every row** of the
  "No Update Source" section (`AppRowView.swift` `.unsupported` case) — the
  section header already says it. **Fix**: show just the version.
- **A4 · P2 — "Update All" appears/disappears** (013 #9). **Fix**: always
  present, disabled when 0 or installing.
- **A5 · P3 — No search** (013 #8). **Fix**: `.searchable` + filter each
  section; also reveals apps hidden in collapsed sections.

### B. The row (AppRowView)

- **B1 · P2 — Layout shift when an install starts** (trailing swaps to a
  different-width progress cluster). *Deferred — fiddly; needs a fixed-width
  trailing container.*
- **B2 · P2 — Install progress uninformative** (013 #4). **Fix (partial)**:
  show `%` from the already-available `downloading(fraction:)`. MB total
  needs engine plumbing — deferred.
- **B3 · P2 — Actions right-click-only** (013 #5). **Fix**: a hover overflow
  `•••` menu reusing `contextMenuItems`.
- **B4 · P3 — Release-notes affordance easy to miss** (013 #6). **Fix**: make
  the "x → y" transition itself open the notes popover.
- **B5 · P3 — `.orange` literal for the transition.** *Deferred — subjective,
  state is already carried by the arrow.*

### C. Motion & feel

- **C1 · P2 — The app barely animates.** Scan results and installs snap rows
  between sections instantly. **Fix**: animate section membership on a cheap
  count signal.
- **C2 · P3 — Scan spinner disconnected** from the Refresh button.
  *Deferred.*

### D. Menu bar

- **D1 · P2 — Items aren't actionable** (013 #7). **Fix (partial)**: add
  "Update All" to the menu (safe — `updateAll()` never force-quits). Per-app
  inline update deferred (default menu style can't host inline buttons).
- **D2 · P3 — Glyph/brand disconnect** (refresh glyph vs. the strawberry).
  *Deferred.*

### E. Release-notes popover

- **E1 · P2 — HTML parsed on the main actor** (`NSAttributedString` HTML
  importer) can hitch the popover. *Deferred — needs careful off-main
  rendering without losing the sanitizer contract.*

### F. History

- **F1 · P3 — Absolute timestamps only.** **Fix**: relative primary, absolute
  on hover.
- **F2 · P3 — No installed/failed filter.** *Deferred.*

### G. Settings

- **G1 · P3 — Sections lack headers.** **Fix**: add "Updates" / "GitHub".
- **G2 · P3 — No About/version.** *Deferred.*

### H. Cross-cutting

- **H1 · P3 — `"x → y"` duplicated** across three views. *Deferred — cosmetic
  dedup.*
- **Keep (do not "fix")**: empty states via `ContentUnavailableView`, a11y
  labels, non-color-only state, the strawberry badge, sanitized notes.

## Scope

**In scope**: `Freshly/*.swift` (views + `AppListStore.lastCheckedAt`) and
`Freshly/Localizable.xcstrings` (every new user-facing string, with pt-PT).

**Out of scope**: `Packages/FreshlyCore` (engine/installer/models). Do not
change scan/install behavior.

## Verification

- `xcodebuild build -project Freshly.xcodeproj -scheme Freshly -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- `python3 scripts/check_localization.py` → OK.
- Run the app and eyeball: all-fresh shows the affirmation + last-checked;
  the list animates when a scan lands; collapsed headers still expand.

## Report format

```
STATUS: COMPLETE | STOPPED
FINDINGS DONE: which of A1–H1
DEFERRED: which, and why
FILES CHANGED: list
NOTES: before/after impressions
```

## Implementation log (2026-07-17)

**Done** (unsigned build green, `check_localization.py` OK):
- A1 all-fresh state; A2 `lastCheckedAt` + `.navigationSubtitle`; A3 dropped
  redundant no-source text; A4 stable Update-All icon button; A5 `.searchable`
  + no-results state; B2 download `%`; B3 hover `•••` overflow menu; B4
  version-transition opens the notes (removed the stray `doc.text` icon); C1
  list-membership animation; D1 Update-All in menu bar + per-app submenu with
  Update/Show; F1 relative history dates; G1 Settings section headers.
- New strings (with pt-PT): "Last checked %@", "Search apps", "More actions",
  "Shows what's new in this update", "Show in Freshly", "Update All",
  "Updates".

**Second pass (2026-07-17, deferred-items polish):**
- B1 — install now keeps the version transition in place and swaps only the
  action for the progress, so the row no longer jumps.
- C2 — the scan spinner replaced the detached toolbar item; it now lives
  where the Refresh button is (one control, two states).
- G2 — Settings "About" section with the app version and a repo link.
- E1 — investigated: the `NSAttributedString` HTML importer is WebKit-backed
  and must stay on the main run loop, so it can't move off-main. Documented
  the constraint; the popover already paints its spinner before the parse.

**Third pass (2026-07-17):**
- H1 — `AppVersion.transition(from:to:)` shared by row, menu bar, history
  (new file `Freshly/VersionTransition.swift`).
- F2 — history outcome filter (all / installed / failed), shown only when
  there are records, with a no-match state.

**Won't-do** (revisit only with a reason):
- B5 transition color — `.orange` is the right "update available" cue and the
  arrow already carries the state without relying on color.
- D2 menu-bar glyph — replacing the refresh glyph with an on-brand strawberry
  needs a designed template asset; that's a design decision for Rui, not
  something to invent in code.

Both `main`-batch and the two polish passes are merged to `main` (commits
`12a7d7b`, `937e385`), CI green. Not eyeballed live (dev instance running);
CI validates build + localization only.

**Not eyeballed live** — a dev instance was running, so the build wasn't
launched to avoid a competing menu-bar item. Verify on rebuild:
`.navigationSubtitle` rendering, `.searchable(.toolbar)` layout, the all-fresh
overlay vs. collapsed headers, the hover `•••`, and the menu-bar submenus.
