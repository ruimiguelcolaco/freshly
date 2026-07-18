import Testing
import FreshlyModels
import FreshlyEngine

@Suite("SourceAssembly")
struct SourceAssemblyTests {
    @Test("Registration order encodes the resolver's precedence")
    func precedenceOrder() {
        let sources = SourceAssembly.sources(
            homebrewEntries: [],
            installedCaskTokens: [],
            definitionCaskTokens: [:],
            githubRepos: ["com.example.App": "owner/repo"],
            githubToken: nil
        )
        #expect(sources.map(\.id) == [.macAppStore, .sparkle, .homebrew, .electron, .github])
    }

    @Test("Homebrew is omitted when the cask index could not be loaded")
    func homebrewOmittedWithoutIndex() {
        let sources = SourceAssembly.sources(
            homebrewEntries: nil,
            installedCaskTokens: [],
            definitionCaskTokens: [:],
            githubRepos: [:],
            githubToken: nil
        )
        #expect(sources.map(\.id) == [.macAppStore, .sparkle, .electron])
    }

    @Test("GitHub is omitted when no definition names a repository")
    func githubOmittedWithoutRepos() {
        let sources = SourceAssembly.sources(
            homebrewEntries: [],
            installedCaskTokens: [],
            definitionCaskTokens: [:],
            githubRepos: [:],
            githubToken: nil
        )
        #expect(sources.map(\.id) == [.macAppStore, .sparkle, .homebrew, .electron])
    }
}
