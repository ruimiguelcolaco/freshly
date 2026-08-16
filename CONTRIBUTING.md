# Contributing to Freshly

Thanks for helping keep everyone's Macs fresh. This guide covers setup,
conventions, and the pull request flow.

## Setup

You need **macOS 15+** and **Xcode 26+**.

```sh
git clone https://github.com/ruimiguelcolaco/freshly.git
cd freshly
open Freshly.xcodeproj
```

Most logic lives in the `FreshlyCore` package and does not need Xcode at all:

```sh
swift test --package-path Packages/FreshlyCore
```

Before opening a pull request, run the same remaining gates as CI:

```sh
xcodebuild test -project Freshly.xcodeproj -scheme Freshly \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FreshlyDerivedData \
  CODE_SIGNING_ALLOWED=NO
swift run --package-path Packages/FreshlyCore validate-definitions \
  Definitions --pack definitions-catalog.json
git diff --exit-code definitions-catalog.json
python3 scripts/check_localization.py
```

DerivedData stays outside the repository because its iCloud-managed location
can add extended attributes that make codesigning reject otherwise valid build
products. Milestone 15 tracks replacing these individual commands with one
local verification entry point shared with CI.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before touching the source engine or
the installer — it documents the module boundaries and the security and
privacy invariants that pull requests must not break.

## What to work on

- Issues labeled `good first issue` are scoped for newcomers.
- New update sources: see [docs/ADDING_A_SOURCE.md](docs/ADDING_A_SOURCE.md).
- App definitions: see [docs/APP_DEFINITIONS.md](docs/APP_DEFINITIONS.md).
- Translations: add your language to `Freshly/Localizable.xcstrings`
  (English is the source; Portuguese shows the expected shape).
- Open a discussion before large changes so nobody duplicates work.

## Code style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Swift 6 strict concurrency; model types are `Sendable` value types.
- No file-header boilerplate (no "Created by…" blocks).
- Comments explain *why*, not *what*. Code, comments, and identifiers are in
  English.
- Logic changes come with tests. The version comparator in particular:
  every new real-world version string edge case gets a test in
  `AppVersionTests` first.
- Time-based behavior belongs in a pure policy under `FreshlyCore` with an
  injected `Date`; app-layer tasks should execute that policy rather than
  embedding wall-clock arithmetic.

## Commits and pull requests

- Imperative subject line, 72 characters or less
  (`Add Homebrew cask source`, not `Added…`/`Adding…`).
- Keep commits and PRs free of tool advertising: no auto-generated
  signatures, no `Co-authored-by` trailers for code-generation or AI
  assistants, and no references to such tools anywhere in code, comments,
  commit messages, or documentation.
- Target `main`. Every CI verification gate must pass.
- One logical change per PR. If you find an unrelated bug on the way, open
  an issue or a separate PR.

## Reporting security issues

Do **not** open a public issue — see [SECURITY.md](SECURITY.md).
