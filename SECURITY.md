# Security Policy

Freshly downloads and replaces application bundles on people's Macs. Security
reports are taken seriously and handled with priority.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately via
[GitHub Security Advisories](https://github.com/ruimiguelcolaco/freshly/security/advisories/new).
You should receive an initial response within 7 days.

## Scope

Anything that could make Freshly install or execute something it should not
is in scope, in particular:

- Bypasses of signature, notarization, or Gatekeeper verification in the
  install pipeline.
- Team-identifier confusion (getting Freshly to replace an app with a bundle
  signed by a different team).
- Time-of-check/time-of-use races between verification and installation.
- Downgrade attacks (tricking Freshly into "updating" to an older, vulnerable
  version).
- Appcast or catalog parsing issues that lead to fetching attacker-controlled
  artifacts.

## Supported versions

After the first public beta, only the newest published beta is supported.
Until then, only the latest state of `main` is supported.

Public beta builds are intentionally unsigned and require the Gatekeeper
exception documented in [docs/INSTALLING.md](docs/INSTALLING.md). Their release
archives are authenticated by published SHA-256 checksums and Sparkle EdDSA
signatures, but they are not notarized by Apple. Stable distribution will begin
only after Developer ID signing and notarization are available.
