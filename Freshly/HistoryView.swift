import AppKit
import SwiftUI
import FreshlyModels

/// The Update History window: every update attempt made through Freshly —
/// what, when, through which channel, and how it ended. Local only.
struct HistoryView: View {
    @Environment(AppListStore.self) private var store

    @State private var confirmingClear = false

    var body: some View {
        List(store.history) { record in
            HistoryRowView(record: record)
        }
        .listStyle(.inset)
        .frame(minWidth: 480, minHeight: 300)
        .navigationTitle("Update History")
        .toolbar {
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

    var body: some View {
        HStack(spacing: 10) {
            outcomeBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(record.appName)
                        .fontWeight(.medium)
                    Text("\(record.fromVersion.rawValue) → \(record.toVersion.rawValue)")
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
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
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
