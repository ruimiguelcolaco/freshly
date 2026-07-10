import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

private struct StubSource: UpdateSource {
    let id: SourceID
    let claim: SourceApplicability

    func applicability(for app: InstalledApp) -> SourceApplicability {
        claim
    }

    func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        nil
    }
}

@Suite("SourceRegistry")
struct SourceRegistryTests {
    private let app = InstalledApp(
        bundleID: "com.example.App",
        name: "Example",
        path: URL(fileURLWithPath: "/Applications/Example.app"),
        version: "1.0"
    )

    @Test("Non-applicable sources are filtered out")
    func filtersNotApplicable() {
        let registry = SourceRegistry(sources: [
            StubSource(id: .sparkle, claim: .notApplicable),
            StubSource(id: .homebrew, claim: .candidate),
        ])
        let applicable = registry.applicableSources(for: app)
        #expect(applicable.count == 1)
        #expect(applicable.first?.source.id == .homebrew)
    }

    @Test("Authoritative sources rank ahead of candidates")
    func authoritativeFirst() {
        let registry = SourceRegistry(sources: [
            StubSource(id: .github, claim: .candidate),
            StubSource(id: .sparkle, claim: .authoritative),
            StubSource(id: .homebrew, claim: .candidate),
        ])
        let applicable = registry.applicableSources(for: app)
        #expect(applicable.first?.source.id == .sparkle)
        #expect(applicable.count == 3)
    }

    @Test("Ties keep registration order: the App Store receipt beats Sparkle")
    func tieBreaksByRegistrationOrder() {
        let registry = SourceRegistry(sources: [
            StubSource(id: .macAppStore, claim: .authoritative),
            StubSource(id: .sparkle, claim: .authoritative),
        ])
        let applicable = registry.applicableSources(for: app)
        #expect(applicable.map(\.source.id) == [.macAppStore, .sparkle])

        let reversed = SourceRegistry(sources: [
            StubSource(id: .sparkle, claim: .authoritative),
            StubSource(id: .macAppStore, claim: .authoritative),
        ])
        #expect(reversed.applicableSources(for: app).map(\.source.id) == [.sparkle, .macAppStore])
    }
}
