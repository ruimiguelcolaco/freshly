import Foundation
import FreshlyModels

/// One `<item>` from a Sparkle appcast feed.
public struct AppcastItem: Sendable, Equatable {
    public var title: String?
    /// `sparkle:version` — corresponds to `CFBundleVersion`.
    public var version: String?
    /// `sparkle:shortVersionString` — the marketing version users see.
    public var shortVersionString: String?
    /// `sparkle:channel`. `nil` means the default (release) channel.
    public var channel: String?
    public var minimumSystemVersion: String?
    public var enclosureURL: URL?
    public var releaseNotesURL: URL?
    /// The item's `<link>` — usually the product page.
    public var link: URL?
    /// Inline release notes from `<description>`, usually HTML.
    public var descriptionHTML: String?
    public var pubDate: Date?
    /// Base64 EdDSA signature of the enclosure (`sparkle:edSignature`).
    public var edSignature: String?

    /// The version to display and compare: marketing version when present,
    /// build version otherwise.
    public var displayVersion: AppVersion? {
        (shortVersionString ?? version).map { AppVersion($0) }
    }

    public init() {}
}

/// Parses Sparkle appcast XML into items. Tolerant by design: unknown
/// elements are ignored, and version attributes on `<enclosure>` fill in
/// for missing `sparkle:` elements, as Sparkle itself allows.
public struct AppcastParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> [AppcastItem] {
        let parser = XMLParser(data: data)
        let delegate = AppcastParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription
            throw UpdateError(.sourceResponseUnreadable(.sparkle, detail: detail))
        }
        return delegate.items
    }
}

private final class AppcastParserDelegate: NSObject, XMLParserDelegate {
    var items: [AppcastItem] = []
    private var currentItem: AppcastItem?
    private var currentText = ""

    private static let pubDateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
    ]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        currentText = ""
        switch elementName {
        case "item":
            currentItem = AppcastItem()
        case "enclosure":
            guard currentItem != nil else { return }
            if let urlString = attributes["url"], let url = URL(string: urlString) {
                currentItem?.enclosureURL = url
            }
            if currentItem?.version == nil {
                currentItem?.version = attributes["sparkle:version"]
            }
            if currentItem?.shortVersionString == nil {
                currentItem?.shortVersionString = attributes["sparkle:shortVersionString"]
            }
            currentItem?.edSignature = attributes["sparkle:edSignature"]
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentText = "" }

        switch elementName {
        case "item":
            if let item = currentItem {
                items.append(item)
            }
            currentItem = nil
        case "title":
            currentItem?.title = text
        case "sparkle:version":
            if !text.isEmpty { currentItem?.version = text }
        case "sparkle:shortVersionString":
            if !text.isEmpty { currentItem?.shortVersionString = text }
        case "sparkle:channel":
            if !text.isEmpty { currentItem?.channel = text }
        case "sparkle:minimumSystemVersion":
            if !text.isEmpty { currentItem?.minimumSystemVersion = text }
        case "sparkle:releaseNotesLink":
            currentItem?.releaseNotesURL = URL(string: text)
        case "link":
            currentItem?.link = URL(string: text)
        case "description":
            if currentItem != nil, !text.isEmpty {
                currentItem?.descriptionHTML = text
            }
        case "pubDate":
            currentItem?.pubDate = Self.parseDate(text)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        currentText += String(decoding: CDATABlock, as: UTF8.self)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in pubDateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
