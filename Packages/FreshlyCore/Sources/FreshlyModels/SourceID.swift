/// Identifies an update source implementation.
///
/// Adding a new source starts with a new case here; see
/// `docs/ADDING_A_SOURCE.md` in the repository root.
public enum SourceID: String, Sendable, Codable, CaseIterable, Hashable {
    case sparkle
    case macAppStore
    case homebrew
    case github
    /// electron-updater (Squirrel.Mac), detected via the app's bundled
    /// `app-update.yml`.
    case electron
}
