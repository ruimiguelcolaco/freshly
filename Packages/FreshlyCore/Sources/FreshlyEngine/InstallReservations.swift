/// Tracks in-flight install identifiers so only one pipeline can own an app
/// at a time. Callers reserve synchronously before creating asynchronous work
/// and release when that work finishes.
public struct InstallReservations<ID: Hashable & Sendable>: Sendable {
    private var identifiers: Set<ID> = []

    public init() {}

    /// Returns `true` only for the request that acquired the install slot.
    public mutating func reserve(_ id: ID) -> Bool {
        identifiers.insert(id).inserted
    }

    public mutating func release(_ id: ID) {
        identifiers.remove(id)
    }

    public func contains(_ id: ID) -> Bool {
        identifiers.contains(id)
    }
}
