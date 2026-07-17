import FreshlyModels

extension AppVersion {
    /// The canonical "installed → available" rendering, shared by the row, the
    /// menu bar, and the update history so the arrow reads the same everywhere.
    static func transition(from: AppVersion, to: AppVersion) -> String {
        "\(from.rawValue) → \(to.rawValue)"
    }
}
