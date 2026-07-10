import FreshlyModels

/// The set of update sources available to the coordinator. Sources are
/// registered at app startup; tests register mocks.
public struct SourceRegistry: Sendable {
    public private(set) var sources: [any UpdateSource]

    public init(sources: [any UpdateSource] = []) {
        self.sources = sources
    }

    public mutating func register(_ source: any UpdateSource) {
        sources.append(source)
    }

    /// Sources that apply to the given app, strongest claim first; ties
    /// keep registration order, so registering the Mac App Store source
    /// before Sparkle makes the receipt win when an app has both. The
    /// resolver treats the first source as the app's primary update channel
    /// and the rest as alternatives.
    public func applicableSources(
        for app: InstalledApp
    ) -> [(source: any UpdateSource, applicability: SourceApplicability)] {
        sources.enumerated()
            .compactMap { index, source -> (Int, any UpdateSource, SourceApplicability)? in
                let applicability = source.applicability(for: app)
                guard applicability != .notApplicable else { return nil }
                return (index, source, applicability)
            }
            .sorted { lhs, rhs in
                lhs.2 == rhs.2 ? lhs.0 < rhs.0 : lhs.2 > rhs.2
            }
            .map { (source: $0.1, applicability: $0.2) }
    }
}
