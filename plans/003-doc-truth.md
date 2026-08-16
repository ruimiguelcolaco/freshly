# Plan 003: The docs describe what the code actually does

> **Executor instructions**: Follow this plan step by step. This is a
> docs-only plan — no build or tests are required, but run the listed
> `grep`/`git` checks. If anything in "STOP conditions" occurs, stop and
> report. When done, update the status row for this plan in
> `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- ARCHITECTURE.md CHANGELOG.md docs/ADDING_A_SOURCE.md Packages/FreshlyCore/Sources/FreshlyInstaller/UpdateInstaller.swift`
> If any file changed since this plan was written, compare the "Current
> state" excerpts against the live text; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

`ARCHITECTURE.md` is declared the source of truth for the security
invariants, and `CHANGELOG.md` is the public record — both have drifted from
the code. A security spec that misstates the enforced verification order
erodes trust in the very document future changes are checked against, and a
changelog missing the headline feature (the fifth update source) is "stale
and wrong," which is worse than missing. Four small, zero-risk corrections.

## Current state

### A. Installer docstring omits SHA-512 — `Packages/FreshlyCore/Sources/FreshlyInstaller/UpdateInstaller.swift:5-17`

```swift
/// Downloads, verifies, and installs one update in place:
/// download → EdDSA → extract → validate (codesign, identity, downgrade,
/// Gatekeeper) → backup → swap → relaunch.
///
/// Verification policy, in order:
/// 1. When the installed app declares an EdDSA public key, the artifact's
///    signature must verify against it. This is Sparkle's trust anchor.
/// 2. The extracted bundle must pass deep code-signature validation, keep
///    the same bundle identifier, and be newer than what is installed
///    (downgrade protection).
/// 3. When the installed app has a team identifier, the update must be
///    signed by the same team.
/// 4. Without a verified EdDSA signature, Gatekeeper must accept the bundle.
```

The SHA-512 checksum step (present in the code, between EdDSA and extract,
and documented in `ARCHITECTURE.md` as rule 2) is missing from this
docstring.

### B. ARCHITECTURE numbered order vs. actual code — `ARCHITECTURE.md:122-147`

The list numbers deep code-signature validation (3) before identity (4)
before downgrade (5). The code (`UpdateInstaller.validate(...)`) actually
checks bundle-ID identity and downgrade *before* deep code-signature
validation, and splits the team check to after it. All checks still run and
the pipeline fails closed, so this is a documentation-accuracy issue, not a
security hole — but the "in this order" claim is wrong.

### C. CHANGELOG stopped at Milestone 7 — `CHANGELOG.md`

Everything is under `## [Unreleased]`, last updated at commit `5088cbb`
(Milestone 7). Since then the project shipped, per `git log` and
`ROADMAP.md` (Milestones 8 and 9 marked done): inline release notes, the
local update-history window, structured localized engine errors, the remote
definitions-catalog refresh, the Electron/electron-updater fifth source, the
menu-bar-first behavior with the count badge, and the Dock-icon Settings
toggle — plus two bug fixes (brew trailing-build-hash comparison; disk-image
mount retry). The file has only an `### Added` block, no `### Fixed`.

### D. Registration-order sentence names 4 of 5 sources — `ARCHITECTURE.md` (Conflict resolution paragraph)

The sentence reads "ties break by registration order: Mac App Store,
Sparkle, Homebrew, then Electron …" — omitting GitHub. GitHub is
candidate-only (never authoritative), so it cannot break an authoritative
tie, but listing four of five invites a double-take.

### E. ADDING_A_SOURCE step list is incomplete — `docs/ADDING_A_SOURCE.md:34-46`

The "Steps" list (SourceID case → create source → register → test →
document) never mentions the two exhaustive `switch`es a new `SourceID`
forces a contributor to extend: `SourceID.displayName` in
`Freshly/UpdateErrorMessages.swift` (also a `Localizable.xcstrings`
touch-point) and `embeddedNotes` in
`Packages/FreshlyCore/Sources/FreshlySources/ReleaseNotesLoader.swift`. Step
3 ("where the app assembles its `SourceRegistry`") gives no path; the actual
site is `Freshly/AppListStore.swift`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Confirm shipped work | `git log --oneline 5088cbb..240f692` | lists the M8/M9/menu-bar/Dock commits |
| Confirm no code touched | `git status --porcelain -- '*.swift'` | empty (docs plan) |

## Scope

**In scope**:
- `Packages/FreshlyCore/Sources/FreshlyInstaller/UpdateInstaller.swift`
  (docstring comment ONLY — no code logic)
- `ARCHITECTURE.md`
- `CHANGELOG.md`
- `docs/ADDING_A_SOURCE.md`

**Out of scope**:
- Any Swift code other than the `UpdateInstaller` header comment.
- Reordering the actual `validate()` checks — this plan documents reality,
  it does not change behavior.

## Git workflow

- Branch: `advisor/003-doc-truth`
- One commit is fine (all docs); imperative subject ≤72, no trailers, e.g.
  "Sync the security-invariant docs with the installer code".

## Steps

### Step 1: Add SHA-512 to the installer docstring (A)

Edit only the comment block at `UpdateInstaller.swift:5-17`: add SHA-512 to
the one-line flow (`download → EdDSA → SHA-512 → extract → validate …`) and
insert a numbered policy step for it (a published checksum, when present,
must match — integrity only, never waives Gatekeeper). Renumber the
following policy items.

**Verify**: `git diff --stat -- '*.swift'` shows only
`UpdateInstaller.swift` changed, and the diff is comment-only (no `func`/
`let`/`guard` lines changed).

### Step 2: Correct the ARCHITECTURE verification-order claim (B)

After the numbered invariants list (ends around `ARCHITECTURE.md:150`), add a
short clarifying sentence, e.g.: "All applicable checks must pass and the
pipeline fails closed; the numbering reflects trust role, not strict
execution order — on the extracted bundle, identity, downgrade, and
code-signature validation are mutually independent (a bundle whose
`Info.plist` was altered to pass the identity or downgrade checks cannot also
pass code-signature validation)." Do not renumber the list.

**Verify**: `grep -n "fails closed" ARCHITECTURE.md` → one match.

### Step 3: Bring the CHANGELOG current (C)

Under `## [Unreleased]`, add the shipped-since-5088cbb items to `### Added`
and create a `### Fixed` section. Match the existing entry voice (concise,
outcome-first). Add, at minimum:
- Added: inline release notes before updating; local update-history window
  (with clear-all); structured, localized engine error messages; remote
  definitions-catalog refresh (bulk, ETag-cached); Electron
  (electron-updater) as the fifth update source with SHA-512 artifact
  verification; menu-bar-first behavior with an update-count badge and a
  Dock-icon Settings toggle.
- Fixed: ignore brew's trailing build-hash when comparing cask versions
  (was a phantom update); retry disk-image mounts under load.

Cross-check names/dates against `git log --oneline 5088cbb..240f692`.

**Verify**: `grep -c "lectron" CHANGELOG.md` → ≥1, and
`grep -c "### Fixed" CHANGELOG.md` → 1.

### Step 4: Fix the registration-order sentence (D)

Append a clause to the sentence naming the four sources, e.g. "… then
Electron (GitHub is candidate-only and never breaks authoritative ties)".

**Verify**: `grep -n "candidate-only and never breaks" ARCHITECTURE.md` →
one match.

### Step 5: Complete the ADDING_A_SOURCE step list (E)

In `docs/ADDING_A_SOURCE.md`, (a) give Step 3 the concrete path
`Freshly/AppListStore.swift` (where the sources array is assembled), and
(b) add a step: a new source must extend the two exhaustive switches —
`SourceID.displayName` in `Freshly/UpdateErrorMessages.swift` (and add its
name to `Freshly/Localizable.xcstrings`) and `embeddedNotes` in
`Packages/FreshlyCore/Sources/FreshlySources/ReleaseNotesLoader.swift` — the
compiler will refuse to build until both are handled.

**Verify**: `grep -n "UpdateErrorMessages\|ReleaseNotesLoader" docs/ADDING_A_SOURCE.md`
→ both referenced.

## Done criteria

ALL must hold:

- [ ] `git status --porcelain -- '*.swift'` shows only
      `UpdateInstaller.swift`, and its diff is comment-only.
- [ ] `grep -c "lectron" CHANGELOG.md` ≥ 1 and `grep -c "### Fixed" CHANGELOG.md` = 1.
- [ ] `grep -n "fails closed" ARCHITECTURE.md` and
      `grep -n "candidate-only and never breaks" ARCHITECTURE.md` each match.
- [ ] `grep -n "UpdateErrorMessages" docs/ADDING_A_SOURCE.md` matches.
- [ ] No files outside the in-scope list modified.
- [ ] `plans/README.md` status row for 003 updated.

## STOP conditions

Stop and report if:

- The "Current state" excerpts don't match the live text (drift).
- The `UpdateInstaller.swift` diff would touch any non-comment line — the
  docstring edit must not alter code.

## Maintenance notes

- Keep the CHANGELOG's `[Unreleased]` block updated per feature commit going
  forward, so this drift doesn't recur.
- If the `validate()` order is ever actually reordered to match the doc
  numbering, remove the Step 2 clarifying sentence.
- Reviewer: confirm the installer docstring change is purely a comment.
