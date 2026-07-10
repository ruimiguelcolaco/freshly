/// Progress of one in-place update, streamed by the installer so the UI can
/// show exactly where an update stands.
public enum InstallPhase: Sendable, Hashable {
    /// Queued behind other installs (bulk updates run sequentially).
    case waiting
    /// `fraction` is `nil` while the download size is unknown.
    case downloading(fraction: Double?)
    case verifyingDownload
    case extracting
    /// Signature, team, and Gatekeeper checks on the extracted bundle.
    case validating
    /// Backing up the old bundle and moving the new one into place.
    case installing
    case relaunching
    case finished
}
