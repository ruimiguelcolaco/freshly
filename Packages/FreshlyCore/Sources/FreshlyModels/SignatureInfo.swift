/// The code-signing state of an application bundle or a downloaded update.
///
/// Freshly surfaces this in the UI and uses it as a hard gate in the install
/// pipeline: an update whose team identifier does not match the installed
/// app's is never installed.
public struct SignatureInfo: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Codable {
        /// Signed with a Developer ID certificate and notarized by Apple.
        case notarized
        /// Validly signed, but notarization was not confirmed.
        case signed
        /// Signed ad hoc (no identity — offers no authorship guarantee).
        case adHocSigned
        case unsigned
        /// Verification has not run yet or failed to produce a result.
        case unknown
    }

    public var status: Status
    /// The Apple Developer team identifier extracted from the signature.
    public var teamID: String?
    /// Human-readable signing identity, e.g. "Developer ID Application: …".
    public var signingIdentity: String?

    public init(status: Status, teamID: String? = nil, signingIdentity: String? = nil) {
        self.status = status
        self.teamID = teamID
        self.signingIdentity = signingIdentity
    }
}
