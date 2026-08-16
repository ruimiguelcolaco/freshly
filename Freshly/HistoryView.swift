import AppKit
import SwiftUI
import FreshlyModels

/// The Update History window: every update attempt made through Freshly —
/// what, when, through which channel, and how it ended. Local only.
struct HistoryView: View {
    @Environment(AppListStore.self) private var store

    @State private var confirmingClear = false
    @State private var filter: Filter = .all

    private enum Filter: Hashable {
        case all, installed, failed
    }

    private var filteredHistory: [UpdateRecord] {
        switch filter {
        case .all: store.history
        case .installed: store.history.filter { if case .installed = $0.outcome { true } else { false } }
        case .failed: store.history.filter { if case .failed = $0.outcome { true } else { false } }
        }
    }

    var body: some View {
        List(filteredHistory) { record in
            HistoryRowView(record: record)
        }
        .listStyle(.inset)
        .frame(minWidth: 480, minHeight: 300)
        .navigationTitle("Update History")
        .toolbar {
            if !store.history.isEmpty {
                ToolbarItem {
                    Picker("Filter", selection: $filter) {
                        Text("All").tag(Filter.all)
                        Text("Installed").tag(Filter.installed)
                        Text("Failed").tag(Filter.failed)
                    }
                    .pickerStyle(.segmented)
                    .help("Filter the history by outcome")
                }
            }
            ToolbarItem {
                Button("Clear History", systemImage: "trash") {
                    confirmingClear = true
                }
                .disabled(store.history.isEmpty)
                .help("Remove every record from the update history")
            }
        }
        .overlay {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No Updates Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Updates installed through Freshly will appear here.")
                )
            } else if filteredHistory.isEmpty {
                ContentUnavailableView(
                    "No matching updates",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No records match this filter.")
                )
            }
        }
        .confirmationDialog(
            "Clear the update history?",
            isPresented: $confirmingClear
        ) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every record. Installed apps are not affected.")
        }
    }
}

private struct HistoryRowView: View {
    let record: UpdateRecord
    @State private var problemReport: ProblemReportContext?

    var body: some View {
        HStack(spacing: 10) {
            outcomeBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(record.appName)
                        .fontWeight(.medium)
                    Text(AppVersion.transition(from: record.fromVersion, to: record.toVersion))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if case .failed(let error) = record.outcome {
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.date.formatted(.relative(presentation: .named)))
                    .help(record.date.formatted(date: .abbreviated, time: .shortened))
                Text(record.source.displayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Menu("More", systemImage: "ellipsis.circle") {
                Button("Report a Problem…") {
                    problemReport = .history(record)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Report a Problem…") {
                problemReport = .history(record)
            }
        }
        .sheet(item: $problemReport) { context in
            ProblemReportView(report: context.report)
        }
    }

    @ViewBuilder
    private var outcomeBadge: some View {
        switch record.outcome {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Installed")
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Failed")
        }
    }
}
