import Foundation
import Testing
@testable import FreshlySources

@Suite("ISO8601")
struct ISO8601Tests {
    @Test("Parses timestamps with fractional seconds")
    func fractionalSeconds() {
        #expect(ISO8601.date(from: "2026-07-07T23:20:34.590Z") != nil)
    }

    @Test("Parses timestamps with whole seconds")
    func wholeSeconds() {
        #expect(ISO8601.date(from: "2026-07-07T23:20:34Z") != nil)
    }

    @Test("Rejects non-date strings")
    func garbage() {
        #expect(ISO8601.date(from: "not a date") == nil)
    }
}
