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

Until the first stable release, only the latest state of `main` is supported.
