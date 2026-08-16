# App Definitions

Some apps can't be matched to an update channel from disk alone: they publish
releases on GitHub without declaring it, their Homebrew cask name isn't
guessable from the bundle ID, or their `Info.plist` reports versions in a
quirky way. *App definitions* fill that gap — a Git-versioned catalog of
per-app hints, contributed through pull requests like any other change.

This is the open equivalent of the "community updates" databases that
commercial updaters kept proprietary. The catalog lives in the repository,
its history is auditable, and every entry is reviewed in public.

The starter catalog covers more than twenty real apps across developer tools,
terminal emulators, media players, window and menu-bar utilities, system
monitors, virtualization, and commercial downloads. Each mapping names an
official appcast, Homebrew cask, or GitHub repository; the validator rejects
entries that do not identify at least one such channel.

## Schema

One JSON file per app in `Definitions/`, named after the bundle ID:

```json
{
    "bundleID": "com.example.App",
    "name": "Example",
    "homebrewCask": "example-app",
    "githubRepo": "example-org/example-app",
    "appcastURL": "https://example.com/appcast.xml",
    "quirks": {
        "versionKey": "CFBundleVersion"
    }
}
```

All fields except `bundleID` are optional, but at least one channel
(`homebrewCask`, `githubRepo`, or `appcastURL`) must be present:

| Field | Meaning |
|---|---|
| `homebrewCask` | Cask token, when name matching cannot find it — or refuses to, because several casks ship the same app name |
| `githubRepo` | `owner/repo` whose Releases carry this app's updates |
| `appcastURL` | Sparkle feed (https only) for apps that don't declare `SUFeedURL` — some configure it in code |
| `quirks.versionKey` | Which `Info.plist` key holds the comparable version (`CFBundleVersion` or `CFBundleShortVersionString`) |

## Ground rules

- Definitions only state facts about where an app publishes updates — they
  never contain download URLs to specific versions, and they cannot override
  the install pipeline's signature verification.
- The whole catalog is fetched in bulk by the app, never queried per-app, so
  no server learns a user's app list. There is no server-side component.
- Definitions are licensed [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
  so any other tool can reuse them freely.

## Contributing a definition

1. Create `Definitions/<bundle-id>.json`. The bundle ID of an installed
   app: `plutil -extract CFBundleIdentifier raw "/Applications/App.app/Contents/Info.plist"`.
2. Run the validator and regenerate the packed catalog (CI runs the same
   check on every PR and fails if the pack is stale):

   ```sh
   swift run --package-path Packages/FreshlyCore validate-definitions Definitions \
     --pack definitions-catalog.json
   ```

3. Open a PR describing how you verified the mapping — e.g. "the cask's
   `.app` matches this bundle ID", "the GitHub releases contain the same
   team-ID-signed bundle", "the appcast is the one the app's own updater
   uses".

## How definitions reach users

`definitions-catalog.json` at the repository root is the whole catalog as
one generated document. Freshly ships a copy inside the app bundle and
refreshes it from the repository's `main` branch on its regular scans
(one bulk request, ETag-cached), so a merged definition reaches users
without waiting for an app release.
