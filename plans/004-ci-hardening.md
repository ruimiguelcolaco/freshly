# Plan 004: CI runs on a supported runtime, caches builds, and cancels stale runs

> **Executor instructions**: Follow this plan step by step. If anything in
> "STOP conditions" occurs, stop and report. When done, update the status
> row for this plan in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- .github/workflows/ci.yml`
> If the workflow changed since this plan was written, compare against the
> "Current state" excerpt; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx / dependencies
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

CI is the project's only automated verification, and it has three avoidable
weaknesses: `actions/checkout@v4` runs on the Node 20 action runtime the
runners now warn is deprecated (a hard break when GitHub retires it would
fail all three jobs at once); every push recompiles `FreshlyCore` cold in
three independent jobs with no caching (the slowest, most redundant part of
CI); and there is no `concurrency` group, so rapid pushes or PR force-pushes
leave obsolete runs burning macOS runner minutes to completion. All three
are standard, low-risk workflow hygiene.

## Current state

### `.github/workflows/ci.yml` (entire file)

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    name: Package tests
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Show toolchain
        run: |
          sw_vers
          xcodebuild -version
          swift --version
      - name: Run FreshlyCore tests
        run: swift test --package-path Packages/FreshlyCore

  build:
    name: App build
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Build (unsigned)
        run: |
          xcodebuild build \
            -project Freshly.xcodeproj \
            -scheme Freshly \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO

  definitions:
    name: Validate app definitions
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Validate and repack
        run: |
          swift run --package-path Packages/FreshlyCore validate-definitions Definitions \
            --pack definitions-catalog.json
      - name: Packed catalog must be committed up to date
        run: git diff --exit-code definitions-catalog.json
```

`FreshlyCore` has zero third-party dependencies and no `Package.resolved`, so
the cache key must be **source-hash based**, not lockfile based. The `test`
and `definitions` jobs both compile the package via SPM; `build` compiles it
via xcodebuild.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Validate YAML locally (if `actionlint` present) | `actionlint .github/workflows/ci.yml` | no errors (skip if not installed) |
| Confirm the job names are unchanged | `grep -n "name:" .github/workflows/ci.yml` | still `Package tests` / `App build` / `Validate app definitions` |

> The real verification is the run on GitHub after the change is pushed —
> but do NOT push unless the operator instructed it. Local checks are
> structural only.

## Scope

**In scope**:
- `.github/workflows/ci.yml` (only this file)

**Out of scope**:
- Merging or renaming jobs — keep the three job names exactly
  (`Package tests`, `App build`, `Validate app definitions`); branch
  protection may reference them by name.
- The `macos-26` runner pin — intentional (Xcode 26 determinism); leave it.
- Any change to the actual test/build/validate commands.

## Git workflow

- Branch: `advisor/004-ci-hardening`
- One commit; imperative subject ≤72, no trailers, e.g. "Harden CI:
  cache builds, cancel stale runs, bump checkout".

## Steps

### Step 1: Add a workflow-level concurrency group

Directly under the `on:` block (before `jobs:`), add:

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

**Verify**: `grep -n "cancel-in-progress" .github/workflows/ci.yml` → one
match.

### Step 2: Bump `actions/checkout` to the current major

Change all three `uses: actions/checkout@v4` to the current major that ships
on a supported Node runtime — `actions/checkout@v5` at time of writing.
Verify on the Actions marketplace that v5 is the current major; if a newer
major exists, use that instead.

**Verify**: `grep -c "actions/checkout@v4" .github/workflows/ci.yml` → 0;
`grep -c "actions/checkout@v5" .github/workflows/ci.yml` → 3 (or the chosen
major, 3×).

### Step 3: Cache the SPM build directory for the two Swift jobs

In the `test` job and the `definitions` job, add an `actions/cache` step
immediately after the `checkout` step and before the compile step:

```yaml
      - name: Cache SPM build
        uses: actions/cache@v4
        with:
          path: Packages/FreshlyCore/.build
          key: ${{ runner.os }}-spm-${{ hashFiles('Packages/FreshlyCore/Package.swift', 'Packages/FreshlyCore/Sources/**') }}
          restore-keys: |
            ${{ runner.os }}-spm-
```

(Verify `actions/cache`'s current major the same way as Step 2; `@v4` at
time of writing.)

**Verify**: `grep -c "actions/cache" .github/workflows/ci.yml` → 2.

### Step 4 (optional): Cache DerivedData for the app-build job

If you want to extend caching to the `build` job, add after its checkout:

```yaml
      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: ${{ runner.os }}-dd-${{ hashFiles('Freshly/**', 'Packages/FreshlyCore/Sources/**') }}
          restore-keys: |
            ${{ runner.os }}-dd-
```

This is lower-value and slightly flakier than the SPM cache; include it only
if it doesn't complicate the diff. Skipping it is acceptable.

**Verify** (if included): the workflow still parses (`actionlint` clean, or
YAML is well-formed).

## Test plan

No unit tests (workflow file). Verification is structural + the eventual CI
run:
- `grep` checks in each step above pass.
- The three job names are unchanged (`grep -n "name:"`).
- If the operator later pushes, all three jobs go green and the run log
  shows cache hits on the second run.

## Done criteria

ALL must hold:

- [ ] `grep -c "actions/checkout@v4" .github/workflows/ci.yml` = 0.
- [ ] `grep -c "cancel-in-progress" .github/workflows/ci.yml` = 1.
- [ ] `grep -c "actions/cache" .github/workflows/ci.yml` ≥ 2.
- [ ] Job names `Package tests`, `App build`, `Validate app definitions` are
      all still present.
- [ ] No files outside `.github/workflows/ci.yml` modified.
- [ ] `plans/README.md` status row for 004 updated.

## STOP conditions

Stop and report if:

- The "Current state" workflow excerpt doesn't match the live file (drift).
- You cannot determine the current `actions/checkout` / `actions/cache`
  major — report and leave `@v4` rather than guessing a version that may not
  exist.
- Adding the cache step would require restructuring the jobs — do not merge
  or rename jobs; report instead.

## Maintenance notes

- Deferred (optional future): folding the `definitions` validation into the
  `test` job would remove one of the three cold compiles, but changes the
  status-check surface — left out here to keep job names stable.
- Reviewer: confirm the cache key hashes the Swift sources (not a lockfile —
  there isn't one), so a genuine source change invalidates the cache.
- When GitHub deprecates the next `checkout`/`cache` major, bump again.
