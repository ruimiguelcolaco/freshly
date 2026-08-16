import Foundation
import FreshlyModels

/// A locally generated, user-reviewable problem report. The app may place
/// this text in a browser or email draft, but never submits it itself.
public struct DiagnosticReport: Sendable, Hashable {
    public let suggestedTitle: String
    public let body: String

    public init(suggestedTitle: String, body: String) {
        self.suggestedTitle = suggestedTitle
        self.body = body
    }

    public init(
        appName: String,
        bundleID: String,
        installedVersion: AppVersion,
        availableVersion: AppVersion? = nil,
        source: SourceID? = nil,
        outcome: String,
        errorDescription: String? = nil,
        freshlyVersion: String,
        macOSVersion: String,
        homeDirectory: URL
    ) {
        let redactor = DiagnosticRedactor(homeDirectory: homeDirectory)
        suggestedTitle = redactor.redact("Problem updating \(appName)")

        var fields = [
            ("Freshly version", freshlyVersion),
            ("macOS version", macOSVersion),
            ("App", appName),
            ("Bundle ID", bundleID),
            ("Installed version", installedVersion.rawValue),
            ("Outcome", outcome),
        ]
        if let availableVersion {
            fields.append(("Available version", availableVersion.rawValue))
        }
        if let source {
            fields.append(("Update source", source.rawValue))
        }
        if let errorDescription {
            fields.append(("Error", errorDescription))
        }

        let diagnostics = fields.map { label, value in
            "- \(label): \(redactor.redact(value))"
        }.joined(separator: "\n")
        body = """
        ## What happened

        <!-- Describe what you did and what you expected. -->

        ## Diagnostic preview

        \(diagnostics)

        <!-- This report was prepared locally. Review and edit it before submitting. -->
        """
    }

    public func githubIssueURL(repository: URL) -> URL? {
        let issueURL = repository.appending(path: "issues/new")
        guard var components = URLComponents(url: issueURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "template", value: "problem_report.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "title", value: suggestedTitle),
            URLQueryItem(name: "diagnostic", value: body),
        ]
        return components.url
    }

    public func emailURL(address: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: suggestedTitle),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

public struct DiagnosticRedactor: Sendable {
    private let homePath: String

    public init(homeDirectory: URL) {
        homePath = homeDirectory.standardizedFileURL.path
    }

    public func redact(_ input: String) -> String {
        var output = redactURLs(in: input)
        if !homePath.isEmpty {
            output = output.replacingOccurrences(of: homePath, with: "<HOME>")
        }
        output = replace(#"/Users/[^/\s]+"#, in: output, with: "/Users/<redacted>")
        output = replace(
            #"(?i)\b(authorization|password|passwd|secret|token|api[_-]?key)(\s*[:=]\s*)[^\s,;]+"#,
            in: output,
            with: "$1$2<redacted>"
        )
        output = replace(#"(?i)\bBearer\s+[A-Za-z0-9._~+\-/]+=*"#, in: output, with: "Bearer <redacted>")
        output = replace(#"\b(?:gh[opusr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#, in: output)
        output = replace(#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b"#, in: output)
        output = replace(#"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b"#, in: output)
        output = replace(#"\b[A-Fa-f0-9]{32,}\b"#, in: output)
        output = replace(#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, in: output, options: [.caseInsensitive])
        output = replace(
            #"(?<![:\w])/(?:Applications|Volumes|private|var|tmp)(?:/[^\s,;:]+)+"#,
            in: output,
            with: "<PATH>"
        )
        return output
    }

    private func redactURLs(in input: String) -> String {
        let expression = try? NSRegularExpression(pattern: #"(?:https?|file)://[^\s<>\"']+"#)
        let range = NSRange(input.startIndex..., in: input)
        let matches = expression?.matches(in: input, range: range) ?? []
        var output = input
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: output) else { continue }
            let raw = String(output[swiftRange])
            let replacement: String
            if raw.hasPrefix("file://") {
                replacement = "<FILE_URL>"
            } else if var components = URLComponents(string: raw) {
                components.user = nil
                components.password = nil
                components.query = nil
                components.fragment = nil
                replacement = components.string ?? "<URL>"
            } else {
                replacement = "<URL>"
            }
            output.replaceSubrange(swiftRange, with: replacement)
        }
        return output
    }

    private func replace(
        _ pattern: String,
        in input: String,
        with replacement: String = "<redacted>",
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        return expression.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}
