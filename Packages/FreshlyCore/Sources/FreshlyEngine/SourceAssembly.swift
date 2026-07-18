import FreshlyModels
import FreshlySources

/// Builds the update sources for a scan in the order the resolver relies on.
///
/// Registration order breaks authoritative ties: an app with both a receipt
/// and a Sparkle feed updates through the App Store; the Caskroom outranks a
/// mere matching cask; a brew-installed Electron app keeps updating through
/// brew so its bookkeeping stays honest. Homebrew is omitted when its index
/// could not be loaded; GitHub when no definition names a repository.
///
/// Pure and offline: the caller performs the I/O (Caskroom detection, the
/// cask-index fetch, the keychain token) and passes the results in, which is
/// what makes this policy unit-testable in isolation.
public enum SourceAssembly {
    public static func sources(
        homebrewEntries: [CaskEntry]?,
        installedCaskTokens: Set<String>,
        definitionCaskTokens: [String: String],
        githubRepos: [String: String],
        githubToken: String?
    ) -> [any UpdateSource] {
        var sources: [any UpdateSource] = [MacAppStoreSource(), SparkleSource()]
        if let homebrewEntries {
            sources.append(HomebrewSource(
                entries: homebrewEntries,
                installedCaskTokens: installedCaskTokens,
                definitionTokens: definitionCaskTokens
            ))
        }
        sources.append(ElectronSource())
        if !githubRepos.isEmpty {
            sources.append(GitHubSource(repos: githubRepos, token: githubToken))
        }
        return sources
    }
}
