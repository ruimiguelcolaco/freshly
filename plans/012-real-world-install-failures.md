# Plan 012: Diagnose and fix the four real apps that fail to update

> **Executor instructions**: This is a DIAGNOSE-FIRST plan. Do Step 1
> (capture the real error for each app) before proposing any fix — the root
> causes below are hypotheses, not conclusions. Run every verification
> command. If a STOP condition occurs, stop and report. When done, update
> the status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 2c207ce..HEAD -- Packages/FreshlyCore/Sources/FreshlyInstaller Packages/FreshlyCore/Sources/FreshlySources/AppcastParser.swift Packages/FreshlyCore/Sources/FreshlySources/SparkleSource.swift`
> If these changed since this plan was written, re-verify the hypotheses
> against current code.

## Status

- **Priority**: P1 (real users cannot update real apps — the core promise)
- **Effort**: M–L (diagnose is S; fixes vary per app, some may be L)
- **Risk**: MED (touches the install pipeline — the most safety-critical code)
- **Depends on**: none
- **Category**: bug / correctness
- **Planned at**: commit `2c207ce`, 2026-07-16

## Why this matters

On a real machine, **four of four** apps offered as updates fail to install
(each shows a warning badge + "Try Again" in the UI): Claude, Dia, Glaze,
Raycast. An updater that finds updates but cannot apply them fails at its one
job. The four fail through **four different paths**, so this is not one bug —
it is a robustness sweep of the install pipeline against real-world artifacts.
Each app must be verified individually.

## Current state — the four failures (from the scan cache, 2026-07-16)

All four are matched to a Homebrew cask or a Sparkle feed but are **not**
installed via `brew`, so Freshly runs its own download→verify→swap pipeline
(`FreshlyInstaller/UpdateInstaller.swift`). The exact `UpdateError` is
in-memory only (`AppListStore.installErrors`) and not persisted, so Step 1
must capture it.

| App | bundleID | installed → offered | source | artifact | team | notes |
|---|---|---|---|---|---|---|
| **Claude** | com.anthropic.claudefordesktop | 1.21459.0 → 1.21459.1 | homebrew (cask `claude`) | `.zip` (downloads.claude.ai) | Q6L2SF6YDW | not running |
| **Dia** | company.thebrowser.dia | 1.40.0 (b83317) → 1.40.0 (83508) | sparkle (EdDSA pinned) | **`.delta`** (`Dia-from-83438-to-83508.delta`) | S6N382Y83G | RC-channel feed |
| **Glaze** | app.glaze.macos.main | 0.9.1 → 0.10.0 | homebrew (cask `raycast-glaze`) | **`.dmg`** | SY64MV22J9 | not running |
| **Raycast** | com.raycast.macos | 1.104.22 → 1.104.23 | homebrew (cask `raycast`) | extensionless URL (sniffed) | SY64MV22J9 | **RUNNING** |

### Per-app hypotheses (to confirm in Step 1, not assume)

- **Dia — Sparkle binary delta (highest confidence).** The enclosure is a
  `.delta`, a Sparkle binary patch Freshly cannot apply; `ArchiveExtractor`
  has no `.delta` format and would throw `unsupportedArchive`. Compounding:
  the delta is *from* build 83438 but the installed build is 83317, so no
  delta-capable updater could apply it either. `AppcastParser` does not
  parse `<sparkle:deltas>` at all (grep: 0 hits), so Freshly is taking a
  delta as the top-level `<enclosure>`. Likely fix: the Sparkle source (or
  installer) must **reject/skip `.delta` enclosures** and use the full-update
  enclosure; if a feed offers only a delta, the app should not be reported as
  an installable update through Freshly's pipeline.
- **Raycast — running-app (high confidence).** It is running; a persistent
  menu-bar app may not quit/relaunch within the 10s budget
  (`RunningApps.quitIfNeeded`), yielding `appDidNotQuit`. Confirm whether the
  failure is the quit guard vs. a verification failure.
- **Glaze — DMG install.** Confirm where it fails: `hdiutil attach`
  (contention/format), the app-bundle location inside the image, Gatekeeper,
  or code-signature/team validation. Team SY64MV22J9.
- **Claude — zip via direct pipeline.** Confirm: Gatekeeper assessment,
  code-signature/team continuity (team Q6L2SF6YDW), or the zip's structure.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Core tests | `swift test --package-path Packages/FreshlyCore` | all pass |
| Build | `swift build --package-path Packages/FreshlyCore` | exit 0 |

## Scope

**In scope** (likely — confirm after Step 1):
- `Packages/FreshlyCore/Sources/FreshlyInstaller/` (ArchiveExtractor,
  UpdateInstaller) and `Packages/FreshlyCore/Sources/FreshlySources/`
  (SparkleSource, AppcastParser) — whichever the diagnosis implicates.
- The matching test files under `Tests/FreshlyCoreTests/`.
- A throwaway diagnostic harness (see Step 1) — **not committed**.

**Out of scope**:
- Do NOT change the install pipeline's security invariants (EdDSA, codesign,
  team continuity, downgrade, Gatekeeper). If an app fails *because* it fails
  a security check, that is the pipeline working — report it; do not weaken
  a check to make an app install.
- Do NOT implement Sparkle binary-delta application (a large feature). The
  Dia fix is to *skip* deltas, not apply them.

## Steps

### Step 1: Capture the real failure for each app — NON-DESTRUCTIVELY

Write a throwaway harness (a scratch SPM executable or a test) that runs the
pipeline **only up to validation, never the bundle swap**, against each app's
real release, and prints the resulting `UpdateError.reason`. Do NOT run the
full `UpdateInstaller.install` on Claude/Glaze/Raycast, because if
verification passes it would actually replace the installed app. Instead
drive `ArtifactDownloader` → `ArchiveExtractor.extractApp` →
`SignatureVerifier`/`Gatekeeper` directly (mirror the sequence in
`UpdateInstaller.performInstall` but stop before `replaceBundle`).

Use each app's real download URL from the scan cache
(`~/Library/Application Support/Freshly/last-scan.json`) or re-scan. Record,
per app, the exact stage and `UpdateError.Reason` that fails (or "reaches
validation cleanly" — meaning the real failure is running-app or permission,
not verification).

**Verify**: you have a concrete `UpdateError.Reason` (or "passes to swap")
for all four apps, written down.

### Step 2: Fix per app, guided by Step 1

Only now decide each fix. Expected shapes (adjust to what Step 1 found):

- **Dia / deltas**: in `SparkleSource` (or `AppcastParser`), ignore
  enclosures whose URL path ends in `.delta` (and any `<sparkle:deltas>`
  block), selecting the full-update enclosure; if only a delta is available,
  report no installable update. Add an `AppcastParserTests`/`SparkleSourceTests`
  case with a feed whose item carries both a full enclosure and a delta,
  asserting the full one is chosen; and a delta-only feed asserting no
  release (or a clear unsupported signal).
- **Raycast / running-app**: confirm the quit/relaunch path; if the 10s
  budget is the issue, consider a longer/among-retry budget or a clearer
  error — but do NOT force-kill. This may be "working as designed" (the app
  wouldn't quit) → then the fix is a better message, not a behavior change.
- **Glaze / Claude**: fix only what Step 1 pins down. If it is a genuine
  Gatekeeper/codesign/team failure, that is the security gauntlet doing its
  job — document it and surface a clearer error rather than installing.

Each behavioral fix needs a test. Do not batch unrelated fixes into one
commit — one commit per app/root-cause.

**Verify**: `swift test --package-path Packages/FreshlyCore` → all pass with
the new per-app regression tests.

### Step 3: Re-verify against the real apps (non-destructive where risky)

Re-run the Step 1 harness; confirm Dia no longer offers the delta (or is
correctly reported as no-update), and that the others reach the expected
outcome. For an app whose fix should let it install, the real end-to-end
install can be verified manually by the maintainer against a disposable copy.

## Done criteria

- [ ] A recorded `UpdateError.Reason` (or "passes validation") for all four
      apps from Step 1.
- [ ] For each root cause that is a real Freshly bug (at minimum Dia's
      delta handling), a fix plus a regression test that fails on the old
      code.
- [ ] `swift test --package-path Packages/FreshlyCore` exits 0.
- [ ] No security invariant weakened (EdDSA/codesign/team/downgrade/
      Gatekeeper unchanged in strength).
- [ ] Findings for any app whose failure is *not* a Freshly bug (e.g. app
      won't quit, or legitimately fails Gatekeeper) written up in NOTES.

## STOP conditions

Stop and report if:

- Fixing an app appears to require weakening a security check — report it as
  "app X fails verification legitimately" instead.
- Step 1 shows an app passes cleanly to the swap (so the real failure is
  environmental/running-app) — do not invent a pipeline bug; report it.
- The Dia fix would require implementing binary-delta application — out of
  scope; the fix is to skip deltas.

## Maintenance notes

- This is the first real-world robustness sweep of the installer; expect it
  to seed follow-up cases (more artifact shapes, more feeds). Keep each
  diagnosis + fix + test tightly scoped so the pipeline stays auditable.
- The delta case suggests a broader question: which Sparkle appcast features
  Freshly deliberately does not support (deltas, `<sparkle:deltas>`,
  informational updates) — document the supported subset in `ARCHITECTURE.md`.
- Reviewer: scrutinize that no fix relaxes verification; a "fix" that makes a
  previously-rejected artifact install must be proven safe, not just green.

## Report format

```
STATUS: COMPLETE | STOPPED
STEPS: per step — done/skipped + verification command result + the captured
       UpdateError.Reason per app
STOPPED BECAUSE: (only if STOPPED) which STOP condition, what was observed
FILES CHANGED: list
NOTES: per-app outcome — Freshly bug (fixed) vs. legitimate failure vs.
       environmental
```
