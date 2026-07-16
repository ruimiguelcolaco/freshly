import Foundation
import Testing
@testable import FreshlySources

@Suite("Cask token matching")
struct CaskMatchingTests {
    private func entry(token: String, appNames: [String]) -> CaskEntry {
        CaskEntry(token: token, version: "1.0", appNames: appNames, homepage: nil, downloadURL: nil)
    }

    @Test("No cask claims the app name")
    func noMatch() {
        let entries = [entry(token: "firefox", appNames: ["Firefox.app"])]
        #expect(HomebrewCatalog.caskTokens(matchingAppNamed: "Unknown.app", in: entries).isEmpty)
    }

    @Test("Exactly one cask claims the app name")
    func oneMatch() {
        let entries = [
            entry(token: "firefox", appNames: ["Firefox.app"]),
            entry(token: "iterm2", appNames: ["iTerm.app"]),
        ]
        #expect(HomebrewCatalog.caskTokens(matchingAppNamed: "Firefox.app", in: entries) == ["firefox"])
    }

    @Test("Two casks claiming the same app name are both surfaced as ambiguous")
    func ambiguousMatch() {
        let entries = [
            entry(token: "shade-one", appNames: ["Shade.app"]),
            entry(token: "shade-two", appNames: ["Shade.app"]),
        ]
        let tokens = HomebrewCatalog.caskTokens(matchingAppNamed: "Shade.app", in: entries)
        #expect(Set(tokens) == ["shade-one", "shade-two"])
        #expect(tokens.count == 2)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        let entries = [entry(token: "firefox", appNames: ["Firefox.app"])]
        #expect(HomebrewCatalog.caskTokens(matchingAppNamed: "firefox.app", in: entries) == ["firefox"])
    }
}
