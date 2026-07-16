import Foundation

enum ISO8601 {
    /// electron-builder and some feeds emit fractional seconds
    /// (`2026-07-07T23:20:34.590Z`); others emit whole seconds. A single
    /// `ISO8601DateFormatter` only accepts one shape, so try both.
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
