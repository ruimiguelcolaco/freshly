# Plan 005: CI fails when a localized string has no catalog entry

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result. If anything in
> "STOP conditions" occurs, stop and report. When done, update the status
> row for this plan in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 240f692..HEAD -- Freshly/UpdateErrorMessages.swift Freshly/Localizable.xcstrings .github/workflows/ci.yml`
> If any file changed since this plan was written, compare against the
> "Current state" notes; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none (coordinates with 004 — both edit `ci.yml`)
- **Category**: tests / dx
- **Planned at**: commit `240f692`, 2026-07-15

## Why this matters

`Freshly/Localizable.xcstrings` is a String Catalog maintained **by hand**
(the project edits it with a merge script that is not in the repo), and the
app's 35+ engine error messages live in `Freshly/UpdateErrorMessages.swift`
as `String(localized:)` calls. The `UpdateError.Reason` and `SourceID`
switches there are exhaustive, so the *compiler* forces a new
`String(localized:)` when a case is added — but nothing forces the matching
catalog entry. Add a new error reason (the enum grows with the install
pipeline) or edit a message without hand-updating the catalog, and a user in
another locale silently gets an untranslated or mis-keyed string, invisible
until they hit that error. There is no current drift (all keys resolve
today), but nothing keeps it that way. This plan adds a CI check that fails
on any `String(localized:)` whose key is absent from the catalog.

The check normalizes interpolations robustly: a code key like
`"…HTTP \(status)"` and a catalog key like `"…HTTP %lld"` both collapse to
the same placeholder sentinel, so the comparison works without the script
knowing each interpolation's type.

## Current state

- `Freshly/UpdateErrorMessages.swift` — `UpdateError.message` and
  `SourceID.displayName`, each a `String(localized: "…")` per case; some
  keys interpolate, e.g.
  `String(localized: "Update check failed: \(source.displayName) returned HTTP \(status)")`.
- `Freshly/Localizable.xcstrings` — JSON: a top-level `"strings"` object
  whose **keys are the English source strings**; each value either has
  `"localizations": {"pt-PT": {...}}` or `"shouldTranslate": false`. The
  interpolated keys use printf placeholders, e.g.
  `"Update check failed: %@ returned HTTP %lld"`.
- Localized `String(localized:)` calls exist across several app files
  (`UpdateErrorMessages.swift`, and others). The check should scan all of
  `Freshly/**.swift`.
- `.github/workflows/ci.yml` — three jobs on `macos-26`; the repo has no
  `scripts/` directory yet. `python3` is available on the runner and on
  developer machines.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Run the check locally | `python3 scripts/check_localization.py` | exit 0, prints an OK summary |
| Confirm it can fail | (temporarily add a bogus `String(localized: "ZZZ nonexistent key")` to a Freshly `.swift`, rerun) | exit 1, names the missing key — then revert the bogus line |

## Scope

**In scope**:
- `scripts/check_localization.py` (create)
- `.github/workflows/ci.yml` (add one job)

**Out of scope**:
- Editing `Localizable.xcstrings` or any Swift source — this plan only adds
  the guard; if the guard finds a *real* current drift, STOP and report it
  (do not silently add catalog entries).
- Orphan detection (catalog keys with no code reference) — too noisy,
  because SwiftUI `Text("…")`/`Button("…")` literals also generate catalog
  keys. Only the forward direction (`String(localized:)` → catalog) is
  checked.

## Git workflow

- Branch: `advisor/005-localization-drift-guard`
- Commit the script, then the CI job; imperative subjects ≤72, no trailers.

## Steps

### Step 1: Write the check script

Create `scripts/check_localization.py`. It must:

1. Load `Freshly/Localizable.xcstrings` (JSON), take the set of keys under
   `"strings"`.
2. Scan every `Freshly/**/*.swift` file for `String(localized:` calls and
   extract the literal first argument (a double-quoted string, honoring
   `\"` escapes). Ignore any `String(localized:)` whose argument is not a
   plain string literal (e.g. a variable) — report those as "skipped" but
   don't fail on them.
3. Normalize both a code key and a catalog key to a common form by replacing
   each interpolation/placeholder with a single sentinel character:
   - code: replace every `\(…)` occurrence (`\\\([^)]*\)`) with `￼`.
   - catalog: replace every printf specifier
     (`%@`, `%lld`, `%ld`, `%d`, `%lf`, `%f`, and positional forms like
     `%1$@`) with `￼`.
4. Build the set of normalized catalog keys. For each extracted code key,
   normalize it and check membership. Collect any code key whose normalized
   form is not present.
5. Exit `1` and print each missing key (with the file it came from) if the
   missing set is non-empty; otherwise print a one-line OK summary
   (`checked N String(localized:) keys, all present`) and exit `0`.

Reference shape (adapt as needed; keep it dependency-free, stdlib only):

```python
#!/usr/bin/env python3
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
catalog = json.loads((ROOT / "Freshly/Localizable.xcstrings").read_text())
SENT = "￼"
placeholder = re.compile(r"%(?:\d+\$)?[@dlf]+")
interp = re.compile(r"\\\([^)]*\)")

def norm_catalog(k): return placeholder.sub(SENT, k)
def norm_code(k): return interp.sub(SENT, k)

catalog_norm = {norm_catalog(k) for k in catalog["strings"]}

call = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
missing, checked, skipped = [], 0, 0
for path in (ROOT / "Freshly").rglob("*.swift"):
    text = path.read_text()
    for m in call.finditer(text):
        checked += 1
        key = m.group(1)
        if norm_code(key) not in catalog_norm:
            missing.append((path.relative_to(ROOT), key))

if missing:
    print("Localization drift — String(localized:) keys missing from Localizable.xcstrings:")
    for p, k in missing:
        print(f"  {p}: {k!r}")
    sys.exit(1)
print(f"OK — checked {checked} String(localized:) keys, all present.")
```

Make it executable (`chmod +x`).

**Verify**: `python3 scripts/check_localization.py` → exit 0 with the OK
line. (There is no drift today, so it must pass on the unmodified repo.)

### Step 2: Prove the check can fail, then revert

Temporarily add `_ = String(localized: "ZZZ definitely not in the catalog")`
to any file under `Freshly/` (e.g. at the top of a function body that
compiles), run the script, confirm it exits `1` and names that key, then
**remove the temporary line**.

**Verify**: with the bogus line, `python3 scripts/check_localization.py;
echo $?` → prints the missing key and `1`; after reverting, → `0`.

### Step 3: Wire it into CI

Add a new job to `.github/workflows/ci.yml`:

```yaml
  localization:
    name: Localization check
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4   # or the major used elsewhere in this file
      - name: Check String Catalog coverage
        run: python3 scripts/check_localization.py
```

If plan 004 already landed, match its `actions/checkout` major and place the
job consistently with the others.

**Verify**: `grep -n "Localization check" .github/workflows/ci.yml` → one
match; the YAML is well-formed.

## Test plan

The script *is* the test. Its own verification (Step 2) demonstrates both a
pass (clean repo) and a fail (injected missing key). No swift-testing case is
added (the surface under test is the app target + the hand-maintained
catalog, neither reachable from `swift test`).

## Done criteria

ALL must hold:

- [ ] `scripts/check_localization.py` exists, is executable, and exits `0`
      on the unmodified repo.
- [ ] Injecting a bogus `String(localized:)` key makes it exit `1` naming
      that key (verified then reverted — the repo is clean at the end).
- [ ] `.github/workflows/ci.yml` has a `Localization check` job running the
      script.
- [ ] No files outside the in-scope list are modified (in particular,
      `Localizable.xcstrings` is unchanged).
- [ ] `plans/README.md` status row for 005 updated.

## STOP conditions

Stop and report (do not improvise) if:

- The script finds a **real** missing key on the unmodified repo — that is a
  genuine current drift; report the exact key(s) rather than editing the
  catalog to paper over it (fixing it may need the project's translation
  workflow).
- The interpolation/placeholder normalization can't reconcile a legitimate
  code/catalog pair after two adjustments — report the specific pair; the
  normalization may need a placeholder form you haven't handled (e.g. a
  format you didn't anticipate), and getting it wrong would make CI flaky.
- Adding the job would force renaming or restructuring the existing jobs.

## Maintenance notes

- **Coordinates with plan 004**: both edit `ci.yml`. Land order doesn't
  matter; if they conflict, keep 004's concurrency/cache additions and this
  job together.
- This guards only `String(localized:)`. If the project later wants full
  coverage (SwiftUI view literals too), that is a larger, noisier check —
  out of scope here.
- **Prerequisite it does NOT cover**: standing up a real unit-test *target*
  for the `Freshly` app (TESTS-01) requires adding a target to
  `Freshly.xcodeproj` — best done in Xcode by the maintainer, and the
  precondition for roadmap plan 006 (extracting orchestration into a
  testable engine facade). This plan delivers the immediately-shippable,
  no-Xcode-editing slice of the localization guard; it does not create the
  app test target.
- Reviewer: confirm the script is stdlib-only and the normalization handles
  the interpolated error messages in `UpdateErrorMessages.swift`.
