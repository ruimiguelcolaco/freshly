import AppKit
import SwiftUI
import FreshlyEngine
import FreshlyModels

struct ProblemReportContext: Identifiable {
    let id = UUID()
    let report: DiagnosticReport

    static func status(_ status: AppUpdateStatus, installError: UpdateError?) -> ProblemReportContext {
        let available: AppVersion?
        let source: SourceID?
        let stateError: UpdateError?
        let outcome: String

        switch status.state {
        case .checking:
            available = nil
            source = nil
            stateError = nil
            outcome = "Check still running"
        case .upToDate:
            available = nil
            source = nil
            stateError = nil
            outcome = "Reported up to date"
        case .outdated(let best, _):
            available = best.version
            source = best.source
            stateError = nil
            outcome = installError == nil ? "Update available" : "Install failed"
        case .skipped(let version):
            available = version
            source = nil
            stateError = nil
            outcome = "Version skipped"
        case .unsupported:
            available = nil
            source = nil
            stateError = nil
            outcome = "No update source"
        case .failed(let error):
            available = nil
            source = nil
            stateError = error
            outcome = "Update check failed"
        }

        return ProblemReportContext(report: makeReport(
            appName: status.app.name,
            bundleID: status.app.bundleID,
            installedVersion: status.app.version,
            availableVersion: available,
            source: source,
            outcome: outcome,
            error: installError ?? stateError
        ))
    }

    static func history(_ record: UpdateRecord) -> ProblemReportContext {
        let outcome: String
        let error: UpdateError?
        switch record.outcome {
        case .installed:
            outcome = "Installed"
            error = nil
        case .failed(let failure):
            outcome = "Install failed"
            error = failure
        }
        return ProblemReportContext(report: makeReport(
            appName: record.appName,
            bundleID: record.bundleID,
            installedVersion: record.fromVersion,
            availableVersion: record.toVersion,
            source: record.source,
            outcome: outcome,
            error: error
        ))
    }

    private static func makeReport(
        appName: String,
        bundleID: String,
        installedVersion: AppVersion,
        availableVersion: AppVersion?,
        source: SourceID?,
        outcome: String,
        error: UpdateError?
    ) -> DiagnosticReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
        return DiagnosticReport(
            appName: appName,
            bundleID: bundleID,
            installedVersion: installedVersion,
            availableVersion: availableVersion,
            source: source,
            outcome: outcome,
            errorDescription: error?.message,
            freshlyVersion: version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}

struct ProblemReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var reportText: String
    private let suggestedTitle: String

    init(report: DiagnosticReport) {
        suggestedTitle = report.suggestedTitle
        _reportText = State(initialValue: report.body)
    }

    private var editedReport: DiagnosticReport {
        DiagnosticReport(suggestedTitle: suggestedTitle, body: reportText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Report a Problem")
                .font(.title2.weight(.semibold))
            Text("This diagnostic was prepared locally. Review and edit exactly what will be shared; Freshly never submits it automatically.")
                .foregroundStyle(.secondary)

            TextEditor(text: $reportText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 280)
                .border(.separator)
                .accessibilityLabel("Diagnostic preview")

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reportText, forType: .string)
                }
                Link(
                    "Report Security Issue Privately",
                    destination: URL(string: "https://github.com/ruimiguelcolaco/freshly/security/advisories/new")!
                )
                .help("Security problems must not be reported publicly")

                Spacer()

                Button("Email…") {
                    if let url = editedReport.emailURL(address: "ruimiguelcolaco@gmail.com") {
                        openURL(url)
                    }
                }
                Button("Open GitHub Issue…") {
                    if let repository = URL(string: "https://github.com/ruimiguelcolaco/freshly"),
                       let url = editedReport.githubIssueURL(repository: repository) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 440)
    }
}
