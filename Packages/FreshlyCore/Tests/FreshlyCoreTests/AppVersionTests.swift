import Testing
@testable import FreshlyModels

@Suite("AppVersion comparison")
struct AppVersionTests {
    @Test("Numeric components compare numerically, not lexicographically")
    func numericOrdering() {
        #expect(AppVersion("1.0") < AppVersion("2.0"))
        #expect(AppVersion("1.9") < AppVersion("1.10"))
        #expect(AppVersion("1.2.3") < AppVersion("1.2.4"))
        #expect(AppVersion("9.9.9") < AppVersion("10.0"))
    }

    @Test("Identical versions are equal")
    func equality() {
        #expect(AppVersion("1.2.3") == AppVersion("1.2.3"))
        #expect(AppVersion("1.2.3") <= AppVersion("1.2.3"))
        #expect(!(AppVersion("1.2.3") < AppVersion("1.2.3")))
    }

    @Test("Separator style does not affect comparison")
    func separatorInsensitivity() {
        #expect(AppVersion("1.2-3") == AppVersion("1.2.3"))
        #expect(AppVersion("1.2.3 (100)") == AppVersion("1.2.3.100"))
        #expect(AppVersion(" 1.2.3 ") == AppVersion("1.2.3"))
    }

    @Test("A numeric continuation is newer: 1.2.0 > 1.2")
    func numericSuffixIsNewer() {
        #expect(AppVersion("1.2") < AppVersion("1.2.0"))
        #expect(AppVersion("1") < AppVersion("1.0"))
    }

    @Test("An alphabetic continuation is a pre-release: 1.0b1 < 1.0")
    func preReleaseIsOlder() {
        #expect(AppVersion("1.0b1") < AppVersion("1.0"))
        #expect(AppVersion("2.0beta") < AppVersion("2.0"))
        #expect(AppVersion("1.0rc1") < AppVersion("1.0"))
    }

    @Test("Pre-release builds order among themselves")
    func preReleaseOrdering() {
        #expect(AppVersion("1.0b1") < AppVersion("1.0b2"))
        #expect(AppVersion("1.0beta2") < AppVersion("1.0beta10"))
        #expect(AppVersion("1.0a5") < AppVersion("1.0b1"))
    }

    @Test("A number beats a letter at the same position: 1.0.1 > 1.0b5")
    func numberBeatsText() {
        #expect(AppVersion("1.0b5") < AppVersion("1.0.1"))
    }

    @Test("Case does not matter in pre-release tags")
    func caseInsensitivity() {
        #expect(AppVersion("1.0B1") == AppVersion("1.0b1"))
    }

    @Test("Homebrew cask style versions with comma-separated builds")
    func caskStyleVersions() {
        #expect(AppVersion("2.0.1,4500") < AppVersion("2.0.1,4567"))
        #expect(AppVersion("2.0.1,4567") < AppVersion("2.0.2,100"))
    }

    @Test("Build numbers in parentheses participate in ordering")
    func buildNumbersInParentheses() {
        #expect(AppVersion("1.2.3 (99)") < AppVersion("1.2.3 (100)"))
    }

    @Test("Huge numeric components do not trap or overflow")
    func hugeNumbers() {
        #expect(AppVersion("20260709.1") < AppVersion("20260710.1"))
        let clamped = AppVersion("99999999999999999999999999")
        #expect(clamped == clamped)
    }

    @Test("Equal versions hash identically")
    func hashingConsistency() {
        let a = AppVersion("1.2-3")
        let b = AppVersion("1.2.3")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Sorting a realistic version history")
    func sortingHistory() {
        let history: [AppVersion] = ["1.0b1", "1.0", "1.0.1", "1.2", "1.2.0", "1.10", "2.0beta", "2.0"]
        #expect(history.sorted() == history)
    }
}
