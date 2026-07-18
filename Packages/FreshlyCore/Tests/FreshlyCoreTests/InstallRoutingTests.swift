import Testing
import FreshlyModels
@testable import FreshlyInstaller

@Suite("InstallRouting.usesBrewUpgrade")
struct InstallRoutingTests {
    private func release(source: SourceID, caskToken: String?) -> ReleaseInfo {
        ReleaseInfo(version: AppVersion("1.0"), caskToken: caskToken, source: source)
    }

    @Test("A brew-installed Homebrew cask upgrades through brew")
    func brewInstalledCask() {
        let release = release(source: .homebrew, caskToken: "firefox")
        #expect(InstallRouting.usesBrewUpgrade(release, installedCaskTokens: ["firefox"]))
    }

    @Test("A Homebrew cask not installed through brew takes the direct pipeline")
    func caskNotInstalledViaBrew() {
        let release = release(source: .homebrew, caskToken: "firefox")
        #expect(!InstallRouting.usesBrewUpgrade(release, installedCaskTokens: ["other"]))
    }

    @Test("A Homebrew release without a cask token takes the direct pipeline")
    func homebrewWithoutToken() {
        let release = release(source: .homebrew, caskToken: nil)
        #expect(!InstallRouting.usesBrewUpgrade(release, installedCaskTokens: ["firefox"]))
    }

    @Test("A non-Homebrew source never routes through brew")
    func nonHomebrewSource() {
        let release = release(source: .github, caskToken: "firefox")
        #expect(!InstallRouting.usesBrewUpgrade(release, installedCaskTokens: ["firefox"]))
    }
}
