# Releasing Freshly

Release automation is prepared, but publishing remains blocked until the
project has a Developer ID Application certificate and notarization
credentials. Never publish an unsigned build.

## One-time secrets

The `Release` workflow expects these GitHub Actions secrets:

- `DEVELOPER_ID_APPLICATION_P12`: base64-encoded Developer ID Application
  certificate and private key in PKCS#12 format
- `DEVELOPER_ID_APPLICATION_PASSWORD`: password for that PKCS#12 file
- `APPLE_TEAM_ID`: Apple Developer team identifier
- `NOTARY_APPLE_ID`: Apple ID used by `notarytool`
- `NOTARY_PASSWORD`: app-specific password for that Apple ID
- `SPARKLE_ED_PRIVATE_KEY`: private EdDSA key exported by Sparkle's
  `generate_keys` tool

The Sparkle secret is configured. The remaining secrets require the Developer
ID certificate and Apple notarization account. The workflow has read-only
repository access while building; only its separate draft-release job receives
`contents: write`.

## Dry run

Run the complete, non-publishing path locally:

```sh
scripts/release/dry_run.sh
```

This creates an unsigned release archive, validates project and bundle
versions, generates a signed Sparkle appcast and Homebrew cask, then creates a
second archive and verifies that both archives are byte-identical. Set
`FRESHLY_RELEASE_OUTPUT` to a nonexistent directory to keep the first result.

The GitHub `Release` workflow can also be dispatched with `signed` disabled.
It uploads the assembled files as a workflow artifact and never creates a
release. Once the Developer ID secrets exist, dispatching with `signed`
enabled exercises signing, notarization, and stapling without publishing.

## Publish

1. Move the contents of `[Unreleased]` in `CHANGELOG.md` under a new version
   heading and leave a fresh empty `[Unreleased]` section.
2. Set `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in both app
   configurations.
3. Run `scripts/verify.sh` and the signed release dry run.
4. Create and push an annotated `v<MARKETING_VERSION>` tag.
5. Inspect the draft GitHub release, its appcast, archive, and cask before
   publishing the draft. Confirm that the appcast embeds the new version's
   changelog; installed copies show it in Sparkle's update alert.
6. Submit the generated `freshly.rb` to Homebrew Cask after the first public
   release exists.

Tag releases always require signing and notarization. The workflow rejects a
tag that does not exactly match the app's marketing version.
