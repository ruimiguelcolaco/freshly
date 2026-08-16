import Foundation
import Testing
import FreshlyEngine
import FreshlyModels

@Suite("DiagnosticReport")
struct DiagnosticReportTests {
    @Test("Sensitive paths, URL parameters, credentials, and identifiers are redacted")
    func redactsSensitiveData() {
        let redactor = DiagnosticRedactor(homeDirectory: URL(filePath: "/Users/alice"))
        let input = """
        /Users/alice/Library/file /Users/bob/Desktop/file /private/tmp/archive.zip
        https://alice:password@example.com/releases/app.zip?token=secret#fragment
        file:///Users/alice/secret.txt Authorization: Bearer abc.def.ghi
        token=plain github_pat_abcdefghijklmnopqrstuvwxyz0123456789
        550E8400-E29B-41D4-A716-446655440000 00:11:22:33:44:55 alice@example.com
        abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd
        """

        let output = redactor.redact(input)

        #expect(!output.contains("alice"))
        #expect(!output.contains("bob"))
        #expect(!output.contains("secret"))
        #expect(!output.contains("fragment"))
        #expect(!output.contains("550E8400"))
        #expect(!output.contains("00:11:22"))
        #expect(!output.contains("github_pat"))
        #expect(output.contains("https://example.com/releases/app.zip"))
        #expect(output.contains("<FILE_URL>"))
    }

    @Test("GitHub and email drafts contain the exact local preview")
    func draftURLsContainPreview() throws {
        let report = DiagnosticReport(
            appName: "Example",
            bundleID: "com.example.app",
            installedVersion: "1.0",
            availableVersion: "2.0",
            source: .sparkle,
            outcome: "Install failed",
            errorDescription: "failed at /Users/alice/Downloads/update.zip?token=secret",
            freshlyVersion: "0.1",
            macOSVersion: "26.0",
            homeDirectory: URL(filePath: "/Users/alice")
        )

        let githubURL = try #require(report.githubIssueURL(
            repository: URL(string: "https://github.com/example/project")!
        ))
        let emailURL = try #require(report.emailURL(address: "support@example.com"))
        let githubItems = URLComponents(url: githubURL, resolvingAgainstBaseURL: false)?.queryItems
        let emailItems = URLComponents(url: emailURL, resolvingAgainstBaseURL: false)?.queryItems

        #expect(githubItems?.first(where: { $0.name == "diagnostic" })?.value == report.body)
        #expect(githubItems?.first(where: { $0.name == "template" })?.value == "problem_report.yml")
        #expect(emailItems?.first(where: { $0.name == "body" })?.value == report.body)
        #expect(!report.body.contains("alice"))
        #expect(!report.body.contains("secret"))
    }
}
