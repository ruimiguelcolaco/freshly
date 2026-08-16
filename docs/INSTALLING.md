# Installing Freshly

Freshly is distributed directly through GitHub, not through the Mac App
Store. Public beta builds are unsigned while the project validates the product
with early users. A signed and notarized build will replace them before the
general release.

## Public beta

1. Download `Freshly-<version>.dmg` and `SHA256SUMS` from the same GitHub
   release.
2. In Terminal, calculate the disk image checksum:

   ```sh
   shasum -a 256 ~/Downloads/Freshly-<version>.dmg
   ```

   Confirm that it matches the `Freshly-<version>.dmg` line in
   `SHA256SUMS`.
3. Open the disk image and drag Freshly to the Applications shortcut.
4. Try to open Freshly once. macOS will block the unsigned beta because it
   cannot identify its developer.
5. Open **System Settings → Privacy & Security**, scroll to Security, choose
   **Open Anyway** for Freshly, then confirm the choice.

Apple documents this exception in
[Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).
Only bypass Gatekeeper for a beta downloaded from this repository whose
checksum matches the published value. The exception is normally required only
for the first launch of each manually downloaded build.

Freshly checks daily for its own updates while it is running. Its Sparkle
archives are authenticated with the project's EdDSA key, and every update
alert includes the version changelog and asks before installation.

## General release

The general release will be signed with Developer ID and notarized by Apple.
It will use the same disk-image installation flow without the unidentified-
developer override. Existing beta users will be offered the signed release
through Freshly's updater.
