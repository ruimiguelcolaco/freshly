# Releasing Freshly

Freshly uses two direct-distribution stages:

- public betas are intentionally unsigned and use prerelease version tags;
- stable releases require Developer ID signing and Apple notarization.

Both stages create a draft GitHub release first. Publishing a draft is always
a separate maintainer decision after its artifacts and installation path have
been tested.

## One-time secrets

The `Release` workflow always expects:

- `SPARKLE_ED_PRIVATE_KEY`: private EdDSA key exported by Sparkle's
  `generate_keys` tool

Stable releases and signed manual dry runs additionally expect:

- `DEVELOPER_ID_APPLICATION_P12`: base64-encoded Developer ID Application
  certificate and private key in PKCS#12 format
- `DEVELOPER_ID_APPLICATION_PASSWORD`: password for that PKCS#12 file
- `APPLE_TEAM_ID`: Apple Developer team identifier
- `NOTARY_APPLE_ID`: Apple ID used by `notarytool`
- `NOTARY_PASSWORD`: app-specific password for that Apple ID

The Sparkle secret is configured. The remaining secrets are deferred until the
stable release. The workflow has read-only repository access while building;
only its separate draft-release job receives `contents: write`.

## Dry run

Run the complete, non-publishing path locally:

```sh
scripts/release/dry_run.sh
```

This creates an unsigned DMG and deterministic ZIP, validates project and
bundle versions, generates SHA-256 checksums, a signed Sparkle appcast, release
notes, and a Homebrew cask, then verifies the ZIP is reproducible and the
checksums match. Set `FRESHLY_RELEASE_OUTPUT` to a nonexistent directory to
keep the first result.

The GitHub `Release` workflow can also be dispatched with `signed` disabled.
It uploads the assembled files as a workflow artifact and never creates a
release. Once the Developer ID secrets exist, dispatching with `signed`
enabled exercises signing, notarization, and stapling without publishing.

## Publish a public beta

Beta versions use a suffix such as `1.0-beta.1`; their exact tag is therefore
`v1.0-beta.1`. A prerelease version tag selects the unsigned path
automatically.

1. Move the contents of `[Unreleased]` in `CHANGELOG.md` under a heading that
   exactly matches the beta version and leave a fresh empty `[Unreleased]`
   section.
2. Set `MARKETING_VERSION` to the beta version and increment
   `CURRENT_PROJECT_VERSION` in both app configurations.
3. Run `scripts/verify.sh` and `scripts/release/dry_run.sh`.
4. Create and push an annotated `v<MARKETING_VERSION>` tag.
5. Inspect the generated draft release. Verify `SHA256SUMS`, mount the DMG,
   drag the app to Applications, and follow [INSTALLING.md](INSTALLING.md) on
   a clean test account. Before declaring the beta update path proven, test a
   beta-to-beta update on both Apple Silicon and Intel.
6. Publish the draft as an ordinary GitHub release. Do not mark it with
   GitHub's prerelease flag: GitHub excludes prereleases from
   `releases/latest/download/appcast.xml`, which is Freshly's static Sparkle
   feed endpoint. The prerelease version and release title still identify it
   clearly as a public beta.

Unsigned beta artifacts must never be presented as notarized or as verified by
Apple. The GitHub release body includes the Gatekeeper warning and links to the
installation instructions automatically.

## Publish a stable release

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

Stable versions have no prerelease suffix. Their tags always require signing
and notarization; the workflow will fail closed if the required credentials
are unavailable. It signs and notarizes the app, then signs, notarizes, and
staples the DMG before recalculating its published checksum. Every beta and
stable tag must exactly match the app's marketing version.
