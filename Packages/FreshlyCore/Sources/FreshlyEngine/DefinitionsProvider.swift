import FreshlyModels

/// Produces the effective definitions catalog for a scan: the bundled floor
/// (shipped inside the app) extended — and per app overridden — by the
/// repository's packed catalog, refreshed each scan. An unreachable or empty
/// remote leaves the bundled floor untouched.
///
/// The remote refresh is I/O; the merge below is pure, which is what makes the
/// override policy unit-testable. The caller supplies the bundled floor, since
/// only the app can read its own bundle resources.
public struct DefinitionsProvider: Sendable {
    private let remote: RemoteDefinitionsCatalog

    public init(remote: RemoteDefinitionsCatalog = RemoteDefinitionsCatalog()) {
        self.remote = remote
    }

    public func current(bundled: DefinitionsCatalog) async -> DefinitionsCatalog {
        Self.merge(remote: await remote.refresh(), over: bundled)
    }

    /// Remote definitions win per bundle ID — placed first, and the catalog
    /// keeps the first entry for a duplicate. An empty remote (offline, or a
    /// catalog that failed to parse) falls back to the bundled floor.
    static func merge(remote: [AppDefinition], over bundled: DefinitionsCatalog) -> DefinitionsCatalog {
        guard !remote.isEmpty else { return bundled }
        return DefinitionsCatalog(definitions: remote + Array(bundled.definitions.values))
    }
}
