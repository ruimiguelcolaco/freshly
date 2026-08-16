import Foundation
import FreshlyEngine
import FreshlyModels
import FreshlyScanner
import FreshlySources

struct AppScanSession: Sendable {
    let installedCaskTokens: Set<String>
    let statuses: AsyncStream<AppUpdateStatus>
}

protocol UpdateScanning: Sendable {
    func start() async -> AppScanSession
}

/// Builds the source graph for one scan. Keeping this outside the UI store
/// makes scan lifecycle policy independently testable without changing the
/// production discovery or source ordering.
struct LiveUpdateScanner: UpdateScanning {
    func start() async -> AppScanSession {
        let definitions = await currentDefinitions()
        let caskTokens = Caskroom.detect()?.installedTokens() ?? []
        let homebrewEntries = try? await HomebrewCatalog().loadEntries()
        let sources = SourceAssembly.sources(
            homebrewEntries: homebrewEntries,
            installedCaskTokens: caskTokens,
            definitionCaskTokens: definitions.caskTokens,
            githubRepos: definitions.githubRepos,
            githubToken: TokenStore.load()
        )
        let coordinator = UpdateCoordinator(
            discoverer: EnrichingDiscoverer(base: AppScanner()) { definitions.enrich($0) },
            registry: SourceRegistry(sources: sources)
        )
        return AppScanSession(
            installedCaskTokens: caskTokens,
            statuses: coordinator.checkAll()
        )
    }

    /// The community definitions shipped inside the app bundle (the
    /// repository's `Definitions/` directory, copied in as a resource).
    private func bundledDefinitions() -> DefinitionsCatalog {
        guard let directory = Bundle.main.url(forResource: "Definitions", withExtension: nil) else {
            return DefinitionsCatalog(definitions: [])
        }
        return DefinitionsCatalog.load(from: directory)
    }

    /// The bundled catalog extended — and, per app, overridden — by the
    /// repository's packed catalog, refreshed on every scan.
    private func currentDefinitions() async -> DefinitionsCatalog {
        await DefinitionsProvider().current(bundled: bundledDefinitions())
    }
}
