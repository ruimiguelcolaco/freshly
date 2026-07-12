import Foundation

/// An application discovered on disk by the scanner.
public struct InstalledApp: Sendable, Hashable, Codable, Identifiable {
    /// The bundle path uniquely identifies an installation — the same bundle
    /// ID can legitimately exist at two paths (e.g. two copies of an app).
    public var id: URL { path }

    public var bundleID: String
    public var name: String
    public var path: URL
    /// `CFBundleShortVersionString`.
    public var version: AppVersion
    /// `CFBundleVersion`, when it differs from the marketing version.
    public var build: String?
    public var signature: SignatureInfo
    /// Channels this app appears to be installed or updated through,
    /// detected offline (Mac App Store receipt, Sparkle feed, Homebrew
    /// cask manifest). Used by the resolver to rank sources.
    public var installChannels: Set<SourceID>
    /// `SUFeedURL` from the app's `Info.plist`, when present.
    public var sparkleFeedURL: URL?
    /// `SUPublicEDKey` from the app's `Info.plist` — the EdDSA public key
    /// Sparkle updates must be signed with. When present, the installer
    /// refuses downloads that do not verify against it.
    public var sparklePublicEDKey: String?
    /// Where this app's electron-updater manifest (`latest-mac.yml` or a
    /// channel variant) lives, resolved by the scanner from the bundled
    /// `app-update.yml`.
    public var electronManifestURL: URL?

    public init(
        bundleID: String,
        name: String,
        path: URL,
        version: AppVersion,
        build: String? = nil,
        signature: SignatureInfo = SignatureInfo(status: .unknown),
        installChannels: Set<SourceID> = [],
        sparkleFeedURL: URL? = nil,
        sparklePublicEDKey: String? = nil,
        electronManifestURL: URL? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.version = version
        self.build = build
        self.signature = signature
        self.installChannels = installChannels
        self.sparkleFeedURL = sparkleFeedURL
        self.sparklePublicEDKey = sparklePublicEDKey
        self.electronManifestURL = electronManifestURL
    }
}
