import Foundation

/// A release reported by an update source for an installed app.
public struct ReleaseInfo: Sendable, Hashable, Codable {
    public var version: AppVersion
    /// The release's build identifier (Sparkle's `sparkle:version`, which
    /// pairs with the installed app's `CFBundleVersion`). When both sides
    /// have one, freshness is decided by builds, not marketing versions —
    /// feeds often decorate `shortVersionString` (e.g. `1.39.0 (83141)`)
    /// in ways that would read as newer than the installed `1.39.0`.
    public var build: String?
    /// Base64 EdDSA signature of the download artifact (Sparkle's
    /// `sparkle:edSignature`), verified against the installed app's
    /// `SUPublicEDKey` before installing.
    public var edSignature: String?
    /// Base64 SHA-512 of the download artifact, when the source publishes
    /// one (electron-updater manifests). Verified after download; unlike
    /// EdDSA it proves integrity, not identity, so Gatekeeper still runs.
    public var sha512: String?
    /// Homebrew cask token, set by the Homebrew source so the installer
    /// can upgrade through `brew` when the app was installed with it.
    public var caskToken: String?
    public var source: SourceID
    /// Direct download for the update artifact, when the source provides one.
    /// `nil` means the source can only redirect (e.g. the Mac App Store).
    public var downloadURL: URL?
    public var releaseNotesURL: URL?
    /// Notes published as a separate document meant for inline display
    /// (Sparkle's `releaseNotesLink`), as opposed to `releaseNotesURL`,
    /// which is a page for the browser.
    public var embeddedNotesURL: URL?
    /// Inline release notes, when the source embeds them (appcast, GitHub).
    public var changelog: String?
    public var publishedAt: Date?
    /// Minimum macOS version declared by the release, when known.
    public var minimumOSVersion: String?

    /// Whether this release is newer than what is installed, using the
    /// strongest comparison available: builds when both sides have one
    /// (Sparkle semantics), marketing versions otherwise.
    public func isNewer(than app: InstalledApp) -> Bool {
        if let releaseBuild = build, let installedBuild = app.build {
            return AppVersion(releaseBuild) > AppVersion(installedBuild)
        }
        return version > app.version
    }

    /// Whether installing this release would be a genuine downgrade over the
    /// installed app. Used by the installer on the *extracted* bundle, whose
    /// `Info.plist` carries the app's own clean `CFBundleShortVersionString`
    /// (not a feed-decorated one), so — unlike `isNewer` — the marketing
    /// version decides and the build only breaks a marketing-version tie.
    /// This matters for apps that ship a static `CFBundleVersion` (e.g.
    /// `0`) while their marketing version increments: `isNewer`'s
    /// build-first rule reads `0 == 0` as "not newer" and would block a real
    /// upgrade. Equal or newer is never a downgrade.
    public func isDowngrade(over app: InstalledApp) -> Bool {
        if version != app.version {
            return version < app.version
        }
        if let build, let installedBuild = app.build {
            return AppVersion(build) < AppVersion(installedBuild)
        }
        return false
    }

    public init(
        version: AppVersion,
        build: String? = nil,
        edSignature: String? = nil,
        sha512: String? = nil,
        caskToken: String? = nil,
        source: SourceID,
        downloadURL: URL? = nil,
        releaseNotesURL: URL? = nil,
        embeddedNotesURL: URL? = nil,
        changelog: String? = nil,
        publishedAt: Date? = nil,
        minimumOSVersion: String? = nil
    ) {
        self.version = version
        self.build = build
        self.edSignature = edSignature
        self.sha512 = sha512
        self.caskToken = caskToken
        self.source = source
        self.downloadURL = downloadURL
        self.releaseNotesURL = releaseNotesURL
        self.embeddedNotesURL = embeddedNotesURL
        self.changelog = changelog
        self.publishedAt = publishedAt
        self.minimumOSVersion = minimumOSVersion
    }
}
