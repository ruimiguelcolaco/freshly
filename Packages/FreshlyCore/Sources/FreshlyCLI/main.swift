import Foundation
import FreshlyEngine
import FreshlyModels
import FreshlyScanner
import FreshlySources

func fail(_ message: String, exitCode: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(exitCode)
}

func repositoryDefinitions() -> DefinitionsCatalog {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let packURL = root.appending(path: "definitions-catalog.json")
    if let data = try? Data(contentsOf: packURL),
       let pack = DefinitionsPack.decode(data) {
        return DefinitionsCatalog(definitions: pack.definitions)
    }
    return DefinitionsCatalog.load(from: root.appending(path: "Definitions", directoryHint: .isDirectory))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["check", "--json"] else {
    fail("usage: freshly check --json", exitCode: 2)
}

let definitions = await DefinitionsProvider().current(bundled: repositoryDefinitions())
let installedCaskTokens = Caskroom.detect()?.installedTokens() ?? []
let homebrewEntries = try? await HomebrewCatalog().loadEntries()
let sources = SourceAssembly.sources(
    homebrewEntries: homebrewEntries,
    installedCaskTokens: installedCaskTokens,
    definitionCaskTokens: definitions.caskTokens,
    githubRepos: definitions.githubRepos,
    githubToken: ProcessInfo.processInfo.environment["FRESHLY_GITHUB_TOKEN"]
)
let coordinator = UpdateCoordinator(
    discoverer: EnrichingDiscoverer(base: AppScanner()) { definitions.enrich($0) },
    registry: SourceRegistry(sources: sources)
)

var settled: [URL: AppUpdateStatus] = [:]
for await status in coordinator.checkAll() {
    if status.state != .checking {
        settled[status.id] = status
    }
}

let report = UpdateCheckReport(statuses: Array(settled.values))
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
do {
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fail("could not encode the check report: \(error.localizedDescription)", exitCode: 1)
}
