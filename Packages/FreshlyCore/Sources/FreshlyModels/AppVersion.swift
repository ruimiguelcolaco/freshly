import Foundation

/// A version string as found in real `Info.plist` files, compared with
/// Sparkle-compatible semantics.
///
/// Real-world Mac version strings are messy: `"1.2.3"`, `"1.2.3 (4567)"`,
/// `"2.1b5"`, or Homebrew's `"1.2.3,4567"`. Comparison tokenizes the string
/// into numeric and alphabetic runs and compares token by token:
///
/// - numeric tokens compare numerically (`1.10` > `1.9`)
/// - alphabetic tokens compare lexicographically, case-insensitively
/// - a numeric token is newer than an alphabetic one at the same position
///   (`1.0.1` > `1.0b5`)
/// - when one version is a prefix of the other, the longer one is newer if
///   its first extra token is numeric (`1.2.0` > `1.2`) and older if it is
///   alphabetic (`1.0b1` < `1.0`)
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var description: String { rawValue }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tokens == rhs.tokens
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(tokens)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let a = lhs.tokens
        let b = rhs.tokens

        for (tokenA, tokenB) in zip(a, b) {
            switch (tokenA, tokenB) {
            case let (.number(x), .number(y)):
                if x != y { return x < y }
            case let (.text(x), .text(y)):
                if x != y { return x < y }
            case (.text, .number):
                return true
            case (.number, .text):
                return false
            }
        }

        guard a.count != b.count else { return false }
        if a.count < b.count {
            if case .number = b[a.count] { return true }
            return false
        } else {
            if case .text = a[b.count] { return true }
            return false
        }
    }

    enum Token: Hashable {
        case number(UInt64)
        case text(String)
    }

    var tokens: [Token] {
        var result: [Token] = []
        var number: UInt64?
        var text = ""

        func flush() {
            if let value = number {
                result.append(.number(value))
                number = nil
            }
            if !text.isEmpty {
                result.append(.text(text))
                text = ""
            }
        }

        for character in rawValue {
            if character.isASCII, let digit = character.wholeNumberValue, (0...9).contains(digit) {
                if !text.isEmpty {
                    result.append(.text(text))
                    text = ""
                }
                let value = UInt64(digit)
                if let existing = number {
                    number = existing > (UInt64.max - value) / 10 ? .max : existing * 10 + value
                } else {
                    number = value
                }
            } else if character.isLetter {
                if let value = number {
                    result.append(.number(value))
                    number = nil
                }
                text.append(contentsOf: character.lowercased())
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}

extension AppVersion: Codable {
    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension AppVersion: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
